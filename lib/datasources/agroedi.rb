module Datasources
  class Agroedi < Base
    description 'AgroEDI Europe'
    credits name: 'Dictionnaire AgroEDI', url: "https://agroedieurope.fr/", provider: "AgroEDI", licence: "proprietary", licence_url: "", updated_at: "2023-01-01"

    def collect
      #Collect each csv file in agroedi directory
      FileUtils.cp Dir.glob('data/agroedi/*.csv'), dir
    end

    def load
      load_csv(dir.join('agroedi - crops.csv'), 'crops')
      load_csv(dir.join('agroedi - dictionnary.csv'), 'dictionnary')
    end

    def self.table_definitions(builder)
      builder.table :registered_agroedi_codes, sql: <<-SQL
        CREATE TABLE registered_agroedi_codes (
          repository_id integer NOT NULL,
          reference_id integer NOT NULL,
          reference_code character varying,
          reference_label character varying,
          ekylibre_scope character varying,
          ekylibre_value character varying
        );
        CREATE INDEX registered_agroedi_codes_reference_code ON registered_agroedi_codes(reference_code);
      SQL

      builder.table(:registered_agroedi_crops, sql: <<-SQL).references(production: [:master_productions, :reference_name])
        CREATE TABLE registered_agroedi_crops (
          agroedi_code character varying NOT NULL,
          agroedi_name character varying NOT NULL,
          production character varying
        );
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_agroedi_codes (repository_id, reference_id, reference_code, reference_label, ekylibre_scope, ekylibre_value)
          SELECT repository_id::INTEGER, reference_id::INTEGER, reference_code, reference_label, ekylibre_scope, ekylibre_value
          FROM agroedi.dictionnary
      SQL

      query <<-SQL
        INSERT INTO registered_agroedi_crops (agroedi_code, agroedi_name, production)
          SELECT agroedi_code, agroedi_name, production
          FROM agroedi.crops
      SQL
    end

  end
end
