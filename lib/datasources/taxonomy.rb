module Datasources
  class Taxonomy < Base
    description 'Taxonomy'
    credits name: 'Taxonomie', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-01-27"

    def collect
      FileUtils.cp Dir.glob('data/taxonomy/taxonomy - taxonomy.csv'), dir
    end

    def load
      load_csv(dir.join('taxonomy - taxonomy.csv'), 'taxonomy')
    end

    def self.table_definitions(builder)
      builder.table :master_taxonomy, sql: <<~SQL
        CREATE TABLE master_taxonomy (
          reference_name character varying PRIMARY KEY NOT NULL,
          parent character varying,
          taxonomic_rank character varying,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_taxonomy_reference_name ON master_taxonomy(reference_name);
      SQL
    end

    def normalize
      query "DELETE FROM master_translations WHERE id LIKE 'taxonomy%'"

      query <<~SQL
        INSERT INTO master_taxonomy (reference_name, parent, taxonomic_rank, translation_id)
          SELECT reference_name, parent, taxonomic_rank, CONCAT('taxonomy_', reference_name)
          FROM taxonomy.taxonomy;
      SQL

      insert_translations('taxonomy', 'taxonomy', 'taxonomy')
    end

  end
end
