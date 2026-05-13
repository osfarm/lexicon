# Workflow — Migration `graphic_parcels` vers RPG 3.0 (GPKG unique, Lambert-93)

> **Statut :** plan d'implémentation. Aucun code modifié à ce stade.
> **Prochaine étape :** lancer `/sc:implement claudedocs/workflow_graphic_parcels_rpg3.md` pour exécution pas à pas.

---

## 1. Objectif

Refondre la datasource `Datasources::GraphicParcels` (`lib/datasources/graphic_parcels.rb`) pour qu'elle importe le **RPG 3.0 millésime 2024** distribué par l'IGN/ASP sous la forme **d'un seul GeoPackage France métropolitaine** en projection **Lambert-93 (EPSG:2154)**, en s'inspirant du pattern d'import de `lib/datasources/hydrography.rb` (ogr2ogr → schéma raw → INSERT normalize).

Réf. doc : `doc/datasources/DC_DL_RPG_3-0.pdf`.

---

## 2. État actuel à remplacer

### 2.1 Datasource existante (`lib/datasources/graphic_parcels.rb`)

- Cible le RPG 2.2 (millésime 2023-01-01), format shapefile.
- Téléchargement programmatique : **17 archives .7z** (13 régions métropole en LAMB93 + 4 zones outre-mer en projections UTM locales).
- Décompression, copie shp/shx/dbf/prj par région.
- Constantes :
  - `ZONES` : 5 codes projection (`LAMB93=2154`, `RGAF09UTM20=5490`, `UTM22RGFG95=2972`, `RGR92UTM40S=2975`, `RGM04UTM38S=4471`).
  - `REGIONS` : 17 codes (R01…R94).
- `load` : `load_shp` (helper Base) par région → 17 tables `parcelles_graphiques_<zone>_<region>` ; chargement parallèle (multi-thread, plafond 10 connexions psql).
- `normalize` : boucle 17 INSERTs avec `ST_Transform(geom, 4326)`, jointure spatiale avec `graphic_parcels.cities` (issue de `data/graphic_parcels/COMMUNE_CARTO.shp`) pour renseigner `city_name` via une table temporaire `ilotscom`.

### 2.2 Table cible `registered_graphic_parcels` (inchangée a priori)

```sql
CREATE TABLE registered_graphic_parcels (
  id character varying NOT NULL,
  cap_crop_code character varying,
  city_name character varying,
  shape postgis.geometry(Polygon, 4326) NOT NULL,
  centroid postgis.geometry(Point, 4326)
);
```

Indexée sur `id`, `city_name`, `shape (GIST)`, `centroid (GIST)`.

---

## 3. Inventaire réel dans `raw/graphic_parcels/` (vérifié)

**État au moment de ce plan** : **les 8 sous-produits RPG 3.0 sont présents**. Total disque : **~42 Go**.

| Fichier | Couche(s) interne(s) | Géométrie | Features | Taille |
|---|---|---|---:|---:|
| `RPG_Parcelles.gpkg` | `RPG_Parcelles` | MultiPolygon | 9 679 522 | 6.2 Go |
| `RPG_Ilots.gpkg` | `RPG_Ilots` | MultiPolygon | 5 837 743 | 4.4 Go |
| `RPG_PAC.gpkg` | `RPG_PAC` | MultiPolygon | 9 230 156 | 6.0 Go |
| `RPG_PP.gpkg` | `RPG_PP` | MultiPolygon | 3 312 751 | 2.5 Go |
| `RPG_BIO.gpkg` | `RPG_BIO` | MultiPolygon | 1 117 752 | 696 Mo |
| `RPG_IAE.gpkg` | `RPG_IAE` | MultiPolygon | 884 160 | 480 Mo |
| `RPG_ZDH.gpkg` | `RPG_ZDH` | MultiPolygon | 4 925 609 | 3.5 Go |
| `RPG_SNA.gpkg` | `SNA_VEGETATION_SURFACIQUE` | MultiPolygon | 18 287 579 | 18 Go (cumulé) |
|  | `SNA_AUTRES_ELEMENTS` | MultiPolygon | 1 949 655 |  |
|  | `SNA_ELEMENT_ARTIFICIALISE` | MultiPolygon | 9 657 399 |  |
|  | `SNA_VEGETATION_PONCTUELLE` | Point | 16 264 398 |  |

Tous les fichiers sont en **EPSG:2154 (Lambert-93)** ✓.

### 3.1 Schémas réels (différences vs PDF)

L'inspection révèle des **divergences entre la documentation PDF et les fichiers livrés** :

| Couche | Champs réels | Conforme PDF ? |
|---|---|---|
| `RPG_Parcelles` | `ID_PARCEL` (str), `SURF_PARC` (real), `CODE_CULTU` (str 3), `CODE_GROUP` (str 2), `CULTURE_D1` (str 3), `CULTURE_D2` (str 3) | ⚠️ **Pas de `cat_cult_p`** (PDF §3.2.1 l'annonçait) |
| `RPG_Ilots` | `num_ilot` (str 12) | OK (PDF §4.1.2) |
| `RPG_PAC` | `code_culture` (str 4), `code_group` (str 2), `surf_parc` (real), `cat_cult_p` (str 3) | ⚠️ **Pas de `id_parcel`** (parcelles anonymisées) |
| `RPG_PP` | idem PAC | ⚠️ Pas de `id_parcel` |
| `RPG_BIO` | idem PAC | ⚠️ Pas de `id_parcel` |
| `RPG_IAE` | idem PAC | ⚠️ Pas de `id_parcel` |
| `RPG_ZDH` | (aucun attribut, géométrie seule) | OK |
| `RPG_SNA` (4 couches) | (aucun attribut, géométrie seule) | OK |

**Points d'attention :**
1. **Casse hétérogène** : `RPG_Parcelles` utilise MAJUSCULES (`ID_PARCEL`), les autres minuscules (`code_culture`). ogr2ogr lowercase par défaut côté PostgreSQL (`LAUNDER=YES`), donc en raw les colonnes seront toutes en minuscules.
2. **Nom et longueur du code culture diffèrent** : `CODE_CULTU` (3 chars) dans `RPG_Parcelles` vs `code_culture` (4 chars) dans les autres. Pas joignables sans transformation.
3. **Pas de clé commune** entre `RPG_Parcelles` (seul porteur d'`ID_PARCEL`) et les autres GPKG : ces sous-produits ne peuvent pas être attachés aux parcelles par jointure attributaire — uniquement par intersection spatiale. `RPG_Ilots` (porteur d'un `num_ilot`) n'est pas non plus joignable directement à `id_parcel` — le PDF §4.1.2 mentionne un exemple de `num_ilot` de la forme `974-9390792` (préfixe région + identifiant), mais sans documentation formelle d'un lien avec `id_parcel`.
4. **Extents** : `RPG_Parcelles` et `RPG_Ilots` sont strictement métropole (`100 km → 1.24 M m` en Lambert-93). `RPG_ZDH` et `RPG_SNA` ont des extents incluant outre-mer (BBox de -6.7 M à +10.3 M m) → données outre-mer reprojetées en Lambert-93 (pas leur projection légale).

## 4. RPG 3.0 — éléments clés extraits du PDF

### 4.1 Offre et format de livraison

À partir du millésime 2024, l'offre RPG est éclatée en 8 sous-produits (PDF §1.1.2), **chacun distribué en GeoPackage séparé** (PDF §13.2) :

| Fichier | Contenu |
|---|---|
| **`RPG_Parcelles.gpkg`** | Parcelles agricoles constatées ← **équivalent direct de l'ancien `PARCELLES_GRAPHIQUES.shp`** |
| `RPG_Ilots.gpkg` | Îlots anonymes |
| `RPG_PAC.gpkg` | Parcelles agricoles catégorisées |
| `RPG_PP.gpkg` | Prairies permanentes |
| `RPG_SNA.gpkg` | Surfaces non agricoles (sous-classes ponctuel/surfacique/artif/autres) |
| `RPG_ZDH.gpkg` | Zones de densité homogène |
| `RPG_IAE.gpkg` | Parcelles éligibles IAE |
| `RPG_BIO.gpkg` | Parcelles bio |

**Pour alimenter `registered_graphic_parcels`, seul `RPG_Parcelles.gpkg` est requis.** Les autres sous-produits sont hors scope (peuvent être ajoutés ultérieurement si besoin).

### 4.2 Projection

PDF §2.3 : projections légales par zone. Pour la France métropolitaine livrée demandée → **Lambert-93 / EPSG:2154**. Le PDF confirme aussi que le RPG est livré pour l'ensemble des départements français + Saint-Barthélemy et Saint-Martin (§2.2). Outre-mer hors scope ici (cf. décision §5.1).

### 4.3 Arborescence de livraison

PDF §12.1 / §13 :

```
RPG/
└── 1_DONNEES_LIVRAISON_{AAAA}/
    └── RPG_{VERSION}_{FORMAT}_{RIG}_{INFO}/
        ├── RPG_Parcelles.gpkg
        ├── RPG_Ilots.gpkg
        ├── ...
LISEZ-MOI.pdf
```

Exemple plausible : `RPG_3-0__GPKG_LAMB93_FXX_2024-01-01/RPG_Parcelles.gpkg`.

### 4.4 Attributs de la classe `RPG Parcelles` (PDF §3.2.2)

| Attribut | Type | Définition |
|---|---|---|
| `id_parcel` | Caractères (10 max.) | Identifiant unique de la parcelle |
| `code_cultu` | Caractères (3) | Code culture principale (lien table REF_CULTURES) |
| `code_group` | Caractères (2) | Code groupe culture principale (1..28, ou `NR`) |
| `culture_d1` | Caractères (3) | Code culture dérobée 1 (optionnel) |
| `culture_d2` | Caractères (3) | Code culture dérobée 2 (optionnel) |
| `surf_parc` | Décimal (8,2) | Surface en hectares |
| `cat_cult_p` | Caractères (3) | Catégorie culture principale : `TA` / `CP` / `PP` / `NA` |

**Géométrie :** surface 2D simple (polygones).

### 4.5 Identifiants

PDF §2.4 : `id_parcel` est désormais **continu depuis l'édition 2022** — donc compatible/comparable entre millésimes 2022+. Avant 2022, pas de correspondance.

### 4.6 Volume

PDF §11.4 :
- France métropolitaine : **~8 Go** (.gpkg unique).
- Région métropolitaine moyenne : ~400 Mo.
- Région outre-mer moyenne : ~15 Mo.

→ Conséquence : import lourd. Tester sur une région d'abord si possible.

---

## 5. Modèle d'import à reprendre : `hydrography.rb`

Pattern récemment validé (cf. commit `15440ee` + modifs récentes) :

- **`collect`** vérifie la présence du fichier `.gpkg` localement, pas de téléchargement réseau (donnée fournie manuellement).
- **`load`** utilise `ogr2ogr` pour pousser le `.gpkg` vers PostgreSQL :
  ```bash
  ogr2ogr -f PostgreSQL "PG:host=... port=... dbname=..." \
    -overwrite \
    -lco SCHEMA=<schema> \
    -lco GEOMETRY_NAME=geom \
    -lco FID=ogc_fid \
    -nlt PROMOTE_TO_MULTI \
    -t_srs EPSG:4326 \
    -nln <table_name> \
    <file.gpkg> <layer_name>
  ```
- Helper `pg_connection_string` (méthode privée) — **avec le préfixe `PG:`** (fix appliqué récemment dans hydrography, à reprendre ici).
- **`normalize`** : INSERTs SQL classiques avec `ST_Force2D` et `ST_Dump` si nécessaire, `ST_Centroid` pour les centroides.

L'avantage d'`ogr2ogr` ici : il reprojette automatiquement (Lambert-93 → WGS84) durant le load, ce qui évite l'étape `ST_Transform` dans le normalize.

---

## 6. Décisions d'architecture à valider

### 6.1 Périmètre géographique

| Option | Implication |
|---|---|
| **A. (recommandé) France métropolitaine seule** | Conforme à la formulation utilisateur ("fichier GPKG unique pour la France, projection 2154"). 1 seul fichier à fournir. Simple. |
| B. Métropole + outre-mer | Charger 1 GPKG par zone (LAMB93 + 4 UTM locales). 5 fichiers, 5 imports ogr2ogr. Plus complexe mais couvre l'usage historique. |

**Proposition retenue : Option A.** Conserver `ZONES`/`REGIONS` comme code mort serait du désordre — on supprime. `RPG_Parcelles.gpkg` livré est strictement métropole (extent vérifié) ; les autres GPKG (PAC, ZDH, SNA…) contiennent visiblement quelques entités outre-mer (extent étendu), à filtrer si elles sont chargées.

### 6.2 Sous-produits RPG à charger

**Contexte mis à jour** : l'utilisateur a déposé **les 8 sous-produits RPG 3.0** dans `raw/graphic_parcels/`. Le choix devient explicite :

| Option | Sous-produits | Volume DB estimé | Cibles `registered_*` |
|---|---|---:|---|
| **A. (recommandé) `RPG_Parcelles` seul** | 1 fichier (6.2 Go raw) | ~12-15 Go | `registered_graphic_parcels` (inchangé) |
| B. Parcelles + Ilots | 2 fichiers (10.6 Go raw) | ~22-25 Go | +`registered_rpg_ilots` |
| C. Parcelles + Ilots + PAC + PP + BIO | 5 fichiers (19.8 Go raw) | ~42-48 Go | +PAC, PP, BIO (3 cibles spatiales) |
| D. Les 8 présents | 8 fichiers (42 Go raw) | ~90 Go | + ZDH, SNA (4 couches), IAE |

**Proposition retenue : Option A** pour la première itération. Justifications :
- Seul `RPG_Parcelles` porte `ID_PARCEL` — les autres couches sont géométriquement utiles mais nécessitent une jointure spatiale lente avec les parcelles si on veut les exploiter ensemble.
- Volume DB raisonnable et délai d'import gérable (~30-60 min ogr2ogr + index).
- Les autres GPKG resteront sur disque (non chargés) ; un futur PR pourra les intégrer si besoin métier (en particulier `RPG_Ilots` pour une vue agrégée).
- **À confirmer côté utilisateur** : si l'objectif était de charger l'ensemble dès maintenant, basculer sur B, C ou D.

### 6.3 Schéma cible

| Option | Impact downstream |
|---|---|
| **A. (recommandé) Inchangé** : `registered_graphic_parcels (id, cap_crop_code, city_name, shape, centroid)` | Compatibilité ascendante totale. Les champs `code_group`, `culture_d1/d2`, `surf_parc` (présents dans `RPG_Parcelles`) sont **perdus**. `cat_cult_p` n'est pas disponible dans `RPG_Parcelles` (cf. §3.1). |
| B. Enrichi : ajouter `crop_group_code` (2), `cover_crop_1` (3), `cover_crop_2` (3), `area_ha` (numeric 8,2) | Plus riche, mais migration côté Ekylibre. `cat_cult_p` reste impossible à renseigner ici. |

**Proposition retenue : Option A** par défaut. Si l'équipe produit veut ces champs, basculer sur B avant l'implémentation.

### 6.4 Stratégie de fourniture du `.gpkg`

✓ **Décision validée** : fichiers fournis manuellement dans `raw/graphic_parcels/`. Confirmé par l'inspection actuelle — les 7 GPKG sont déjà déposés.

`collect` vérifie la présence du (ou des) `.gpkg` requis et lève une erreur explicite sinon (pattern `hydrography#collect`).

### 6.5 Devenir du shapefile des communes

`data/graphic_parcels/COMMUNE_CARTO.shp` est déjà bundlé dans le repo (cf. listing) et sert au join spatial pour `city_name`. **À conserver tel quel** — pas de raison de changer.

Décision dérivée : maintenir le chargement existant via `load_shp` + `ALTER TABLE ... ST_Transform → 4326`.

---

## 7. Plan d'implémentation détaillé

### Phase 1 — Préparation (~10 min)

- [ ] **1.1** Confirmer les 5 décisions ci-dessus (§6) — en particulier §6.2 (Parcelles seul vs élargi : A/B/C/D).
- [x] **1.2** ~~Récupérer le `.gpkg`~~ — **fait** : `RPG_Parcelles.gpkg` (et 6 autres sous-produits) sont déjà présents dans `raw/graphic_parcels/`.
- [x] **1.3** ~~Inspecter le GPKG~~ — **fait** (cf. §3) : couche **`RPG_Parcelles`**, MultiPolygon, EPSG:2154, attributs `ID_PARCEL`, `SURF_PARC`, `CODE_CULTU` (3), `CODE_GROUP` (2), `CULTURE_D1` (3), `CULTURE_D2` (3). FID `fid`, géométrie `geom`.
- [ ] **1.4** Re-lire `lib/datasources/hydrography.rb` (méthodes `collect`, `load`, `pg_connection_string`) pour réutiliser le pattern à l'identique.

### Phase 2 — Refonte de `lib/datasources/graphic_parcels.rb` (~1h30)

- [ ] **2.1** Mettre à jour les métadonnées :
  - `LAST_UPDATED = "2024-01-01"` (à confirmer selon la date d'édition exacte des données).
  - `description "RPG v3.0 — Parcelles agricoles constatées (France métropolitaine)"`.
  - `credits` : conserver URL géoservices, provider IGN/ASP, ajouter mention "MASA" si pertinent.
- [ ] **2.2** Supprimer `ZONES` et `REGIONS` (et toute la logique multi-zone associée).
- [ ] **2.3** Définir les constantes :
  ```ruby
  SCHEMA = 'graphic_parcels'.freeze
  GPKG_FILE = 'RPG_Parcelles.gpkg'.freeze
  LAYER = 'parcelles_graphiques'.freeze  # nom de la couche raw dans le schéma
  SOURCE_SRID = 2154
  ```
- [ ] **2.4** Ajouter en commentaire d'en-tête la procédure manuelle (mirror du commentaire de `hydrography.rb` : « drop the `.gpkg` file into `raw/graphic_parcels/`... »).

### Phase 3 — `collect` (~15 min)

- [ ] **3.1** Vérifier la présence du `.gpkg` et lever une erreur explicite sinon (pattern `hydrography#collect`).
- [ ] **3.2** Pas de téléchargement, pas de décompression.

### Phase 4 — `load` (~45 min)

- [ ] **4.1** `database.ensure_schema(SCHEMA)`.
- [ ] **4.2** Toujours charger les communes (logique existante) :
  - `FileUtils.cp_r 'data/graphic_parcels/.', dir` (ou ne copier que `COMMUNE_CARTO.*`).
  - `load_shp(dir.join('COMMUNE_CARTO.shp'), table_name: 'cities')`.
  - `ALTER TABLE cities ALTER COLUMN geom TYPE postgis.geometry(MultiPolygon, 4326) USING postgis.ST_Transform(geom, 4326);`.
- [ ] **4.3** Charger le RPG via `ogr2ogr`. Nom de couche confirmé : **`RPG_Parcelles`** (cf. §3) :
  ```ruby
  execute <<~BASH
    ogr2ogr \
      -f PostgreSQL "#{pg_connection_string}" \
      -overwrite \
      -lco SCHEMA=#{SCHEMA} \
      -lco GEOMETRY_NAME=geom \
      -lco FID=ogc_fid \
      -nlt PROMOTE_TO_MULTI \
      -t_srs EPSG:4326 \
      -nln #{LAYER} \
      "#{dir.join(GPKG_FILE)}" RPG_Parcelles
  BASH
  ```
  Côté PostgreSQL, ogr2ogr applique `LAUNDER=YES` par défaut → les colonnes seront en minuscules : `id_parcel`, `surf_parc`, `code_cultu`, `code_group`, `culture_d1`, `culture_d2`.
- [ ] **4.4** Helper `pg_connection_string` privé, **avec préfixe `PG:`** (copier la version corrigée de `hydrography.rb`).

### Phase 5 — `table_definitions` (~10 min)

- [ ] **5.1** Garder à l'identique (option A §5.3) :
  ```ruby
  builder.table :registered_graphic_parcels, sql: <<-SQL
    CREATE TABLE registered_graphic_parcels (
      id character varying NOT NULL,
      cap_crop_code character varying,
      city_name character varying,
      shape postgis.geometry(Polygon, 4326) NOT NULL,
      centroid postgis.geometry(Point, 4326)
    );
    CREATE INDEX ...
  SQL
  ```
  *Note : type `Polygon` vs `MultiPolygon`. Le `-nlt PROMOTE_TO_MULTI` côté ogr2ogr force MultiPolygon dans la table raw — un `ST_Dump` en normalize redonnera des Polygon simples. Conserver `Polygon` côté cible.*
- [ ] **5.2** (Optionnel — option B §5.3) Ajouter `crop_group_code`, `cover_crop_1`, `cover_crop_2`, `area_ha numeric(8,2)`, `cult_category character varying(3)`.

### Phase 6 — `normalize` (~45 min)

- [ ] **6.1** INSERT unique (plus de boucle multi-zone) avec `ST_Dump` pour repolygoniser les MultiPolygon et `ST_Buffer(geom, 0.0)` pour réparer d'éventuelles invalidités (logique reprise de l'existant). Colonnes source en minuscules après ogr2ogr (`id_parcel`, `code_cultu`) :
  ```sql
  INSERT INTO registered_graphic_parcels (id, cap_crop_code, shape, centroid)
  SELECT
    id_parcel,
    code_cultu,
    (postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(geom), 0.0))).geom,
    postgis.ST_Centroid((postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(geom), 0.0))).geom)
  FROM graphic_parcels.parcelles_graphiques
  ```
  *Note : `ST_Transform` non requis — ogr2ogr a déjà reprojeté en 4326.*
- [ ] **6.2** UPDATE `city_name` via jointure spatiale. Reprendre la logique existante ou la simplifier en un seul UPDATE :
  ```sql
  UPDATE registered_graphic_parcels p
     SET city_name = c.nom_com
    FROM graphic_parcels.cities c
   WHERE postgis.ST_Intersects(p.centroid, c.geom);
  ```
  → plus simple que la table temporaire `ilotscom`. À garder simple si la jointure est performante ; sinon conserver l'approche existante (table intermédiaire) pour éviter de balayer les communes plusieurs fois.
- [ ] **6.3** (Si option B §5.3) ajouter les colonnes enrichies dans la SELECT.

### Phase 7 — Nettoyage et validation (~30 min)

- [ ] **7.1** Supprimer le code obsolète : `create_table_command`, `import_shp_command`, le multi-threading, les blocs `imports.each`, etc.
- [ ] **7.2** Garder ou supprimer la table temporaire `ilotscom` selon la décision §6.2.
- [ ] **7.3** Lancer dans Docker :
  ```bash
  ./lexicon collect graphic_parcels   # vérifie présence du .gpkg
  ./lexicon load graphic_parcels      # charge cities + RPG via ogr2ogr
  ./lexicon normalize graphic_parcels # alimente registered_graphic_parcels
  ```
  Idéalement, surveiller le temps et l'occupation disque (table d'~8 Go en source).
- [ ] **7.4** Sanity checks SQL :
  - `SELECT COUNT(*) FROM lexicon.registered_graphic_parcels;` (de l'ordre de 9-10 millions de parcelles attendues pour la France).
  - `SELECT COUNT(*) FROM lexicon.registered_graphic_parcels WHERE city_name IS NULL;` (≪ 1 % attendu).
  - `SELECT cap_crop_code, COUNT(*) FROM lexicon.registered_graphic_parcels GROUP BY cap_crop_code ORDER BY COUNT(*) DESC LIMIT 10;` (codes culture cohérents).
  - Vérification spatiale : `SELECT postgis.ST_SRID(shape) FROM lexicon.registered_graphic_parcels LIMIT 1;` doit retourner 4326.
- [ ] **7.5** `./lexicon validate` pour confirmer l'alignement schéma vs définitions.

### Phase 8 — Finition (~15 min)

- [ ] **8.1** Mettre à jour `doc/datasources/graphic_parcels.md` (mention RPG 3.0, format GPKG, projection 2154, procédure de dépôt manuel).
- [ ] **8.2** Vérifier que les `resources/flavors/*.yml` ne référencent rien qui aurait changé (table cible inchangée → a priori OK).
- [ ] **8.3** Commit court conforme au style projet (ex. `Migrate graphic_parcels to RPG 3.0 (single GPKG)`).

---

## 8. Points de vigilance

1. **Volume `RPG_Parcelles.gpkg` : 6.2 Go ; total des 8 sous-produits déposés : ~42 Go**. Prévoir disque ample (compter ~2x en base avec les index spatiaux). Pour Parcelles seul, l'import ogr2ogr peut prendre 20-40 min ; le `CREATE INDEX … USING GIST` final peut prendre encore 15-30 min. Surveiller `pg_stat_progress_create_index`.
2. **`PG:` prefix obligatoire** sur la chaîne de connexion ogr2ogr (sinon erreur `PostgreSQL driver doesn't currently support database creation`). Bug rencontré sur `hydrography` — ne pas refaire.
3. **Géométrie source : MultiPolygon** (confirmé via `ogrinfo`, cf. §3). `-nlt PROMOTE_TO_MULTI` reste utile car la table cible attend `Polygon` après `ST_Dump`.
4. **Géométries invalides** : Le `ST_Buffer(geom, 0.0)` est conservé comme protection (rare mais possible sur des données issues de déclarations PAC). Vérifier que les performances tiennent — sinon désactiver et compter sur la qualité IGN.
5. **Continuité d'`id_parcel`** : seulement à partir de 2022 (PDF §2.4). Si Ekylibre exploitait des identifiants RPG d'avant 2022, prévenir.
6. **Saint-Barthélemy / Saint-Martin** : couverts par le RPG (§2.2). L'extent de `RPG_Parcelles` est strictement métropole — ces deux collectivités ne sont pas dans ce fichier. Confirmer hors-scope.
7. **Modèle hydrography** : `pg_connection_string` est privée et locale. Possible duplication entre les deux datasources — si une troisième en a besoin, factoriser dans `Datasources::Base`. Pas urgent.
8. **Suppression complète du téléchargement automatique** : assumée. L'ancienne logique curl + 7z est définitivement supprimée, pas conservée en commentaire (CLAUDE.md : pas de code mort).
9. **7 autres GPKG présents non chargés** (Option A §6.2) : leur présence dans `raw/graphic_parcels/` n'a pas d'effet sur l'import, mais ils occupent ~36 Go sur disque. À documenter ou nettoyer selon préférence utilisateur.

---

## 9. Effort estimé

| Phase | Estimation |
|---|---|
| 1. Préparation + inspection du .gpkg | 15 min |
| 2. Refonte (constantes, headers) | 1 h 30 |
| 3. `collect` | 15 min |
| 4. `load` (ogr2ogr + cities) | 45 min |
| 5. `table_definitions` | 10 min |
| 6. `normalize` | 45 min |
| 7. Nettoyage + validation runtime | 30 min |
| 8. Finition (doc + commit) | 15 min |
| **Total** | **~4 h** (chargement ogr2ogr exclus — peut prendre 30-60 min en background) |

---

## 10. Critères d'acceptation

- `./lexicon run graphic_parcels` se termine sans erreur sur le `.gpkg` France métropolitaine.
- `registered_graphic_parcels` contient ≈ 9-10 M lignes.
- Toutes les géométries `shape` sont en SRID 4326 et valides.
- `city_name` est renseigné pour > 99 % des parcelles.
- `cap_crop_code` couvre l'ensemble des codes attendus (REF_CULTURES).
- `./lexicon validate` passe.
- Le code ne contient plus aucune référence à `ZONES`, `REGIONS`, `shp2pgsql`, `7z`, multi-threading psql.

---

## 11. Hors scope (à traiter séparément si besoin)

- Outre-mer (R01-R04, R06) en projections UTM locales.
- Sous-produits `RPG_Ilots`, `RPG_PAC`, `RPG_PP`, `RPG_SNA`, `RPG_ZDH`, `RPG_IAE`, `RPG_BIO`.
- Table de référence cultures (REF_CULTURES, REF_CULTURES_GROUPES_CULTURES, REF_CULTURES_DEROBEES) — pourrait alimenter une jointure descriptive.
- Téléchargement automatisé depuis géoservices IGN.
- Comparaison inter-millésimes (RPG 2023 vs 2024 via `id_parcel` continu à partir de 2022).
- Factorisation de `pg_connection_string` dans `Datasources::Base` (à faire quand 3+ datasources l'utiliseront).
