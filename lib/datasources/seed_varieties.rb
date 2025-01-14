module Datasources
  class SeedVarieties < Base
    description 'Seed varieties from GNIS (Groupement National Interprofessionnel des Semences et plants)'
    credits name: 'Liste des variétés de semences', url: "https://www.semae.fr/catalogue-varietes/base-varietes-gnis/", provider: "SEMAE", licence: "", licence_url: "", updated_at: "2023-11-15"

    def collect
      downloader.curl "https://www.gnis.fr/wp-admin/admin-ajax.php?action=exportCsv", out: 'gnis.csv'
      FileUtils.cp Dir.glob('data/seed_varieties/seed_varieties - seed_species.csv'), dir
    end

    def load
      load_csv(dir.join('gnis.csv'), 'gnis', col_sep: ';')
      load_csv(dir.join('seed_varieties - seed_species.csv'), 'seed_species')
    end

    def self.table_definitions(builder)
      builder.table(:registered_seed_varieties, sql: <<-SQL).references(id_specie: [:master_taxonomy, :reference_name])
        CREATE TABLE registered_seed_varieties (
          id character varying PRIMARY KEY NOT NULL,
          id_specie character varying NOT NULL,
          specie_name jsonb,
          specie_name_fra character varying,
          variety_name character varying,
          registration_date date
        );

        CREATE INDEX registered_seed_varieties_id ON registered_seed_varieties(id);
        CREATE INDEX registered_seed_varieties_id_specie ON registered_seed_varieties(id_specie);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_seed_varieties (id, id_specie, specie_name, specie_name_fra, variety_name, registration_date)
          SELECT REPLACE(code_gnis, ' ', ''), specie, CONCAT('{"fra":"', name, '"}')::JSONB, name, variete, TO_DATE(date_d_inscription, 'YYYYMMDD')
          FROM seed_varieties.gnis JOIN seed_varieties.seed_species
          ON gnis.id_espece = seed_species.id
      SQL
    end
  end
end
