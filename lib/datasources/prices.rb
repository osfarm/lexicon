module Datasources
  class Prices < Base
    description 'Price catalog of variants'
    credits name: 'Prix de références des intrants, matériels et main d oeuvre', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2022-02-22"
    translations :worker_contracts

    # A table was added: where each price comes from
    schema_revision 2
    # Prices read every week in `fertilizers`, `seeds`, `phytosanitary_prices` and `fuel_prices` replace the ones of
    # the files of data/prices. Only the price of an article comes here, never who sells it.
    depends_on :fertilizers, :seeds, :phytosanitary_prices, :fuel_prices

    MASS_PACKAGINGS = "CASE reference_packaging_name WHEN 'ton_bulk' THEN 1.0 WHEN 'kilo_bulk' THEN 0.001 END"
    GNR_ARTICLE = 'non_road_diesel'
    # Percent of N, P2O5 and K2O below which a formula is not priced from its nutrients
    MINIMUM_NPK = 20

    def collect
      #Collect each csv file in prices directory
      FileUtils.cp Dir.glob('data/prices/*.csv'), dir
    end

    def load
      load_csv(dir.join('prices - other_input_costs.csv'), 'other_input_costs')
      load_csv(dir.join('prices - seed_costs.csv'), 'seed_costs')
      load_csv(dir.join('prices - farm_product_costs.csv'), 'farm_product_costs')
      load_csv(dir.join('prices - fertilizer_costs.csv'), 'fertilizer_costs')
      load_csv(dir.join('prices - phytosanitary_costs.csv'), 'phytosanitary_costs')
      load_csv(dir.join('prices - phytosanitary_amm_costs.csv'), 'phytosanitary_amm_costs')
      load_csv(dir.join('prices - equipment_costs.csv'), 'equipment_costs')
      load_csv(dir.join('prices - worker_contracts.csv'), 'worker_contracts')
    end

    def self.table_definitions(builder)
      builder.table(:master_prices, sql: <<-SQL).references(reference_article_name: [:master_variants, :reference_name], reference_packaging_name: [:master_packagings, :reference_name])
        CREATE TABLE master_prices (
          id character varying PRIMARY KEY NOT NULL,
          reference_name character varying NOT NULL,
          reference_article_name character varying NOT NULL,
          unit_pretax_amount numeric(19,4) NOT NULL,
          currency character varying NOT NULL,
          reference_packaging_name character varying NOT NULL,
          started_on date NOT NULL,
          variant_id character varying,
          packaging_id character varying,
          usage character varying NOT NULL,
          main_indicator character varying,
          main_indicator_unit character varying,
          main_indicator_minimal_value numeric(19,4),
          main_indicator_maximal_value numeric(19,4),
          working_flow_value numeric(19,4),
          working_flow_unit character varying,
          threshold_min_value numeric(19,4),
          threshold_max_value numeric(19,4)
        );

        CREATE INDEX master_prices_reference_name ON master_prices(reference_name);
        CREATE INDEX master_prices_reference_article_name ON master_prices(reference_article_name);
        CREATE INDEX master_prices_reference_packaging_name ON master_prices(reference_packaging_name);
      SQL

      builder.table :master_doer_contracts, sql: <<-SQL
        CREATE TABLE master_doer_contracts (
          reference_name character varying PRIMARY KEY NOT NULL,
          worker_variant character varying NOT NULL,
          salaried boolean,
          contract_end character varying,
          legal_monthly_working_time numeric(8,2) NOT NULL,
          legal_monthly_offline_time numeric(8,2) NOT NULL,
          min_raw_wage_per_hour numeric(8,2) NOT NULL,
          salary_charges_ratio numeric(8,2) NOT NULL,
          farm_charges_ratio numeric(8,2) NOT NULL,
          translation_id character varying NOT NULL
        );
      SQL

      builder.table(:master_phytosanitary_prices, sql: <<-SQL).references(reference_article_name: [:registered_phytosanitary_products, :id], reference_packaging_name: [:master_packagings, :reference_name])
        CREATE TABLE master_phytosanitary_prices (
          id character varying PRIMARY KEY NOT NULL,
          reference_name character varying NOT NULL,
          reference_article_name integer NOT NULL,
          unit_pretax_amount numeric(19,4) NOT NULL,
          currency character varying NOT NULL,
          reference_packaging_name character varying NOT NULL,
          started_on date NOT NULL,
          usage character varying NOT NULL
        );
      SQL

      builder.table :master_price_sources, sql: <<-SQL
        CREATE TABLE master_price_sources (
          id character varying PRIMARY KEY NOT NULL,
          price_table character varying NOT NULL,
          method character varying NOT NULL,
          source character varying NOT NULL,
          negotiated boolean,
          previous_amount numeric(19,4),
          previous_started_on date,
          detail character varying
        );

        CREATE INDEX master_price_sources_method ON master_price_sources(method);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
        currency, reference_packaging_name, started_on, usage)
         SELECT CONCAT('FE', n), name, article, price::NUMERIC,
         currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
         FROM prices.fertilizer_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
        currency, reference_packaging_name, started_on, usage)
         SELECT CONCAT('SE', n), name, article, price::NUMERIC,
         currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
         FROM prices.seed_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
        currency, reference_packaging_name, started_on, usage)
         SELECT CONCAT('PE', n), name, article, price::NUMERIC,
         currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
         FROM prices.phytosanitary_costs;

        INSERT INTO master_phytosanitary_prices (id, reference_name, reference_article_name, unit_pretax_amount,
         currency, reference_packaging_name, started_on, usage)
          SELECT CONCAT('PH', n), name, article_id::INTEGER, price::NUMERIC,
          currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
          FROM prices.phytosanitary_amm_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
          currency, reference_packaging_name, started_on, usage)
          SELECT CONCAT('F_P', n), name, article, price::NUMERIC,
          currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
          FROM prices.farm_product_costs;

       INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
          currency, reference_packaging_name, started_on, usage)
          SELECT CONCAT('OI', n), name, article, price::NUMERIC,
          currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
          FROM prices.other_input_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount, -- Equipment costs (1st segment)
        currency, reference_packaging_name, started_on, usage, main_indicator,
        main_indicator_unit, main_indicator_minimal_value, main_indicator_maximal_value,
        working_flow_value, working_flow_unit, threshold_min_value, threshold_max_value)
          SELECT CONCAT('E', n, '_a'), CONCAT(equipment, '_a'), equipment, segment_1_cost::NUMERIC,
          'euro', unit, TO_DATE(date, 'DD/MM/YYYY'), 'cost', main_indicator,
          indicator_unit, minimal_value::NUMERIC, maximal_value::NUMERIC,
          working_flow_value::NUMERIC, working_flow_unit, 0, segment_1_threshold::NUMERIC
          FROM prices.equipment_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount, -- Equipment costs (2nd segment)
        currency, reference_packaging_name, started_on, usage, main_indicator,
        main_indicator_unit, main_indicator_minimal_value, main_indicator_maximal_value,
        working_flow_value, working_flow_unit, threshold_min_value, threshold_max_value)
          SELECT CONCAT('E', n, '_b'), CONCAT(equipment, '_b'), equipment, segment_2_cost::NUMERIC,
          'euro', unit, TO_DATE(date, 'DD/MM/YYYY'), 'cost', main_indicator,
          indicator_unit, minimal_value::NUMERIC, maximal_value::NUMERIC,
          working_flow_value::NUMERIC, working_flow_unit, segment_1_threshold::NUMERIC, segment_2_threshold::NUMERIC
          FROM prices.equipment_costs;

        INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount, -- Equipment costs (3rd segment)
        currency, reference_packaging_name, started_on, usage, main_indicator,
        main_indicator_unit, main_indicator_minimal_value, main_indicator_maximal_value,
        working_flow_value, working_flow_unit, threshold_min_value, threshold_max_value)
          SELECT CONCAT('E', n, '_c'), CONCAT(equipment, '_c'), equipment, segment_3_cost::NUMERIC,
          'euro', unit, TO_DATE(date, 'DD/MM/YYYY'), 'cost', main_indicator,
          indicator_unit, minimal_value::NUMERIC, maximal_value::NUMERIC,
          working_flow_value::NUMERIC, working_flow_unit, segment_2_threshold::NUMERIC, segment_3_threshold::NUMERIC
          FROM prices.equipment_costs
      SQL

      #Calculation of last segment

      def mean(*values)
        values.reduce(&:+) / values.length.to_f
      end

      def covariance(values_x, values_y)
        mean_x = mean(*values_x)
        mean_y = mean(*values_y)
        values = values_x.zip(values_y)
        sum = values.map { |(x, y)| (x - mean_x) * (y - mean_y) }.reduce(&:+)
        sum / values.length
      end

      def variance(*values)
        covariance(values, values)
      end

      def compute_last_segment_cost(x1, y1, x2, y2, x3, y3, x4)
        xs = [x1, x2, x3]
        ys = [y1, y2, y3]
        logx = xs.map { |x| Math.log(x) }
        logy = ys.map { |y| Math.log(y) }
        mean_x = mean(*logx)
        mean_y = mean(*logy)
        var = variance(*logx)
        cov = covariance(logx, logy)
        a = cov / var
        b = mean_y - a * mean_x
        (Math.exp(b) * (x4 ** a)).round(4)
      end

      equipment_costs = query "SELECT * FROM prices.equipment_costs"

      equipment_costs.each do |row|
        segment_4_threshold = (row['segment_3_threshold'].to_f*1.4).round
        segment_4_cost = compute_last_segment_cost(
          row['segment_1_threshold'].to_f, row['segment_1_cost'].to_f,
          row['segment_2_threshold'].to_f, row['segment_2_cost'].to_f,
          row['segment_3_threshold'].to_f, row['segment_3_cost'].to_f, segment_4_threshold).round(2)
        query "INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount,
        currency, reference_packaging_name, started_on, usage, main_indicator,
        main_indicator_unit, main_indicator_minimal_value, main_indicator_maximal_value,
        working_flow_value, working_flow_unit, threshold_min_value, threshold_max_value)
        VALUES ($1, $2, $3, $4, 'euro', $5, TO_DATE($6, 'DD/MM/YYYY'), 'cost', $7, $8, $9, $10, $11, $12, $13, $14)",
        'E'+row['n']+'_d', row['equipment']+'_d', row['equipment'], segment_4_cost, row['unit'], row['date'], row['main_indicator'], row['indicator_unit'],
        row['minimal_value'], row['maximal_value'], row['working_flow_value'], row['working_flow_unit'], row['segment_3_threshold'], segment_4_threshold
      end

      query "DELETE FROM master_translations WHERE id LIKE 'worker_contracts%'"

      query <<-SQL
        INSERT INTO master_doer_contracts (reference_name, worker_variant, salaried, contract_end, -- Worker contracts
        legal_monthly_working_time, legal_monthly_offline_time, min_raw_wage_per_hour, salary_charges_ratio, farm_charges_ratio, translation_id)
          SELECT reference_name, worker_variant, salaried::BOOLEAN, contract_end,
          legal_monthly_working_time::NUMERIC, legal_monthly_offline_time::NUMERIC, min_raw_wage_per_hour::NUMERIC,
          salary_charges_ratio::NUMERIC, farm_charges_ratio::NUMERIC, CONCAT('worker_contracts_', reference_name)
          FROM prices.worker_contracts;
      SQL
      insert_translations('prices', 'worker_contracts', 'worker_contracts')

      record_reference_prices
      refresh_fertilizers if built?('registered_fertilizer_monthly_prices')
      refresh_seeds if built?('registered_seed_monthly_prices')
      refresh_phytosanitary_products if built?('registered_phytosanitary_monthly_prices')
      refresh_non_road_diesel if built?('registered_fuel_monthly_prices')
      report_unpriced_workflow_articles
    end

    private

      # The datasources that read prices may not be built on this machine: their prices are then left as the files give them
      def built?(table)
        found = !query("SELECT to_regclass('lexicon.#{table}') AS found").first['found'].nil?
        logger.warn("#{table} is not built: the prices it would refresh keep the ones of data/prices") unless found

        found
      end

      # A technical workflow is costed with these prices: an article it names and that has none is said, when the
      # workflows are built on this machine
      def report_unpriced_workflow_articles
        return if query("SELECT to_regclass('lexicon.technical_workflow_procedure_items') AS found").first['found'].nil?

        unpriced = query(<<-SQL).map { |row| row['article_reference'] }
          SELECT DISTINCT article_reference
            FROM technical_workflow_procedure_items AS item
           WHERE COALESCE(article_reference, '') <> ''
             AND NOT EXISTS (SELECT 1 FROM master_prices WHERE reference_article_name = item.article_reference)
             AND NOT EXISTS (SELECT 1 FROM master_phytosanitary_prices WHERE reference_article_name::text = item.article_reference)
           ORDER BY 1
        SQL
        logger.warn("#{unpriced.size} articles of the technical workflows have no price: #{unpriced.join(', ')}") if unpriced.any?
      end

      # Every price starts as the one of the files of data/prices
      def record_reference_prices
        query <<-SQL
          INSERT INTO master_price_sources (id, price_table, method, source)
            SELECT id, 'master_prices', 'reference', 'prices' FROM master_prices
            UNION ALL
            SELECT id, 'master_phytosanitary_prices', 'reference', 'prices' FROM master_phytosanitary_prices
        SQL
      end

      # Replaces prices and says where the new ones come from. `refreshed` gives id, amount, started_on, method,
      # source, negotiated and detail for the prices to replace. An article may carry several prices, one per date:
      # only its latest is replaced, the older ones stay as its history.
      def replace_prices(table, refreshed)
        query <<-SQL
          WITH refreshed AS (#{refreshed}),
               replaced AS (
                 UPDATE #{table} AS price
                    SET unit_pretax_amount = refreshed.amount, started_on = refreshed.started_on
                   FROM refreshed, (SELECT id, unit_pretax_amount, started_on FROM #{table}) AS previous
                  WHERE price.id = refreshed.id AND previous.id = price.id AND refreshed.amount > 0
                    AND price.started_on = (SELECT max(started_on) FROM #{table} AS other
                                             WHERE other.reference_article_name = price.reference_article_name
                                               AND other.reference_packaging_name = price.reference_packaging_name)
              RETURNING price.id, previous.unit_pretax_amount AS previous_amount, previous.started_on AS previous_started_on
               )
          UPDATE master_price_sources AS origin
             SET method = refreshed.method, source = refreshed.source, negotiated = refreshed.negotiated,
                 previous_amount = replaced.previous_amount, previous_started_on = replaced.previous_started_on, detail = refreshed.detail
            FROM replaced JOIN refreshed ON refreshed.id = replaced.id
           WHERE origin.id = replaced.id
        SQL
      end

      # An article sold by a merchant takes its latest monthly price, in bulk when there is one. Any other mineral
      # fertiliser sold by the tonne is priced from its formula and the value of a kilogram of N, P2O5, K2O and SO3
      # that month, as long as the formula is mostly those: magnesium and calcium have no known value, and a
      # speciality sold by the kilogram is not worth its nutrients only.
      def refresh_fertilizers
        replace_prices('master_prices', <<-SQL)
          SELECT price.id, round(observed.price * #{MASS_PACKAGINGS}, 4) AS amount, observed.month AS started_on, 'observed' AS method,
                 'fertilizers' AS source, observed.negotiated, 'monthly price, ' || observed.packaging AS detail
            FROM master_prices AS price
            JOIN (SELECT DISTINCT ON (fertilizer.variant_reference_name)
                         fertilizer.variant_reference_name AS article, monthly.price, monthly.month, monthly.packaging, monthly.negotiated
                    FROM registered_fertilizer_monthly_prices AS monthly
                    JOIN registered_fertilizers AS fertilizer ON fertilizer.id = monthly.fertilizer_id
                   WHERE fertilizer.variant_reference_name IS NOT NULL AND monthly.unit = 'ton'
                   ORDER BY fertilizer.variant_reference_name, monthly.month DESC, (monthly.packaging = 'bulk') DESC, monthly.price
                 ) AS observed ON observed.article = price.reference_article_name
           WHERE price.id LIKE 'FE%' AND #{MASS_PACKAGINGS} IS NOT NULL
        SQL

        content = ->(nutrient) { "COALESCE(substring(variant.indicators->>'#{nutrient}_concentration' from '^[0-9.]+')::numeric, 0)" }
        value = ->(nutrient) { "(SELECT value FROM registered_fertilizer_unit_values WHERE nutrient = '#{nutrient}' ORDER BY month DESC LIMIT 1)" }
        replace_prices('master_prices', <<-SQL)
          SELECT price.id,
                 round(10 * (#{content.call('nitrogen')} * #{value.call('N')} + #{content.call('phosphorus')} * #{value.call('P2O5')}
                             + #{content.call('potassium')} * #{value.call('K2O')} + #{content.call('sulfur_dioxide')} * #{value.call('SO3')})
                       * #{MASS_PACKAGINGS}, 4) AS amount,
                 (SELECT max(month) FROM registered_fertilizer_unit_values) AS started_on, 'estimated' AS method, 'fertilizers' AS source,
                 NULL::boolean AS negotiated, 'formula priced with the value of N, P2O5, K2O and SO3' AS detail
            FROM master_prices AS price
            JOIN master_variants AS variant ON variant.reference_name = price.reference_article_name
            JOIN master_price_sources AS origin ON origin.id = price.id AND origin.method = 'reference'
           WHERE price.id LIKE 'FE%' AND price.reference_packaging_name = 'ton_bulk' AND variant.nature = 'mineral_fertilizer'
             AND #{content.call('nitrogen')} + #{content.call('phosphorus')} + #{content.call('potassium')} >= #{MINIMUM_NPK}
             AND #{content.call('magnesium')} + #{content.call('calcium')} = 0
             AND (SELECT count(DISTINCT nutrient) FROM registered_fertilizer_unit_values
                   WHERE month = (SELECT max(month) FROM registered_fertilizer_unit_values)) = 4
        SQL
      end

      # A seed takes the latest median price per kilogram of its species; of its genus when the article names a genus
      def refresh_seeds
        replace_prices('master_prices', <<-SQL)
          SELECT price.id, round(avg(monthly.price_per_kilogram) * #{MASS_PACKAGINGS} * 1000, 4) AS amount, max(monthly.month) AS started_on,
                 'observed' AS method, 'seeds' AS source, NULL::boolean AS negotiated,
                 'median price of ' || string_agg(species.id, ', ' ORDER BY species.id) AS detail
            FROM master_prices AS price
            JOIN master_variants AS variant ON variant.reference_name = price.reference_article_name
            JOIN registered_seed_species AS species
              ON species.taxon_reference_name = variant.target_specie
              OR species.taxon_reference_name LIKE replace(variant.target_specie, '_', '\_') || '\_%'
            JOIN registered_seed_monthly_prices AS monthly
              ON monthly.species_id = species.id AND monthly.organic = (price.reference_article_name LIKE '%organic%')
             AND monthly.month = (SELECT max(month) FROM registered_seed_monthly_prices WHERE species_id = species.id)
           WHERE price.id LIKE 'SE%' AND #{MASS_PACKAGINGS} IS NOT NULL
           GROUP BY price.id, price.reference_packaging_name
        SQL
      end

      # A product takes the latest monthly price read for its authorisation number; one never priced before is added
      def refresh_phytosanitary_products
        latest = <<-SQL
          SELECT DISTINCT ON (product_id, unit) product_id, price, month, negotiated,
                 CASE unit WHEN 'liter' THEN 'liter_bulk' WHEN 'kilogram' THEN 'kilo_bulk' END AS packaging
            FROM registered_phytosanitary_monthly_prices
           ORDER BY product_id, unit, month DESC
        SQL
        query <<-SQL
          WITH added AS (
            INSERT INTO master_phytosanitary_prices (id, reference_name, reference_article_name, unit_pretax_amount, currency,
                                                     reference_packaging_name, started_on, usage)
              SELECT 'PHM' || latest.product_id, latest.product_id || '_bulk', latest.product_id, latest.price, 'euro', latest.packaging,
                     latest.month, 'cost'
                FROM (#{latest}) AS latest
               WHERE latest.packaging IS NOT NULL
                 AND EXISTS (SELECT 1 FROM registered_phytosanitary_products WHERE id = latest.product_id)
                 AND NOT EXISTS (SELECT 1 FROM master_phytosanitary_prices WHERE reference_article_name = latest.product_id)
            RETURNING id, reference_article_name
          )
          INSERT INTO master_price_sources (id, price_table, method, source, negotiated, detail)
            SELECT added.id, 'master_phytosanitary_prices', 'observed', 'phytosanitary_prices', latest.negotiated, 'monthly price'
              FROM added JOIN (#{latest}) AS latest ON latest.product_id = added.reference_article_name
        SQL
        replace_prices('master_phytosanitary_prices', <<-SQL)
          SELECT price.id, latest.price AS amount, latest.month AS started_on, 'observed' AS method, 'phytosanitary_prices' AS source,
                 latest.negotiated, 'monthly price' AS detail
            FROM master_phytosanitary_prices AS price
            JOIN (#{latest}) AS latest ON latest.product_id = price.reference_article_name AND latest.packaging = price.reference_packaging_name
            JOIN master_price_sources AS origin ON origin.id = price.id AND origin.method = 'reference'
        SQL
      end

      # Non-road diesel: the average of the month, before VAT, the price a farm pays
      def refresh_non_road_diesel
        query <<-SQL
          WITH added AS (
            INSERT INTO master_prices (id, reference_name, reference_article_name, unit_pretax_amount, currency, reference_packaging_name,
                                       started_on, usage)
              SELECT 'OI_#{GNR_ARTICLE}', '#{GNR_ARTICLE}_bulk', '#{GNR_ARTICLE}', price_excluding_vat, 'euro', 'liter_bulk', month, 'cost'
                FROM registered_fuel_monthly_prices
               WHERE product = '#{GNR_ARTICLE}' AND EXISTS (SELECT 1 FROM master_variants WHERE reference_name = '#{GNR_ARTICLE}')
               ORDER BY month DESC LIMIT 1
            RETURNING id
          )
          INSERT INTO master_price_sources (id, price_table, method, source, negotiated, detail)
            SELECT id, 'master_prices', 'observed', 'fuel_prices', false, 'monthly average before VAT' FROM added
        SQL
      end

  end
end
