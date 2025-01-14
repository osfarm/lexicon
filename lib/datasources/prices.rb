module Datasources
  class Prices < Base
    description 'Price catalog of variants'
    credits name: 'Prix de références des intrants, matériels et main d oeuvre', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2022-02-22"

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

        INSERT INTO master_phytosanitary_prices (id, reference_name, reference_article_name, unit_pretax_amount,
         currency, reference_packaging_name, started_on, usage)
          SELECT CONCAT('PH', n), name, article_id::INTEGER, price::NUMERIC,
          currency, packaging, TO_DATE(date, 'DD/MM/YYYY'), 'cost'
          FROM prices.phytosanitary_costs;

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
        VALUES ($1, $2, $3, $4, 'euro', $5, $6, 'cost', $7, $8, $9, $10, $11, $12, $13, $14)",
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
    end

  end
end
