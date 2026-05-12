module Datasources
  class Hydrography < Base
    LAST_UPDATED = "2024-09-15"
    description 'hydro data from IGN (national BD TOPO GeoPackage)'
    credits name: 'BD TOPO Hydrographie',
            url: "https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#bd-topo",
            provider: "IGN",
            licence: "Open Licence",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf",
            updated_at: LAST_UPDATED

    # The national BD TOPO GeoPackage is provided manually:
    # drop the .gpkg file into `raw/hydrography/`. Either keep the
    # default filename below or any other `*.gpkg` (auto-detected).
    GPKG_FILE = "bdtopo.gpkg".freeze

    SCHEMA = 'hydrography'.freeze

    WATER_LAYERS = %w(surface_hydrographique detail_hydrographique troncon_hydrographique).freeze
    BUILDING_LAYERS = %w(batiment pylone).freeze
    AREA_LAYERS = %w(haie zone_de_vegetation).freeze
    LAYERS = (WATER_LAYERS + BUILDING_LAYERS + AREA_LAYERS).freeze

    def collect
      path = gpkg_path
      if path.nil?
        raise "No GeoPackage found in #{dir}. Place the IGN BD TOPO national GeoPackage (e.g. #{GPKG_FILE}) there before running."
      end

      logger.debug "Found GeoPackage: #{path}"
    end

    def load
      path = gpkg_path
      raise "No GeoPackage found in #{dir}" if path.nil?

      database.ensure_schema(SCHEMA)
      conn = pg_connection_string

      LAYERS.each do |layer|
        logger.debug "Loading layer #{layer} into #{SCHEMA}.#{layer}..."
        execute <<~BASH
          ogr2ogr \
            -f PostgreSQL "#{conn}" \
            -overwrite \
            -lco SCHEMA=#{SCHEMA} \
            -lco GEOMETRY_NAME=geom \
            -lco FID=ogc_fid \
            -nlt PROMOTE_TO_MULTI \
            -t_srs EPSG:4326 \
            -nln #{layer} \
            "#{path}" #{layer}
        BASH
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_cadastral_buildings, sql: <<-SQL
        CREATE TABLE registered_cadastral_buildings(
          id SERIAL PRIMARY KEY NOT NULL,
          reference_name character varying,
          nature character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_cadastral_buildings_id ON registered_cadastral_buildings(id);
        CREATE INDEX registered_cadastral_buildings_reference_name ON registered_cadastral_buildings(reference_name);
        CREATE INDEX registered_cadastral_buildings_shape ON registered_cadastral_buildings USING GIST (shape);
        CREATE INDEX registered_cadastral_buildings_centroid ON registered_cadastral_buildings USING GIST (centroid);
      SQL

      builder.table :registered_area_items, sql: <<-SQL
        CREATE TABLE registered_area_items (
          id character varying PRIMARY KEY NOT NULL,
          name jsonb,
          nature character varying,
          point postgis.geometry(Point,4326),
          shape postgis.geometry(MultiPolygon,4326),
          lines postgis.geometry(MultiLineString,4326),
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_area_items_id ON registered_area_items(id);
        CREATE INDEX registered_area_items_nature ON registered_area_items(nature);
        CREATE INDEX registered_area_items_shape ON registered_area_items USING GIST (shape);
        CREATE INDEX registered_area_items_point ON registered_area_items USING GIST (point);
        CREATE INDEX registered_area_items_lines ON registered_area_items USING GIST (lines);
        CREATE INDEX registered_area_items_centroid ON registered_area_items USING GIST (centroid);
      SQL

      builder.table :registered_hydrographic_items, sql: <<-SQL
        CREATE TABLE registered_hydrographic_items (
          id character varying PRIMARY KEY NOT NULL,
          name jsonb,
          nature character varying,
          point postgis.geometry(Point,4326),
          shape postgis.geometry(MultiPolygon,4326),
          lines postgis.geometry(MultiLineString,4326),
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_hydrographic_items_nature ON registered_hydrographic_items(nature);
        CREATE INDEX registered_hydrographic_items_shape ON registered_hydrographic_items USING GIST (shape);
        CREATE INDEX registered_hydrographic_items_point ON registered_hydrographic_items USING GIST (point);
        CREATE INDEX registered_hydrographic_items_lines ON registered_hydrographic_items USING GIST (lines);
        CREATE INDEX registered_hydrographic_items_centroid ON registered_hydrographic_items USING GIST (centroid);
      SQL
    end

    def normalize
      logger.debug "Load Water layers into registered_hydrographic_items..."
      query("INSERT INTO registered_hydrographic_items (id, name, nature, point)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || toponyme || '\"}')::jsonb,
      nature, (postgis.ST_Dump(postgis.ST_Force2D(geom))).geom
      FROM #{SCHEMA}.detail_hydrographique ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items (id, name, nature, shape)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || nom_p_eau || '\"}')::jsonb,
      nature, postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(geom))).geom)
      FROM #{SCHEMA}.surface_hydrographique ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items (id, name, nature, lines)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || nom_c_eau || '\"}')::jsonb,
      nature, postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(geom))).geom)
      FROM #{SCHEMA}.troncon_hydrographique ON CONFLICT DO NOTHING")

      logger.debug "Load Building layer into registered_cadastral_buildings..."
      query("INSERT INTO registered_cadastral_buildings (reference_name, nature, shape)
      SELECT id, usage1,
      postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(geom))).geom)
      FROM #{SCHEMA}.batiment ON CONFLICT DO NOTHING")

      logger.debug "Load Area layers into registered_area_items..."
      query("INSERT INTO registered_area_items (id, name, nature, lines)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || 'haie' || '\"}')::jsonb, 'edge',
      postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(geom))).geom)
      FROM #{SCHEMA}.haie ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, shape)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || nature || '\"}')::jsonb, 'green_zone',
      postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(geom))).geom)
      FROM #{SCHEMA}.zone_de_vegetation ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, point)
      SELECT CONCAT(id, '_fra'), ('{\"fra\": \"' || 'pylone' || '\"}')::jsonb, 'electric_pole',
      (postgis.ST_Dump(postgis.ST_Force2D(geom))).geom
      FROM #{SCHEMA}.pylone ON CONFLICT DO NOTHING")

      logger.debug "Compute centroid on Building..."
      query("UPDATE lexicon.registered_cadastral_buildings SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")

      logger.debug "Compute centroid on Area items..."
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(lines) WHERE lines IS NOT NULL AND postgis.ST_IsValid(lines) = true")
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(point) WHERE point IS NOT NULL AND postgis.ST_IsValid(point) = true")

      logger.debug "Compute centroid on Hydrographic items..."
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(lines) WHERE lines IS NOT NULL AND postgis.ST_IsValid(lines) = true")
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(point) WHERE point IS NOT NULL AND postgis.ST_IsValid(point) = true")

      logger.debug "Delete items where centroid is missing on Building, Area items and Hydrographic items..."
      query("DELETE FROM lexicon.registered_cadastral_buildings WHERE centroid IS NULL")
      query("DELETE FROM lexicon.registered_hydrographic_items WHERE centroid IS NULL")
      query("DELETE FROM lexicon.registered_area_items WHERE centroid IS NULL")
    end

    private

      # @return [Pathname, nil]
      def gpkg_path
        default = dir.join(GPKG_FILE)
        return default if File.exist?(default)

        first = Dir.glob(dir.join('*.gpkg')).first
        first.nil? ? nil : Pathname.new(first)
      end

      def pg_connection_string
        host = ENV.fetch('POSTGRES_HOST', 'localhost')
        port = ENV.fetch('POSTGRES_PORT', '5432')
        user = ENV.fetch('POSTGRES_USER', 'lexicon')
        password = ENV.fetch('POSTGRES_PASSWORD', '')
        name = ENV['POSTGRES_NAME'] || ENV.fetch('POSTGRES_DB', 'lexicon')

        parts = ["host=#{host}", "port=#{port}", "user=#{user}", "dbname=#{name}"]
        parts << "password=#{password}" unless password.empty?
        parts.join(' ')
      end
  end
end
