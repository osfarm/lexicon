module Datasources
  class ChartOfAccounts < Base
    description 'Chart of accounts'
    credits name: 'Plans de comptes de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    def collect
      FileUtils.cp Dir.glob('data/chart_of_accounts/chart_of_accounts - chart_of_accounts.csv'), dir
    end

    def load
      load_csv(dir.join('chart_of_accounts - chart_of_accounts.csv'), 'chart_of_accounts')
    end

    def self.table_definitions(builder)
      builder.table :master_chart_of_accounts, sql: <<-SQL
        CREATE TABLE master_chart_of_accounts (
          id integer PRIMARY KEY NOT NULL,
          reference_name character varying,
          previous_reference_name character varying,
          fr_pcga character varying,
          fr_pcg82 character varying,
          name jsonb
        );

        CREATE INDEX master_chart_of_accounts_reference_name ON master_chart_of_accounts(reference_name);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO master_chart_of_accounts (id, reference_name, previous_reference_name, fr_pcga, fr_pcg82, name)
          SELECT n::INTEGER, name, previous_name, fr_pcga, fr_pcg82, CONCAT('{"fra":"', label_fr, '"}')::JSONB
          FROM chart_of_accounts.chart_of_accounts
      SQL
    end

  end
end
