# Conception — Lexicon v2, jalon J1 : mises à jour indépendantes

Conception du 2026-10-03. Exigences : `claudedocs/brainstorm_lexicon_v2.md`
(F1 à F11, N1 à N5, N8). Ce document ne couvre que J1 ; il prépare J2 à J5
sans les concevoir.

## 0. Décisions de conception

Vos réponses aux questions ouvertes, et les choix qui vous étaient laissés.

| # | Sujet | Décision |
|---|---|---|
| C1 | API (D7) | **`lexicon-rest-api` est gardée.** Elle lit `"${DB_SCHEMA}".table` : avec un schéma servi au nom stable `lexicon` et des tables inchangées, elle fonctionne avec un seul changement de configuration (`DB_SCHEMA=lexicon`) |
| C2 | Gem `lexicon-common` (Q10) | **Réécrite dans le monorepo.** Le format de package est repris et étendu ; loader, bascule et transport sont neufs. La dépendance à la gem disparaît en fin de J1 |
| C3 | Stockage (D10) | **Disque du serveur**, dans un dépôt de packages servi en lecture seule par HTTPS. Aucune offre gratuite ne tient 52 Go par jeu complet |
| C4 | Sauvegarde (Q5b) | **Le dépôt de packages** est sauvegardé vers S3 par Dokploy. Les schémas `lexicon`, `lexicon_staging` et `lexicon_meta` ne le sont pas : ils se reconstruisent depuis les packages. Le schéma `lexicon_access` (clés d'API, voir le document d'administration) est le seul état non reconstructible : il est sauvegardé chaque jour |
| C5 | Traductions (Q6) | Cible : **`label jsonb` dans chaque table** (pas de jointure, ajouter une langue = ajouter une clé ; `master_nomenclatures` le fait déjà). En J1, on ne migre pas les 14 tables existantes : chaque datasource écrit ses traductions dans **sa propre table**, et `master_translations` devient une vue (§5.2) |
| C6 | Flavors (Q7) | **Conservés, déplacés de la publication vers l'export.** Le serveur charge toujours les données complètes ; un flavor produit un *bundle* filtré, chargeable ailleurs avec le même loader (§7) |
| C7 | Autres consommateurs (Q9) | Cultia consomme un flavor : J1 garde les noms de tables et de colonnes, et fournit le bundle `cultia` |
| C8 | n8n et IA (Q11) | Hors J1 : aucune exigence de J1 n'en a besoin |
| C9 | Propriétaires dans les fiches (Q12) | Oui, personnes morales seulement. Concerne J3 |
| C10 | Version d'une datasource | **Date de build**, `AAAA.MM.JJ.N`, attribuée automatiquement. Un `schema_revision` entier, porté par la recette, signale les changements de structure |
| C11 | Retour arrière (F10) | **Rechargement du package précédent** depuis le dépôt. Aucune copie de l'ancienne version n'est gardée en base |
| C12 | Langage | **Ruby**, dans l'image Docker actuelle, côté build comme côté serveur |

Le tableau de rétention demandé (Q8) est en annexe A, à compléter.

## 1. Vue d'ensemble

```
 Machine de build (la vôtre)                    Serveur (32 Go / 800 Go, Dokploy)
┌───────────────────────────────┐              ┌─────────────────────────────────────────┐
│ ./lexicon run <ds>            │              │  /srv/lexicon/packages   (dépôt)        │
│   collect → load → normalize  │              │   ├── index.json                        │
│   Postgres local, schéma      │              │   └── <ds>/<version>/…                  │
│   `lexicon`                   │              │        │                  │             │
│                               │   rsync      │        │ lit              │ sert (HTTPS,│
│ ./lexicon package <ds>        │   sur SSH    │        ▼                  ▼  lecture)   │
│   → out/packages/<ds>/<v>/    │ ───────────▶ │  ┌──────────┐      ┌────────────┐       │
│                               │  (données,   │  │  loader  │      │  packages  │──────▶│ Cultia, edge,
│ ./lexicon publish <ds>        │   puis       │  └────┬─────┘      │  statiques │       │ téléchargement
│   → rsync, index.json en      │   index.json │       │ staging    └────────────┘       │
│     dernier                   │   en dernier)│       │ → contrôles                     │
└───────────────────────────────┘              │       │ → bascule                       │
                                               │       ▼                                 │
                                               │  ┌───────────────────────┐   ┌───────┐  │
                                               │  │ Postgres + PostGIS    │◀──│  API  │◀─│─ utilisateurs
                                               │  │  lexicon      (servi) │   └───────┘  │
                                               │  │  lexicon_staging      │              │
                                               │  │  lexicon_meta         │   sauvegarde │
                                               │  └───────────────────────┘   du dépôt   │
                                               │                              ─────────▶ │ S3
                                               └─────────────────────────────────────────┘
```

Quatre conteneurs sur le serveur : Postgres/PostGIS, loader, serveur de
fichiers statiques pour le dépôt, API. Le loader et la base ne sont pas
exposés.

## 2. Unité de publication : la datasource

- Une datasource = un package = une version = une bascule.
- **Chaque table appartient à une seule datasource.** C'est déjà vrai des 40
  datasources du package `6.0.2-full` (vérifié : aucune table partagée), à
  trois exceptions traitées au §5 : `master_translations`,
  `datasource_credits`, `lexicon.version`.
- Le `VERSION` global ne désigne plus que l'outillage.

### 2.1 Dépendances entre datasources (mesurées)

| Datasource | Dépend de (clé étrangère) | Dépend de (lecture au `normalize`) |
|---|---|---|
| `variants` | `taxonomy`, `units` | |
| `productions` | `taxonomy`, `units` | |
| `budgets` | `units`, `variants` | |
| `prices` | `phytosanitary`, `units`, `variants` | |
| `seed_varieties` | `taxonomy` | |
| `agroedi` | `productions` | |
| `technical_workflows` | `productions` | |
| `technical_workflow_sequences` | `productions`, `technical_workflows` | |
| `industry_sector` | `productions` | `taxonomy`, `open_nomenclature` |
| `rd_agri` | `productions`, `taxonomy` | `industry_sector`, `open_nomenclature`, `administrative_areas`, `phytosanitary` |

Tableau calculé par `Packaging::DependencyResolver` sur les 41 datasources
(lot 1) ; les 31 autres n'ont aucune dépendance.

Les six datasources lourdes
(hydrographie, cadastre, météo, RPG, propriétaires, prix cadastraux) n'ont
aucune dépendance : 96 % du volume se met à jour sans rien revalider.

Les lectures au `normalize` ne sont pas des clés étrangères : elles sont
déclarées à la main dans la datasource, par `depends_on`.

## 3. Format de package (version 3)

```
packages/
├── index.json
└── phytosanitary/
    └── 2026.10.03.1/
        ├── manifest.json
        ├── structure.sql        # CREATE TABLE, sans index secondaires
        ├── indexes.sql          # CREATE INDEX, à jouer après les données
        └── data/
            ├── registered_phytosanitary_products_0.csv.gz
            └── …
```

Les données restent des CSV compressés chargés par `COPY`, comme aujourd'hui
(géométries au format texte natif de PostGIS). Le passage à Parquet n'apporte
rien à J1.

### 3.1 `manifest.json`

```json
{
  "format": 3,
  "name": "phytosanitary",
  "version": "2026.10.03.1",
  "schema_revision": 4,
  "structure_hash": "sha256:…",
  "built_at": "2026-10-03T17:15:00Z",
  "tool_version": "7.0.0",
  "flavor": null,
  "credits": [
    { "name": "E-Phy", "provider": "ANSES", "url": "…", "licence": "Licence Ouverte 2.0",
      "licence_url": "…", "updated_at": "2026-09-15" }
  ],
  "depends_on": [
    { "name": "taxonomy", "built_against": "2026.09.15.1", "kind": "foreign_key" }
  ],
  "tables": [
    { "name": "registered_phytosanitary_products", "rows": 15234,
      "files": [ { "path": "data/registered_phytosanitary_products_0.csv.gz",
                   "sha256": "…", "bytes": 1048576 } ] }
  ],
  "foreign_keys": [
    { "table": "…", "column": "…", "references_table": "…", "references_column": "…" }
  ]
}
```

- `depends_on.kind` vaut `foreign_key` (déduit des `references` de la
  recette) ou `normalize` (déclaré à la main, §2.1).
- `rows` permet le contrôle de complétude au chargement.
- `structure_hash` détecte un changement de structure non annoncé par
  `schema_revision`.

### 3.2 `index.json`

```json
{
  "updated_at": "2026-10-03T17:20:00Z",
  "datasources": {
    "phytosanitary": { "current": "2026.10.03.1",
                       "versions": ["2026.09.15.1", "2026.10.03.1"] }
  }
}
```

`current` est la version que le serveur doit servir. La publication le fait
avancer ; le retour arrière le fait reculer. C'est le seul fichier modifié en
place, et il est écrit en dernier (F4).

## 4. Côté serveur

### 4.1 Schémas

| Schéma | Rôle |
|---|---|
| `lexicon` | Données servies. Nom stable : l'API et les consommateurs n'ont plus de schéma versionné à suivre (F26) |
| `lexicon_staging` | Chargement en cours. Vide hors chargement |
| `lexicon_meta` | Suivi des versions et des chargements |
| `postgis` | Extension, comme aujourd'hui |

### 4.2 `lexicon_meta`

```sql
CREATE TABLE lexicon_meta.packages (
  name            varchar PRIMARY KEY,
  version         varchar NOT NULL,
  schema_revision integer NOT NULL,
  structure_hash  varchar NOT NULL,
  loaded_at       timestamptz NOT NULL,
  stale           boolean NOT NULL DEFAULT false,  -- une dépendance a changé depuis le build
  manifest        jsonb NOT NULL
);

CREATE TABLE lexicon_meta.package_tables (
  table_name varchar PRIMARY KEY,
  package    varchar NOT NULL REFERENCES lexicon_meta.packages(name)
);

CREATE TABLE lexicon_meta.loads (
  id          bigserial PRIMARY KEY,
  name        varchar NOT NULL,
  version     varchar NOT NULL,
  previous    varchar,
  started_at  timestamptz NOT NULL,
  finished_at timestamptz,
  state       varchar NOT NULL
              CHECK (state IN ('loading', 'checking', 'swapped', 'failed', 'rolled_back')),
  detail      jsonb                                 -- contrôles, durées, erreur
);
```

`packages` répond à F9. `loads` est le journal qui sert à N8 et au retour
arrière. `package_tables` garantit qu'une table n'a qu'un propriétaire.

### 4.3 Le chargement d'une datasource

```
loader                         dépôt                 Postgres
  │  lit index.json  ───────────▶│
  │  current ≠ version en service ?
  │  télécharge rien : le dépôt est local
  │  vérifie les sha256  ────────▶│
  │
  │  ── phase 1 : staging (aucun verrou sur `lexicon`) ──────────────────▶
  │     pour chaque table, une transaction :
  │       CREATE TABLE lexicon_staging.t     (structure.sql)
  │       COPY … FROM PROGRAM 'zcat …'
  │       CREATE INDEX …                     (indexes.sql)
  │     ANALYZE
  │
  │  ── phase 2 : contrôles ─────────────────────────────────────────────▶
  │     a. lignes chargées = `rows` du manifest
  │     b. chute de volume : lignes < 70 % de la version en service → refus
  │        (levé par --force)
  │     c. clés sortantes : aucun orphelin de staging.t vers lexicon.cible
  │     d. clés entrantes : aucun orphelin de lexicon.dépendante vers staging.t
  │     e. aucun objet étranger (vue, vue matérialisée) ne dépend des tables
  │        à remplacer
  │     échec → DROP des tables de staging, `loads.state = failed`,
  │             l'ancienne version reste en service (F8)
  │
  │  ── phase 3 : bascule, une transaction ──────────────────────────────▶
  │     SET lock_timeout = '5s'      (nouvel essai, 5 tentatives)
  │     DROP des clés étrangères entrantes et sortantes
  │     ALTER TABLE lexicon.t          SET SCHEMA lexicon_staging  (renommée t__old)
  │     ALTER TABLE lexicon_staging.t  SET SCHEMA lexicon
  │     ADD CONSTRAINT … FOREIGN KEY … NOT VALID      (entrantes et sortantes)
  │     UPDATE lexicon_meta.packages, package_tables, loads
  │     COMMIT
  │
  │  ── phase 4 : après la bascule ──────────────────────────────────────▶
  │     VALIDATE CONSTRAINT …        (déjà vérifié en 2c et 2d)
  │     DROP TABLE lexicon_staging.t__old
  │     régénère les vues dérivées (§5)
  │     marque `stale` les datasources construites contre l'ancienne version
```

- La phase 1 est la seule longue ; elle ne touche pas aux données servies
  (F7). La phase 3 ne déplace que des entrées de catalogue : elle dure moins
  d'une seconde quelle que soit la taille.
- `SET SCHEMA` exige un verrou exclusif bref. Une requête longue de l'API peut
  le retarder ; `lock_timeout` évite de bloquer les lectures derrière lui.
- Les tables d'une datasource basculent ensemble : jamais d'état mixte.
- Une datasource nouvelle suit le même chemin, sans ancienne version à
  écarter. Une datasource retirée de `index.json` est supprimée par
  `lexicon server prune`, jamais automatiquement.

### 4.4 Dépendances (F11)

| Situation | Comportement |
|---|---|
| `taxonomy` change, toutes les références existent encore | Bascule. `variants`, `productions`, `seed_varieties`, `rd_agri` sont marquées `stale` |
| `taxonomy` change, `variants` référence un taxon supprimé | Refus en 2d, avec la liste des valeurs orphelines. Il faut publier `variants` en même temps |
| Plusieurs datasources publiées ensemble | Le loader les traite comme un **lot** : staging de toutes, contrôles croisés entre versions de staging, une seule transaction de bascule |
| Dépendance `normalize` | Jamais bloquante. Seulement `stale` |

`stale` est une information pour le mainteneur (« à reconstruire »), pas un
état d'erreur : la datasource reste servie.

### 4.5 Retour arrière (F10)

`lexicon server rollback <ds>` remet `current` sur la version précédente dans
`index.json` et relance le chargement normal. Le coût est celui d'un
chargement : quelques secondes pour un référentiel, plusieurs heures pour le
cadastre. Garder l'ancienne version en base rendrait le retour instantané
mais doublerait le disque des grosses datasources ; ce choix peut être rouvert
datasource par datasource en J2.

### 4.6 Déclenchement

Le loader est un conteneur permanent qui surveille `index.json` (toutes les
cinq minutes, ou à la demande par `lexicon server sync`). Un verrou
consultatif Postgres garantit un seul chargement à la fois.

## 5. Les trois tables partagées

Elles empêchent aujourd'hui toute bascule indépendante.

### 5.1 `datasource_credits`

Reconstruite à chaque dump pour toutes les datasources. Elle devient une
**vue** sur `lexicon_meta.packages.manifest->'credits'`, de mêmes colonnes.
`Credits.ts` de l'API continue de fonctionner.

### 5.2 `master_translations`

Alimentée par 13 datasources, chacune effaçant puis réinsérant ses lignes.

- Chaque datasource écrit dans sa propre table `<ds>__translations(id, fra,
  eng)`, qui fait partie de son package.
- `master_translations` devient une **vue** `UNION ALL` de ces tables,
  régénérée par le loader en phase 4.
- Les colonnes `translation_id` ne changent pas. `Production.ts` de l'API et
  Cultia continuent de fonctionner.
- Changement côté code : `Base#insert_translations` vise la table de la
  datasource, et les 13 datasources déclarent cette table.

Les nouvelles tables utilisent `label jsonb` (C5). La migration des 14 tables
existantes se fera table par table, hors J1, la vue restant en place tant
qu'un consommateur s'en sert.

### 5.3 `lexicon.version`

Supprimée. `lexicon_meta.packages` la remplace. Cultia ne la lit pas (§12).

## 6. Côté build

### 6.1 Commandes

| Commande | Rôle |
|---|---|
| `./lexicon run <ds>` | Inchangée |
| `./lexicon package <ds…>` | Produit `out/packages/<ds>/<version>/` depuis le schéma local `lexicon`. Remplace `dump` |
| `./lexicon publish <ds…>` | Envoie le package, puis met `current` à jour dans `index.json` |
| `./lexicon bundle <flavor>` | Produit un bundle filtré (§7) |
| `./lexicon status` | Version locale, publiée et en service de chaque datasource |
| `./lexicon server sync [ds…]` | Sur le serveur : charge ce qui doit l'être |
| `./lexicon server status` | Versions en service, `stale`, derniers chargements |
| `./lexicon server rollback <ds>` | §4.5 |
| `./lexicon server prune` | Supprime les datasources retirées et les versions hors rétention |

`dump`, `remote`, `production` et `version bump` disparaissent.

### 6.2 `package`

- Exporte table par table avec `\copy … TO PROGRAM 'pigz'`, comme aujourd'hui,
  mais **sans renommer le schéma `lexicon`** : le dump actuel le renomme le
  temps de l'export, ce qui bloque tout autre usage de la base.
- Sépare la structure en `structure.sql` (tables) et `indexes.sql` (index
  secondaires). Les clés primaires restent dans `CREATE TABLE`.
- Refuse de produire un package si la validation locale échoue (tables
  vides, clés étrangères absentes). Cela suppose de corriger `./lexicon
  validate`, qui plante aujourd'hui.
- Borne le parallélisme (4 exports simultanés par défaut).

### 6.3 `publish`

1. `rsync` du répertoire de version vers le serveur, reprise possible.
2. Vérification distante des sha256.
3. Mise à jour de `index.json`, envoyée en dernier (F4).

L'accès se fait par une clé SSH dédiée, limitée à `rsync` dans le dépôt de
packages (`rrsync`). La machine de build n'a aucun accès à la base (N5).

## 7. Flavors et bundles (C6)

- Un **bundle** est un dépôt de packages complet et autonome : son propre
  `index.json` et un sous-ensemble de datasources, filtrées ou non. Il se
  charge avec `lexicon server sync` sur n'importe quel Postgres.
- `./lexicon bundle cultia` lit `resources/flavors/cultia.yml` (format
  inchangé : `without`, filtres SQL par table) et produit
  `out/bundles/cultia/`. Le champ `flavor` du manifest l'identifie.
- Les bundles sont publiés sous `packages/_bundles/<flavor>/`. Cultia
  télécharge le sien par HTTPS.
- L'usage « edge » que vous décrivez (références spatiales autour d'un point
  ou d'une parcelle) demande des flavors **paramétrés** (point, rayon). Les
  flavors actuels codent les coordonnées en dur dans le YAML ; les paramétrer
  est une extension naturelle, placée en J2.

## 8. Dimensionnement du serveur

### 8.1 Disque (N1)

| Poste | Taille |
|---|---:|
| Base servie | 278 Go |
| Staging, pire cas (`hydrography`, 3 tables) | 103 Go |
| WAL et fichiers temporaires | 20 Go |
| Dépôt : un jeu complet de packages | 52 Go |
| Système, Docker, journaux | 20 Go |
| **Total engagé** | **≈ 475 Go** |
| **Reste pour l'historique, les bundles et J3** | **≈ 325 Go** |

Les 325 Go restants représentent six jeux complets de packages, ou bien
davantage si seules les petites datasources gardent un historique long
(annexe A).

### 8.2 Mémoire (N2)

| Poste | Réglage |
|---|---|
| `shared_buffers` | 8 Go |
| `effective_cache_size` | 20 Go |
| `maintenance_work_mem` | 2 Go |
| `work_mem` | 64 Mo |
| `max_connections` | 50 |
| Loader | 2 flux `COPY` et 2 créations d'index simultanés au plus |
| API | 1 Go |
| Dokploy, Traefik, serveur statique | 2 Go |

Le chargement est borné à 2 flux pour laisser le cache disque à l'API. La gem
actuelle lance un thread par fichier sans limite.

### 8.3 Journal de transactions

`wal_level = minimal` et `max_wal_senders = 0`. Avec ce réglage, une table
créée et remplie dans la même transaction n'écrit pas ses données dans le
WAL : c'est ce qui rend le chargement du cadastre supportable en temps et en
disque. Contrepartie : ni réplication ni restauration à un instant donné.
C'est acceptable puisque la base se reconstruit depuis le dépôt (C4).

## 9. Vérification contre les exigences

| Exigence | Réponse |
|---|---|
| F1, F2, F3, F5 | Format v3, version par datasource, `index.json`, `depends_on` (§3) |
| F4 | `index.json` écrit en dernier (§3.2, §6.3) |
| F5b | Dépôt sur le serveur ; plus aucun appel au MinIO (§6.1) |
| F6 | Loader permanent (§4.6) |
| F7, F8 | Staging sans verrou, bascule en une transaction, échec sans effet (§4.3) |
| F9 | `lexicon_meta.packages`, `server status` (§4.2) |
| F10 | `server rollback` (§4.5) |
| F11 | Contrôles 2c et 2d, lots, `stale` (§4.4) |
| N1, N2 | §8 |
| N3 | Coût = chargement de la seule datasource. À mesurer sur `phytosanitary` (cible : 15 min) |
| N4 | Hors J1 pour la partie « build identique » ; le manifest porte déjà les sha256 |
| N5 | Clé SSH limitée au dépôt, base non exposée (§6.3) |
| N8 | `status`, `server status`, `server rollback` (§6.1) |

## 10. Risques

| Risque | Parade |
|---|---|
| Chargement initial du cadastre et de l'hydrographie sur le serveur | Mesurer tôt (lot 7). Sans index secondaires pendant le `COPY` et avec `wal_level = minimal`, l'ordre de grandeur attendu est de quelques heures par datasource |
| Clé primaire créée avant les données sur les tables de 100 Go | Accepté en J1. Si la mesure est mauvaise, déplacer la clé primaire dans `indexes.sql` |
| Verrou de bascule retardé par une requête longue de l'API | `lock_timeout` et nouvelles tentatives ; `statement_timeout` côté API |
| Disque de la machine de build (180 Go libres) | `out/6.0.2-full` (52 Go) et les anciens flavors deviennent supprimables une fois les packages publiés |
| MinIO déjà indisponible : plus aucun moyen de publier jusqu'au lot 2 | Garder `out/` intact ; avancer le lot 2 juste après le lot 1 |

## 11. Lots et effort

| Lot | Contenu | Effort |
|---|---|---:|
| 1 | Format v3, commande `package`, séparation structure / index, correction de `validate` — **fait** | 4–5 j |
| 2 | `publish`, `index.json`, accès SSH restreint, `status` | 2–3 j |
| 3 | Loader : staging, contrôles, bascule, `lexicon_meta`, verrou, journal | 6–8 j |
| 4 | Dépendances : contrôles d'orphelins, lots, `stale`, `rollback` | 3–4 j |
| 5 | Tables partagées : traductions, crédits, version | 2–3 j |
| 6 | Bundles et flavors | 2–3 j |
| 7 | Serveur : Postgres réglé, loader, dépôt statique, sauvegarde S3 par Dokploy, mesures de chargement | 2–3 j |
| 8 | Bascule : chargement initial complet, API sur `DB_SCHEMA=lexicon`, bundle `cultia`, retrait de la gem, documentation, réécriture de `ROADMAP.md` | 4–5 j |
| | **Total** | **25–34 j** |

Ordre conseillé : 1, 2, 3 et 5 d'abord, validés de bout en bout sur `units` puis
`phytosanitary` (qui exerce la dépendance `prices → phytosanitary`). Le lot 7
peut démarrer en parallèle dès que le serveur est accessible.

## 12. Points confirmés

1. Cultia ne lit ni `lexicon.version`, ni un nom de schéma versionné, ni
   `datasource_credits`. La vue de compatibilité `lexicon.version` (§5.3)
   n'est donc pas créée.
2. Débit montant : 500 Mb/s en filaire. L'envoi initial de 52 Go prend
   environ un quart d'heure ; le transport n'est pas une contrainte.
3. Le MinIO est déjà indisponible. Les seuls packages existants sont ceux de
   `out/` sur la machine de build (`6.0.2-full`, `6.0.2-innovation`,
   `6.0.2-cultia`, `6.1.0-cultia`) : ils sont à conserver jusqu'à la fin du
   lot 8. Les commandes `remote` et `production` actuelles ne fonctionnent
   plus ; le lot 2 est donc le premier moyen de republier.
4. Annexe A complétée : seuls `graphic_parcels` (par campagne) et
   `cap_beneficiaries` restent interrogeables dans le passé. Les nombres de
   versions gardées proposés sont retenus tels quels.

L'interface de gestion des accès (clés d'API, quotas) fait l'objet d'un
document séparé : `claudedocs/design_lexicon_v2_admin.md`.

## Annexe A — Rétention et historique (Q8), à compléter

Colonnes à remplir : **versions gardées** dans le dépôt (téléchargeables, F28)
et **interrogeable dans le passé** par l'API (F29, conçu en J2). Les valeurs
proposées sont des points de départ.

| Datasource | Base | Package | Fréquence de la source | Versions gardées (proposé) | Interrogeable dans le passé (proposé) | Votre choix |
|---|---:|---:|---|---:|---|---|
| hydrography | 103 Go | 24,9 Go | annuelle | 1 | non | non |
| cadastre | 100 Go | 22,3 Go | trimestrielle | 1 | non | non |
| weather | 43 Go | 2,4 Go | continue | 2 | non (déjà une série temporelle) | non |
| graphic_parcels (RPG) | 12 Go | 3,9 Go | annuelle | 3 | oui, par campagne | oui, par campagne|
| cadastre_owners | 10 Go | 0,7 Go | annuelle | 2 | non | non |
| cadastral_prices | 6,6 Go | 0,6 Go | semestrielle | 2 | non (déjà daté) | non |
| postal_codes | 0,7 Go | 0,5 Go | annuelle | 2 | non | non |
| cap_beneficiaries | 0,7 Go | 0,05 Go | annuelle | 5 | oui | oui |
| rica | 0,6 Go | 0,1 Go | annuelle | 3 | non (déjà daté) | non |
| enterprises | 0,4 Go | 0,05 Go | mensuelle | 3 | non | non |
| phytosanitary | 0,14 Go | < 0,01 Go | hebdomadaire | 12 | oui | non |
| rd_agri | 0,09 Go | à mesurer | à la demande | 3 | non | non |
| protected_natural_zones | 0,08 Go | 0,08 Go | annuelle | 2 | non | non |
| eu_market_prices | 0,06 Go | < 0,01 Go | hebdomadaire | 4 | non (déjà daté) | non |
| Référentiels métier (units, taxonomy, variants, productions, prices, budgets, technical_workflows, technical_workflow_sequences, intervention_models, industry_sector, open_nomenclature, chart_of_accounts, user_roles, translations, legal_positions, phenological_stages, production_documentations, enterprise_classifications) | < 0,05 Go au total | < 0,01 Go | à chaque modification | toutes | oui | non |
| Autres petits jeux (seed_varieties, vine_varieties, agroedi, soil, protected_water_zones, msa_populations, quality_and_origin_signs, administrative_areas, agricultural_pictures) | < 0,05 Go au total | < 0,02 Go | annuelle | 5 | non | non |

Avec ces valeurs, l'historique occupe environ 20 Go dans le dépôt, loin des
325 Go disponibles. Conséquence pour J2 : l'interrogation dans le passé ne
concerne que `graphic_parcels` et `cap_beneficiaries`, deux jeux déjà
organisés par campagne ou par année. Elle peut donc se traiter par une
colonne de millésime dans la table, sans conserver plusieurs versions en
base.
