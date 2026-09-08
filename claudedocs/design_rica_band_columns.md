# Correction — `registered_rica_holdings` : colonnes de tranche promues en numérique

> **Bug de données confirmé**, présent sur les 9 millésimes livrés (2016→2024, 65 535
> lignes). Datasource `rica` — `lib/datasources/rica.rb:234-235`.
> Consommateur impacté connu : `cultia_back` (`app/services/rica/similarity.py`).
> Contexte d'origine : [`workflow_rica_datasource.md`](workflow_rica_datasource.md).

---

## 1. Le bug

`insert_holdings` promeut deux variables du fichier micro-données en colonnes typées :

```ruby
# lib/datasources/rica.rb:234-235
NULLIF(t.sauti, '')::numeric(14,2),   -- → sau_ha
NULLIF(t.sutot, '')::numeric(14,2),   -- → total_area_ha
```

`SAUTI` et `SUTOT` **ne sont pas des surfaces**. Dans le Fichier Micro-Données (FMD), qui
est une publication **anonymisée**, ce sont des **codes de tranche ordinaux**. Le
dictionnaire livré dans le même dossier le dit explicitement :

```
2024,SAUTI,SAU totale (tranche),caractères,
2024,SUTOT,Superficie totale (SAU et hors SAU) (tranche),caractères,
```

`caractères` — pas `numérique`. Le cast en `numeric(14,2)` réussit sans erreur parce qu'un
code de tranche s'écrit `'12'`, et la colonne s'appelle `sau_ha`.

### 1.1 Preuve

```
année   n       max(sau_ha)   moyenne
2016    7 271   30.00         13.8
2017    7 282   30.00         13.7
2018    7 220   30.00         13.7
2019    7 203   30.00         13.5
2020    7 355   30.00         13.0
2021    7 412   30.00         13.1
2022    7 322   30.00         13.2
2023    7 220   30.00         13.3
2024    7 250   30.00         13.4
```

`max = 30,00` **sur les neuf millésimes**. C'est le numéro de la dernière modalité de
`SAUTI`, pas une surface :

```
2024,SAUTI,0,Surface nulle
2024,SAUTI,1,Surface non nulle et inférieure à 5 ha
2024,SAUTI,2,Surface égale ou supérieure à 5 ha et inférieure à 10 ha
…
2024,SAUTI,29,Surface égale ou supérieure à 350 ha et inférieure à 400 ha
2024,SAUTI,30,Surface égale ou supérieure 400 ha
```

La SAU moyenne d'une exploitation française est de l'ordre de 70–80 ha. Une moyenne à
13,4 ha et un maximum à 30 ha sur un échantillon national ne sont pas plausibles une
seconde — c'est le signe qui aurait dû alerter.

### 1.2 Ce n'est pas un cas isolé

**123 variables du millésime 2024 sont des tranches.** Toutes ont une entrée dans
`registered_rica_modalities`. Les structurelles :

| Famille | Variables |
|---|---|
| Surfaces d'exploitation | `SAUTI` `SUTOT` `SAUIR` `SAFVD` `SAFER` `SAMET` `SAGRA` `SJACH` `SPARC` `SUGEL` `SFPTO` |
| Surfaces **par culture** | les 47 `SUT3*` (`SUT3BLET`, `SUT3COLZ`, …) |
| Effectifs **par catégorie animale** | les 35 `EFM6*` (`EFM6VLAI`, `EFM6TRUI`, …) |
| Cheptel | `UGBTO` `UGBBO` `UGBCA` `UGBHE` `UGBOV` `UGBPO` |
| Travail | `TOUTA` `TVUTA` `TVL11` `EFF10` |
| Divers | `CDEXE` `TRA05` `FJURI` `RIMPO` `ZALTI` `ZDEFA` `ZENVI` `SEXEP` `STATU` `VDETAIL` `IRMODE` `IRORIGI` `OTEXE` `OTE64F` `OTEFDA` `OTEFDD` `REGIO` `FOAGR` `FOGEN` `DJAXP` |

Restent en **valeur réelle** : tout ce qui est en euros (`PBV*`, `VAV*`, `ACV*`, `CHR*`,
`PBRTO`, `EBEXP`, `RESEX`…), les quantités (`PRQ*`, `PBQ*`, `VAQ*`, `ACQ*`), et — piège dans
le piège — **`SUI3*` (surface irriguée) et `SUD4*` (surface développée horticole), qui sont
en hectares réels** alors que leurs voisines `SUT3*` sont des tranches.

Les autres colonnes promues sont **saines** : `gross_product` (`PBRTO`),
`gross_operating_surplus` (`EBEXP`), `operating_result` (`RESEX`) et
`extrapolation_coefficient` (`EXTR2`) sont tous déclarés `numérique` au dictionnaire.

### 1.3 Aucune donnée n'est perdue

`sauti` et `sutot` figurent dans `NATIVE_RAW_COLUMNS` (`rica.rb:94-97`) et sont donc
**retirées du blob `data`** :

```ruby
jsonb_payload = "to_jsonb(t.*)" + NATIVE_RAW_COLUMNS.map { |c| " - '#{c}'" }.join
```

Le code de tranche n'existe donc qu'**une seule fois**, dans une colonne qui prétend être
des hectares. Rien à re-collecter : la correction est un renommage plus un typage, pas une
reconstruction.

---

## 2. Cause racine

Le loader promeut une variable en colonne numérique **sans consulter le `data_type` que le
dictionnaire déclare**, alors que ce dictionnaire est chargé par la même passe
`normalize`, depuis le même dossier source, quelques lignes plus bas
(`insert_variables`). L'information nécessaire était là.

C'est la seule des trois corrections ci-dessous qui empêche le bug de revenir.

---

## 3. Corrections proposées

### 3.1 Fix A — renommer les colonnes (bloquant)

```sql
sau_ha        numeric(14,2)   →   sau_band         integer
total_area_ha numeric(14,2)   →   total_area_band  integer
```

Renommer, et pas seulement documenter. Le nom est le porteur du bug : `sau_ha` **dit**
hectares, et tout consommateur raisonnable le croit — c'est exactement ce qui est arrivé
côté `cultia_back`, où le score de similarité compare des hectares réels à des codes de
tranche, avec une documentation affirmant « hectares des deux côtés, pas de conversion ».

Un simple commentaire SQL n'aurait pas empêché cela : personne ne lit le commentaire d'une
colonne dont le nom paraît sans ambiguïté.

Type `integer` : les codes vont de 0 à 30. `numeric(14,2)` sur un code ordinal invite au
calcul (`avg(sau_ha)`), qui n'a aucun sens.

### 3.2 Fix B — bornes structurées sur `registered_rica_modalities` (recommandé)

Le renommage rend la colonne honnête mais inexploitable : un consommateur qui veut afficher
ou comparer une surface doit convertir la tranche en bornes, donc **parser du français** :

```
"Surface égale ou supérieure à 15 ha et inférieure à 20 ha"
"Effectif moyen non nul et inférieur à 5"
"Surface égale ou supérieure 400 ha"          ← sans le « à », coquille SSP
```

Laisser chaque consommateur écrire sa propre regex sur ces libellés, c'est distribuer le
prochain bug. Le parsing appartient au lexicon, qui a déjà les données en main :

```sql
ALTER TABLE registered_rica_modalities
  ADD COLUMN lower_bound numeric,   -- borne basse incluse, NULL si non parsable
  ADD COLUMN upper_bound numeric,   -- borne haute exclue, NULL si tranche ouverte
  ADD COLUMN bound_unit  varchar;   -- 'ha', 'tête', 'UTA', 'EUR', … NULL si non quantitatif
```

Renseignées à la normalisation, par une règle documentée et testée, `NULL` quand le libellé
ne s'y prête pas (`FJURI`, `ZALTI`, `IRMODE`… ne sont pas des tranches quantitatives mais des
nomenclatures). Une modalité « Surface nulle » donne `[0, 0]` ; une modalité ouverte
« ≥ 400 ha » donne `lower_bound = 400, upper_bound = NULL`.

Bénéfice bien au-delà de `sau_ha` : les 47 surfaces par culture et les 35 effectifs animaux
deviennent exploitables d'un coup, ce qui est précisément ce dont `cultia_back` a besoin
pour son chantier « activités » (131 activités RICA, dont les surfaces et les effectifs sont
tous en tranches).

**Règle à faire respecter côté consommateur, à écrire dans le README de la datasource** :
une grandeur dont le dénominateur est une tranche s'expose comme un **intervalle**
(`lower_bound` → `upper_bound`), jamais comme une valeur ponctuelle. Un rendement
« `PRQ3BLET / centre de tranche` » affiché comme un nombre est le même bug sous une autre
forme.

### 3.3 Fix C — garde-fou à la promotion (empêche la récidive)

Une assertion à la normalisation : **refuser de promouvoir en colonne numérique une variable
que le dictionnaire du millésime déclare `char` / `caractères`.**

```
promote(:sau_band, from: 'sauti', expect: :char)      → OK
promote(:gross_product, from: 'pbrto', expect: :num)  → OK
promote(:sau_ha, from: 'sauti', expect: :num)         → ÉCHEC au chargement
```

Deux détails d'implémentation :

- **Le vocabulaire du dictionnaire a changé au millésime 2023** : `num`/`char` jusqu'à 2022,
  `numérique`/`caractères` à partir de 2023. La vérification doit accepter les deux
  orthographes, sans quoi elle échouerait sur la moitié des millésimes.
- **Les dictionnaires ne couvrent que 2019+** (`registered_rica_variables` n'a pas de ligne
  avant 2019), alors que les holdings remontent à 2016 — et sont bandées dès 2016
  (`max(sau_ha) = 30` en 2016). Pour un millésime sans dictionnaire, se replier sur le
  dictionnaire connu le plus proche plutôt que de désactiver le contrôle.

C'est le seul des trois fixes qui protège les **futures** promotions. Sans lui, la prochaine
variable ajoutée en colonne reproduira le bug.

---

## 4. Impact sur les consommateurs

Le renommage est une **rupture de schéma**. Elle doit être portée par un bump de version du
paquet lexicon et signalée aux consommateurs.

`cultia_back` (seul consommateur identifié à ce jour) :

| Fichier | Changement |
|---|---|
| `app/services/rica/group_stats.py` | `ALLOWED_COLUMNS` : `sau_ha`/`total_area_ha` → `sau_band`/`total_area_band` |
| `app/services/rica/similarity.py` | `_score_size` compare des hectares à un code de tranche — **le bug fonctionnel** |
| `app/services/rica/holdings.py` | champs exposés par l'API |
| `prisma/schema.prisma` | régénéré par `prisma db pull` |
| `doc/rica_similarity.md:138`, `doc/rica_flow_individuel.md:102` | « hectares des deux côtés, pas de conversion » — **affirmation fausse** |

Ordre imposé : **lexicon d'abord** (renommage + rechargement), `cultia_back` ensuite. Entre
les deux, `prisma db pull` ne résoudrait plus `sau_ha`.

Point important : `cultia_back` reconstruit `public.rica_group_stats` depuis ce schéma, mais
son axe de regroupement repose sur `gross_product` — colonne **saine**. Le bug ne contamine
donc **pas** les statistiques de groupe ; il est circonscrit au score de similarité et à
tout affichage direct de la surface.

---

## 5. Mise à jour de la documentation existante

[`workflow_rica_datasource.md`](workflow_rica_datasource.md) porte l'hypothèse d'origine et
doit être corrigé, sans quoi la prochaine lecture refera le même choix :

- **§ 2.4, ligne 72** — « `SAUTI` / `SUTOT` — surfaces (SAU, totale) » : ce sont des
  **tranches**, à dire explicitement.
- **§ Phase 5, ligne 184** — `sau_ha numeric(10,2), -- sauti` : c'est la décision de
  conception à l'origine du bug.
- Ajouter au § « Points de vigilance » : **le FMD est une publication anonymisée ; toute
  variable dont le libellé du dictionnaire contient `(tranche)` ou dont le `data_type` est
  `char`/`caractères` est un code ordinal.** Croiser systématiquement avec
  `registered_rica_modalities` avant toute promotion en colonne.

---

## 6. Critères d'acceptation

1. `sau_band` / `total_area_band` sont de type `integer` ; aucune colonne du schéma
   `lexicon` ne porte un suffixe d'unité (`_ha`) sur une valeur qui n'est pas dans cette
   unité.
2. `registered_rica_modalities` porte `lower_bound` / `upper_bound` / `bound_unit`,
   renseignés pour les 123 variables de tranche de 2024, `NULL` pour les nomenclatures.
3. La modalité ouverte (« ≥ 400 ha ») a `upper_bound IS NULL`, et « Surface nulle » a
   `lower_bound = 0 AND upper_bound = 0`.
4. Une tentative de promotion d'une variable `char` en colonne numérique **échoue au
   chargement**, sur les millésimes 2016→2024, avec un message nommant la variable.
5. La vérification du `data_type` accepte les deux vocabulaires (`num`/`numérique`,
   `char`/`caractères`).
6. `workflow_rica_datasource.md` ne décrit plus `SAUTI`/`SUTOT` comme des surfaces.

## 7. Question ouverte

**Faut-il aussi exposer `sau_ha_min` / `sau_ha_max` directement sur
`registered_rica_holdings` ?** Ce serait une dénormalisation (les bornes sont déjà dans
`registered_rica_modalities`), mais elle épargnerait une jointure à chaque lecture et
supprimerait la tentation de recaster `sau_band` en hectares.

Recommandation : **non dans un premier temps.** La jointure est bon marché, et deux sources
pour la même vérité finissent toujours par diverger. À reconsidérer si un consommateur
montre que la jointure est coûteuse à l'échelle.
