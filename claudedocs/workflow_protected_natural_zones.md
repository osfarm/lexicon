# Workflow — Migration `protected_natural_zones` vers NATURA_BDD 12/2024

> **Statut :** plan d'implémentation. Aucun code modifié à ce stade.
> **Prochaine étape :** lancer `/sc:implement claudedocs/workflow_protected_natural_zones.md` pour exécution pas à pas.

---

## 1. Objectif

Adapter la datasource `Datasources::ProtectedNaturalZones` (`lib/datasources/protected_natural_zones.rb`) à la nouvelle livraison MNHN **NATURA_BDD 12/2024**, qui regroupe l'intégralité des sites Natura 2000 (SIC + ZPS) dans **un shapefile unique** accompagné d'une trentaine de tables CSV de référence.

---

## 2. État actuel à remplacer

### 2.1 Datasource existante (`lib/datasources/protected_natural_zones.rb`)

- Télécharge **deux ZIP séparés** via `data.gouv.fr` (un pour SIC, un pour ZPS) puis les décompresse avec `7z`.
- Charge deux shapefiles `sic.shp` et `zps.shp` (en Lambert-93) via `load_shp` → tables `protected_natural_zones.sic_zones` et `protected_natural_zones.zps_zones`.
- `normalize` : deux INSERTs distincts dans `registered_natural_zones`, avec `nature='sic'` / `'zps'` et `sitename` directement disponible dans le shapefile.
- Calcule les centroïdes par UPDATE à la fin.

### 2.2 Table cible `registered_natural_zones` (à conserver inchangée a priori)

```sql
CREATE TABLE registered_natural_zones (
  id character varying NOT NULL,
  name character varying,
  nature character varying NOT NULL,
  shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
  centroid postgis.geometry(Point, 4326)
);
```

Indexée sur `id`, `nature`, `shape (GIST)`, `centroid (GIST)`.

---

## 3. Inventaire réel dans `raw/protected_natural_zones/NATURA_BDD_122024/` (vérifié)

### 3.1 Shapefile unique

`SIG_NATURA/natura_sig.{shp,shx,dbf,prj,cpg,qmd}` :

| Caractéristique | Valeur |
|---|---|
| Driver | ESRI Shapefile |
| Géométrie | Polygon (2D) |
| Feature Count | **1 762** |
| SRID | EPSG:2154 (Lambert-93, RGF93 v1) — confirmé via `.prj` |
| Encoding | UTF-8 (`.cpg`) |
| Extent | strictement métropole (`(-265 km, 6035 km) → (1247 km, 7135 km)` en LAMB93) |

**Attributs du shapefile (2 seuls champs métier) :**

| Champ | Type | Contenu |
|---|---|---|
| `cd_sig` | String(254) | Identifiant SIG de la forme `I098FR<sitecode>` (ex. `I098FR5312003`) |
| `type_espac` | String(254) | `'SIC'` (1 355 features) ou `'ZPS'` (407 features) |

**Différences vs ancien schéma :**
- ⚠️ **Pas de `sitename` dans le shapefile** (l'ancien le portait).
- ⚠️ **Pas de `sitecode` direct** — il faut l'extraire de `cd_sig` (substring après le préfixe `I098`).
- ⚠️ **Un seul shapefile** au lieu de deux ; la discrimination SIC/ZPS se lit dans `type_espac`.

### 3.2 Tables CSV de référence

35 fichiers `*.csv.csv` (extension doublée, séparateur `;`, valeurs quotées) couvrant l'ensemble du modèle Natura 2000 (méthodologie standard EU Standard Data Form). Le seul qui nous intéresse pour `registered_natural_zones` :

**`biotop.csv.csv`** — table maîtresse des sites :

| Champ utile | Type | Rôle |
|---|---|---|
| `sitecode` | String | Identifiant FR (`FR8201697`) |
| `site_name` | String | Libellé du site (ex. "Massif des Ecrins") |
| `type` | String | SIC / ZPS / pSIC |
| `area`, `longitude`, `latitude`, `fr_alt_*` | Numériques | Métadonnées géographiques |
| `pk_natura`, `cd_sig` | String | Clés techniques (joinables au shapefile) |

Format : 1ʳᵉ ligne = en-tête, séparateur `;`, valeurs entourées de `"`.

**Conséquence** : pour reconstruire le `sitename`, il faut charger `biotop.csv.csv` en table raw, puis joindre par `sitecode` (extrait de `cd_sig`) lors du normalize.

Les 34 autres CSV (espèces, habitats, mesures, contacts, documents administratifs, etc.) ne sont pas utiles pour la cible `registered_natural_zones` mais pourraient l'être pour des datasources annexes plus tard.

---

## 4. Décisions d'architecture à valider

### 4.1 Stratégie de chargement géométrique

| Option | Description |
|---|---|
| **A. (recommandé) `load_shp`** | Pattern actuel, helper natif `Base#load_shp(file, table_name:, srid: 2154)`. Charge `natura_sig.shp` en `protected_natural_zones.natura_sig` en LAMB93. ST_Transform en normalize. |
| B. `ogr2ogr` | Pattern `hydrography` / `graphic_parcels`. Permet de reprojeter directement en 4326 au load. Pas requis ici (shapefile petit, 87 Mo). |

**Proposition retenue : Option A** — plus simple, fidèle au pattern actuel, le shapefile est petit. `ST_Transform` reste en normalize comme avant.

### 4.2 Source du `sitename`

| Option | Description |
|---|---|
| **A. (recommandé) Charger `biotop.csv.csv` + join** | Charger comme table raw `biotop`, joindre par `sitecode` durant le normalize. Permet d'avoir le libellé exact. |
| B. Laisser `name` NULL | Plus simple, mais perte d'information utile pour Ekylibre (affichage du nom du site). |
| C. Utiliser `cd_sig` ou `sitecode` comme name de fallback | Pas de libellé humain. |

**Proposition retenue : Option A.** Le coût est faible (1 fichier CSV de 935 Ko à charger) et préserve la valeur fonctionnelle.

### 4.3 Stratégie de fourniture des données

| Option | Description |
|---|---|
| **A. (recommandé) Manuelle** | L'utilisateur dépose le dossier `NATURA_BDD_122024/` dans `raw/protected_natural_zones/` (déjà fait — vérifié). |
| B. Curl automatique | Les anciens URLs `data.gouv.fr/r/939f828d…` et `r/879e29aa…` ne servent plus la nouvelle base NATURA_BDD unifiée. L'URL d'origine est probablement un export INPN (zone restreinte). À valider si automatisable. |

**Proposition retenue : Option A.** `collect` se contente de vérifier la présence des fichiers attendus et lève une erreur explicite sinon (pattern `hydrography#collect`).

### 4.4 Schéma cible `registered_natural_zones`

| Option | Implication |
|---|---|
| **A. (recommandé) Inchangé** : `(id, name, nature, shape, centroid)` | Compatibilité ascendante. `id` = `sitecode` FR, `nature` = `'sic'` / `'zps'` (minuscules comme avant). |
| B. Enrichi : ajouter `area_ha`, `longitude_ref`, `latitude_ref`, `altitude_mean` depuis biotop | Plus riche, mais migration produit à valider. |

**Proposition retenue : Option A** par défaut.

### 4.5 Valeurs de `nature`

| Option | Description |
|---|---|
| **A. (recommandé) Conserver `'sic'` / `'zps'` en minuscules** | Cohérence avec les données déjà éventuellement en base, et avec le code actuel. |
| B. Garder la casse source (`'SIC'` / `'ZPS'`) | Inutile et rupture de compatibilité. |

**Proposition retenue : Option A.** Mapping via `lower(type_espac)`.

---

## 5. Plan d'implémentation détaillé

### Phase 1 — Préparation (~15 min)

- [ ] **1.1** Confirmer les 5 décisions ci-dessus (§4).
- [x] **1.2** ~~Récupérer les données~~ — **fait** : `NATURA_BDD_122024/` est déjà déposé dans `raw/protected_natural_zones/`.
- [x] **1.3** ~~Inspecter le shapefile et CSV~~ — **fait** (cf. §3) : couche `natura_sig` en LAMB93, attributs `cd_sig`/`type_espac`, table `biotop.csv.csv` pour le sitename.
- [ ] **1.4** Re-lire `lib/datasources/hydrography.rb` (pattern `collect` avec vérification de présence) pour aligner le style.

### Phase 2 — Refonte de `lib/datasources/protected_natural_zones.rb` (~45 min)

- [ ] **2.1** Mettre à jour les métadonnées :
  - `LAST_UPDATED = "2024-12-01"` (ou date plus précise si disponible dans la livraison).
  - `description "Natura 2000 — Sites SIC et ZPS (MNHN/INPN, NATURA_BDD 12/2024)"`.
  - `credits` : conserver provider MNHN, URL INPN.
- [ ] **2.2** Constantes :
  ```ruby
  SCHEMA = 'protected_natural_zones'.freeze
  SHP_FILE = 'NATURA_BDD_122024/SIG_NATURA/natura_sig.shp'.freeze
  BIOTOP_FILE = 'NATURA_BDD_122024/biotop.csv.csv'.freeze
  RAW_SHP_TABLE = 'natura_sig'.freeze
  RAW_BIOTOP_TABLE = 'biotop'.freeze
  SOURCE_SRID = 2154
  ```
- [ ] **2.3** Commentaire d'en-tête expliquant la procédure manuelle (drop the `NATURA_BDD_122024/` directory in `raw/protected_natural_zones/`).

### Phase 3 — `collect` (~15 min)

- [ ] **3.1** Vérifier la présence des deux fichiers requis (`SHP_FILE` et `BIOTOP_FILE`) ; raise avec liste des fichiers manquants.
- [ ] **3.2** Supprimer le téléchargement curl (URLs obsolètes) et la décompression 7z.

### Phase 4 — `load` (~30 min)

- [ ] **4.1** `load_shp(dir.join(SHP_FILE), table_name: RAW_SHP_TABLE, srid: SOURCE_SRID)` → produit `protected_natural_zones.natura_sig`.
- [ ] **4.2** `load_csv(dir.join(BIOTOP_FILE), RAW_BIOTOP_TABLE, col_sep: ';')` → produit `protected_natural_zones.biotop` (toutes colonnes en VARCHAR via `csv_loader`).
- [ ] **4.3** Pas de chargement des 34 autres CSV (hors scope).

### Phase 5 — `table_definitions` (~5 min)

- [ ] **5.1** Inchangé (option §4.4 A). Conserver tel quel.

### Phase 6 — `normalize` (~45 min)

- [ ] **6.1** INSERT unique avec extraction du `sitecode` depuis `cd_sig` (suppression du préfixe `I098`), join avec `biotop` pour le `name`, et `lower(type_espac)` pour le `nature` :
  ```sql
  INSERT INTO registered_natural_zones (id, name, nature, shape)
  SELECT
    substring(n.cd_sig FROM 5)        AS id,
    b.site_name                       AS name,
    lower(n.type_espac)               AS nature,
    postgis.ST_Multi(postgis.ST_Transform(n.geom, 4326)) AS shape
  FROM protected_natural_zones.natura_sig n
  LEFT JOIN protected_natural_zones.biotop b
    ON b.sitecode = substring(n.cd_sig FROM 5);
  ```
  Notes :
  - `substring(... FROM 5)` retire le préfixe `I098` (4 caractères) → reste `FR<sitecode>`.
  - `LEFT JOIN` pour ne pas perdre une parcelle dont le sitecode serait absent du biotop.
  - `ST_Multi` pour forcer MultiPolygon (cible) — les Polygons simples du shapefile sont promus.
- [ ] **6.2** UPDATE des centroïdes (logique inchangée) :
  ```sql
  UPDATE lexicon.registered_natural_zones
     SET centroid = postgis.ST_Centroid(shape)
   WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true;
  ```

### Phase 7 — Validation (~30 min)

- [ ] **7.1** `./lexicon run protected_natural_zones` dans Docker.
- [ ] **7.2** Sanity checks SQL :
  - `SELECT nature, COUNT(*) FROM lexicon.registered_natural_zones GROUP BY nature;` → attendu : `sic` ≈ 1355, `zps` ≈ 407 (à confirmer après ST_Multi/ST_Dump).
  - `SELECT COUNT(*) FROM lexicon.registered_natural_zones WHERE name IS NULL;` → idéalement 0, sinon investiguer les sitecodes orphelins.
  - `SELECT postgis.ST_SRID(shape) FROM lexicon.registered_natural_zones LIMIT 1;` → 4326.
  - `SELECT id, name, nature FROM lexicon.registered_natural_zones LIMIT 5;` → cohérence (`FR8201697`, "Massif…", `sic`).
- [ ] **7.3** `./lexicon validate`.

### Phase 8 — Finition (~15 min)

- [ ] **8.1** Mettre à jour `doc/datasources/*.md` si une fiche existe pour cette datasource.
- [ ] **8.2** Vérifier les flavors (`resources/flavors/*.yml`) — la table cible est inchangée, a priori RAS.
- [ ] **8.3** Commit court conforme au style projet (ex. `Update protected_natural_zones to NATURA_BDD 2024`).

---

## 6. Points de vigilance

1. **Téléchargement automatique abandonné** : les URLs `data.gouv.fr` du code actuel sont obsolètes (la base a été restructurée). Si l'équipe veut un téléchargement automatique, il faut identifier l'URL INPN actuelle (à creuser séparément).
2. **Extension `.csv.csv`** : les fichiers ont une extension doublée. Pas un problème côté `load_csv` (le helper utilise le path complet), mais étrange. Ne pas renommer — `collect` doit pointer sur le chemin exact.
3. **Encodage du CSV `biotop`** : valeurs quotées avec `"`, séparateur `;`. `csv_loader` détecte automatiquement l'encoding (CharlockHolmes) et passe à `psql COPY`. Ça devrait fonctionner sans manipulation.
4. **`substring(cd_sig FROM 5)` hardcodé** : suppose que le préfixe est toujours `I098` (4 chars). Sur les 1762 features inspectées, c'est cohérent ; mais si la livraison future change, prévoir un test (ex. `LEFT(cd_sig, 4) = 'I098'`).
5. **Jointure `LEFT JOIN biotop`** : si certains sitecodes du shapefile manquent dans biotop, `name` sera NULL (acceptable, la colonne le permet). Surveiller le taux d'absence.
6. **Promotion Polygon → MultiPolygon** : le shapefile est en Polygon 2D, la cible attend MultiPolygon. `ST_Multi(...)` force la conversion sans pertes.
7. **`type_espac` valeurs autres que SIC/ZPS** : sur cet échantillon, seules SIC et ZPS sont présentes. Au cas où une livraison future ajouterait `pSIC` ou autre, `lower(type_espac)` les transmettra tels quels (et l'écriture en base ne sera pas filtrée).
8. **Suppression de `7z`** : plus utilisé pour ce datasource, mais reste dépendance d'autres (`cadastral_prices`). RAS côté Dockerfile.
9. **34 CSV non chargés** : ils restent sur disque, ~33 Mo cumulés. Documenter dans le PR que c'est volontaire.

---

## 7. Effort estimé

| Phase | Estimation |
|---|---|
| 1. Préparation | 15 min |
| 2. Refonte (constantes, headers) | 45 min |
| 3. `collect` | 15 min |
| 4. `load` | 30 min |
| 5. `table_definitions` | 5 min |
| 6. `normalize` | 45 min |
| 7. Validation | 30 min |
| 8. Finition | 15 min |
| **Total** | **~3 h 30** |

---

## 8. Critères d'acceptation

- `./lexicon run protected_natural_zones` termine sans erreur.
- `registered_natural_zones` contient ≈ 1 762 lignes (1 355 sic + 407 zps), modulo l'effet de `ST_Multi`/`ST_Dump`.
- Aucune ligne n'a `nature` autre que `sic` / `zps`.
- ≥ 99 % des lignes ont un `name` non NULL (vérifier le taux exact).
- Toutes les géométries `shape` sont en SRID 4326.
- `./lexicon validate` passe.
- Le code ne contient plus aucune référence à `sic.zip`, `zps.zip`, ni aux URLs `data.gouv.fr`.

---

## 9. Hors scope (à traiter séparément)

- Chargement des 34 autres CSV (espèces, habitats, mesures…) — utile pour des datasources annexes éventuelles (`master_natura2000_species`, etc.).
- Téléchargement automatique depuis le portail INPN (URL actuelle à identifier).
- Enrichissement du schéma cible avec `area_ha`, `longitude_ref`, `latitude_ref`, `altitude_mean` (depuis biotop).
- Couverture outre-mer (la livraison actuelle est strictement métropole — sites Natura 2000 outre-mer fournis séparément par l'INPN).
