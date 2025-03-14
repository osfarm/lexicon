module Datasources
  class Enterprises < Base
    LAST_UPDATED = "2025-01-01"
    description 'French Enterprises datasource'
    credits name: 'Base SIRENE', url: "https://www.data.gouv.fr/fr/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/", provider: "INSEE", licence: "Open Licence 2.0", licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence", updated_at: LAST_UPDATED

    CODES_APE = "'01.11Z', '01.12Z', '01.13Z', '01.14Z', '01.15Z', '01.16Z', '01.19Z', '01.21Z', '01.22Z', '01.23Z',
             '01.24Z', '01.5Z', '01.26Z', '01.27Z', '01.28Z', '01.29Z', '01.30Z', '01.41Z', '01.42Z', '01.43Z',
             '01.44Z', '01.45Z', '01.46Z', '01.47Z', '01.49Z', '01.50Z', '01.61Z', '01.62Z', '01.63Z', '01.64Z',
             '01.70Z', '02.10Z', '02.20Z', '02.30Z', '02.40Z', '03.11Z', '03.12Z', '03.21Z', '03.22Z'"
    def collect
      downloader.curl "http://files.data.gouv.fr/insee-sirene/StockEtablissement_utf8.zip", out: 'eta_utf8.zip'
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
          country character varying,
          centroid postgis.geometry(Point,4326)
        );

        CREATE INDEX registered_enterprises_french_main_activity_code ON registered_enterprises(french_main_activity_code);
        CREATE INDEX registered_enterprises_name ON registered_enterprises(name);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_enterprises (establishment_number, french_main_activity_code, name, address, postal_code, city, country, centroid)
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
            END
          FROM enterprises.postal_codes WHERE activite_principale_etablissement IN (#{CODES_APE})
      SQL
    end
  end
end
