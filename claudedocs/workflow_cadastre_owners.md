# Workflow — Datasource `cadastre_owners` (Propriétaires personnes morales du cadastre)

> **Statut :** plan d'implémentation. Aucun code n'est généré à ce stade.
> **Prochaine étape :** lancer `/sc:implement claudedocs/workflow_cadastre_owners.md` pour exécuter le plan pas à pas.
>
> **Révision 2 :** prise en compte des tables `lexicon` déjà existantes (`registered_enterprises`, `registered_cadastral_parcels`, `registered_cadastral_buildings`) et stratégie d'adaptation/update transverse.

---

## 1. Objectif

Créer une datasource `CadastreOwners` (`lib/datasources/cadastre_owners.rb`) qui charge et normalise les fichiers MAJIC 2025 des **personnes morales** propriétaires de parcelles cadastrales (bâti et non-bâti) déjà présents dans `raw/cadastre_owners/`.

La datasource doit :
- exposer les propriétaires personnes morales (SIREN, forme juridique, dénomination, groupe) ;
- exposer pour chaque propriétaire les locaux (bâti) et parcelles (non-bâti) détenues, avec adresse et droits réels ;
- **pré-calculer des clés de jointure** pour relier facilement le dataset à :
  - `lexicon.registered_cadastral_parcels` (via un `cadastral_parcel_id` composé identique au format Étalab),
  - `lexicon.registered_enterprises` (via le numéro SIREN, extrait du SIRET établissement) ;
- **enrichir** légèrement les tables existantes (`registered_enterprises`, `registered_cadastral_parcels`) avec des colonnes additives utiles à ces jointures, sans casser les datasources qui les peuplent.

Source : DGFiP / MAJIC — Fichiers `PM_25_B_DDD.csv` (locaux bâti) et `PM_25_NB_DDD.csv` (parcelles non-bâti), millésime 2025.

---

## 2. État existant des tables `lexicon` concernées

Inventaire avant adaptation :

| Table `lexicon` | Datasource propriétaire | Contenu actuel | Pertinence pour `cadastre_owners` |
|---|---|---|---|
| `registered_enterprises` | `enterprises` (SIRENE INSEE) | 1 ligne par SIRET filtré sur codes APE agricoles (≈ `01.*`, `02.*`, `03.*`). PK = `establishment_number` (SIRET 14). Pas de colonne `siren` isolée. | **Cible de jointure** par SIREN ; à **étendre** avec une colonne `siren` indexée. |
| `registered_cadastral_parcels` | `cadastre` (Étalab GeoJSON) | 1 ligne par parcelle. PK = `id` (varchar = INSEE+préfixe+section+numéro). Géométrie `shape`/`centroid` PostGIS. | **Cible de jointure** par `cadastral_parcel_id` ; à **enrichir** (optionnel) avec un compteur de propriétaires PM. |
| `registered_cadastral_buildings` | **`hydrography`** (IGN BD TOPO) ⚠️ | 1 ligne par **empreinte au sol** de bâtiment (couche `batiment.gpkg` IGN), géométrie `shape`/`centroid`, attributs `reference_name = cleabs`, `nature = usage_1`. **Aucun lien fiscal/cadastral, aucun SIREN, aucun parcel_id.** Référencée par 4 flavors (`ekyagri`, `sydec`, `test`, `pv`, `innovation`). | **Conflit de nom uniquement** : il s'agit d'empreintes IGN, pas de locaux MAJIC. Choix retenu : **ne pas modifier** cette table, et **renommer** la nouvelle table « locaux » pour éviter toute confusion. Option alternative discutée en §8 (Q4). |

### 2.1 Collision sémantique sur `registered_cadastral_buildings`

Le nom `registered_cadastral_buildings` est trompeur dans le code actuel :
- **Contenu réel :** empreintes au sol IGN BD TOPO (`cleabs`, `usage_1`, `geom`) ;
- **Ce que suggère le nom :** locaux/lots cadastraux DGFiP (avec adresse, propriétaire, lot d'habitation…).

Ces deux semantiques **ne sont pas compatibles** :
- 1 empreinte IGN (polygone) ≠ 1 local MAJIC (lot fiscal). Une empreinte peut héberger N locaux (immeuble collectif) ; un local peut s'étaler sur plusieurs empreintes (rare).
- Les attributs sont disjoints : IGN n'a ni `siren`, ni `parcel_id`, ni `building/entrance/level/door` ; MAJIC n'a pas de géométrie.

**Décision (recommandée) :** la nouvelle table « locaux MAJIC » s'appellera **`registered_cadastral_premises`** (premises = locaux en anglais juridique/immobilier). Voir §6.

> Une alternative serait de **renommer** la table existante `registered_cadastral_buildings` → `registered_building_footprints` (sémantiquement plus juste) et de réutiliser le nom libéré pour MAJIC. Cette option est **non retenue par défaut** car elle casse 5 flavors + potentiellement l'ERP Ekylibre downstream. Cf. §8 Q4.

---

## 3. Analyse des données brutes

### 3.1 Structure des dossiers `raw/cadastre_owners/`

```
raw/cadastre_owners/
├── locaux_2025/      # 100 fichiers PM_25_B_*.csv  (~ 2.6 Go)  — bâti / locaux
│   ├── PM_25_B_010.csv … PM_25_B_950.csv
│   ├── PM_25_B_2A0.csv, PM_25_B_2B0.csv         # Corse
│   ├── PM_25_B_971.csv … PM_25_B_976.csv        # DOM
│   ├── PM_25_B_140.csv                           # cas atypique (D-140 / hors séquence)
│   ├── PB_25_B_750 (1 à12).csv                  # Paris arr. 1–12 (préfixe PB, parenthèses)
│   ├── PB_25_B_750 (18 à 20).csv                # Paris arr. 18–20
│   └── PM_25_B_750 (13 à 17).csv                # Paris arr. 13–17
└── parcelles_2025/   # 100 fichiers PM_25_NB_*.csv (~ 3.6 Go) — non-bâti / parcelles
    └── PM_25_NB_010.csv … PM_25_NB_976.csv
```

### 3.2 Schéma des CSV `locaux_2025/`

Séparateur `;`, encodage à confirmer (probablement Windows-1252 / ISO-8859-15), CRLF.

| # | Colonne CSV | Type | Notes |
|---|---|---|---|
| 1 | `Département` | varchar(3) | `01`, `2A`, `971`… |
| 2 | `Code Direction` | varchar(1) | typiquement `0` |
| 3 | `Code Commune` | varchar(3) | code commune (3 chiffres) |
| 4 | `Nom de la commune` | varchar | |
| 5 | `Préfixe` | varchar(3) | souvent vide ; `000` par défaut |
| 6 | `Section` | varchar(2) | `ZH`, `A`, `AB`… |
| 7 | `N° plan` | varchar(4) | numéro de parcelle |
| 8 | `Bâtiment` | varchar(1) | |
| 9 | `Entrée` | varchar(2) | |
| 10 | `Niveau` | varchar(2) | |
| 11 | `Porte` | varchar(5) | n° de local/lot |
| 12 | `N° voirie` | varchar(4) | |
| 13 | `Indice de répétition` | varchar(1) | B / T |
| 14 | `Code voie MAJIC` | varchar(5) | |
| 15 | `Code voie Rivoli` | varchar(4) | code FANTOIR |
| 16 | `Nature voie` | varchar(4) | RUE, BD, AV… |
| 17 | `Nom voie` | varchar | |
| 18 | `Code droit` | varchar | « P - Propriétaire »… |
| 19 | `N° Majic` | varchar(6) | id interne MAJIC |
| 20 | `N° SIREN` | varchar(9) | **clé entreprises** (peut être `U…` = pseudo-SIREN BND) |
| 21 | `Groupe personne` | varchar | « 5 - Office HLM »… |
| 22 | `Forme juridique` | varchar(4) | |
| 23 | `Forme juridique abrégée` | varchar | |
| 24 | `Dénomination` | varchar | raison sociale |

### 3.3 Schéma des CSV `parcelles_2025/`

Mêmes colonnes 1–7, puis adresse (col 8–13), puis :
- `Contenance` (parcelle, centiares),
- `SUF` (subdivision fiscale),
- `Nature culture` (`BS - Taillis sous Futaies`…),
- `Contenance` (SUF, centiares) — **doublon d'entête à dédoublonner au load**,
- mêmes colonnes 18–24 que locaux.

### 3.4 Codes et nomenclatures

- **Code droit** : 28 codes-lettres (P, U, N, B, R, F, T, D, …).
- **Groupe personne morale** : 10 groupes (0–9).
- **Nature voie** : ~200 codes.
- **Nature culture** : codes 1–2 lettres (AB, B, BF, BS, P…).

Lookups statiques à embarquer dans `data/cadastre_owners/*.csv` (cf. §5.5).

---

## 4. Stratégie d'intégration avec les tables existantes

### 4.1 Principe directeur

- **Pas de duplication de données** : on ne recopie pas les colonnes déjà présentes ailleurs.
- **Ajouts additifs uniquement** : toute modification de table existante = nouvelle colonne avec `DEFAULT NULL` ou `DEFAULT 0`, **jamais** de retrait/changement de type.
- **UPDATE cross-datasource** : `cadastre_owners.normalize` peut faire des `UPDATE lexicon.<autre_table>` à condition d'utiliser le préfixe `lexicon.` (cf. `hydrography.rb` ligne 167 pour le pattern).
- **Ordre d'exécution** : `cadastre_owners` doit s'exécuter **après** `cadastre` et `enterprises` (sinon les `UPDATE` ne trouvent rien). Si lancé en parallèle (`./lexicon run -P`), c'est l'utilisateur qui doit gérer l'ordre ; documenter dans le `description`.

### 4.2 Adaptation de `registered_enterprises` (datasource `enterprises`)

**Problème :** le SIREN (9 chars) n'est pas une colonne dédiée ; il faudrait faire `LEFT(establishment_number, 9) = siren` à chaque jointure, sans index utilisable.

**Adaptation proposée :**

```sql
-- Dans enterprises.rb -> self.table_definitions(builder), nouvelle version :
CREATE TABLE registered_enterprises (
  establishment_number character varying PRIMARY KEY NOT NULL,
  siren character varying,                         -- ← AJOUTÉ
  french_main_activity_code character varying NOT NULL,
  name character varying,
  address character varying,
  postal_code character varying,
  city character varying,
  country character varying,
  centroid postgis.geometry(Point,4326)
);

CREATE INDEX registered_enterprises_french_main_activity_code ON registered_enterprises(french_main_activity_code);
CREATE INDEX registered_enterprises_name ON registered_enterprises(name);
CREATE INDEX registered_enterprises_siren ON registered_enterprises(siren);  -- ← AJOUTÉ
```

Et dans `enterprises.rb#normalize`, ajouter `siren` à l'INSERT :
```sql
INSERT INTO registered_enterprises (establishment_number, siren, french_main_activity_code, …)
  SELECT siret, LEFT(siret, 9), activite_principale_etablissement, …
```

> **Note :** alternative envisagée — colonne `siren GENERATED ALWAYS AS (LEFT(establishment_number, 9)) STORED`. Plus élégante mais nécessite Postgres ≥ 12 et impose la recréation de la table à chaque changement de version. Préférer la colonne classique alimentée par `enterprises#normalize`.

**Limitation rappelée :** `registered_enterprises` ne contient **que les SIRET d'APE agricoles** (`01.*`, `02.*`, `03.*`). Donc parmi les ~millions de SIREN propriétaires MAJIC, seule une fraction matchera. C'est **acceptable** (le but est de relier les exploitations agricoles à leurs parcelles, pas l'ensemble du tissu économique). On ne modifie **pas** le filtre APE.

### 4.3 Adaptation de `registered_cadastral_parcels` (datasource `cadastre`)

**Problème :** depuis une parcelle, pas de moyen direct de savoir si elle est détenue par une personne morale agricole sans JOIN.

**Adaptation proposée (optionnelle, débrayable) :**

```sql
-- Dans cadastre.rb -> self.table_definitions(builder), ajout :
CREATE TABLE registered_cadastral_parcels(
  id character varying PRIMARY KEY NOT NULL,
  …  -- inchangé
  pm_owners_count integer DEFAULT 0,         -- ← AJOUTÉ
  has_agricultural_pm_owner boolean DEFAULT false   -- ← AJOUTÉ (optionnel)
);

CREATE INDEX registered_cadastral_parcels_pm_owners_count
  ON registered_cadastral_parcels(pm_owners_count)
  WHERE pm_owners_count > 0;
```

Les colonnes sont **alimentées par `cadastre_owners#normalize`**, pas par `cadastre` (cadastre garde sa logique Python d'INSERT pur).

```sql
-- À la fin de cadastre_owners#normalize :
UPDATE lexicon.registered_cadastral_parcels p
   SET pm_owners_count = sub.cnt
  FROM (
    SELECT cadastral_parcel_id, COUNT(DISTINCT majic_number) AS cnt
      FROM lexicon.registered_cadastral_parcel_owners
     GROUP BY cadastral_parcel_id
  ) sub
 WHERE p.id = sub.cadastral_parcel_id;

UPDATE lexicon.registered_cadastral_parcels p
   SET has_agricultural_pm_owner = true
  FROM lexicon.registered_cadastral_parcel_owners po
  JOIN lexicon.registered_enterprises e ON e.siren = po.siren
 WHERE p.id = po.cadastral_parcel_id;
```

**Risque flavor :** ces colonnes additives n'affectent pas les `filter:` existants des flavors (`ekyagri`, `test`…) — `SELECT *` lors du `dump` continuera à fonctionner. À valider tout de même (cf. §10).

**Alternative minimaliste :** ne **rien modifier** dans `registered_cadastral_parcels` et laisser l'ERP faire le JOIN. À discuter (Q5).

### 4.4 Adaptation de `registered_cadastral_buildings` (datasource `hydrography`)

**Décision : NE PAS MODIFIER.**

Justification : cette table contient des empreintes IGN, sans aucun champ fiscal/cadastral. Y injecter des colonnes MAJIC (`siren`, `majic_number`, `address`…) introduirait une confusion structurelle (1 empreinte ≠ 1 local) et alourdirait inutilement la table.

Le lien entre une **empreinte IGN** et un **local MAJIC** serait géométrique (`ST_Intersects(building.shape, premises_address_point)`) et coûteux à matérialiser. Si un cas d'usage le justifie plus tard, une **vue matérialisée** `cadastral_buildings_with_premises` pourrait être créée dans une v2.

---

## 5. Plan d'implémentation côté `cadastre_owners`

### 5.1 Phase **Collect**

**v1 : no-op** (les fichiers sont fournis manuellement). Pattern identique à `hydrography#collect` (vérification de présence + log) :

```ruby
def collect
  missing = []
  missing << "locaux_2025/"    if Dir.glob(dir.join('locaux_2025/*.csv')).empty?
  missing << "parcelles_2025/" if Dir.glob(dir.join('parcelles_2025/*.csv')).empty?
  raise "Missing CSV files in #{dir}: #{missing.join(', ')}" unless missing.empty?
end
```

À termier (Q1) : ajouter un téléchargement depuis MinIO interne si disponible.

### 5.2 Phase **Load** (schema `cadastre_owners`)

Deux tables raw avec création **explicite** (pour gérer l'entête `Contenance` dupliquée et fixer le typage) :

```sql
CREATE TABLE cadastre_owners.raw_locaux (
  department, direction_code, commune_code, commune_name,
  section_prefix, section, plan_number,
  building, entrance, level, door,
  street_number, street_rep, majic_road_code, rivoli_road_code, road_nature, road_name,
  droit_code_label, majic_number, siren, group_label,
  legal_form_code, legal_form_short, denomination
  -- toutes en varchar
);

CREATE TABLE cadastre_owners.raw_parcelles (
  department, direction_code, commune_code, commune_name,
  section_prefix, section, plan_number,
  street_number, street_rep, majic_road_code, rivoli_road_code, road_nature, road_name,
  parcel_surface     integer,
  suf                varchar,
  culture_nature_label varchar,
  suf_surface        integer,
  droit_code_label, majic_number, siren, group_label,
  legal_form_code, legal_form_short, denomination
  -- reste en varchar
);
```

**Procédure :**
1. `query` les `CREATE TABLE`.
2. Boucle `Dir.glob` sur `raw/cadastre_owners/locaux_2025/*.csv` → `COPY` (gérer espaces/parenthèses des fichiers Paris).
3. Idem `parcelles_2025`.
4. Logguer le nombre de lignes par fichier.
5. Encoding à confirmer (`LATIN1` probable).

### 5.3 Phase **Normalize** (schema `lexicon`)

Trois nouvelles tables `lexicon` + 1 à 3 UPDATE cross-datasource.

**Ordre :**
1. `INSERT INTO registered_cadastral_owners` (déduplication par `majic_number`).
2. `INSERT INTO registered_cadastral_premises` depuis `raw_locaux` (1 ligne / local / droit).
3. `INSERT INTO registered_cadastral_parcel_owners` depuis `raw_parcelles` (1 ligne / parcelle / suf / droit).
4. `UPDATE lexicon.registered_cadastral_parcels SET pm_owners_count = …, has_agricultural_pm_owner = …` (cf. §4.3).
5. `VACUUM ANALYZE` (optionnel).

> **Pré-requis runtime :** `lexicon.registered_cadastral_parcels` et `lexicon.registered_enterprises` doivent exister. Si cadastre/enterprises n'ont pas tourné, les UPDATE sont des no-op (0 lignes affectées) — pas d'erreur, juste un warning.

---

## 6. Schéma cible des nouvelles tables (`lexicon`)

### 6.1 `registered_cadastral_owners`

Une ligne par personne morale (groupée par `majic_number`).

```sql
CREATE TABLE registered_cadastral_owners (
  majic_number       varchar PRIMARY KEY NOT NULL,
  siren              varchar,                  -- NULL si commence par 'U' (BND)
  denomination       varchar,
  legal_form_code    varchar,
  legal_form_short   varchar,
  person_group_code  varchar,                  -- '0'..'9'
  person_group_label varchar
);
CREATE INDEX registered_cadastral_owners_siren ON registered_cadastral_owners(siren);
CREATE INDEX registered_cadastral_owners_denomination ON registered_cadastral_owners(denomination);
CREATE INDEX registered_cadastral_owners_person_group ON registered_cadastral_owners(person_group_code);
```

### 6.2 `registered_cadastral_premises` (locaux MAJIC — **renommé** depuis le plan v1)

```sql
CREATE TABLE registered_cadastral_premises (
  id                    serial PRIMARY KEY NOT NULL,
  cadastral_parcel_id   varchar NOT NULL,        -- ← JOIN registered_cadastral_parcels.id
  town_insee_code       varchar NOT NULL,
  section_prefix        varchar,
  section               varchar,
  work_number           varchar,
  building              varchar,                  -- lettre de bâtiment MAJIC
  entrance              varchar,
  level                 varchar,
  door                  varchar,
  address               varchar,                  -- concat numéro+rep+nature+nom voie
  street_rivoli_code    varchar,                  -- FANTOIR
  droit_code            varchar,                  -- 'P', 'U', 'N'…
  majic_number          varchar NOT NULL,         -- FK logique → registered_cadastral_owners
  siren                 varchar                   -- redondé pour requêtes rapides
);
CREATE INDEX registered_cadastral_premises_parcel_id ON registered_cadastral_premises(cadastral_parcel_id);
CREATE INDEX registered_cadastral_premises_majic ON registered_cadastral_premises(majic_number);
CREATE INDEX registered_cadastral_premises_siren ON registered_cadastral_premises(siren);
CREATE INDEX registered_cadastral_premises_insee ON registered_cadastral_premises(town_insee_code);
```

### 6.3 `registered_cadastral_parcel_owners`

```sql
CREATE TABLE registered_cadastral_parcel_owners (
  id                       serial PRIMARY KEY NOT NULL,
  cadastral_parcel_id      varchar NOT NULL,
  town_insee_code          varchar NOT NULL,
  section_prefix           varchar,
  section                  varchar,
  work_number              varchar,
  parcel_surface_area      integer,
  suf                      varchar,
  culture_nature_code      varchar,
  suf_surface_area         integer,
  address                  varchar,
  street_rivoli_code       varchar,
  droit_code               varchar,
  majic_number             varchar NOT NULL,
  siren                    varchar
);
CREATE INDEX registered_cadastral_parcel_owners_parcel_id ON registered_cadastral_parcel_owners(cadastral_parcel_id);
CREATE INDEX registered_cadastral_parcel_owners_majic    ON registered_cadastral_parcel_owners(majic_number);
CREATE INDEX registered_cadastral_parcel_owners_siren    ON registered_cadastral_parcel_owners(siren);
CREATE INDEX registered_cadastral_parcel_owners_insee    ON registered_cadastral_parcel_owners(town_insee_code);
CREATE INDEX registered_cadastral_parcel_owners_culture  ON registered_cadastral_parcel_owners(culture_nature_code);
```

### 6.4 Diagramme des jointures (après adaptation)

```
┌─────────────────────────┐         siren            ┌────────────────────────┐
│ registered_enterprises  │◄──────────────────────►  │ registered_cadastral_  │
│   establishment_number  │                          │   owners               │
│   siren  ← NOUVEAU      │                          │   majic_number (pk)    │
│   …                     │                          │   siren                │
└─────────────────────────┘                          │   denomination …       │
                                                     └────┬───────────────────┘
                                                          │ majic_number
                                                          ▼
┌──────────────────────────┐  cadastral_   ┌──────────────────────────────────┐
│ registered_cadastral_    │  parcel_id    │ registered_cadastral_parcel_     │
│   parcels                │◄──────────────│   owners                         │
│   id (pk)                │               │   cadastral_parcel_id, siren,    │
│   shape, centroid, …     │               │   majic_number, culture, suf …   │
│   pm_owners_count       │               └──────────────────────────────────┘
│      ← NOUVEAU           │
│   has_agricultural_     │  cadastral_   ┌──────────────────────────────────┐
│      pm_owner ← NOUVEAU  │  parcel_id    │ registered_cadastral_premises    │
│                          │◄──────────────│   (locaux MAJIC)                 │
└──────────────────────────┘               │   cadastral_parcel_id, siren,    │
                                           │   majic_number, building/door …  │
                                           └──────────────────────────────────┘

  ┌─────────────────────────────┐
  │ registered_cadastral_       │  ← INCHANGÉ (empreintes IGN BD TOPO).
  │   buildings  (hydrography)  │     Pas de FK vers les nouvelles tables.
  │   id, reference_name,       │     Lien possible uniquement par jointure spatiale.
  │   nature, shape, centroid   │
  └─────────────────────────────┘
```

---

## 7. Stratégie SQL de normalisation (esquisse)

### 7.1 Construction de `cadastral_parcel_id`

Format Étalab : `INSEE(5) + PRÉFIXE(3) + SECTION(2) + NUMÉRO(4)`.

```sql
CONCAT(
  department || commune_code,                                                    -- INSEE 5
  LPAD(COALESCE(NULLIF(section_prefix, ''), '000'), 3, '0'),
  LPAD(TRIM(section), 2, '0'),
  LPAD(TRIM(plan_number), 4, '0')
) AS cadastral_parcel_id
```

→ test post-normalize : `% lignes sans match dans registered_cadastral_parcels` doit être < 1 %.

### 7.2 Owners (déduplication)

```sql
INSERT INTO registered_cadastral_owners (
  majic_number, siren, denomination,
  legal_form_code, legal_form_short, person_group_code, person_group_label
)
SELECT DISTINCT ON (majic_number)
  majic_number,
  CASE WHEN siren ~ '^[0-9]{9}$' THEN siren END,
  denomination, legal_form_code, legal_form_short,
  SPLIT_PART(group_label, ' - ', 1),
  SPLIT_PART(group_label, ' - ', 2)
FROM (
  SELECT * FROM cadastre_owners.raw_locaux
  UNION ALL
  SELECT * FROM cadastre_owners.raw_parcelles
) merged
ORDER BY majic_number, siren NULLS LAST;
```

### 7.3 Premises & parcel_owners

Patterns identiques (cf. v1 du plan), avec extraction `droit_code = SPLIT_PART(droit_code_label, ' - ', 1)` et `culture_nature_code = SPLIT_PART(culture_nature_label, ' - ', 1)`.

### 7.4 Adaptation `registered_enterprises` (modification de `enterprises.rb`)

```sql
-- À ajouter dans enterprises.rb#normalize (existant) :
INSERT INTO registered_enterprises (
  establishment_number, siren, french_main_activity_code, name, address, postal_code, city, country, centroid
)
  SELECT siret,
         LEFT(siret, 9),                          -- ← AJOUTÉ
         activite_principale_etablissement,
         …  -- inchangé
```

### 7.5 UPDATE cross-datasource `registered_cadastral_parcels` (depuis `cadastre_owners#normalize`)

```sql
UPDATE lexicon.registered_cadastral_parcels p
   SET pm_owners_count = sub.cnt
  FROM (
    SELECT cadastral_parcel_id, COUNT(DISTINCT majic_number) AS cnt
      FROM lexicon.registered_cadastral_parcel_owners
     GROUP BY cadastral_parcel_id
  ) sub
 WHERE p.id = sub.cadastral_parcel_id;

UPDATE lexicon.registered_cadastral_parcels p
   SET has_agricultural_pm_owner = true
 WHERE EXISTS (
   SELECT 1
     FROM lexicon.registered_cadastral_parcel_owners po
     JOIN lexicon.registered_enterprises e ON e.siren = po.siren
    WHERE po.cadastral_parcel_id = p.id
 );
```

---

## 8. Points à clarifier avec l'utilisateur (avant `/sc:implement`)

| # | Question | Impact | Default proposé |
|---|---|---|---|
| Q1 | Source du collect : MinIO interne ou manuel ? | Implémentation `collect` | Manuel (no-op + vérif présence) |
| Q2 | Encoding réel des CSV ? | `COPY ... WITH (ENCODING …)` | `LATIN1` (à valider sur un fichier) |
| Q3 | Convention INSEE DOM (`971` + 2 vs 3 chars) ? | Construction `cadastral_parcel_id` | Format Étalab brut, validé par test de couverture |
| **Q4** | **Nom de la nouvelle table « locaux » : `registered_cadastral_premises` (recommandé) ou renommer l'existante `registered_cadastral_buildings` (IGN) en `registered_building_footprints` et réutiliser le nom pour MAJIC ?** | **Schéma + 5 flavors + ERP** | `registered_cadastral_premises` (zéro breaking change) |
| **Q5** | **Ajouter `pm_owners_count` + `has_agricultural_pm_owner` à `registered_cadastral_parcels` ?** | Ajout de 2 colonnes + 2 UPDATE post-normalize | **Oui** (utile, peu coûteux, additif) |
| **Q6** | **Ajouter `siren` à `registered_enterprises` ?** | Ajout colonne + index + 1 modif `enterprises.rb` | **Oui** (utile, additif, coût négligeable) |
| Q7 | Faut-il aussi prévoir les personnes physiques (fichiers PP) plus tard ? | Naming : `cadastre_owners` reste valide | Oui, scope ouvert |
| Q8 | Inclure la datasource dans `light.yml` (= `without:`) ? | `resources/flavors/light.yml` | Oui (datasource lourde, ~6 Go raw) |
| Q9 | Que faire des flavors `test` / `ekyagri` / `pv` / `sydec` / `innovation` qui filtrent `registered_cadastral_parcels` par zone ? Faut-il y ajouter un filtre sur les nouvelles tables `registered_cadastral_premises` et `registered_cadastral_parcel_owners` ? | Packaging par flavor cohérent | **Oui**, dupliquer le filtre via `cadastral_parcel_id IN (SELECT id FROM registered_cadastral_parcels WHERE …)` ou clause spatiale équivalente |

---

## 9. Plan d'exécution étape par étape

### Étape 1 — Préparation
- [ ] Confirmer encoding et structure d'un fichier de chaque type (`file -i`, `head -3 | xxd`).
- [ ] Confirmer Q1–Q9.
- [ ] Créer `data/cadastre_owners/{droit_codes,person_groups,road_types,culture_natures}.csv` depuis les `.odt`.

### Étape 2 — Adaptation des datasources existantes
- [ ] **Si Q6 = oui** : modifier `lib/datasources/enterprises.rb`
  - Ajouter `siren character varying` + index dans `table_definitions`.
  - Ajouter `LEFT(siret, 9)` dans l'`INSERT` de `normalize`.
- [ ] **Si Q5 = oui** : modifier `lib/datasources/cadastre.rb`
  - Ajouter `pm_owners_count integer DEFAULT 0` et `has_agricultural_pm_owner boolean DEFAULT false` + index conditionnel dans `table_definitions`.
  - **Ne pas modifier** `cadastre/__init__.py` (Python) — les nouvelles colonnes restent à leur DEFAULT à la sortie de `cadastre#normalize`.
- [ ] `./lexicon validate` pour s'assurer que les nouveaux schémas restent cohérents.
- [ ] (Sanity check) Vérifier qu'aucun flavor ne fait un `INSERT` ou un `SELECT col_list` qui se casserait sur les nouvelles colonnes.

### Étape 3 — Squelette de la nouvelle datasource
- [ ] Créer `lib/datasources/cadastre_owners.rb` héritant `Datasources::Base`.
- [ ] `description`, `credits` (DGFiP / MAJIC / Licence Ouverte 2.0).
- [ ] `def collect` no-op + vérification de présence.
- [ ] Vérifier l'auto-discovery via `./lexicon list`.

### Étape 4 — `table_definitions` de `cadastre_owners`
- [ ] Déclarer les 3 nouvelles tables `lexicon` (§6.1–6.3).
- [ ] `./lexicon validate`.

### Étape 5 — `load`
- [ ] `CREATE TABLE cadastre_owners.raw_locaux / raw_parcelles` explicitement.
- [ ] Boucle `COPY` sur les CSV (gérer espaces/parenthèses Paris).
- [ ] Test sur 1 département : compter les lignes.

### Étape 6 — `normalize`
- [ ] Insertion `registered_cadastral_owners`.
- [ ] Insertion `registered_cadastral_premises`.
- [ ] Insertion `registered_cadastral_parcel_owners`.
- [ ] **Si Q5 = oui** : UPDATE de `lexicon.registered_cadastral_parcels` (pm_owners_count + has_agricultural_pm_owner).
- [ ] Logguer compteurs (`logger.debug`).

### Étape 7 — Validation croisée
- [ ] % de lignes `registered_cadastral_parcel_owners` sans match dans `registered_cadastral_parcels` → cible < 1 %.
- [ ] % de SIREN MAJIC trouvés dans `registered_enterprises.siren` → audit (info).
- [ ] Distribution des `person_group_code` (sanity check).
- [ ] **Si Q5 = oui** : vérifier que `SUM(pm_owners_count) > 0` et qu'il existe au moins quelques `has_agricultural_pm_owner = true`.

### Étape 8 — Intégration flavors
- [ ] **Si Q8 = oui** : ajouter `cadastre_owners` à `resources/flavors/light.yml` `without:`.
- [ ] **Si Q9 = oui** : ajouter aux flavors géo-filtrés (`ekyagri`, `pv`, `sydec`, `test`, `innovation`) un filtre `WHERE cadastral_parcel_id IN (SELECT id FROM registered_cadastral_parcels WHERE …)` pour les 3 nouvelles tables `lexicon`.

### Étape 9 — Documentation
- [ ] `doc/datasources/cadastre_owners.md` : fiche descriptive, schéma, jointures.
- [ ] Mettre à jour `CLAUDE.md` si la liste des datasources y figure.

### Étape 10 — Exécution complète & dump
- [ ] `./lexicon clean && ./lexicon run cadastre enterprises cadastre_owners` (ordre garanti).
- [ ] `./lexicon validate`.
- [ ] `./lexicon dump cadastre_owners` (sanity check packaging).

---

## 10. Risques & mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Encoding CSV mal détecté → caractères corrompus dans `denomination` | Élevée | Moyen | Tester `file -i` ; option `WITH (ENCODING 'LATIN1')` |
| `cadastral_parcel_id` ne matche pas le format Étalab pour Corse/DOM | Moyenne | Élevé | Test de couverture (§7.1) ; itérer jusqu'à < 1 % mismatch |
| Volumétrie : 6 Go raw, ~100 M lignes — load long | Élevée | Faible | `COPY` rapide ; créer index après `INSERT` |
| Entête `Contenance` dupliquée dans CSV parcelles → COPY échoue | Élevée | Élevé | Création explicite de la table raw (§5.2) |
| Fichiers Paris au nom irrégulier ignorés | Moyenne | Moyen | `Dir.glob` + quoting ; log du compte de fichiers |
| SIREN « pseudo » (`U…`) traité comme valide → faux JOINs | Moyenne | Moyen | Filtre regex `^[0-9]{9}$` |
| **Modification de `cadastre.rb` casse un flavor existant (filter `SELECT *` ou ordre de colonnes attendu)** | **Faible** | **Élevé** | Ajout de colonnes en **fin** de table avec `DEFAULT` ; relancer `./lexicon dump` pour `ekyagri`, `test`, `pv`, `sydec`, `innovation` et vérifier qu'aucun ne casse |
| **Modification de `enterprises.rb` rompt l'ordre des colonnes attendu par un consommateur en aval (Ekylibre ERP)** | **Moyenne** | **Élevé** | Ajout en **fin** de liste de colonnes ; **ne pas** réordonner ; communiquer le changement à l'équipe ERP |
| **UPDATE cross-datasource de `cadastre_owners` exécuté sans cadastre/enterprises tournés → 0 ligne affectée silencieuse** | Élevée (test/CI) | Faible | Log warning si `(SELECT COUNT(*) FROM lexicon.registered_cadastral_parcels) = 0` |
| Datasource lourde incluse par défaut dans tous les flavors → packages volumineux | Élevée | Moyen | Ajouter à `light.yml` `without:` |
| **Le `dump` versionné `lexicon__<version>` ne contient pas les colonnes ajoutées si l'utilisateur ne re-dump pas après changement de schéma** | Moyenne | Moyen | Bumper la version (`./lexicon version bump minor`) après changement de schéma |

---

## 11. Livrables attendus

À la fin de l'implémentation :

**Nouveaux fichiers :**
- `lib/datasources/cadastre_owners.rb` — datasource Ruby.
- `data/cadastre_owners/{droit_codes,person_groups,road_types,culture_natures}.csv` — lookups statiques.
- `doc/datasources/cadastre_owners.md` — fiche descriptive (optionnel).

**Fichiers modifiés :**
- `lib/datasources/enterprises.rb` — ajout colonne `siren` + index + alimentation (si Q6).
- `lib/datasources/cadastre.rb` — ajout colonnes `pm_owners_count`, `has_agricultural_pm_owner` (si Q5).
- `resources/flavors/light.yml` — ajout dans `without:` (si Q8).
- `resources/flavors/{ekyagri,test,pv,sydec,innovation}.yml` — filtres géographiques (si Q9).

**Nouvelles tables `lexicon` :**
- `registered_cadastral_owners`
- `registered_cadastral_premises`
- `registered_cadastral_parcel_owners`

**Tables `lexicon` enrichies :**
- `registered_enterprises` : `+ siren` (si Q6).
- `registered_cadastral_parcels` : `+ pm_owners_count`, `+ has_agricultural_pm_owner` (si Q5).

**Table `lexicon` inchangée :**
- `registered_cadastral_buildings` (IGN BD TOPO via `hydrography`) — explicitement laissée en l'état.

**Critères d'acceptation :**
- `./lexicon run cadastre enterprises cadastre_owners` se termine sans erreur (ordre garanti).
- `SELECT COUNT(*) FROM lexicon.registered_cadastral_owners` > 100 000.
- `SELECT COUNT(*) FROM lexicon.registered_cadastral_parcel_owners po JOIN lexicon.registered_cadastral_parcels p ON p.id = po.cadastral_parcel_id` couvre > 95 % de `po`.
- `SELECT COUNT(*) FROM lexicon.registered_enterprises e JOIN lexicon.registered_cadastral_owners o ON o.siren = e.siren` > 0 (au moins quelques jointures).
- `./lexicon dump` pour les 5 flavors géo-filtrés réussit (pas de régression).

---

> **STOP — ce document est un plan. Aucun code ni schéma n'a été modifié.**
> Pour exécuter : `/sc:implement claudedocs/workflow_cadastre_owners.md`.
