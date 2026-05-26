# Workflow — Intégration `data/productions/suggestions.csv` dans les fichiers de productions

**Stratégie :** systematic · **Profondeur :** deep · **Cible :** dispatcher 151 suggestions dans les fichiers `data/productions/productions - <slug>_productions.csv`
**Date :** 2026-05-22 · **Auteur du plan :** Claude (sc:workflow)

> ⚠️ Ce document est un **plan d'implémentation uniquement**. Aucun code/CSV n'est écrit à ce stade. Utiliser `/sc:implement` après revue (et validation des questions ouvertes §2).

---

## 1. Contexte & Intention

Le fichier `data/productions/suggestions.csv` propose **151 productions** à ajouter au référentiel `master_productions`. Elles sont déjà pré-classées dans 7 catégories (colonne `categorie_cible`). Le but est de :

1. **Dispatcher** chaque ligne vers le fichier `data/productions/productions - <categorie>.csv` correspondant.
2. **Enrichir** chaque ligne avec les colonnes manquantes du schéma cible (qui en compte 14, vs 7 dans suggestions).
3. **Compléter la colonne `specie`** en interrogeant `master_taxonomy` pour les productions animales et végétales.

### Distribution des suggestions

| `categorie_cible` | Lignes | Fichier cible | Existe ? |
|---|---|---|---|
| `animal_productions` | 48 | `productions - animal_productions.csv` | ✅ (5 lignes) |
| `auxiliary_productions` | 16 | `productions - auxiliary_productions.csv` | ✅ (2 lignes) |
| `crop_productions` | 22 | `productions - crop_productions.csv` | ✅ (centaines) |
| `processing_productions` | 26 | `productions - processing_productions.csv` | ✅ (5 lignes) |
| `service_productions` | 24 | `productions - service_productions.csv` | ✅ (3 lignes) |
| `energy_productions` | 9 | `productions - energy_productions.csv` | ❌ **à créer** |
| `environmental_productions` | 6 | `productions - environmental_productions.csv` | ❌ **à créer** |

### Schéma cible (rappel)

```
reference_name, activity_family, fra, eng, specie, usage,
started_on, stopped_on, agroedi_crop_code, season, life_duration,
idea_botanic_family, idea_specie_family, idea_output_family [, color]
```

(La colonne `color` existe uniquement dans `crop_productions.csv`.)

### Schéma source (suggestions.csv)

```
categorie_cible, sous_categorie, reference_name, fra, eng, usage, justification
```

Le mapping de base : `reference_name`, `fra`, `eng`, `usage` se copient ; `justification` se jette ; `sous_categorie` est indicatif (ne se mappe pas directement à `activity_family`) ; les **7 colonnes manquantes** se génèrent.

---

## 2. Questions ouvertes (à trancher avant `/sc:implement`)

### Q1. Que faire des 15 lignes `energy_productions` + `environmental_productions` ?

**Trois options** :

- **A. Créer deux nouveaux fichiers** `productions - energy_productions.csv` et `productions - environmental_productions.csv`, et étendre `lib/datasources/productions.rb` pour les charger.
  - **Avantages** : fidèle à l'intention `selon la première colonne du fichier`. Catégories cohérentes pour future évolution (méthanisation, agrivoltaïque, crédits carbone sont structurellement distincts).
  - **Coût** : ~25 lignes à ajouter dans `productions.rb` (load + 2× `INSERT INTO master_productions` + 2× `insert_translations`), + une décision sur les nouveaux `activity_family` slugs.
  - **Recommandation par défaut** ⭐.

- **B. Remapper dans les fichiers existants** :
  - `energy_productions` → vers `auxiliary_productions` (méthanisation, photovoltaïque = équipements d'exploitation) avec `activity_family = 'energy_production'` (nouveau slug).
  - `environmental_productions` → vers `service_productions` (crédits carbone, Natura 2000 = services rémunérés) avec `activity_family = 'environmental_service'` (nouveau slug).
  - **Avantages** : zéro modification de `productions.rb`, intégration plus rapide.
  - **Coût** : sémantique discutable — l'agrivoltaïsme n'est pas vraiment un service.

- **C. Différer** : commenter les 15 lignes en `# TODO` dans suggestions.csv, traiter dans un workflow séparé.

> **Question pour l'utilisateur** : on retient A, B, ou C ? On retient **A**.

### Q2. Comment résoudre les `usage` non standard ?

Le référentiel existant utilise un vocabulaire restreint :
`flower, fodder, fruit, grain, meadow, meat, milk, plant, seed, vegetable, wood`.

`suggestions.csv` introduit ~30 nouveaux usages : `egg, reproduction, foie_gras, honey_pollination, wool, work, leisure, catering, lodging, retail, service, biogas, carbon, biodiversity, cosmetic, kombucha`, etc.

**Trois options** :

- **A. Conserver les usages de suggestions tels quels** — élargir de facto le vocabulaire. La colonne `usage` n'a pas de contrainte SQL (cf. `master_productions.usage character varying`), donc rien ne casse.
- **B. Mapper sur le vocabulaire existant** — perte d'information (p. ex. `foie_gras` → `meat`, `honey_pollination` → vide).
- **C. Hybride** : conserver les usages parlants (`milk, meat, egg, honey, wool`) et neutraliser les autres en `service` ou vide pour les non-cultures.

> **Recommandation par défaut** ⭐ : **A** — élargir le vocabulaire en gardant les valeurs de suggestions, sauf normalisation triviale (`honey_pollination` → `honey`, `milk_meat` → choisir l'un selon la sous-catégorie ; cf. table d'attribution §4.2).

### Q3. Précision attendue pour la colonne `specie` ?

L'utilisateur a écrit *« complete les colonnes manquantes avec la table master_taxonomy pour la colonne varieties »*. Il n'y a pas de colonne `varieties` dans le schéma des productions — la colonne taxonomique est **`specie`**. On retient :

- Pour animaux/plantes : valeur tirée de `master_taxonomy.reference_name` (rang `specie` de préférence, sinon `genus`).
- Pour services/processing/auxiliaire/énergie/environnement : valeur littérale (`service`, `meat`, `milk`, `biogas`, etc.) **non rattachée** à `master_taxonomy`. C'est cohérent avec l'existant (`master_productions.specie` n'a pas de FK sur `master_taxonomy`).
- Pour les rares espèces **manquantes** dans `master_taxonomy` (cf. liste §4.4) : laisser `specie` à vide et flagger via TODO en commentaire de PR — l'ajout dans `master_taxonomy` est hors scope.

> **Recommandation par défaut** ⭐ : appliquer la table §4 telle quelle.

### Q4. Doublons potentiels ?

Quelques `reference_name` de suggestions sont déjà présents en BD :

| Suggestion | Existe déjà ? |
|---|---|
| `mushroom` (Champignons de Paris) | À vérifier dans `crop_productions.csv` (le commentaire suggère que `truffle` existe dans `wood` — donc renommage potentiel) |
| `forestry` | Possiblement présent (commentaire « plus large que 'wood' ») |
| `truffle` | Suggestions dit « existe en 'wood' mais à scinder » |

> **Action** : §5.1 vérifie chaque `reference_name` contre les fichiers cibles avant insertion. Doublons = à examiner cas par cas (mise à jour vs nouvelle ligne).

---

## 3. Architecture cible

### 3.1 Fichiers à modifier / créer

| Action | Chemin | Rôle |
|---|---|---|
| **Modifier** | `data/productions/productions - animal_productions.csv` | +48 lignes |
| **Modifier** | `data/productions/productions - crop_productions.csv` | +22 lignes |
| **Modifier** | `data/productions/productions - processing_productions.csv` | +26 lignes |
| **Modifier** | `data/productions/productions - service_productions.csv` | +24 lignes |
| **Modifier** | `data/productions/productions - auxiliary_productions.csv` | +16 lignes |
| **Créer (Q1.A)** | `data/productions/productions - energy_productions.csv` | 9 lignes + en-tête |
| **Créer (Q1.A)** | `data/productions/productions - environmental_productions.csv` | 6 lignes + en-tête |
| **Modifier (Q1.A)** | `lib/datasources/productions.rb` | +load_csv ×2, +INSERT INTO master_productions ×2, +insert_translations ×2, +DELETE FROM master_translations ×2 |
| **Supprimer** | `data/productions/suggestions.csv` | Une fois dispatché, le fichier n'a plus de raison d'être commité (ou le déplacer dans `doc/` comme archive) |

### 3.2 Modifications nécessaires dans `lib/datasources/productions.rb` (si Q1.A)

Trois zones à compléter (numéros de lignes actuels) :

- **Ligne 41-45** (load) : ajouter
  ```ruby
  load_csv(dir.join('productions - energy_productions.csv'), 'energy_productions')
  load_csv(dir.join('productions - environmental_productions.csv'), 'environmental_productions')
  ```

- **Ligne 174-178** (delete translations) :
  ```ruby
  query "DELETE FROM master_translations WHERE id LIKE 'energy_productions%'"
  query "DELETE FROM master_translations WHERE id LIKE 'environmental_productions%'"
  ```

- **Lignes 186-215** (normalize INSERT) : ajouter 2 blocs `INSERT INTO master_productions` calqués sur le pattern auxiliary/service (sans `agroedi_crop_code`, `season`, `idea_*`, `color`).

- **Lignes 222-226** (translations) :
  ```ruby
  insert_translations('productions', 'energy_productions', 'energy_productions')
  insert_translations('productions', 'environmental_productions', 'environmental_productions')
  ```

- **Commentaire de classification ligne 180-184** (mise à jour) : ajouter
  ```
  # energy_productions => energy_production
  # environmental_productions => environmental_service, environmental_credit
  ```

### 3.3 Conventions de remplissage (colonnes générées)

| Colonne cible | Source / Règle |
|---|---|
| `reference_name` | `suggestions.reference_name` (copie directe) |
| `activity_family` | Selon table §4.1 |
| `fra` | `suggestions.fra` (copie directe) |
| `eng` | `suggestions.eng` (copie directe) |
| `specie` | Selon tables §4.2 / §4.3 (lookup master_taxonomy ou valeur littérale) |
| `usage` | Selon table §4.2 (le plus souvent = `suggestions.usage`, sinon mappé) |
| `started_on` | `01/09/00` (animaux/cultures pluriannuelles) sinon `01/01/00` |
| `stopped_on` | `31/08/01` (animaux/cultures pluriannuelles) sinon `31/12/00` |
| `agroedi_crop_code` | vide |
| `season` | vide |
| `life_duration` | `20` (défaut) — sauf cas explicites (`piglet`=1, `lamb`=1, `broiler_chicken`=1, `laying_hen`=2, `rabbit`=1, etc.) ; cf. §4.5 |
| `idea_botanic_family`, `idea_specie_family`, `idea_output_family` | vide |
| `color` (crop only) | vide |

---

## 4. Tables d'attribution prescrites

### 4.1 `activity_family` par catégorie

| Catégorie source | `activity_family` à appliquer | Note |
|---|---|---|
| `animal_productions` | `animal_farming` | uniforme |
| `crop_productions` (mycélium, algues, fleurs, sylviculture, semences, plants) | `plant_farming` | uniforme, sauf cas vine_nursery → `vine_farming` |
| `processing_productions` (boissons alcoolisées) | `wine_making` pour `brewery, cidery, distillery` ; `processing` pour le reste |
| `service_productions` | `service_delivering` | uniforme |
| `auxiliary_productions` (gestion) | `administering` | accounting, commercial_management, human_resources, regulatory_compliance |
| `auxiliary_productions` (travaux/stockage/infra/R&D) | `tool_maintaining` | tout le reste |
| `energy_productions` (Q1.A) | `energy_production` | **nouveau slug** |
| `environmental_productions` (Q1.A) | `environmental_service` | **nouveau slug** |

### 4.2 Mapping ligne-par-ligne pour `animal_productions` (48 lignes)

| ref_name | sous_cat | specie | usage | life_dur |
|---|---|---|---|---|
| milk_ewe | Ovins | `ovis_aries` | milk | 7 |
| meat_ewe | Ovins | `ovis_aries` | meat | 7 |
| lamb | Ovins | `ovis_aries` | meat | 1 |
| ram | Ovins | `ovis_aries` | reproduction | 8 |
| milk_goat | Caprins | `capra_hircus` | milk | 8 |
| meat_goat | Caprins | `capra_hircus` | meat | 8 |
| kid | Caprins | `capra_hircus` | meat | 1 |
| buck | Caprins | `capra_hircus` | reproduction | 8 |
| sow | Porcins | `sus_scrofa` | reproduction | 5 |
| piglet | Porcins | `sus_scrofa` | meat | 1 |
| fattening_pig | Porcins | `sus_scrofa` | meat | 1 |
| boar | Porcins | `sus_scrofa` | reproduction | 5 |
| laying_hen | Volailles | `gallus_gallus` | egg | 2 |
| broiler_chicken | Volailles | `gallus_gallus` | meat | 1 |
| turkey | Volailles | `meleagris_gallopavo` | meat | 1 |
| duck_meat | Volailles | `anas_platyrhynchos` | meat | 1 |
| fattened_duck | Volailles | `anas_platyrhynchos` | foie_gras | 1 |
| goose | Volailles | `anser_anser` | meat | 1 |
| guinea_fowl | Volailles | `numida_meleagris` | meat | 1 |
| quail | Volailles | **(vide — manquant)** | meat | 1 |
| pigeon | Volailles | **(vide — manquant)** | meat | 1 |
| rabbit | Cuniculture | `oryctolagus_cuniculus` | meat | 1 |
| doe_rabbit | Cuniculture | `oryctolagus_cuniculus` | reproduction | 3 |
| draft_horse | Équins | `equus_caballus` | work | 20 |
| saddle_horse | Équins | `equus_caballus` | leisure | 20 |
| race_horse | Équins | `equus_caballus` | race | 20 |
| pony | Équins | `equus_caballus` | leisure | 20 |
| donkey | Équins | `equus_asinus` | work | 20 |
| beehive | Apiculture | `apis_mellifera` | honey | 5 |
| queen_bee | Apiculture | `apis_mellifera` | reproduction | 3 |
| trout | Aquaculture | **(vide — manquant)** | fish | 3 |
| carp | Aquaculture | **(vide — manquant)** | fish | 4 |
| sturgeon | Aquaculture | `acipenser` | caviar | 10 |
| salmon | Aquaculture | `salmo_salar` | fish | 3 |
| oyster | Conchyliculture | `crassostrea_gigas` | shellfish | 3 |
| mussel | Conchyliculture | `mytilus_edulis` | shellfish | 2 |
| scallop | Conchyliculture | `pecten_maximus` | shellfish | 3 |
| deer | Cervidés | **(vide — manquant)** | meat | 5 |
| fallow_deer | Cervidés | **(vide — manquant)** | meat | 5 |
| snail | Élevages spécialisés | `helix_aspersa` | meat | 1 |
| insect | Élevages spécialisés | **(vide — manquant)** | protein | 1 |
| earthworm | Élevages spécialisés | **(vide — manquant)** | compost | 1 |
| alpaca | Camélidés | **(vide — manquant)** | wool | 15 |
| llama | Camélidés | **(vide — manquant)** | wool | 15 |
| ostrich | Ratites | `struthio_camelus` | meat | 15 |
| buffalo | Autres | **(vide — manquant)** | milk | 15 |
| bull | Bovins (compl.) | `bos_taurus` | reproduction | 8 |
| dairy_heifer | Bovins (compl.) | `bos_taurus` | milk | 3 |

**Espèces manquantes dans `master_taxonomy`** (8 lignes) → `specie` vide + commentaire `# TODO: add to master_taxonomy`. Liste : `coturnix_coturnix` (quail), `columba_livia` (pigeon), `oncorhynchus_mykiss` (trout), `cyprinus_carpio` (carp), `cervus_elaphus` (deer), `dama_dama` (fallow_deer), `tenebrio_molitor` (insect — peut être tout autre ordre), `lumbricidae` (earthworm), `vicugna_pacos` (alpaca), `lama_glama` (llama), `bubalus_bubalis` (buffalo). À ajouter dans une mise à jour séparée du datasource `taxonomy`.

> Tous les usages ci-dessus (`work`, `leisure`, `race`, `egg`, `foie_gras`, `caviar`, `fish`, `shellfish`, `protein`, `compost`, `wool`, `honey`) **n'existent pas** dans le vocabulaire actuel. Conservés tels quels selon décision Q2.A.

### 4.3 Mapping ligne-par-ligne pour `crop_productions` (22 lignes)

| ref_name | sous_cat | specie | usage |
|---|---|---|---|
| mushroom | Cultures spécialisées | **(vide — `agaricus_bisporus` manquant)** | vegetable |
| shiitake | Cultures spécialisées | **(vide — `lentinula_edodes` manquant)** | vegetable |
| oyster_mushroom | Cultures spécialisées | **(vide — `pleurotus_ostreatus` manquant)** | vegetable |
| truffle | Cultures spécialisées | **(vide — `tuber_melanosporum` manquant)** | fruit |
| spirulina | Cultures spécialisées | **(vide — `arthrospira_platensis` manquant)** | alga |
| seaweed | Cultures spécialisées | **(vide — multiples espèces)** | alga |
| edible_flower | Cultures spécialisées | vide | flower |
| cut_flower | Cultures spécialisées | vide | flower |
| aquaponics | Systèmes innovants | vide | vegetable |
| hydroponics | Systèmes innovants | vide | vegetable |
| vertical_farming | Systèmes innovants | vide | vegetable |
| agroforestry | Systèmes innovants | vide | mixed |
| forestry | Sylviculture | vide | wood |
| christmas_tree | Sylviculture | vide | ornamental |
| poplar | Sylviculture | `populus` (genre) si présent, sinon vide | wood |
| energy_wood | Sylviculture | vide | wood_energy |
| seed_cereal | Semences | vide | seed |
| seed_vegetable | Semences | vide | seed |
| seed_forage | Semences | vide | seed |
| vine_nursery | Plants/pépinières | `vitis_vinifera` (à vérifier) | plant |
| fruit_nursery | Plants/pépinières | vide | plant |
| vegetable_seedling | Plants/pépinières | vide | plant |

> Pour `mushroom`, `truffle`, `forestry` — vérifier en §5.1 s'ils sont déjà présents dans `crop_productions.csv` ; si oui, ajuster le `reference_name` ou mettre à jour la ligne existante au lieu d'ajouter.

### 4.4 Mapping `processing_productions` (26 lignes)

`specie` = la matière première traitée (string littérale, pas FK master_taxonomy). `activity_family` = `wine_making` pour les boissons alcoolisées fermentées, sinon `processing`.

| ref_name | sous_cat | specie | usage | activity_family |
|---|---|---|---|---|
| cheese_making | Transformation lait | milk | cheese | processing |
| yogurt_making | Transformation lait | milk | yogurt | processing |
| butter_making | Transformation lait | milk | butter | processing |
| ice_cream_making | Transformation lait | milk | ice_cream | processing |
| charcuterie | Transformation viande | meat | cured_meat | processing |
| cutting_workshop | Transformation viande | meat | meat_cut | processing |
| canning_meat | Transformation viande | meat | canned_meat | processing |
| canning_vegetable | Transformation végétale | vegetable | canned_vegetable | processing |
| jam_making | Transformation végétale | fruit | jam | processing |
| juice_making | Transformation végétale | fruit | juice | processing |
| drying_workshop | Transformation végétale | plant | dried_product | processing |
| oil_press | Transformation végétale | seed | oil | processing |
| flour_mill | Transformation végétale | grain | flour | processing |
| bakery | Transformation végétale | grain | bread | processing |
| pastry | Transformation végétale | grain | pastry | processing |
| brewery | Boissons | grain | beer | wine_making |
| cidery | Boissons | fruit | cider | wine_making |
| distillery | Boissons | wine | spirit | wine_making |
| vinegar_making | Boissons | wine | vinegar | processing |
| kombucha_kefir | Boissons | plant | fermented_drink | processing |
| honey_house | Apiculture | honey | honey | processing |
| soap_making | Cosmétique/artisanat | milk | soap | processing |
| essential_oil | Cosmétique/artisanat | plant | essential_oil | processing |
| cosmetic_workshop | Cosmétique/artisanat | plant | cosmetic | processing |
| legume_processing | Légumineuses/céréales | grain | legume_product | processing |
| pasta_making | Légumineuses/céréales | grain | pasta | processing |

### 4.5 Mapping `service_productions` (24 lignes), `auxiliary_productions` (16 lignes), `energy_productions` (9 lignes), `environmental_productions` (6 lignes)

Pour ces 55 lignes, **règle uniforme** :
- `specie` = `service` (sauf `methanization`/`digestate`/`biofuel` → `biogas` ; `photovoltaic`/`wind_turbine`/`micro_hydro` → `electricity` ; `solar_thermal`/`biomass_boiler` → `heat` ; `carbon_credit` → `carbon` ; `biodiversity_credit`/`natura_2000`/`wildlife_area` → `biodiversity` ; `water_payment` → `water` ; `seed_conservation` → `seed`).
- `usage` = valeur de `suggestions.usage` telle quelle.
- `started_on=01/01/00`, `stopped_on=31/12/00`, `life_duration=20`.
- `activity_family` selon table §4.1.

Tableau exhaustif ligne par ligne dans l'annexe `claudedocs/workflow_productions_suggestions_appendix.md` (à générer pendant `/sc:implement` si besoin pour revue).

### 4.6 Durées de vie (`life_duration`) à appliquer

Par défaut **20 ans** pour tout ce qui n'est pas un animal. Pour les animaux, valeurs proposées (en années) :

| Catégorie | Animaux d'abattage (cycle court) | Animaux de production (cycle long) | Reproducteurs |
|---|---|---|---|
| Bovins | calf, lamb, kid, piglet, broiler, duck_meat, rabbit, turkey: **1** | milk_cow, milk_ewe, milk_goat: 7-8 ; dairy_heifer: 3 | bull, ram, buck, boar: 5-8 |
| Volailles | 1-2 | laying_hen: 2 | queen_bee: 3 |
| Apiculture | — | beehive: 5 | — |
| Aquaculture | trout, salmon, oyster, scallop: 2-3 | sturgeon: 10 | — |
| Équins | — | 20 | — |
| Grands gibiers | — | deer, fallow_deer, alpaca, llama, ostrich, buffalo: 15 | — |

---

## 5. Plan d'exécution séquentiel (pour `/sc:implement`)

| # | Phase | Action | Validation |
|---|---|---|---|
| 1 | **Vérif. préalable** | Pour chaque `reference_name` dans suggestions, vérifier l'absence dans le fichier cible (`grep -F "<ref_name>," "data/productions/productions - <cat>.csv"`). Lister les doublons éventuels. | Aucun doublon (ou décision documentée pour chacun). |
| 2 | **Vérif. taxonomy** | Pour chaque ligne du mapping §4.2/§4.3 prévue avec specie non vide, vérifier : `SELECT 1 FROM lexicon.master_taxonomy WHERE reference_name = '<specie>';`. | 100 % des specie non vides existent en BD. |
| 3 | **Décision Q1** | Si Q1.A retenu : créer les deux fichiers vides avec en-tête (14 colonnes, comme animal_productions). | Fichiers créés. |
| 4 | **Append CSV** | Ajouter les lignes en respectant les tables §4 et l'ordre alphabétique de `reference_name` au sein de chaque fichier. **Conserver les en-têtes existants**. Pour `crop_productions.csv` : 15 colonnes (avec `color` vide pour les 22 ajouts). | `wc -l` correspond aux deltas attendus. |
| 5 | **Datasource (Q1.A)** | Modifier `lib/datasources/productions.rb` selon §3.2. | `./lexicon list` montre toujours `productions`. |
| 6 | **Run pipeline** | `./lexicon run productions` | Collect/Load/Normalize OK. |
| 7 | **Validation BD** | Cf. assertions §6. | Tous les checks passent. |
| 8 | **Archive** | Soit supprimer `data/productions/suggestions.csv`, soit le déplacer vers `doc/archive/2026-05-22_productions_suggestions.csv`. | Fichier ne traîne plus dans `data/productions/` (sinon il sera chargé par le `Dir.glob('*.csv')` du collect — cf. `productions.rb:34`). |
| 9 | **Flavors** | Vérifier si les flavors `light`, `cultia`, `test` ont des filtres sur `master_productions` qui pourraient masquer les ajouts. Cf. `resources/flavors/test.yml:productions`. | Aucun ajustement nécessaire OU patch documenté. |

**⚠️ Critique — étape 8** : `productions.rb:34` fait `FileUtils.cp Dir.glob('data/productions/*.csv'), dir`, donc **suggestions.csv sera copié dans raw/** s'il reste dans data/. Pas grave en soi (rien ne le charge), mais c'est un fichier orphelin. À nettoyer.

---

## 6. Assertions de validation (étape §5.7)

```sql
-- 1. Comptes attendus dans master_productions par activity_family
SELECT activity_family, COUNT(*) FROM lexicon.master_productions GROUP BY activity_family ORDER BY 1;
-- attendu (variations possibles selon état actuel) :
-- animal_farming                +48
-- plant_farming, vine_farming   +22 (sauf vine_nursery → vine_farming)
-- processing, wine_making       +26
-- service_delivering            +24
-- administering, tool_maintaining +16
-- energy_production             +9      (si Q1.A)
-- environmental_service         +6      (si Q1.A)

-- 2. Specie cohérent quand renseigné — pour les productions animales seulement
SELECT mp.reference_name, mp.specie
  FROM lexicon.master_productions mp
  LEFT JOIN lexicon.master_taxonomy mt ON mt.reference_name = mp.specie
  WHERE mp.activity_family = 'animal_farming'
    AND mp.specie IS NOT NULL
    AND mt.reference_name IS NULL;
-- attendu : 0 lignes. Toute ligne retournée = specie référencé inexistant en taxonomy → corriger.

-- 3. Aucun reference_name dupliqué
SELECT reference_name, COUNT(*) FROM lexicon.master_productions GROUP BY reference_name HAVING COUNT(*) > 1;
-- attendu : 0 lignes (sinon il faudra arbitrer le doublon — cf. §5.1).

-- 4. Toutes les nouvelles entrées ont une translation
SELECT mp.reference_name
  FROM lexicon.master_productions mp
  LEFT JOIN lexicon.master_translations mt ON mt.id = mp.translation_id
  WHERE mt.id IS NULL
    AND mp.reference_name IN ('milk_ewe', 'cheese_making', 'farm_inn', 'methanization');
-- attendu : 0 lignes.

-- 5. Dates valides
SELECT reference_name, started_on, stopped_on FROM lexicon.master_productions
  WHERE started_on IS NULL OR stopped_on IS NULL OR stopped_on < started_on;
-- attendu : 0 lignes.

-- 6. life_duration cohérent pour les jeunes animaux d'abattage
SELECT reference_name, life_duration FROM lexicon.master_productions
  WHERE reference_name IN ('lamb', 'kid', 'piglet', 'broiler_chicken', 'duck_meat', 'rabbit', 'turkey')
    AND life_duration > '2 years'::INTERVAL;
-- attendu : 0 lignes (sinon cycle de vie incohérent).
```

---

## 7. Risques & points d'attention

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Doublons silencieux (`mushroom`, `forestry`, `truffle`) faisant échouer le PRIMARY KEY de `master_productions` | Élevée | Élevé (normalize échoue, rollback) | Étape §5.1 obligatoire avant insertion |
| Espèces manquantes dans master_taxonomy (~13 cas) | Certain | Faible | `specie` laissé NULL (la colonne est nullable). Ajout taxonomy dans un workflow séparé. |
| Format de date hétérogène | Faible | Moyen | `TO_DATE('01/09/00', 'DD/MM/YY')` accepte le format ; vérifier via assertion #5 |
| Le `Dir.glob` du collect copiera suggestions.csv si laissé en place | Certain | Faible | Étape §5.8 (déplacer/supprimer) |
| Nouveau slug `activity_family = energy_production` / `environmental_service` peut casser un consommateur ERP côté Ekylibre qui filtre sur une whitelist | Faible | Moyen | Coordonner avec l'équipe ERP avant merge si Q1.A retenu |
| Le `usage` vocabulaire élargi peut surprendre l'ERP s'il a une whitelist côté frontal | Moyenne | Faible | Documenter les nouveaux usages dans le CHANGELOG ou la description du package |

---

## 8. Hors scope

- ❌ Ajout des espèces manquantes (`oncorhynchus_mykiss`, `agaricus_bisporus`, etc.) dans le datasource `taxonomy`. À traiter dans `/sc:workflow taxonomy_expansion` séparé.
- ❌ Refonte du vocabulaire `usage` (passage à une table contrôlée).
- ❌ Migration des entrées existantes (p. ex. déplacer `truffle` de `wood` à `fruit`) — si conflit détecté §5.1, on n'écrase pas l'existant sans accord explicite.
- ❌ Création d'une UI ou d'un mapping côté Ekylibre pour exposer ces nouvelles productions.
- ❌ Vérification métier (un expert agricole doit valider la cohérence des `life_duration` proposés).

---

## 9. Prochaine étape

1. **Trancher les questions §2** (Q1, Q2, Q3, Q4) — surtout Q1 (créer ou non les 2 nouveaux fichiers).
2. Lancer `/sc:implement claudedocs/workflow_productions_suggestions.md`.
3. L'implémenteur procédera dans cet ordre : vérif doublons (§5.1) → écriture CSV (§5.4) → datasource si Q1.A (§5.5) → run pipeline (§5.6) → assertions (§6) → nettoyage (§5.8).
4. Commit groupé avec message reflétant la portée (`feat(productions): add 151 entries from suggestions.csv across 7 categories`).
