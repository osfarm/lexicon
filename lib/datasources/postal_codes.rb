module Datasources
  class PostalCodes < Base
    description 'French Enterprises postal and insee codes with gps coordinates'
    credits name: 'Codes postaux et communes', url: "https://www.data.gouv.fr/fr/datasets/base-officielle-des-codes-postaux/", provider: "Groupe La Poste", licence: "ODbl", licence_url: "https://opendatacommons.org/licenses/odbl/summary/", updated_at: "2026-05-08"

    def collect
      downloader.curl 'https://www.data.gouv.fr/api/1/datasets/r/008a2dda-2c60-4b63-b910-998f6f818089', out: 'postal_codes.csv'
      downloader.curl 'http://files.opendatarchives.fr/professionnels.ign.fr/adminexpress/ADMIN-EXPRESS_4-0__GPKG_LAMB93_FXX_2026-01-19.7z', out: 'communes.7z'
    end
    
    # Layers of ADMIN EXPRESS that give a shape to an INSEE code: communes, and the arrondissements of Paris,
    # Lyon and Marseille, which the postal reference lists under their own code
    LAYERS = %w[commune arrondissement_municipal].freeze

    # Paris, Lyon and Marseille as whole communes, and the codes of their arrondissements. The postal reference
    # only lists the arrondissements, while many datasets give the code of the commune.
    WHOLE_COMMUNES = { '75056' => '751__', '69123' => '6938_', '13055' => '132__' }.freeze

    def load
      load_csv(dir.join('postal_codes.csv'), 'postal_codes', col_sep: ';')
      execute("7z x #{dir.join('communes.7z')} -o#{dir}/archive -aoa")
      gpkg = Dir.glob(dir.join('archive/**/*.gpkg').to_s).first
      raise "No GeoPackage found in #{dir.join('communes.7z')}" if gpkg.nil?

      # Only what normalize reads is loaded, and without spatial index: nothing searches this table
      LAYERS.each_with_index do |layer, index|
        execute <<~BASH
          ogr2ogr \
            -f PostgreSQL "#{pg_connection_string}" \
            #{index.zero? ? '-overwrite' : '-append'} \
            -lco SCHEMA=#{name} \
            -lco GEOMETRY_NAME=geom \
            -lco FID=ogc_fid \
            -lco SPATIAL_INDEX=NONE \
            -nlt MULTIPOLYGON \
            -nln #{name}.communes \
            -sql "SELECT code_insee, geometrie FROM #{layer}" \
            "#{gpkg}"
        BASH
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_postal_codes, sql: <<-SQL
        CREATE TABLE registered_postal_codes (
          id character varying PRIMARY KEY NOT NULL,
          country character varying NOT NULL,
          code character varying NOT NULL,
          city_name character varying NOT NULL,
          postal_code character varying NOT NULL,
          city_delivery_name character varying,
          city_delivery_detail character varying,
          city_centroid postgis.geometry(Point,4326),
          city_shape postgis.geometry(MultiPolygon, 4326)
      );

        CREATE INDEX registered_postal_codes_country ON registered_postal_codes(country);
        CREATE INDEX registered_postal_codes_city_name ON registered_postal_codes(city_name);
        CREATE INDEX registered_postal_codes_postal_code ON registered_postal_codes(postal_code);
        CREATE INDEX registered_postal_codes_centroid ON registered_postal_codes USING GIST (city_centroid);
        CREATE INDEX registered_postal_codes_shape ON registered_postal_codes USING GIST (city_shape);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_postal_codes (id, country, code, city_name, postal_code, city_delivery_name, city_delivery_detail)
          SELECT CONCAT(code_commune_insee, '_', code_postal, '_', SUBSTR(REPLACE(libelle_d_acheminement, ' ', ''), 1, 6), '_', SUBSTR(REPLACE(ligne_5, ' ', ''), 1, 12)),
            'FR',
            code_commune_insee,
            regexp_replace(nom_de_la_commune, '(^|\s)([DL]) ','\\1\\2''', 'g'),
            code_postal,
            libelle_d_acheminement,
            ligne_5
          FROM postal_codes.postal_codes
      SQL

      # A whole commune bears each postal code of its arrondissements, under the name they are delivered by
      WHOLE_COMMUNES.each do |code, arrondissements|
        query <<-SQL
          INSERT INTO registered_postal_codes (id, country, code, city_name, postal_code, city_delivery_name)
            SELECT DISTINCT CONCAT('#{code}', '_', postal_code, '_', SUBSTR(REPLACE(city_delivery_name, ' ', ''), 1, 6), '_'),
              'FR', '#{code}', city_delivery_name, postal_code, city_delivery_name
            FROM registered_postal_codes
            WHERE code LIKE '#{arrondissements}'
              AND NOT EXISTS (SELECT 1 FROM registered_postal_codes WHERE code = '#{code}')
        SQL
      end

      # update shape
      query <<-SQL
        UPDATE registered_postal_codes
          SET city_shape = postgis.ST_Transform(c.geom, 4326)
          FROM postal_codes.communes c WHERE c.code_insee = code
      SQL

      # compute centroid
      query <<-SQL
        UPDATE registered_postal_codes
          SET city_centroid = postgis.ST_Centroid(city_shape)
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
