module Datasources
  class LegalPositions < Base
    description 'Legal positions'
    credits name: 'Liste des types de structures juridiques', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    def collect
      FileUtils.cp Dir.glob('data/legal_positions/legal_positions - legal_positions.csv'), dir
    end

    def load
      load_csv(dir.join('legal_positions - legal_positions.csv'), 'legal_positions')
    end

    def self.table_definitions(builder)
      builder.table :master_legal_positions, sql: <<-SQL
        CREATE TABLE master_legal_positions (
          code character varying PRIMARY KEY NOT NULL,
          name jsonb,
          nature character varying NOT NULL,
          country character varying NOT NULL,
          insee_code character varying NOT NULL,
          fiscal_positions text[]
        );
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO master_legal_positions (code, name, nature, country, insee_code, fiscal_positions)
          SELECT code, CONCAT('{"fra":"', name, '"}')::JSONB, nature, country, insee_code, CONCAT('{', fiscal_positions, '}')::TEXT[]
          FROM legal_positions.legal_positions
      SQL
    end
  end
end
