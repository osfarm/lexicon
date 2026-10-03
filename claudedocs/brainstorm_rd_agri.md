# Brainstorm — Datasource `rd_agri` (Plateforme R&D agricole)

> Document d'exigences issu de `/sc:brainstorm`. Pas de conception : le schéma
> des tables et l'architecture relèvent de `/sc:design`.
> Sources étudiées : `raw/rd_agri/` (exports CSV du 2026-09-15) et la base
> `lexicon` 6.0.2 chargée localement.
> Révision 5 : décisions Q14b, Q16, Q17, Q18. **Discovery terminée** : aucune
> question bloquante, prêt pour `/sc:design`.

## 0. Décisions prises

| # | Question | Décision |
|---|---|---|
| Q1 | Licence | https://rd-agri.fr/legal/ → CC BY-NC-SA 4.0 par défaut |
| Q2 | Usage prioritaire | **U1** : relier les productions Ekylibre aux documents R&D |
| Q3 | Collecte | **Dépôt manuel** de l'export CSV |
| Q4 | Labels d'enrichissement | **Filtrer** (§3) |
| Q8 | Génération | **v1** : PostgreSQL, ce dépôt |
| Q9 | Clause NC | **Pas de problème** : Lexicon n'est pas commercial |
| Q10 | Grain filière | Une filière est liée à **toutes** ses productions |
| Q11 | Limiter les documents par production | **Non** |
| Q12 | Filtres de l'export | **Aucun** : catalogue complet |
| Q13 | Liaisons secondaires du MVP | **Zones administratives, agriculture biologique, ravageurs et maladies**. Thèmes techniques exclus. |
| Q14 | Filières sans taxon unique (Volaille, Grande culture, Légume, Fruit…) | **Nouvelle datasource `industry_sector`** ; `activity_family` inchangée (§5) |
| Q15 | Compléter `master_taxonomy` | **Oui**, périmètre recadré en §6 : 32 productions agricoles sans espèce, pas les 86 « espèces » non biologiques |
| Q16 | Mots-clés « Productions animales » / « Productions végétales » | **Ignorés** |
| Q17 | Ravageurs et maladies | **Seulement les bioagresseurs nommés** ; catégories d'usage (fongicide, insecticide, désherbage, adventices…) exclues |
| Q18 | Productions multi-taxons | **Rattachement au genre** (§6.2, TX5) |

Le MVP repose sur l'export **Documents** seul. Projets et jeux de données sont
hors périmètre (§12).

## 1. La source

[rd-agri.fr](https://rd-agri.fr/), édité par l'**ACTA** avec l'APCA et la DGER,
centralise les livrables des projets de R&D agricole (CASDAR, France Relance,
GIEE, Groupes Ecophyto 30 000).

### 1.1 Licence

Les [mentions légales](https://rd-agri.fr/legal/) placent les contenus sous
**CC BY-NC-SA 4.0**, sauf mention contraire dans la notice, avec obligation de
**citer rd-agri comme auteur principal**. Lexicon n'étant pas commercial (Q9),
la licence ne bloque pas l'intégration. Il en découle :

- **BY** : `credits` avec rd-agri comme auteur principal et la licence ;
- **SA** : les tables dérivées de rd_agri sont diffusées sous CC BY-NC-SA 4.0 ;
- les **descriptions** peuvent être reprises ;
- la colonne **`Auteurs`** reste exclue. Ce n'est pas une question de licence :
  elle contient des données nominatives, et les mentions légales renvoient aux
  règles de la CNIL.

## 2. L'export documents

CSV `;`, UTF-8 avec BOM, CRLF, champs multilignes entre guillemets. Aucune
ligne malformée. **40 523 lignes**, 18 colonnes, 327 Mo.

| Colonne | Remplissage | Remarque | Rôle |
|---|---:|---|---|
| Type | 100 % | `Document` | contrôle du fichier |
| Titre | 99 % | 39 297 distincts | exposé + liaison |
| Année de publication | 100 % | 1996→2026, 98 % depuis 2015 ; 239 à `0` et 2 à `1900` | exposé |
| Description | 84 % | jusqu'à 11 Ko, 32 contiennent du HTML ; 17,6 Mo au total | exposé (nettoyé) + liaison |
| Mots-clés | 34 % | 1 280 valeurs, propres | liaison |
| URL de la notice | 41 % | site de l'éditeur d'origine | exposé |
| Code projet / Nom du projet | 99 % | préfixe régional pour les GIEE | exposé + liaison zones |
| Organisme(s) | 74 % | séparés par `,` ou `;`, 3 972 variantes | liaison zones |
| Publicateur | 99 % | 541 valeurs, non normalisé | exposé, normalisé |
| Date de création / publication | 16 % / 86 % | texte FR : `05 janvier 2026` | exposé |
| Format | 0 % | vide | ignoré |
| Langue | 41 % | `Français`, `français`, `FR`, `Fancais`… | exposé, normalisé |
| Auteurs | 70 % | **nominatif** | **exclu** |
| Labels tirés de l'enrichissement | 93 % | 291 Mo, bruités (§3) | liaison après filtrage, **non exposé** |
| URL de la page | 100 % | `https://rd-agri.fr/detail/DOCUMENT/<uuid>`, unique | **identifiant** + exposé |
| URL du document | 92 % | 262 doublons | exposé |

## 3. Filtrer les labels d'enrichissement

- Médiane de 373 labels par document. 58 % des documents portent le même bloc
  d'une quarantaine de cultures, placé en fin de liste : c'est une expansion de
  thésaurus.
- Filtrer par seuil de fréquence donne 8 à 11 % de précision indirecte.
  **Écarté.**
- **Filtre retenu** : un label n'est gardé que s'il apparaît, pluriel toléré,
  dans le **titre ou la description**. Comparaison en minuscules, **accents
  conservés** : sans eux, « maïs » devient « mais » et les faux positifs
  triplent.

## 4. Liaisons avec les datasources Lexicon existantes

21 référentiels comparés par 4 canaux : mots-clés, labels bruts, labels
confirmés, titre.

| Datasource | Documents liés | Verdict |
|---|---:|---|
| **productions** | **41 %** (§4.1) | ✅ MVP |
| **taxonomy** | pivot filière → productions | ✅ MVP |
| **administrative_areas** | 20 % organismes · 7,5 % code GIEE · 12 % titre | ✅ MVP (Q13) |
| **open_nomenclature · `production_systems`** | 4,3 % (agriculture biologique 1 453 ; conservation 245) | ✅ MVP (Q13) |
| **phytosanitary (cibles) + nomenclature `issue_natures`** | 3 % + 1,3 % | ✅ MVP (Q13) |
| intervention_models / `procedure_*` | 6,5 % | ❌ exclu (Q13) |
| phenological_stages | 1 % | ❌ |
| seed_varieties, produits phyto commerciaux, quality_and_origin_signs, vine_varieties | faux positifs (« campagne », « bilan », « Charolais », « Melon ») | ❌ |
| natural_zones, OTEX, sols, substances actives | ≈ 0 % | ❌ |
| enterprises (SIRENE) | 33 organismes sur 3 972 | ❌ |

**Transitivité** : via la production liée, Ekylibre accède aussi aux
itinéraires techniques, à la documentation Triple Performance, aux rendements,
aux prix et aux codes PAC.

### 4.1 Productions

| Canal | Documents |
|---|---:|
| A — mots-clés (filière via taxonomie, ou libellé de production) | 8 063 (20 %) |
| B — labels confirmés (productions + taxonomie) | 9 079 (22 %) |
| C — titre (libellé de production ou de taxon) | 6 948 (17 %) |
| **A ∪ B ∪ C** | **16 728 (41 %)** |

Pivot taxonomique (genre → espèce → production) :

| Mot-clé | Taxon | Productions |
|---|---|---|
| Bovin | `bos` | bull, calf, dairy_heifer, heifer, meat_cow, milk_cow, young_bull |
| Caprin | `capra` | buck, kid, meat_goat, milk_goat |
| Ovin | `ovis` | lamb, meat_ewe, milk_ewe, ram |
| Porcin | `sus` | boar, fattening_pig, piglet, sow |
| Équin | `equus` | donkey, draft_horse, pony, race_horse, saddle_horse |
| Vigne | `vitis` | vine, vine_nursery |

Le pivot ne couvre pas les filières qui regroupent plusieurs genres ou un usage
(Volaille, Grande culture, Légume, Fruit, Prairie, Fourrages) : voir §5.

### 4.2 Zones administratives
1. Préfixe du **code projet GIEE**, correspondance déterministe (`AGINOR`
   Normandie, `AGIOCC` Occitanie, `AGIARA`, `AGINA`, `AGIPDL`, `AGIPACA`,
   `AGIBZH`, `AGIGE`, `AGIBFC`, `AGICVL`, `AGIHDF`) : 3 019 documents.
2. **Organismes** (« CRA Bretagne », « Chambre d'agriculture du
   Tarn-et-Garonne ») : 7 914 documents.
3. **Titre** : 4 700 documents. Ambiguïtés : « Rhône », « Nord », « Loire » ;
   libellé le plus long prioritaire et liste d'exclusion.

Libellés Lexicon non standard à gérer : `Grand-Est`, `Nouvelle Aquitaine`.

### 4.3 Agriculture biologique
`master_nomenclatures` (`production_systems`) : « agriculture biologique »
(1 453 documents par labels confirmés, 441 par titre, 93 par mots-clés),
« agriculture de conservation » (245), « agriculture durable » (77). Mêmes
canaux que les productions.

### 4.4 Ravageurs et maladies
Deux référentiels complémentaires :
- `registered_phytosanitary_usages.target_name_label_fra` et
  `registered_phytosanitary_target_name_to_pfi_targets` : désherbage, pucerons,
  thrips, taupins, virus, fusarioses…
- `master_nomenclatures` (`issue_natures`) : sécheresse, fusariose, rouille
  jaune, sclérotinia, flavescence dorée, septoriose, mammite…

Couverture : environ 4 à 5 % des documents avant exclusion. Les termes
génériques issus des catégories d'usage phyto (« fongicide », « insecticide »,
« désherbage », « adventices », « désinfection », « Stimul. Déf. Plantes »…) ne
désignent pas un bioagresseur. Ils sont **exclus** (Q17), ce qui réduit la
couverture ; elle sera remesurée pendant la conception.

## 5. Chantier « filières » : datasource `industry_sector` (Q14)

### 5.1 Pourquoi une nouvelle datasource plutôt que `activity_family` (validé, Q14b)

| Critère | Compléter `activity_family` | **Nouvelle datasource** |
|---|---|---|
| Nature | Colonne à valeur unique de `master_productions`, reprise par la nomenclature Ekylibre `activity_families` (8 valeurs) et par `master_budgets` | Référentiel dédié |
| Cardinalité | 1 production → 1 famille | 1 production → **n** filières (le maïs relève des grandes cultures et des fourrages ; la prairie des fourrages et de l'herbe) |
| Hiérarchie | À plat | Productions animales > Bovins > Bovin lait |
| Impact Ekylibre | ⚠️ Changer ou ajouter des valeurs modifie un énuméré utilisé par l'ERP (familles d'activités, budgets) | Aucun : ajout pur |
| Réutilisation | — | rd_agri, mais aussi statistiques, filtres Ekylibre, prix, budgets |

→ **Décision : nouvelle datasource `industry_sector`**, sans toucher à `activity_family`.

Remarque : la nomenclature `activity_families` compte 8 valeurs, alors que
`master_productions` en utilise 10 (`energy_production` et
`environmental_service` n'y sont pas). C'est une incohérence existante, hors
périmètre, à signaler.

### 5.2 Existant réutilisable
- `master_nomenclatures` (`crop_sets`, 45 groupes) : Céréales, Céréales à
  paille, Oléagineux, Protéagineux, Légumes, Légumes en maraîchage, Prairie,
  Arboriculture, Plantes aromatiques et médicinales, Cultures tropicales…,
  définis par listes de taxons.
- `registered_phytosanitary_cropsets` (66 groupes E-phy) : Cultures fruitières,
  Cultures légumières, Graminées fourragères, Légumineuses fourragères, Petits
  fruits…
- Productions génériques déjà présentes : `cereal`, `meadow`, `orchard`,
  `oleaginous`, `proteaginous`, `fallow`…
- `master_taxonomy` : genres, familles, classe `aves`.

### 5.3 Filières attendues (vocabulaire rd_agri)

| Filière rd_agri | Mots-clés (nb docs) | Règle d'appartenance pressentie |
|---|---|---|
| Bovin viande | Bovin viande (2 803), Jeunes bovins, Veau de boucherie (170) | taxon `bos` + usage viande |
| Bovin lait | Bovin lait (678), Production laitière (101) | taxon `bos` + usage lait |
| Caprin | Caprin (1 924), Caprins | taxon `capra` |
| Ovin viande / Ovin lait / Ovin | 498 / 357 / 296 | taxon `ovis` (± usage) |
| Porcin | Porcin (595) | taxon `sus` |
| **Volaille** | Volaille (537), Volailles de chair | liste : poulet, poule pondeuse, dinde, pintade, canards, oies, cailles, pigeons… |
| Équin | Equin (138) | taxon `equus` |
| **Grande culture** | Grande culture (929), Céréale | liste ou `crop_sets` (céréales, oléagineux, protéagineux) + génériques `cereal`, `oleaginous`, `proteaginous` |
| **Légume** | Légume (363), Végétal-Maraichage | usage `vegetable` et/ou `crop_sets` légumes |
| **Fruit** | Fruit (258) | usage `fruit` et/ou `crop_sets` arboriculture |
| Vigne | Vigne (486) | taxon `vitis` |
| **Prairie / Fourrages** | Prairie (245), permanente (81), temporaire (66), Fourrages (162), Cultures fourragères (110), Plante fourragère (95) | usage `fodder` / `meadow` + `meadow` |
| **Horticulture** | horticulture (21), horticulteurs, horticole | usage `flower` / `ornamental` |
| Agroforesterie | Agroforesterie (366) | production `agroforestry` |
| ~~Productions animales / végétales~~ | 343 / 532 | **ignorés** (Q16) |

### 5.4 Exigences — datasource `industry_sector`
- **FG1** — Nouvelle datasource v1 `industry_sector`
  (`lib/datasources/industry_sector.rb`), autonome, réutilisable hors rd_agri.
- **FG2** — Référentiel de filières : identifiant (`reference_name`), libellés
  fra/eng via `master_translations`, parent optionnel (hiérarchie).
- **FG3** — Appartenance production ↔ filière en **n-n**, vers
  `master_productions.reference_name`.
- **FG4** — Appartenance déclarée par **règle** (taxon, avec ou sans usage) ou
  par **liste explicite**. Les règles sont résolues à la normalisation, via la
  hiérarchie `master_taxonomy`.
- **FG5** — Définitions versionnées en CSV dans `data/` et relisibles par un
  agronome.
- **FG6** — Contrôles : aucune production inexistante ; chaque filière contient
  au moins une production ; toute production `animal_farming` appartient à au
  moins une filière. Les productions `plant_farming` sans filière sont
  **listées** dans le log, sans faire échouer la normalisation.
- **FG7** — `activity_family` et la nomenclature `activity_families` ne sont pas
  modifiées.

## 6. Chantier « complétion de la taxonomie » (Q15)

### 6.1 Recadrage du périmètre

Les « 86 productions dont l'espèce est absente de `master_taxonomy` » (révision 3)
ne sont **pas des êtres vivants**. Leur colonne `specie` contient des
pseudo-valeurs :

| Famille | `specie` | Exemples |
|---|---|---|
| service_delivering, tool_maintaining, administering | `service` | direct_sale, camping, irrigation, accounting |
| energy_production | `biogas`, `electricity`, `heat` | methanization, photovoltaic |
| environmental_service | `biodiversity`, `carbon`, `water`, `seed` | carbon_credit, natura_2000 |
| processing, wine_making | `milk`, `meat`, `grain`, `fruit`, `wine`… | cheese_making, brewery |

→ **À ne pas ajouter à la taxonomie.** Ces productions sont d'ailleurs exclues
des liaisons rd_agri.

Les **vrais manques** concernent les productions agricoles : **32 productions
`plant_farming` / `animal_farming` sans espèce**.

| Famille | Productions | Taxon candidat | Présent dans `master_taxonomy` |
|---|---|---|---|
| animal | buffalo | *Bubalus bubalis* | ❌ |
| animal | deer / fallow_deer | *Cervus elaphus* / *Dama dama* | ❌ |
| animal | alpaca / llama | *Vicugna pacos* / *Lama glama* | ❌ |
| animal | quail / pigeon | *Coturnix coturnix* / *Columba livia* | ❌ (classe `aves` présente) |
| animal | carp / trout | *Cyprinus carpio* / *Oncorhynchus mykiss* | ❌ |
| animal | insect | classe *Insecta* | ✅ `insecta` |
| animal | earthworm | plusieurs genres (*Eisenia*, *Lumbricus*) | ❌ |
| plant | poplar | *Populus* | ❌ |
| plant | mushroom / oyster_mushroom / shiitake / truffle | *Agaricus bisporus* / *Pleurotus ostreatus* / *Lentinula edodes* / *Tuber melanosporum* | ❌ (**aucun champignon** dans la taxonomie, pas de rang `fungi`) |
| plant | spirulina / seaweed | *Arthrospira platensis* / plusieurs genres | ❌ |
| plant | christmas_tree | *Abies* / *Picea* (plusieurs) | ❌ |
| plant | agroforestry, aquaponics, hydroponics, vertical_farming, cut_flower, edible_flower, energy_wood, forestry, fruit_nursery, seed_cereal, seed_forage, seed_vegetable, vegetable_seedling | **systèmes ou usages**, pas un taxon | — |

Par ailleurs, 28 productions agricoles génériques (`cereal`, `meadow`,
`orchard`, `oleaginous`, `proteaginous`, `fallow`…) pointent volontairement
vers `plant` ou vers une famille (`fabaceae`, `rutaceae`). C'est **correct** :
elles relèvent des filières (§5), pas de la taxonomie.

### 6.2 Exigences — taxonomie
- **TX1** — Ajouter à `data/taxonomy/taxonomy - taxonomy.csv` les taxa manquants
  des productions agricoles **quand un taxon unique existe** : espèce et genre
  parent, famille si absente. Libellés fra/eng.
- **TX2** — Ajouter la branche **champignons** (rang de tête « fungi », au même
  niveau que `plant` et `animal`), nécessaire pour mushroom, oyster_mushroom,
  shiitake et truffle.
- **TX3** — Renseigner `specie` des productions concernées dans
  `data/productions/productions - *_productions.csv`.
- **TX4** — Ne pas inventer de taxon pour les systèmes et usages (agroforestry,
  hydroponics, seed_*…) ni pour les pseudo-espèces (§6.1).
- **TX5** — Productions multi-taxons : rattachement **au genre** (Q18). Genres
  pressentis, à confirmer pendant la conception :
  - christmas_tree → *Abies* (sapin de Nordmann, majoritaire en France) ;
  - earthworm → *Eisenia* (lombriculture) ;
  - seaweed → pas de genre dominant (*Saccharina*, *Undaria*, *Ulva*…) : choisir
    le genre le plus cultivé en France, ou laisser l'espèce vide si aucun ne
    s'impose.
- **TX6** — Contrôle : 0 parent orphelin (déjà vrai aujourd'hui) ; toute
  `specie` de production agricole non vide existe dans `master_taxonomy`.
- **TX7** — Vérifier que les datasources consommatrices de `specie` (variants,
  phytosanitary cropsets, prices…) ne régressent pas.

## 7. Exigences fonctionnelles — datasource `rd_agri`

### Collecte (dépôt manuel)
- **F1** — L'export CSV « Documents » est déposé dans `raw/rd_agri/`.
- **F2** — `collect` repère l'export par son **contenu** (en-têtes, `Type` =
  `Document`), quel que soit le nom du fichier.
- **F3** — Échec explicite (fichier absent, en-têtes inattendus, zéro ligne)
  avec rappel de la procédure.
- **F4** — Procédure d'export documentée dans `doc/`.

### Documents
- **F5** — Parsing CSV strict (BOM, `;`, CRLF, champs multilignes).
- **F6** — Identifiant stable : UUID de `URL de la page`.
- **F7** — Années `0` et `1900` → `NULL` ; dates françaises → `date`.
- **F8** — Publicateurs canoniques (correspondance dans `data/rd_agri/`) ;
  langue normalisée en code ISO.
- **F9** — Description exposée, **HTML retiré** et espaces normalisés.
- **F10** — Aucune limite du nombre de documents par production.

### Règles communes aux liaisons
- **F11** — Canaux : **mots-clés** (correspondance versionnée), **labels
  confirmés** (§3), **titre**.
- **F12** — Comparaison en minuscules, accents conservés, pluriel en `s` toléré,
  libellé le plus long prioritaire.
- **F13** — Chaque liaison indique son canal (`keyword` / `label` / `title` /
  `project_code` / `organism`).
- **F14** — Overrides manuels (ajout ou exclusion) prioritaires, et liste
  d'exclusion de termes ambigus, dans `data/rd_agri/`.

### Liaison document → production
- **F15** — Relation n-n vers `master_productions.reference_name`.
- **F16** — Mots-clés résolus via **`industry_sector`** (§5) : une filière est
  liée à toutes ses productions (Q10). Sinon égalité directe avec un libellé
  de production. Les mots-clés « Productions animales » et « Productions
  végétales » sont **ignorés** (Q16).
- **F17** — Labels et titre comparés aux libellés de production et de taxon
  (rangs genre, espèce, variété), résolus via `master_taxonomy`.
- **F18** — Seules les familles `plant_farming`, `animal_farming` et
  `vine_farming` peuvent être liées.

### Liaison document → zone administrative
- **F19** — Relation n-n vers `registered_administrative_areas` (région ou
  département), par préfixe du code projet GIEE, organismes, puis titre (§4.2).

### Liaison document → système de production
- **F20** — Relation n-n vers les entrées `production_systems` de
  `master_nomenclatures` (agriculture biologique, de conservation…).

### Liaison document → ravageur / maladie
- **F21** — Relation n-n vers les cibles phytosanitaires
  (`target_name_label_fra`, cibles PFI) et vers `issue_natures`, avec leur
  provenance.
- **F22** — **Seuls les bioagresseurs nommés** sont liés (pucerons, thrips,
  fusariose, rouille jaune, flavescence dorée, mammite…). Les catégories
  d'usage (« fongicide », « insecticide », « désherbage », « adventices »,
  « désinfection », « Stimul. Déf. Plantes »…) sont exclues par une liste
  versionnée dans `data/rd_agri/` (Q17).

### Données exclues
- **F23** — Non exposés : `Auteurs`, `Organisme(s)` bruts, `Format`, labels bruts.
- **F24** — Pas de liaison vers intervention_models, phenological_stages,
  seed_varieties, produits phyto commerciaux, quality_and_origin_signs,
  vine_varieties, natural_zones, OTEX, enterprises.

### Packaging
- **F25** — `credits` : « Plateforme R&D Agricole », `https://rd-agri.fr`,
  provider « rd-agri (ACTA) », licence `CC BY-NC-SA 4.0`, licence_url
  `https://creativecommons.org/licenses/by-nc-sa/4.0/deed.fr`, `updated_at` = date
  de l'export.
- **F26** — `table_definitions` avec `references` vers `master_productions`,
  `registered_administrative_areas` et les tables de `industry_sector`.
  `./lexicon validate` passe.

## 8. Exigences non fonctionnelles

- **NF1 — Ordre d'exécution** : `taxonomy` → `productions` → **`industry_sector`** →
  `administrative_areas`, `open_nomenclature`, `phytosanitary` → `rd_agri`.
  Chaque datasource échoue si l'une de ses dépendances est vide.
- **NF2 — Intégrité** : aucune liaison vers une entrée inexistante.
- **NF3 — Volume** : pas de labels bruts (291 Mo) dans le package ;
  descriptions incluses (≈ 18 Mo avant compression).
- **NF4 — Idempotence** : un même export produit les mêmes liaisons.
- **NF5 — Traçabilité** : date d'export et canal de chaque liaison conservés.
- **NF6 — Maintenabilité** : toutes les correspondances et exclusions sont des
  CSV dans `data/`.
- **NF7 — Performance** : `normalize` de l'ordre de la minute.
- **NF8 — Conformité** : ni PDF ni fichier source redistribués ; pas de données
  nominatives.

## 9. User stories et critères d'acceptation

**US1 — Mainteneur Lexicon**
- [ ] `./lexicon run taxonomy productions industry_sector rd_agri` passe après dépôt de l'export
- [ ] ≥ 40 000 documents, identifiant unique et non nul pour 100 %
- [ ] **≥ 40 % des documents liés à au moins une production** (mesuré avant filières : 41 %)
- [ ] 0 liaison vers une entrée inexistante
- [ ] ni `Auteurs` ni labels bruts dans le package
- [ ] `./lexicon validate` et `./bin/rubocop` passent

**US2 — Utilisateur Ekylibre, par production**
- [ ] « Bovin viande » donne tous les documents liés aux productions bovines d'usage viande
- [ ] Volaille, Grande culture, Légume, Fruit, Prairie ont des documents liés via `industry_sector`
- [ ] aucune liaison issue des mots-clés « Productions animales » ou « Productions végétales »
- [ ] **précision ≥ 90 %** sur 50 liaisons tirées au hasard **par canal**
- [ ] document affiché : titre, année, publicateur canonique, description, lien, « Source : rd-agri — CC BY-NC-SA 4.0 »

**US3 — Utilisateur Ekylibre, par région**
- [ ] les 13 régions métropolitaines ont des documents liés
- [ ] précision ≥ 90 % sur 50 liaisons par canal (`project_code`, `organism`, `title`)

**US4 — Utilisateur Ekylibre, bio et bioagresseurs**
- [ ] ≥ 1 400 documents liés à « agriculture biologique »
- [ ] précision ≥ 90 % sur 50 liaisons ravageur/maladie
- [ ] aucune liaison vers une catégorie d'usage (fongicide, insecticide, désherbage, adventices…)

**US5 — Mainteneur taxonomie / filières**
- [ ] toute production `animal_farming` a une espèce existante **ou** appartient à une filière
- [ ] mushroom, oyster_mushroom, shiitake, truffle rattachés à une branche champignons
- [ ] christmas_tree et earthworm rattachés à un genre
- [ ] aucune régression sur `variants`, `phytosanitary`, `prices` (`./lexicon validate`, décomptes avant/après)

## 10. Questions ouvertes

Aucune question bloquante. Points à trancher pendant la conception :

| # | Point | Chantier |
|---|---|---|
| D1 | Genre retenu pour `seaweed` (TX5) | Taxonomie |
| D2 | Règle d'appartenance de chaque filière : taxon + usage, `crop_sets` ou liste explicite (§5.3) | `industry_sector` |
| D3 | Liste exacte des catégories d'usage phyto à exclure (F22) et nouvelle mesure de la couverture ravageurs/maladies | rd_agri |
| D4 | Liste d'exclusion des noms de zones ambigus (« Rhône », « Nord »…) | rd_agri |

## 11. Découpage (3 chantiers, dans l'ordre des dépendances)

1. **Taxonomie + productions** (§6) : ajout des taxons manquants et de la
   branche champignons, `specie` des 32 productions agricoles.
2. **Datasource `industry_sector`** (§5) : nouvelle, réutilisable.
3. **Datasource `rd_agri`** (§7) : consomme 1 et 2.

## 12. Hors périmètre

- U2 projets et financements, U3 corpus `lexicon-ai`, organismes → SIRENE,
  jeux de données.
- Thèmes techniques (intervention_models, `procedure_*`) : exclus par Q13.
- Mots-clés « Productions animales » / « Productions végétales » : ignorés (Q16).
- Correction de la nomenclature `activity_families` (8 valeurs contre 10
  utilisées).
- Étiquetage par LLM des documents non liés.

## 13. Prochaines étapes

1. `/sc:design` : chantier 1 (taxonomie), puis 2 (`industry_sector`), puis 3 (`rd_agri`).
2. `/sc:implement`, puis revues de précision (US2 à US4).
