module Datasources
  class AdministrativeAreas < Base
    description 'Référentiel administratif France (régions & départements, COG INSEE 2021)'
    credits name: 'Découpage administratif COG 2021',
            url: "https://www.insee.fr/fr/information/2114819",
            provider: "INSEE",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: "2021-01-01"

    SCHEMA      = 'administrative_areas'.freeze
    REGIONS     = 'a-reg2021.json'.freeze
    DEPARTMENTS = 'a-dep2021.json'.freeze

    def collect
      missing = [REGIONS, DEPARTMENTS].reject { |f| File.exist?(dir.join(f)) }
      raise "Missing source file(s) in #{dir}: #{missing.join(', ')}" unless missing.empty?
    end

    def load
      database.ensure_schema(SCHEMA)
      conn = pg_connection_string

      load_geojson(dir.join(REGIONS),     'raw_regions',     conn)
      load_geojson(dir.join(DEPARTMENTS), 'raw_departments', conn)
    end

    def self.table_definitions(builder)
      builder.table :registered_administrative_areas, sql: <<-SQL
        CREATE TABLE registered_administrative_areas (
          kind         character varying NOT NULL,
          code         character varying NOT NULL,
          name         character varying NOT NULL,
          parent_code  character varying,
          shape        postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid     postgis.geometry(Point, 4326),
          PRIMARY KEY (kind, code),
          CONSTRAINT registered_administrative_areas_kind_chk
            CHECK (kind IN ('region', 'department'))
        );
        CREATE INDEX registered_administrative_areas_code        ON registered_administrative_areas(code);
        CREATE INDEX registered_administrative_areas_parent_code ON registered_administrative_areas(parent_code);
        CREATE INDEX registered_administrative_areas_shape       ON registered_administrative_areas USING GIST (shape);
        CREATE INDEX registered_administrative_areas_centroid    ON registered_administrative_areas USING GIST (centroid);
      SQL
    end

    def normalize
      logger.debug "Normalizing administrative regions (#{SCHEMA}.raw_regions → registered_administrative_areas)..."
      query <<~SQL
        INSERT INTO registered_administrative_areas (kind, code, name, parent_code, shape, centroid)
        SELECT
          'region',
          reg,
          libgeo,
          NULL,
          postgis.ST_Multi(geom)::postgis.geometry(MultiPolygon, 4326),
          postgis.ST_PointOnSurface(geom)
        FROM #{SCHEMA}.raw_regions
        ON CONFLICT (kind, code) DO NOTHING
      SQL

      logger.debug "Normalizing administrative departments (#{SCHEMA}.raw_departments → registered_administrative_areas)..."
      query <<~SQL
        INSERT INTO registered_administrative_areas (kind, code, name, parent_code, shape, centroid)
        SELECT
          'department',
          dep,
          libgeo,
          reg,
          postgis.ST_Multi(geom)::postgis.geometry(MultiPolygon, 4326),
          postgis.ST_PointOnSurface(geom)
        FROM #{SCHEMA}.raw_departments
        ON CONFLICT (kind, code) DO NOTHING
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
