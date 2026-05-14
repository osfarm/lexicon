# Workflow — Datasource `administrative_areas` + analyse lien RICA ↔ Productions

> **Statut :** plan d'implémentation. Aucun code n'est modifié par ce document.
> **Suivant :** `/sc:implement` ou exécution manuelle phase par phase.

---

## Partie 1 — Analyse : lien RICA ↔ `master_productions` (lecture seule)

### Constat

- `Datasources::Rica` produit `registered_rica_holdings` (clé `idnum, year`) avec, comme axes d'orientation agricole :
  - `ote_17` (`OTEXE`) — orientation technico-économique des exploitations, 17 postes
  - `ote_64` (`OTE64F`) — orientation détaillée, 64 postes
  - `region_code` (`REGIO`, ancien découpage) et `new_region_code` (`NREG`, découpage post-2016)
  - `extr2` (coefficient d'extrapolation), `sau_ha`, `sutot`, etc.
  - Tout le reste (productions par culture, surfaces, charges, etc.) est conservé en `data jsonb`.
- `Datasources::Productions` produit `master_productions` (PK `reference_name`, ex. `wheat`, `barley`, `milk_cow`) qualifié par `activity_family`, `specie`, `usage`, `agroedi_crop_code`.

### Conclusion : pas de lien direct possible

- `registered_rica_holdings.idnum` est **anonymisé** (RICA est un panel statistique). Aucune jointure 1-1 avec une production de référence n'est possible — RICA décrit des exploitations, pas des cultures de référence.
- `ote_17` / `ote_64` ne correspondent **pas** à `master_productions.reference_name` : ce sont des **classes d'orientation** agrégées (ex. OTE 1500 = « Grandes cultures », OTE 4500 = « Bovins lait ») couvrant **plusieurs** productions à la fois. Relation N↔N.
- Les surfaces / productions par culture sont disséminées dans le `data jsonb` des holdings (variables `S08`, `S10`, `Q…`, etc. — décrites par `registered_rica_variables`/`_modalities`). Elles n'utilisent pas les `reference_name` Ekylibre.

### Recommandation (hors scope de ce workflow)

Si un rapprochement est nécessaire pour des cas d'usage côté Ekylibre, le seul vecteur viable est une **table de correspondance curée à la main**, à traiter dans un PR séparé :

```sql
master_rica_ote_productions (
  ote_kind         varchar NOT NULL,   -- '17' ou '64'
  ote_code         varchar NOT NULL,   -- '1500', '4500', ...
  production_ref   varchar NOT NULL,   -- FK master_productions.reference_name
  weight           numeric,            -- optionnel : pondération si OTE multi-productions
  PRIMARY KEY (ote_kind, ote_code, production_ref)
)
```

Cette curation demande une expertise métier (matrice OTE Eurostat × référentiel productions Ekylibre) et n'est donc **pas incluse** dans ce workflow.

---

## Partie 2 — Nouveau datasource `administrative_areas`

### Objectif

Exposer un référentiel géographique officiel (régions + départements France 2021) dans une table unique `registered_administrative_areas`, avec géométrie PostGIS, permettant de joindre toutes les données régionales/départementales du Lexicon — notamment `registered_rica_holdings.new_region_code`.

### Sources

| Fichier (`raw/administrative_areas/`) | Type     | Nb features | Propriétés                  |
| ------------------------------------- | -------- | ----------- | --------------------------- |
| `a-reg2021.json`                      | GeoJSON  | 18          | `reg`, `libgeo`             |
| `a-dep2021.json`                      | GeOJSON  | 101         | `dep`, `reg`, `libgeo`      |

Référentiel COG 2021 (Code Officiel Géographique INSEE), licence OdbL / Etalab.

### Schéma cible (table unifiée — choix retenu)

```sql
CREATE TABLE registered_administrative_areas (
  code         character varying PRIMARY KEY NOT NULL,  -- '01'..'976' (dép) ou '11'..'94' (reg)
  kind         character varying NOT NULL,              -- 'region' | 'department'
  name         character varying NOT NULL,              -- libgeo
  parent_code  character varying,                       -- code de la région parent (NULL pour les régions)
  shape        postgis.geometry(MultiPolygon, 4326) NOT NULL,
  centroid     postgis.geometry(Point, 4326),
  CONSTRAINT registered_administrative_areas_kind_chk
    CHECK (kind IN ('region', 'department'))
);
CREATE INDEX registered_administrative_areas_kind        ON registered_administrative_areas(kind);
CREATE INDEX registered_administrative_areas_parent_code ON registered_administrative_areas(parent_code);
CREATE INDEX registered_administrative_areas_shape       ON registered_administrative_areas USING GIST (shape);
CREATE INDEX registered_administrative_areas_centroid    ON registered_administrative_areas USING GIST (centroid);
```

> ⚠️ Collision possible entre `dep='01'` et `reg='01'`. Vérifier dans les données 2021 que les espaces de codes ne se chevauchent pas ; si nécessaire, préfixer (`'D-01'`, `'R-11'`) ou élargir la PK en `(kind, code)`. **Décision à valider en phase 1.**

### Lien RICA documenté (jointure type)

```sql
SELECT h.idnum, h.year, a.name AS region_name
FROM registered_rica_holdings h
JOIN registered_administrative_areas a
  ON a.kind = 'region'
 AND a.code = h.new_region_code;
```

Aucune contrainte FK n'est ajoutée (les codes RICA peuvent inclure des valeurs hors France métropolitaine selon les millésimes) — la cohérence se vérifiera en phase 5 (validation).

---

## Plan d'implémentation

### Phase 1 — Validation des hypothèses (avant code)

- [ ] **1.1** Vérifier collision de codes : `python3 -c "import json; ..."` sur les deux fichiers pour s'assurer qu'aucun `dep` 2021 ne partage la valeur d'un `reg`. Selon le résultat, garder `code` PK ou passer en PK composite `(kind, code)`.
- [ ] **1.2** Confirmer que les codes `reg` du référentiel COG 2021 correspondent bien aux valeurs présentes dans `registered_rica_holdings.new_region_code` (ex. `'84'` Auvergne-Rhône-Alpes, `'11'` Île-de-France…) — sample SQL après prochain run RICA.
- [ ] **1.3** Décider du nom du dossier d'archive : conserver `a-dep2021.json` / `a-reg2021.json` ou renommer en `departments_2021.geojson` / `regions_2021.geojson` (cohérence avec les conventions actuelles). Recommandation : **conserver les noms upstream** pour traçabilité.

### Phase 2 — Datasource Ruby

Créer `lib/datasources/administrative_areas.rb` selon le pattern `Datasources::Base` + `cadastre_owners.rb` (helper `pg_connection_string`) + `hydrography.rb` (ogr2ogr GeoJSON → PostGIS).

Squelette attendu :

```ruby
module Datasources
  class AdministrativeAreas < Base
    description 'Référentiel administratif France (régions & départements, COG INSEE)'
    credits name: 'Découpage administratif COG 2021',
            url:  'https://www.insee.fr/fr/information/2114819',
            provider: 'INSEE',
            licence:  'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2021-01-01'

    SCHEMA      = 'administrative_areas'.freeze
    REGIONS     = 'a-reg2021.json'.freeze
    DEPARTMENTS = 'a-dep2021.json'.freeze

    def collect
      missing = [REGIONS, DEPARTMENTS].reject { |f| File.exist?(dir.join(f)) }
      raise "Missing source file(s) in #{dir}: #{missing.join(', ')}" unless missing.empty?
    end

    def load
      database.ensure_schema(SCHEMA)
      conn = pg_connection_string                       # cf. cadastre_owners.rb
      load_geojson(dir.join(REGIONS),     'raw_regions',     conn)
      load_geojson(dir.join(DEPARTMENTS), 'raw_departments', conn)
    end

    def self.table_definitions(builder)
      builder.table :registered_administrative_areas, sql: <<-SQL
        CREATE TABLE registered_administrative_areas (
          code         character varying PRIMARY KEY NOT NULL,
          kind         character varying NOT NULL,
          name         character varying NOT NULL,
          parent_code  character varying,
          shape        postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid     postgis.geometry(Point, 4326),
          CONSTRAINT registered_administrative_areas_kind_chk
            CHECK (kind IN ('region', 'department'))
        );
        CREATE INDEX registered_administrative_areas_kind        ON registered_administrative_areas(kind);
        CREATE INDEX registered_administrative_areas_parent_code ON registered_administrative_areas(parent_code);
        CREATE INDEX registered_administrative_areas_shape       ON registered_administrative_areas USING GIST (shape);
        CREATE INDEX registered_administrative_areas_centroid    ON registered_administrative_areas USING GIST (centroid);
      SQL
    end

    def normalize
      query <<~SQL
        INSERT INTO registered_administrative_areas (code, kind, name, parent_code, shape, centroid)
        SELECT
          reg, 'region', libgeo, NULL,
          postgis.ST_Multi(geom)::postgis.geometry(MultiPolygon, 4326),
          postgis.ST_PointOnSurface(geom)
        FROM #{SCHEMA}.raw_regions;

        INSERT INTO registered_administrative_areas (code, kind, name, parent_code, shape, centroid)
        SELECT
          dep, 'department', libgeo, reg,
          postgis.ST_Multi(geom)::postgis.geometry(MultiPolygon, 4326),
          postgis.ST_PointOnSurface(geom)
        FROM #{SCHEMA}.raw_departments;
      SQL
    end

    private

      def load_geojson(path, table, conn)
        logger.debug "Loading GeoJSON #{path} into #{SCHEMA}.#{table}..."
        execute <<~BASH
          ogr2ogr \
            -f PostgreSQL "#{conn}" \
            -overwrite \
            -lco SCHEMA=#{SCHEMA} \
            -lco GEOMETRY_NAME=geom \
            -lco FID=ogc_fid \
            -nlt PROMOTE_TO_MULTI \
            -t_srs EPSG:4326 \
            -nln #{table} \
            "#{path}"
        BASH
      end

      def pg_connection_string
        # ⇒ extraire dans Datasources::Base ou dupliquer depuis cadastre_owners.rb
        host = ENV.fetch('POSTGRES_HOST', 'localhost')
        port = ENV.fetch('POSTGRES_PORT', '5432')
        user = ENV.fetch('POSTGRES_USER', 'lexicon')
        password = ENV.fetch('POSTGRES_PASSWORD', '')
        name = ENV['POSTGRES_NAME'] || ENV.fetch('POSTGRES_DB', 'lexicon')
        "PG:host=#{host} port=#{port} user=#{user} password=#{password} dbname=#{name}"
      end
  end
end
```

- [ ] **2.1** Créer `lib/datasources/administrative_areas.rb`.
- [ ] **2.2** Décider : extraire `pg_connection_string` dans `Datasources::Base` (factorisation avec `cadastre_owners.rb`) ou dupliquer localement. **Recommandation : factoriser** dans un PR de suivi pour ne pas élargir le scope ici.
- [ ] **2.3** Vérifier que `ogr2ogr` est disponible dans l'image Docker (déjà utilisé par `hydrography.rb` et `graphic_parcels.rb`, donc OK).

### Phase 3 — Données et tests locaux

- [ ] **3.1** `./lexicon list` → vérifier l'auto-découverte Zeitwerk de `administrative_areas`.
- [ ] **3.2** `./lexicon collect administrative_areas` → no-op (les fichiers sont déjà dans `raw/`).
- [ ] **3.3** `./lexicon load administrative_areas` → contrôle PostGIS : `SELECT COUNT(*) FROM administrative_areas.raw_regions;` (= 18) et `… raw_departments;` (= 101).
- [ ] **3.4** `./lexicon normalize administrative_areas` → `SELECT kind, COUNT(*) FROM lexicon.registered_administrative_areas GROUP BY kind;` (= region 18, department 101).
- [ ] **3.5** Vérifier 5 jointures :
  ```sql
  SELECT d.code, d.name AS dept, r.name AS region
    FROM lexicon.registered_administrative_areas d
    JOIN lexicon.registered_administrative_areas r
      ON r.kind = 'region' AND r.code = d.parent_code
   WHERE d.kind = 'department'
   LIMIT 5;
  ```
- [ ] **3.6** Test du lien RICA (si la base contient déjà du RICA chargé) :
  ```sql
  SELECT a.code, a.name, COUNT(*) AS holdings_2023
    FROM lexicon.registered_rica_holdings h
    JOIN lexicon.registered_administrative_areas a
      ON a.kind = 'region' AND a.code = h.new_region_code
   WHERE h.year = 2023
   GROUP BY a.code, a.name
   ORDER BY a.code;
  ```
  → toutes les régions RICA 2023 doivent matcher. Lignes orphelines = signal à investiguer (DOM-TOM, codes invalides).

### Phase 4 — Validation schéma & flavors

- [ ] **4.1** `./lexicon validate` → la nouvelle table doit être déclarée et conforme.
- [ ] **4.2** Mettre à jour les **flavors** : décider si `administrative_areas` doit être inclus dans :
  - `resources/flavors/light.yml` (probablement oui — petite table de référence très utile)
  - `resources/flavors/test.yml` (oui — utilisé partout pour les joins géo)
  - `resources/flavors/pv.yml`, `innovation.yml`, `ekyagri.yml`, `sydec.yml` (selon usage)
  - Pour `test.yml`, ajouter un filtre spatial (ex. seulement les 2 départements autour de `POINT(-0.78 45.81)`) pour rester cohérent avec les autres datasets du flavor.
- [ ] **4.3** `./lexicon dump all --flavor test` → archive sans erreur.

### Phase 5 — Documentation & qualité

- [ ] **5.1** Mettre à jour `doc/CONTRIBUTING.md` si une convention nouvelle (PK composite, helper extrait) est introduite.
- [ ] **5.2** Ajouter une entrée dans `CLAUDE.md` ou `doc/datasources/` décrivant le datasource et le lien documenté avec `registered_rica_holdings.new_region_code`.
- [ ] **5.3** `./bin/rubocop` (note : `datasources/` est exclu d'après `.rubocop.yml`, à confirmer dans la config courante).
- [ ] **5.4** Vérifier que les commentaires inline sont minimaux (seulement le *pourquoi* non-évident).

### Phase 6 — Bump & publication

- [ ] **6.1** `./lexicon version bump minor` (ajout fonctionnel non breaking).
- [ ] **6.2** `./lexicon dump all` puis `./lexicon remote upload <version>` selon procédure habituelle.

---

## Dépendances & ordre d'exécution

```
Phase 1 (validation hypothèses)
       │
       ▼
Phase 2 (datasource)  ──►  Phase 3 (tests locaux)
                                   │
                                   ▼
                           Phase 4 (validate + flavors)
                                   │
                                   ▼
                           Phase 5 (doc + lint)
                                   │
                                   ▼
                           Phase 6 (version + dump)
```

Les phases 2-3 peuvent être itérées plusieurs fois ; les phases 4-6 sont strictement séquentielles.

---

## Points de décision ouverts (à trancher pendant l'implémentation)

1. **PK simple `code` vs composite `(kind, code)`** — dépend du résultat de **1.1**.
2. **Factorisation `pg_connection_string`** dans `Base` — faire maintenant ou dans un PR de cleanup séparé.
3. **Centroid : `ST_Centroid` vs `ST_PointOnSurface`** — `PointOnSurface` garantit un point *à l'intérieur* du polygone (utile pour la Corse ou les départements ultramarins concaves). Recommandation : `ST_PointOnSurface`.
4. **Filtre spatial pour `flavors/test.yml`** — quels départements inclure, et faut-il aussi inclure leur région parent ?
5. **Inclure les COM/TOM (Saint-Martin, Saint-Pierre-et-Miquelon…)** ou se limiter au périmètre du GeoJSON COG 2021 livré ?

---

## Hors scope (à ne pas traiter dans ce workflow)

- Table de correspondance `master_rica_ote_productions` (cf. Partie 1).
- Mise à jour vers un millésime COG plus récent (2024/2025) — le fichier 2021 est livré tel quel.
- Reprojections, simplifications topologiques (`ST_SimplifyPreserveTopology`) pour alléger le payload — possibles dans une itération ultérieure si la taille des géométries pose problème côté Ekylibre.
- Communes (niveau 3) — non demandé, et déjà partiellement couvert par `postal_codes.rb`.

---

## Prochaine étape

`/sc:implement claudedocs/workflow_administrative_areas.md` pour exécuter le plan phase par phase.
