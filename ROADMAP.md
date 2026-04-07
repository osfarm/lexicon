# ROADMAP — Lexicon v2

## Vision

La v2 décompose le monorepo actuel en une constellation de dépôts indépendants — un par source de données. Chaque dépôt produit un **package normalisé** (un `schema.json` + des fichiers CSV) qui est déposé dans un bucket S3. Une instance **Supabase** joue le rôle de base de données finale : elle importe les packages depuis S3 et les matérialise dans un schéma `lexicon`.

```
[Repo datasource A] ──build──▶ package A ──▶ ┐
[Repo datasource B] ──build──▶ package B ──▶ ├──▶ S3 bucket ──▶ Supabase (schéma lexicon)
[Repo datasource C] ──build──▶ package C ──▶ ┘
```

---

## Architecture cible

### 1. Dépôt par datasource

Chaque source de données devient un dépôt GitHub autonome nommé `lexicon-<name>` (ex: `lexicon-units`, `lexicon-phytosanitary`).

**Structure type :**

```
lexicon-phytosanitary/
├── VERSION                 # version sémantique du package (ex: 1.3.0)
├── schema.json             # déclaration des tables (source de vérité)
├── src/
│   ├── collect.rb          # téléchargement des sources brutes
│   └── normalize.rb        # transformation → fichiers CSV
├── data/                   # fichiers statiques versionnés dans le dépôt
├── Dockerfile              # environnement de build reproductible
└── .github/
    └── workflows/
        ├── build.yml       # push sur main : build + dépôt en S3 (draft)
        └── release.yml     # tag : publication du package en S3 (stable)
```

Le `collect` télécharge les sources brutes, le `normalize` produit les CSV finaux. Aucune base de données intermédiaire : la transformation s'effectue en mémoire ou via des fichiers temporaires.

---

### 2. Format du package

Un package est un répertoire déposé dans S3 contenant :

```
s3://lexicon-packages/
  phytosanitary/
    1.3.0/
      manifest.json
      schema.json
      registered_phytosanitary_products.csv
      registered_phytosanitary_usages.csv
      ...
  units/
    2.0.0/
      manifest.json
      schema.json
      master_dimensions.csv
      master_units.csv
      master_packagings.csv
  index.json                ← registre global de tous les datasources
```

#### `manifest.json`

```json
{
  "name": "phytosanitary",
  "version": "1.3.0",
  "built_at": "2026-04-07T10:00:00Z",
  "tables": ["registered_phytosanitary_products", "registered_phytosanitary_usages"],
  "checksums": {
    "schema.json": "sha256:...",
    "registered_phytosanitary_products.csv": "sha256:..."
  }
}
```

#### `schema.json`

Décrit la structure des tables, les types de colonnes, les index et les clés étrangères. C'est la source de vérité que l'importer utilise pour créer ou mettre à jour les tables dans Supabase.

```json
{
  "name": "units",
  "version": "2.0.0",
  "description": "Dimensions, units and packaging",
  "credits": [
    {
      "name": "Liste des unités et conditionnements de références",
      "provider": "Ekylibre SAS",
      "url": "https://ekylibre.com",
      "licence": "CC-BY-SA 4.0",
      "updated_at": "2022-02-23"
    }
  ],
  "tables": [
    {
      "name": "master_units",
      "columns": [
        { "name": "reference_name", "type": "varchar",       "primary_key": true,  "nullable": false },
        { "name": "dimension",      "type": "varchar",       "primary_key": false, "nullable": false },
        { "name": "symbol",         "type": "varchar",       "primary_key": false, "nullable": false },
        { "name": "a",              "type": "numeric(25,10)","primary_key": false, "nullable": true  },
        { "name": "label",          "type": "jsonb",         "primary_key": false, "nullable": true  }
      ],
      "indexes": [
        { "name": "master_units_reference_name", "columns": ["reference_name"], "type": "btree" }
      ],
      "foreign_keys": [
        {
          "column": "dimension",
          "references_table": "master_dimensions",
          "references_column": "reference_name"
        }
      ]
    }
  ]
}
```

**Types supportés dans `schema.json` :**

| Type dans schema.json | Type SQL Supabase |
|---|---|
| `varchar` | `character varying` |
| `integer` | `integer` |
| `numeric(p,s)` | `numeric(p,s)` |
| `jsonb` | `jsonb` |
| `text[]` | `text[]` |
| `boolean` | `boolean` |
| `date` | `date` |
| `timestamp` | `timestamp` |
| `geometry(type,srid)` | `postgis.geometry(type,srid)` |

**Colonnes géométriques dans les CSV :** encodées en WKT (Well-Known Text), ex: `MULTIPOLYGON(((2.3 48.8,...)))`. L'importer effectue la conversion WKT → PostGIS lors de l'import.

#### `index.json` (racine du bucket)

Liste de tous les datasources avec leurs versions disponibles. Mis à jour à chaque publication.

```json
{
  "updated_at": "2026-04-07T10:00:00Z",
  "datasources": {
    "units":          { "latest": "2.0.0", "versions": ["1.0.0", "2.0.0"] },
    "phytosanitary":  { "latest": "1.3.0", "versions": ["1.0.0", "1.1.0", "1.3.0"] },
    "cadastre":       { "latest": "3.1.0", "versions": ["3.0.0", "3.1.0"] }
  }
}
```

---

### 3. Importer Supabase (`lexicon-importer`)

Nouveau projet CLI qui lit les packages depuis S3 et alimente le schéma `lexicon` de Supabase.

**Commandes principales :**

```sh
lexicon-importer sync                        # synchronise tous les datasources (dernière version)
lexicon-importer sync phytosanitary          # synchronise un seul datasource
lexicon-importer sync phytosanitary@1.3.0    # version spécifique
lexicon-importer status                      # versions installées vs disponibles
lexicon-importer diff phytosanitary          # compare l'installé avec la dernière version S3
```

**Comportement lors d'un `sync` :**

1. Télécharge `index.json` depuis S3
2. Pour chaque datasource, compare la version installée (table de suivi `lexicon._packages`) avec la version disponible
3. Si une nouvelle version est disponible :
   a. Télécharge `schema.json` et les CSVs
   b. Vérifie les checksums du `manifest.json`
   c. Crée ou met à jour les tables dans le schéma `lexicon`
   d. Désactive temporairement les FK inter-datasources
   e. Importe les CSV (`COPY FROM` ou `INSERT`)
   f. Réactive et valide les FK
   g. Met à jour `lexicon._packages`

**Table de suivi dans Supabase :**

```sql
CREATE TABLE lexicon._packages (
  name       varchar PRIMARY KEY NOT NULL,
  version    varchar NOT NULL,
  synced_at  timestamp NOT NULL
);
```

**Résolution des dépendances :** les FK cross-datasources (ex: `master_units` → `master_dimensions`) sont résolues par ordre topologique à partir des `foreign_keys` déclarés dans les `schema.json`. L'importer construit le graphe de dépendances et ordonne les imports en conséquence.

---

### 4. Traductions

En v1, `master_translations` est une table partagée alimentée par tous les datasources, avec des identifiants de la forme `units_kilogram`. Cette approche crée un couplage fort.

**En v2 :** les traductions sont embarquées directement dans chaque table via une colonne `label jsonb`.

```json
{ "fra": "Kilogramme", "eng": "Kilogram", "deu": "Kilogramm" }
```

- Chaque datasource est autonome : pas de dépendance à `master_translations`
- Le `datasource translations` (v1) est supprimé
- La migration se fait datasource par datasource : lors du portage vers v2, les colonnes `translation_id` sont remplacées par `label jsonb`

---

## Phases de migration

### Phase 1 — Fondations (standard & outillage)

**Objectif :** définir les contrats techniques et créer le socle commun.

- [ ] Finaliser le format `schema.json` (types, géométrie, FK)
- [ ] Créer le dépôt template `lexicon-datasource-template` avec la structure type, le Dockerfile et les workflows CI/CD
- [ ] Développer le CLI `lexicon-importer` (sync, status, diff)
- [ ] Mettre en place le bucket S3 avec la structure `/<name>/<version>/`
- [ ] Valider le cycle complet sur un datasource simple : **`units`**

### Phase 2 — Migration des datasources simples (données statiques)

Datasources dont les données sources sont des fichiers CSV stockés dans `data/` — pas de téléchargement, pas de géométrie.

- [ ] `units`
- [ ] `translations` → fusion des labels dans chaque table concernée
- [ ] `taxonomy`
- [ ] `variants`
- [ ] `user_roles`
- [ ] `open_nomenclature`
- [ ] `chart_of_accounts`
- [ ] `intervention_models`
- [ ] `technical_workflows` / `technical_workflow_sequences`
- [ ] `productions`
- [ ] `budgets`

### Phase 3 — Migration des datasources avec téléchargement (CSV/XLS)

Datasources qui collectent des données via HTTP sans géométrie.

- [ ] `phytosanitary`
- [ ] `legal_positions`
- [ ] `seed_varieties`
- [ ] `vine_varieties`
- [ ] `phenological_stages`
- [ ] `eu_market_prices`
- [ ] `prices`
- [ ] `quality_and_origin_signs`
- [ ] `postal_codes`
- [ ] `enterprises`
- [ ] `agroedi`
- [ ] `weather`

### Phase 4 — Migration des datasources géographiques (PostGIS)

Datasources avec des colonnes géométriques — nécessitent l'encodage WKT dans les CSV et la conversion par l'importer.

- [ ] `cadastre` *(Python)*
- [ ] `graphic_parcels`
- [ ] `cadastral_prices`
- [ ] `hydrography`
- [ ] `protected_water_zones`
- [ ] `protected_natural_zones`
- [ ] `soil`

### Phase 5 — Orchestration & monitoring

- [ ] Mettre en place les GitHub Actions pour la publication automatique sur tag
- [ ] Ajouter un tableau de bord de suivi des versions (S3 `index.json` → UI)
- [ ] Automatiser la détection des nouvelles versions chez les fournisseurs (scraping / API)
- [ ] Définir la politique de rétention des anciennes versions sur S3
- [ ] Documenter le process de création d'un nouveau datasource en v2

---

## Comparaison v1 / v2

| Aspect | v1 (actuel) | v2 (cible) |
|---|---|---|
| Dépôt | Monorepo unique | Un dépôt par datasource |
| Base intermédiaire | PostgreSQL local (Docker) | Aucune — transformation en mémoire/fichiers |
| Format de sortie | Dump SQL compressé | `schema.json` + CSV par table |
| Distribution | MinIO / S3 (archive) | S3 (fichiers individuels versionnés) |
| Base finale | PostgreSQL Ekylibre | Supabase (schéma `lexicon`) |
| Traductions | Table `master_translations` partagée | Colonne `label jsonb` par table |
| Cycle de release | Monolithique (toutes sources ensemble) | Indépendant par datasource |
| Géométrie | PostGIS natif | WKT dans CSV, conversion à l'import |
| Dépendances cross-datasource | Gérées par le monorepo | Résolues par graphe topologique dans l'importer |
