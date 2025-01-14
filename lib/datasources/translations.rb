module Datasources
  class Translations < Base
    description 'Translations of variants, productions, taxonomy and user_roles'
    credits name: 'Traductions', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-01-27"

    def collect
    end

    def load
    end

    def self.table_definitions(builder)
      builder.table :master_translations, sql: <<~SQL
        CREATE TABLE master_translations (
          id character varying PRIMARY KEY NOT NULL,
          fra character varying NOT NULL,
          eng character varying NOT NULL
        )
      SQL
    end

    def normalize
    end

  end
end
