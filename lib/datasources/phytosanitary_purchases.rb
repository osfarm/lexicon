# frozen_string_literal: true

require 'json'

module Datasources
  # Purchases of plant protection products, in kilograms of active substance, estimated commune by commune
  # by the statistics office of the ministry of ecological transition (SDES) from what distributors declare
  # to the national sales database (BNV-D). The last five years are kept, for metropolitan France.
  #
  # These are purchases, not uses: a quantity is declared at the postal code of the buyer, then shared between
  # the communes of that postal code in proportion to their farmland outside grassland.
  class PhytosanitaryPurchases < Base
    description "Achats de produits phytosanitaires estimés à la commune (BNV-D) : quantités de substances actives par année, produit et substance, sur les cinq dernières années"
    credits name: "Achats de produits phytosanitaires estimés à l'échelle de la commune",
            url: 'https://www.data.gouv.fr/datasets/achats-de-produits-phytosanitaires-estimes-a-lechelle-de-la-commune',
            provider: 'Service des données et études statistiques (SDES)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-07-22'

    schema_revision 1
    # The source is as recent as the last year it covers
    source_date 'SELECT make_date(max(year), 12, 31) FROM registered_phytosanitary_purchase_communes'
    pivot :commune, table: :registered_phytosanitary_purchase_communes, column: :insee_code
    pivot :amm, table: :registered_phytosanitary_purchases, column: :product_id

    DATASET_URL = 'https://www.data.gouv.fr/api/1/datasets/achats-de-produits-phytosanitaires-estimes-a-lechelle-de-la-commune/'
    YEARS_KEPT = 5
    # What the source writes in place of a value under statistical secrecy
    SECRET = 'secret'

    # The functions of the source, long labels shortened to a key
    FUNCTIONS = {
      'Herbicide et anti mousse' => 'herbicide',
      'Fongicide - bactéricide - virucide' => 'fungicide',
      'Insecticide - acaricide - nématicide - médiateur chimique' => 'insecticide'
    }.freeze
    OTHER_FUNCTION = 'other'

    # Downloads the file (1.4 GB) when the source published a new one since the last collect.
    def collect
      description = dir.join('dataset.json')
      execute "curl -sSLf --retry 2 -o '#{description}.new' '#{DATASET_URL}'"
      resource = JSON.parse(File.read("#{description}.new")).fetch('resources').find { |found| found['format'] == 'parquet' }
      raise "No Parquet file in #{DATASET_URL}" if resource.nil?

      known = description.exist? ? JSON.parse(description.read).fetch('resources').find { |found| found['format'] == 'parquet' } : nil
      if parquet.size? && known && known['last_modified'] == resource['last_modified']
        logger.debug "Purchases of #{resource['last_modified']} already collected"
      else
        execute "curl -sSLf --retry 2 -o '#{parquet}' '#{resource.fetch('url')}'"
        raise "Nothing downloaded from #{resource['url']}" unless parquet.size?
      end
      File.rename("#{description}.new", description)
    end

    # Reads the Parquet file with DuckDB and writes what is kept as CSV: one line per commune, year, product and
    # substance, and the count of lines the source keeps secret in each commune and year.
    def load
      raise "No file #{parquet}: run the collect phase first" unless parquet.size?

      script = dir.join('extract.sql')
      script.write(extraction)
      execute "python3 -c \"import duckdb; duckdb.connect().execute(open('#{script}').read())\""

      %w[purchases masked].each do |table|
        file = dir.join("#{table}.csv")
        raise "DuckDB wrote no #{file}" unless file.size?

        load_csv(file, table)
      end
    end

    def self.table_definitions(builder)
      builder.table(:registered_phytosanitary_purchases, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_purchases (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          product_id integer NOT NULL,
          substance character varying NOT NULL,
          cas_number character varying,
          function character varying NOT NULL,
          danger character varying,
          biocontrol boolean,
          organic boolean,
          quantity numeric(14,4) NOT NULL,
          PRIMARY KEY (insee_code, year, product_id, substance)
        );
        CREATE INDEX registered_phytosanitary_purchases_substance ON registered_phytosanitary_purchases (substance, year);
        CREATE INDEX registered_phytosanitary_purchases_product ON registered_phytosanitary_purchases (product_id, year);
        CREATE INDEX registered_phytosanitary_purchases_cas ON registered_phytosanitary_purchases (cas_number);
      SQL

      builder.table(:registered_phytosanitary_purchase_summaries, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_purchase_summaries (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          function character varying NOT NULL,
          danger character varying NOT NULL,
          quantity numeric(14,4) NOT NULL,
          substances_count integer NOT NULL,
          PRIMARY KEY (insee_code, year, function, danger)
        );
      SQL

      # What France buys of each substance, year by year: also the list of the substances the source names
      builder.table(:registered_phytosanitary_purchase_substances, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_purchase_substances (
          substance character varying NOT NULL,
          year integer NOT NULL,
          cas_number character varying,
          function character varying NOT NULL,
          danger character varying,
          quantity numeric(14,4) NOT NULL,
          communes_count integer NOT NULL,
          products_count integer NOT NULL,
          PRIMARY KEY (substance, year)
        );
      SQL

      builder.table(:registered_phytosanitary_purchase_communes, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_purchase_communes (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          quantity numeric(14,4),
          products_count integer NOT NULL,
          substances_count integer NOT NULL,
          masked boolean NOT NULL,
          masked_lines integer NOT NULL,
          PRIMARY KEY (insee_code, year)
        );
        CREATE INDEX registered_phytosanitary_purchase_communes_year ON registered_phytosanitary_purchase_communes (year);
      SQL
    end

    def normalize
      functions = FUNCTIONS.map { |label, key| "WHEN '#{label}' THEN '#{key}'" }.join(' ')

      query <<~SQL
        INSERT INTO registered_phytosanitary_purchases
          (insee_code, year, product_id, substance, cas_number, function, danger, biocontrol, organic, quantity)
          SELECT insee_code, year::integer, amm::integer, substance, NULLIF(cas, ''),
                 CASE function #{functions} ELSE '#{OTHER_FUNCTION}' END,
                 NULLIF(danger, ''),
                 CASE biocontrol WHEN 'oui' THEN true WHEN 'non' THEN false END,
                 CASE organic WHEN 'uab' THEN true WHEN 'non uab' THEN false END,
                 quantity::numeric
            FROM #{name}.purchases
           ORDER BY insee_code, year
      SQL

      query <<~SQL
        INSERT INTO registered_phytosanitary_purchase_summaries (insee_code, year, function, danger, quantity, substances_count)
          SELECT insee_code, year, function, COALESCE(danger, 'Autre'), sum(quantity), count(DISTINCT substance)
            FROM registered_phytosanitary_purchases
           GROUP BY insee_code, year, function, COALESCE(danger, 'Autre')
      SQL

      query <<~SQL
        INSERT INTO registered_phytosanitary_purchase_substances
          (substance, year, cas_number, function, danger, quantity, communes_count, products_count)
          SELECT substance, year, min(cas_number), min(function), min(danger), sum(quantity),
                 count(DISTINCT insee_code), count(DISTINCT product_id)
            FROM registered_phytosanitary_purchases
           GROUP BY substance, year
      SQL

      # A commune whose every purchase is secret has a line all the same: no quantity, and `masked`
      query <<~SQL
        INSERT INTO registered_phytosanitary_purchase_communes
          (insee_code, year, quantity, products_count, substances_count, masked, masked_lines)
          SELECT insee_code, year, known.quantity, COALESCE(known.products_count, 0), COALESCE(known.substances_count, 0),
                 secret.lines IS NOT NULL, COALESCE(secret.lines, 0)
            FROM (SELECT insee_code, year, sum(quantity) AS quantity, count(DISTINCT product_id) AS products_count,
                         count(DISTINCT substance) AS substances_count
                    FROM registered_phytosanitary_purchases
                   GROUP BY insee_code, year) AS known
            FULL JOIN (SELECT insee_code, year::integer AS year, lines::integer AS lines FROM #{name}.masked) AS secret
           USING (insee_code, year)
      SQL
    end

    private

      def parquet
        dir.join('purchases.parquet')
      end

      # Metropolitan communes of the last years. A commune, a product and a substance are met twice in a year
      # now and then: their quantities are added.
      def extraction
        kept = <<~SQL
          FROM read_parquet('#{parquet}')
          WHERE annee > (SELECT max(annee) FROM read_parquet('#{parquet}')) - #{YEARS_KEPT}
            AND code_insee <> '00000' AND code_insee NOT LIKE '97%' AND code_insee NOT LIKE '98%'
        SQL

        <<~SQL
          COPY (
            SELECT CAST(annee AS INTEGER) AS year, code_insee AS insee_code, amm, substance, any_value(cas) AS cas,
                   any_value(fonction_sdes) AS function, any_value(danger) AS danger,
                   any_value(biocontrole) AS biocontrol, any_value(uab) AS organic,
                   sum(CAST(quantite_substance AS DOUBLE)) AS quantity
            #{kept} AND quantite_substance <> '#{SECRET}'
            GROUP BY annee, code_insee, amm, substance
          ) TO '#{dir.join('purchases.csv')}' (HEADER, DELIMITER ',');

          COPY (
            SELECT CAST(annee AS INTEGER) AS year, code_insee AS insee_code, count(*) AS lines
            #{kept} AND quantite_substance = '#{SECRET}'
            GROUP BY annee, code_insee
          ) TO '#{dir.join('masked.csv')}' (HEADER, DELIMITER ',');
        SQL
      end
  end
end
