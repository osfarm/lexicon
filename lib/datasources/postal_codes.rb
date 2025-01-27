module Datasources
  class PostalCodes < Base
    description 'French Enterprises postal and insee codes with gps coordinates'
    credits name: 'Codes postaux et communes', url: "https://www.data.gouv.fr/fr/datasets/base-officielle-des-codes-postaux/", provider: "Groupe La Poste", licence: "ODbl", licence_url: "https://opendatacommons.org/licenses/odbl/summary/", updated_at: "2025-01-08"

    def collect
      downloader.curl 'https://www.data.gouv.fr/fr/datasets/r/0f8ae8bd-9c0a-4a62-9be5-4798cbac07ff', out: 'postal_codes.csv'
      downloader.curl 'http://files.opendatarchives.fr/professionnels.ign.fr/adminexpress/ADMIN-EXPRESS_3-2__SHP_LAMB93_FXX_2024-11-18.7z', out: 'communes.7z'
    end

    def load
      load_csv(dir.join('postal_codes.csv'), 'postal_codes', col_sep: ',')
      execute("7z x #{dir.join('communes.7z')} -o#{dir}/archive -aoa")
      archive_glob = dir.join("archive/ADMIN-EXPRESS_3-2__SHP_LAMB93_FXX_2024-11-18/ADMIN-EXPRESS/1_DONNEES_LIVRAISON_2024-11-00163/ADE_3-2_SHP_LAMB93_FXX-ED2024-11-18/COMMUNE.shp")
      archive_path = Dir.glob(archive_glob).first
      load_shp(dir.join(archive_path), table_name: "communes", srid: 2154)
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

      # update shape
      query <<-SQL
        UPDATE registered_postal_codes
          SET city_shape = postgis.ST_Transform(c.geom, 4326)
          FROM postal_codes.communes c WHERE c.insee_com = code
      SQL

      # compute centroid
      query <<-SQL
        UPDATE registered_postal_codes
          SET city_centroid = postgis.ST_Centroid(city_shape)
      SQL
    end
  end
end
