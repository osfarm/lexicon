module Datasources
  class Units < Base
    description 'Dimensions, units and packaging'
    credits name: 'Liste des unités et conditionnements de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2022-02-23"

    def collect
      #Collect each csv file in units directory
      FileUtils.cp Dir.glob('data/units/*.csv'), dir
    end

    def load
      load_csv(dir.join('units - dimensions.csv'), 'dimensions')
      load_csv(dir.join('units - units.csv'), 'units')
      load_csv(dir.join('units - packagings.csv'), 'packagings')
    end

    def self.table_definitions(builder)
      builder.table :master_dimensions, sql: <<~SQL
        CREATE TABLE master_dimensions (
          reference_name character varying PRIMARY KEY NOT NULL,
          symbol character varying NOT NULL,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_dimensions_reference_name ON master_dimensions(reference_name);
      SQL

      builder.table :master_units, sql: <<~SQL
        CREATE TABLE master_units (
          reference_name character varying PRIMARY KEY NOT NULL,
          dimension character varying NOT NULL,
          symbol character varying NOT NULL,
          a numeric(25,10),
          d numeric(25,10),
          b numeric(25,10),
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_units_reference_name ON master_units(reference_name);
      SQL

      builder.table :master_packagings, sql: <<~SQL
        CREATE TABLE master_packagings (
          reference_name character varying PRIMARY KEY NOT NULL,
          capacity numeric(25,10) NOT NULL,
          capacity_unit character varying NOT NULL,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_packagings_reference_name ON master_packagings(reference_name);
      SQL

    end

    def normalize

      query "DELETE FROM master_translations WHERE id LIKE 'dimensions%'"
      query "DELETE FROM master_translations WHERE id LIKE 'units%'"
      query "DELETE FROM master_translations WHERE id LIKE 'packaging%'"

      query <<-SQL
        INSERT INTO master_dimensions (reference_name, symbol, translation_id)
          SELECT reference_name, symbol, CONCAT('dimensions_', reference_name)
          FROM units.dimensions;

        INSERT INTO master_units (reference_name, dimension, symbol, a, d, b, translation_id)
          SELECT reference_name, dimension, symbol, a::NUMERIC, d::NUMERIC, b::NUMERIC, CONCAT('units_', reference_name)
          FROM units.units;

        INSERT INTO master_packagings (reference_name, capacity, capacity_unit, translation_id)
          SELECT reference_name, capacity::NUMERIC, capacity_unit, CONCAT('packagings_', reference_name)
          FROM units.packagings;
      SQL

      insert_translations('units', 'dimensions', 'dimensions')
      insert_translations('units', 'units', 'units')
      insert_translations('units', 'packagings', 'packagings')

    end

  end
end
