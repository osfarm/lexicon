# frozen_string_literal: true

require 'csv'

module Datasources
  # National average prices of oil products, read every Friday by the DGEC (ministry of ecological
  # transition) and published every Monday. Only non-road diesel (GNR) is loaded: the tables carry a
  # `product` column so that the road fuels and heating oil of the same workbook can join it later.
  class FuelPrices < Base
    description 'Prix moyens nationaux des produits pétroliers relevés chaque vendredi par la DGEC : gazole non routier (GNR)'
    credits name: 'Prix des produits pétroliers',
            url: 'https://www.ecologie.gouv.fr/politiques-publiques/prix-produits-petroliers',
            provider: 'Ministère de la Transition écologique (DGEC)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-02'

    schema_revision 1
    # The source is as recent as its last reading, whatever the day it is collected
    source_date 'SELECT max(observed_on) FROM registered_fuel_prices'

    PAGE_URL = 'https://www.ecologie.gouv.fr/politiques-publiques/prix-produits-petroliers'
    # The name of the file ends with a counter that changes: the link is found by its beginning
    WORKBOOK_LINK = %r{href="(https://www\.ecologie\.gouv\.fr/sites/default/files/documents/Prix%20HTT%20et%20TTC%20depuis%20janvier%202020[^"]*\.xlsx)"}.freeze
    SHEET = 'Carburants non routiers'
    USER_AGENT = 'Lexicon OSFarm (+https://lexicon.osfarm.org)'

    # Downloads the workbook of the day. The previous ones are kept: a past collection can be replayed.
    def collect
      page = dir.join("page_#{Date.today.iso8601}.html")
      download(PAGE_URL, page)
      link = page.read[WORKBOOK_LINK, 1]
      raise "No link to the workbook 'Prix HTT et TTC depuis janvier 2020' in #{PAGE_URL}" if link.nil?

      download(link, dir.join("prices_#{Date.today.iso8601}.xlsx"))
    end

    # Checks the sheet before anything is loaded: a doubtful workbook stops here, the published tables untouched.
    def load
      workbook = Pathname.glob(dir.join('prices_*.xlsx')).max
      raise "No workbook in #{dir}: run the collect phase first" if workbook.nil?

      document = ::Roo::Spreadsheet.open(workbook.to_s)
      raise "No sheet '#{SHEET}' in #{workbook}" unless document.sheets.include?(SHEET)

      sheet = document.sheet(SHEET)
      readings = Readings.new((1..sheet.last_row).map { |index| sheet.row(index) })
      readings.validate!

      write_csv('readings.csv', %w[observed_on excluding_taxes including_taxes], readings.weekly.map(&:to_a))
      write_csv('months.csv', %w[month excluding_taxes including_taxes observations last_observed_on], readings.monthly.map(&:to_a))
      load_csv(dir.join('readings.csv'), 'readings')
      load_csv(dir.join('months.csv'), 'months')
    end

    def self.table_definitions(builder)
      builder.table(:registered_fuel_prices, sql: <<~SQL)
        CREATE TABLE registered_fuel_prices (
          id character varying PRIMARY KEY NOT NULL,
          product character varying NOT NULL,
          observed_on date NOT NULL,
          price_excluding_taxes numeric(8,4) NOT NULL,
          price_excluding_vat numeric(8,4) NOT NULL,
          price_including_taxes numeric(8,4) NOT NULL,
          currency character varying NOT NULL,
          unit character varying NOT NULL
        );
        CREATE INDEX registered_fuel_prices_product_observed_on ON registered_fuel_prices (product, observed_on);
      SQL

      builder.table(:registered_fuel_monthly_prices, sql: <<~SQL)
        CREATE TABLE registered_fuel_monthly_prices (
          id character varying PRIMARY KEY NOT NULL,
          product character varying NOT NULL,
          month date NOT NULL,
          price_excluding_taxes numeric(8,4) NOT NULL,
          price_excluding_vat numeric(8,4) NOT NULL,
          price_including_taxes numeric(8,4) NOT NULL,
          observations integer NOT NULL,
          last_observed_on date NOT NULL,
          currency character varying NOT NULL,
          unit character varying NOT NULL
        );
        CREATE INDEX registered_fuel_monthly_prices_product_month ON registered_fuel_monthly_prices (product, month);
      SQL
    end

    def normalize
      excluding_vat = "including_taxes::numeric / #{1 + Readings::VAT_RATE}"

      query <<~SQL
        INSERT INTO registered_fuel_prices (id, product, observed_on, price_excluding_taxes, price_excluding_vat,
                                            price_including_taxes, currency, unit)
          SELECT '#{Readings::PRODUCT}_' || observed_on, '#{Readings::PRODUCT}', observed_on::date,
                 excluding_taxes::numeric, #{excluding_vat}, including_taxes::numeric, 'EUR', 'liter'
            FROM #{name}.readings
           ORDER BY observed_on
      SQL
      query <<~SQL
        INSERT INTO registered_fuel_monthly_prices (id, product, month, price_excluding_taxes, price_excluding_vat,
                                                    price_including_taxes, observations, last_observed_on, currency, unit)
          SELECT '#{Readings::PRODUCT}_' || left(month, 7), '#{Readings::PRODUCT}', month::date,
                 excluding_taxes::numeric, #{excluding_vat}, including_taxes::numeric,
                 observations::integer, last_observed_on::date, 'EUR', 'liter'
            FROM #{name}.months
           ORDER BY month
      SQL
    end

    private

      def download(url, file)
        execute "curl -sSLf --retry 2 -A '#{USER_AGENT}' -o '#{file}' '#{url}'"
        raise "Nothing downloaded from #{url}" unless file.size?
      end

      def write_csv(file, headers, rows)
        CSV.open(dir.join(file), 'w') do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
  end
end
