module Datasources
  class Enterprises < Base
    LAST_UPDATED = "2025-01-01"
    description 'French establishments of every activity (Base SIRENE)'
    credits name: 'Base SIRENE', url: "https://www.data.gouv.fr/fr/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/", provider: "INSEE", licence: "Open Licence 2.0", licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence", updated_at: LAST_UPDATED
    pivot :commune, table: :registered_enterprises, column: :insee_code, minimum: 0.9

    def collect
      downloader.curl "https://www.data.gouv.fr/api/1/datasets/r/0651fb76-bcf3-4f6a-a38d-bc04fa708576", out: 'eta_utf8.zip'
    end

    def load
      execute("7z x #{dir.join('eta_utf8.zip')} -o#{dir}/archive -aoa")
      load_csv(dir.join('archive/StockEtablissement_utf8.csv'), 'postal_codes', col_sep: ',')
    end

    def self.table_definitions(builder)
      builder.table :registered_enterprises, sql: <<-SQL
        CREATE TABLE registered_enterprises (
          establishment_number character varying PRIMARY KEY NOT NULL,
          french_main_activity_code character varying NOT NULL,
          name character varying,
          address character varying,
          postal_code character varying,
          city character varying,
          insee_code character varying,
          country character varying,
          centroid postgis.geometry(Point,4326),
          siren character varying
        );

        CREATE INDEX registered_enterprises_french_main_activity_code ON registered_enterprises(french_main_activity_code);
        CREATE INDEX registered_enterprises_name ON registered_enterprises(name);
        CREATE INDEX registered_enterprises_siren ON registered_enterprises(siren);
        CREATE INDEX registered_enterprises_establishment_number ON registered_enterprises(establishment_number);
        CREATE INDEX registered_enterprises_insee_code ON registered_enterprises(insee_code);
        CREATE INDEX registered_enterprises_postal_code ON registered_enterprises(postal_code);
        CREATE INDEX registered_enterprises_city ON registered_enterprises(city);
        CREATE INDEX registered_enterprises_centroid ON registered_enterprises USING GIST (centroid);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_enterprises (establishment_number, french_main_activity_code, name, address, postal_code, city, country, centroid, siren, insee_code)
          SELECT
            siret,
            activite_principale_etablissement,
            COALESCE(enseigne1_etablissement, enseigne2_etablissement, enseigne3_etablissement, denomination_usuelle_etablissement),
            CONCAT(numero_voie_etablissement, COALESCE(indice_repetition_etablissement,''), type_voie_etablissement, libelle_voie_etablissement),
            code_postal_etablissement,
            libelle_commune_etablissement,
            'FR',
            CASE WHEN coordonnee_lambert_abscisse_etablissement IS NOT NULL AND coordonnee_lambert_abscisse_etablissement <> '[ND]'
              THEN postgis.ST_Transform(
                    postgis.ST_SetSRID(
                      postgis.ST_MakePoint(coordonnee_lambert_abscisse_etablissement::numeric, coordonnee_lambert_ordonnee_etablissement::numeric),
                       2154),
                      4326)
              ELSE NULL
            END,
            siren,
            code_commune_etablissement
          -- Every establishment, whatever its activity; the few without an activity code are left out
          FROM enterprises.postal_codes WHERE activite_principale_etablissement IS NOT NULL
      SQL
    end
  end
end
