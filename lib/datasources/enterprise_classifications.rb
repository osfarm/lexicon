module Datasources
  class EnterpriseClassifications < Base
    description 'Classifications des entreprises agricoles : codes NAF agricoles (INSEE) et OTEX (Agreste)'
    credits name: 'NAF rév. 2 (sous-ensemble agricole) et OTEX v2',
            url: 'https://www.insee.fr/fr/information/2120875',
            provider: 'INSEE / Agreste-SSP',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: '2026-05-22'

    FILES = {
      'naf_rev2_ag.csv' => 'naf_rev2_ag',
      'otex_v2.csv'     => 'otex_v2',
      'otex_naf.csv'    => 'otex_naf'
    }.freeze

    def collect
      FILES.each_key do |filename|
        FileUtils.cp("data/enterprise_classifications/#{filename}", dir)
      end
    end

    def load
      FILES.each do |filename, table|
        load_csv(dir.join(filename), table)
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_agricultural_naf_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_naf_codes (
          code character varying PRIMARY KEY NOT NULL,
          label jsonb NOT NULL
        );
      SQL

      builder.table :registered_agricultural_otex_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_otex_codes (
          code character varying PRIMARY KEY NOT NULL,
          label jsonb NOT NULL,
          parent_code character varying NOT NULL,
          parent_label jsonb NOT NULL
        );
        CREATE INDEX registered_agricultural_otex_codes_parent_code
          ON registered_agricultural_otex_codes(parent_code);
      SQL

      builder.table :registered_agricultural_naf_otex_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_naf_otex_codes (
          id SERIAL PRIMARY KEY NOT NULL,
          otex_code character varying NOT NULL,
          naf_code character varying NOT NULL,
          UNIQUE (otex_code, naf_code)
        );
        CREATE INDEX registered_agricultural_naf_otex_codes_otex_code
          ON registered_agricultural_naf_otex_codes(otex_code);
        CREATE INDEX registered_agricultural_naf_otex_codes_naf_code
          ON registered_agricultural_naf_otex_codes(naf_code);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_agricultural_naf_codes (code, label)
          SELECT code, jsonb_build_object('fra', label)
          FROM enterprise_classifications.naf_rev2_ag
      SQL

      query <<-SQL
        INSERT INTO registered_agricultural_otex_codes (code, label, parent_code, parent_label)
          SELECT code,
                 jsonb_build_object('fra', label),
                 parent_code,
                 jsonb_build_object('fra', parent_label)
          FROM enterprise_classifications.otex_v2
      SQL

      query <<-SQL
        INSERT INTO registered_agricultural_naf_otex_codes (otex_code, naf_code)
          SELECT otex_code, trim(naf)
          FROM enterprise_classifications.otex_naf,
               UNNEST(string_to_array(naf_codes, ';')) AS naf
          WHERE naf_codes IS NOT NULL AND trim(naf_codes) <> ''
          ON CONFLICT (otex_code, naf_code) DO NOTHING
      SQL
    end
  end
end
