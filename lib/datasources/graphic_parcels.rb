module Datasources
  class GraphicParcels < Base
    LAST_UPDATED = "2024-01-01"
    description 'RPG v3.0 — Parcelles agricoles constatées (France métropolitaine)'
    credits name: 'RPG — Registre Parcellaire Graphique v3.0',
            url: "https://geoservices.ign.fr/rpg",
            provider: "IGN / ASP / MASA",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: LAST_UPDATED

    # The RPG GeoPackage is provided manually: drop `RPG_Parcelles.gpkg`
    # (France métropolitaine, Lambert-93 / EPSG:2154) into `raw/graphic_parcels/`.
    GPKG_FILE = "RPG_Parcelles.gpkg".freeze
    SOURCE_LAYER = "RPG_Parcelles".freeze
    SCHEMA = 'graphic_parcels'.freeze
    RAW_TABLE = 'parcelles_graphiques'.freeze

    def collect
      path = dir.join(GPKG_FILE)
      raise "Missing #{GPKG_FILE} in #{dir}. Drop the RPG_Parcelles GeoPackage (Lambert-93) there before running." unless File.exist?(path)

      logger.debug "Found GeoPackage: #{path}"
    end

    def load
      logger.debug "Loading communes shapefile..."
      FileUtils.cp_r 'data/graphic_parcels/.', dir
      load_shp(dir.join("COMMUNE_CARTO.shp"), table_name: 'cities')

      query <<-SQL
        ALTER TABLE cities
         ALTER COLUMN geom TYPE postgis.geometry(MultiPolygon, 4326)
          USING postgis.ST_Transform(geom, 4326);
      SQL

      database.ensure_schema(SCHEMA)
      conn = pg_connection_string
      gpkg = dir.join(GPKG_FILE)

      logger.debug "Loading layer #{SOURCE_LAYER} from #{GPKG_FILE} into #{SCHEMA}.#{RAW_TABLE}..."
      execute <<~BASH
        ogr2ogr \
          -f PostgreSQL "#{conn}" \
          -overwrite \
          -lco SCHEMA=#{SCHEMA} \
          -lco GEOMETRY_NAME=geom \
          -lco FID=ogc_fid \
          -nlt PROMOTE_TO_MULTI \
          -t_srs EPSG:4326 \
          -nln #{RAW_TABLE} \
          "#{gpkg}" #{SOURCE_LAYER}
      BASH
    end

    def self.table_definitions(builder)
      builder.table :registered_graphic_parcels, sql: <<-SQL
        CREATE TABLE registered_graphic_parcels (
          id character varying NOT NULL,
          cap_crop_code character varying,
          city_name character varying,
          shape postgis.geometry(Polygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_graphic_parcels_id ON registered_graphic_parcels(id);
        CREATE INDEX registered_graphic_parcels_city_name ON registered_graphic_parcels(city_name);
        CREATE INDEX registered_graphic_parcels_shape ON registered_graphic_parcels USING GIST (shape);
        CREATE INDEX registered_graphic_parcels_centroid ON registered_graphic_parcels USING GIST (centroid);
      SQL
    end

    def normalize
      logger.debug "Insert parcels into registered_graphic_parcels..."
      query <<~SQL
        INSERT INTO registered_graphic_parcels (id, cap_crop_code, shape, centroid)
        SELECT
          id_parcel,
          code_cultu,
          (postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(geom), 0.0))).geom,
          postgis.ST_Centroid((postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(geom), 0.0))).geom)
        FROM #{SCHEMA}.#{RAW_TABLE};
      SQL

      logger.debug "Resolve city_name via spatial join on communes..."
      query <<~SQL
        UPDATE registered_graphic_parcels p
           SET city_name = c.nom_com
          FROM #{SCHEMA}.cities c
         WHERE postgis.ST_Intersects(p.centroid, c.geom);
      SQL
    end

    private

      def pg_connection_string
        host = ENV.fetch('POSTGRES_HOST', 'localhost')
        port = ENV.fetch('POSTGRES_PORT', '5432')
        user = ENV.fetch('POSTGRES_USER', 'lexicon')
        password = ENV.fetch('POSTGRES_PASSWORD', '')
        name = ENV['POSTGRES_NAME'] || ENV.fetch('POSTGRES_DB', 'lexicon')

        parts = ["host=#{host}", "port=#{port}", "user=#{user}", "dbname=#{name}"]
        parts << "password=#{password}" unless password.empty?
        "PG:#{parts.join(' ')}"
      end
  end
end
