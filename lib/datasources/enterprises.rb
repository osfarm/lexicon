module Datasources
  class Enterprises < Base
    LAST_UPDATED = "2024-09-01"
    description 'French Enterprises datasource'
    credits name: 'Base SIRENE', url: "https://www.data.gouv.fr/fr/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/", provider: "INSEE", licence: "Open Licence 2.0", licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence", updated_at: LAST_UPDATED

    def collect
      downloader.curl "http://files.data.gouv.fr/insee-sirene/StockEtablissement_utf8.zip", out: 'StockEtablissement_utf8.zip'
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
          country character varying
        );

        CREATE INDEX registered_enterprises_french_main_activity_code ON registered_enterprises(french_main_activity_code);
        CREATE INDEX registered_enterprises_name ON registered_enterprises(name);
      SQL
    end

    python :normalize
  end
end
