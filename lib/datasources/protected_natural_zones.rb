module Datasources
  class ProtectedNaturalZones < Base
    LAST_UPDATED = "2024-12-01"
    description 'Natura 2000 — Sites SIC et ZPS (MNHN/INPN, NATURA_BDD 12/2024)'
    credits name: 'Zones Natura 2000 — NATURA_BDD',
            url: "https://inpn.mnhn.fr/programme/natura2000",
            provider: "MNHN / INPN",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: LAST_UPDATED

    # The NATURA_BDD dataset is provided manually: drop the `NATURA_BDD_122024/`
    # directory (containing `SIG_NATURA/natura_sig.shp` and `biotop.csv.csv`)
    # into `raw/protected_natural_zones/`.
    SCHEMA = 'protected_natural_zones'.freeze
    SHP_FILE = 'NATURA_BDD_122024/SIG_NATURA/natura_sig.shp'.freeze
    BIOTOP_FILE = 'NATURA_BDD_122024/biotop.csv.csv'.freeze
    RAW_SHP_TABLE = 'natura_sig'.freeze
    RAW_BIOTOP_TABLE = 'biotop'.freeze
    SOURCE_SRID = 2154

    def collect
      missing = [SHP_FILE, BIOTOP_FILE].reject { |f| File.exist?(dir.join(f)) }
      unless missing.empty?
        raise "Missing NATURA_BDD file(s) in #{dir}: #{missing.join(', ')}"
      end

      logger.debug "Found Natura shapefile: #{dir.join(SHP_FILE)}"
      logger.debug "Found Natura biotop CSV: #{dir.join(BIOTOP_FILE)}"
    end

    def load
      logger.debug "Loading Natura shapefile into #{SCHEMA}.#{RAW_SHP_TABLE}..."
      load_shp(dir.join(SHP_FILE), table_name: RAW_SHP_TABLE, srid: SOURCE_SRID)

      logger.debug "Loading biotop CSV into #{SCHEMA}.#{RAW_BIOTOP_TABLE}..."
      load_csv(dir.join(BIOTOP_FILE), RAW_BIOTOP_TABLE, col_sep: ';')
    end

    def self.table_definitions(builder)
      builder.table :registered_natural_zones, sql: <<-SQL
        CREATE TABLE registered_natural_zones (
          id character varying NOT NULL,
          name character varying,
          nature character varying NOT NULL,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );

        CREATE INDEX registered_natural_zones_id ON registered_natural_zones (id);
        CREATE INDEX registered_natural_zones_nature ON registered_natural_zones (nature);
        CREATE INDEX registered_natural_zones_shape ON registered_natural_zones USING GIST (shape);
        CREATE INDEX registered_natural_zones_centroid ON registered_natural_zones USING GIST (centroid);
      SQL
    end

    def normalize
      logger.debug "Insert Natura zones into registered_natural_zones..."
      query <<~SQL
        INSERT INTO registered_natural_zones (id, name, nature, shape)
        SELECT
          substring(n.cd_sig FROM 5),
          b.site_name,
          lower(n.type_espac),
          postgis.ST_Multi(postgis.ST_Transform(n.geom, 4326))
        FROM #{SCHEMA}.#{RAW_SHP_TABLE} n
        LEFT JOIN #{SCHEMA}.#{RAW_BIOTOP_TABLE} b
          ON b.sitecode = substring(n.cd_sig FROM 5);
      SQL

      logger.debug "Compute centroid on Natural zones..."
      query <<~SQL
        UPDATE lexicon.registered_natural_zones
           SET centroid = postgis.ST_Centroid(shape)
         WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true;
      SQL
    end
  end
end
