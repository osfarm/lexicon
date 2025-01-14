module Datasources
  class Productions < Base
    description 'Production database'
    credits name: 'Productions de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-09-10"

    def collect
      FileUtils.cp Dir.glob('data/productions/*.csv'), dir
    end

    YEARS = %w[2017 2018 2019 2020 2021 2022 2023 2024].freeze

    def load
      load_csv(dir.join('productions - crop_productions.csv'), 'crop_productions')
      load_csv(dir.join('productions - animal_productions.csv'), 'animal_productions')
      load_csv(dir.join('productions - auxiliary_productions.csv'), 'auxiliary_productions')
      load_csv(dir.join('productions - processing_productions.csv'), 'processing_productions')
      load_csv(dir.join('productions - service_productions.csv'), 'service_productions')

      load_csv(dir.join('productions - sna_codes.csv'), 'sna_codes')
      load_csv(dir.join('productions - start_states.csv'), 'start_states')
      load_csv(dir.join('productions - tfi_2020.csv'), 'tfi_2020')
      YEARS.each do |year|
        load_csv(dir.join('productions - cap_'+year.to_s+'.csv'), 'cap_'+year.to_s)
      end
      load_csv(dir.join('departments_regions.csv'), 'departments_regions')
      load_csv(dir.join('productions - yields.csv'), 'crop_yields')
      # plant_farming_price FR grain
      load_csv(dir.join('productions - crop_price_2019.csv'), 'crop_price_2019')
      load_csv(dir.join('productions - crop_price_2020.csv'), 'crop_price_2020')
      load_csv(dir.join('productions - crop_price_2021.csv'), 'crop_price_2021')
      load_csv(dir.join('productions - crop_matif_price.csv'), 'crop_matif_price')
      load_csv(dir.join('productions - crop_shipping_price.csv'), 'crop_shipping_price')
      # animal_farming_price FR milk | milk_cow
      load_csv(dir.join('productions - milk_cow_prices.csv'), 'milk_cow_prices')
      # animal_farming_price FR meat
      load_csv(dir.join('productions - meat_cow_m_prices.csv'), 'meat_cow_m_prices') # milk_cow
      load_csv(dir.join('productions - meat_cow_l_prices.csv'), 'meat_cow_l_prices') # milk_cow
      load_csv(dir.join('productions - meat_heifer_vml_prices.csv'), 'meat_heifer_vml_prices') # heifer
      load_csv(dir.join('productions - meat_young_bull_l_prices.csv'), 'meat_young_bull_l_prices') # young_bull
    end

    def self.table_definitions(builder)
      builder.table(:master_productions, sql: <<-SQL)
        CREATE TABLE master_productions (
          reference_name character varying PRIMARY KEY NOT NULL,
          activity_family character varying NOT NULL,
          specie character varying,
          usage character varying,
          started_on DATE NOT NULL,
          stopped_on DATE NOT NULL,
          agroedi_crop_code character varying,
          season character varying,
          life_duration interval,
          idea_botanic_family character varying,
          idea_specie_family character varying,
          idea_output_family character varying,
          color character varying,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_productions_reference_name ON master_productions(reference_name);
        CREATE INDEX master_productions_specie ON master_productions(specie);
        CREATE INDEX master_productions_activity_family ON master_productions(activity_family);
        CREATE INDEX master_productions_agroedi_crop_code ON master_productions(agroedi_crop_code);
      SQL

      builder.table(:master_production_start_states, sql: <<-SQL).references(production: [:master_productions, :reference_name])
        CREATE TABLE master_production_start_states (
          production character varying NOT NULL,
          year integer NOT NULL,
          key character varying NOT NULL
        );
      SQL

      builder.table(:master_crop_production_cap_codes, sql: <<-SQL).references(production: [:master_productions, :reference_name])
        CREATE TABLE master_crop_production_cap_codes (
          cap_code character varying NOT NULL,
          cap_label character varying NOT NULL,
          production character varying NOT NULL,
          cap_precision character varying,
          cap_category character varying,
          is_seed boolean,
          year integer NOT NULL,
          PRIMARY KEY(cap_code, production, year)
        );
      SQL

      builder.table :master_crop_production_cap_sna_codes, sql: <<-SQL
        CREATE TABLE master_crop_production_cap_sna_codes (
          reference_name character varying PRIMARY KEY NOT NULL,
          nature character varying NOT NULL,
          parent character varying,
          translation_id character varying NOT NULL
        );
      SQL

      builder.table(:master_crop_production_tfi_codes, sql: <<-SQL).references(production: [:master_productions, :reference_name])
        CREATE TABLE master_crop_production_tfi_codes (
          tfi_code character varying NOT NULL,
          tfi_label character varying NOT NULL,
          production character varying,
          tfi_crop_group character varying,
          campaign integer NOT NULL
        );
      SQL

      builder.table(:master_production_yields, sql: <<-SQL).references(production: [:master_productions, :reference_name], specie: [:master_taxonomy, :reference_name])
        CREATE TABLE master_production_yields (
          department_zone character varying NOT NULL,
          specie character varying NOT NULL,
          production character varying NOT NULL,
          yield_value numeric(8,2) NOT NULL,
          yield_unit character varying NOT NULL,
          campaign integer NOT NULL
        );
        CREATE INDEX master_production_yields_specie ON master_production_yields(specie);
        CREATE INDEX master_production_yields_production ON master_production_yields(production);
        CREATE INDEX master_production_yields_campaign ON master_production_yields(campaign);
      SQL

      builder.table(:master_production_prices, sql: <<-SQL).references(specie: [:master_taxonomy, :reference_name])
        CREATE TABLE master_production_prices (
          department_zone character varying NOT NULL,
          started_on DATE NOT NULL,
          nature character varying,
          price_duration interval NOT NULL,
          specie character varying NOT NULL,
          waiting_price numeric(8,2) NOT NULL,
          final_price numeric(8,2) NOT NULL,
          currency character varying NOT NULL,
          price_unit character varying NOT NULL,
          product_output_specie character varying NOT NULL,
          production_reference_name character varying,
          campaign integer,
          organic boolean,
          label character varying
        );
        CREATE INDEX master_production_prices_specie ON master_production_prices(specie);
        CREATE INDEX master_production_prices_department_zone ON master_production_prices(department_zone);
        CREATE INDEX master_production_prices_started_on ON master_production_prices(started_on);
        CREATE INDEX master_production_prices_product_output_specie ON master_production_prices(product_output_specie);
      SQL
    end

    def normalize
      query "DELETE FROM master_translations WHERE id LIKE 'crop_productions%'"
      query "DELETE FROM master_translations WHERE id LIKE 'animal_productions%'"
      query "DELETE FROM master_translations WHERE id LIKE 'auxiliary_productions%'"
      query "DELETE FROM master_translations WHERE id LIKE 'processing_productions%'"
      query "DELETE FROM master_translations WHERE id LIKE 'service_productions%'"

      # crop_productions => plant_farming, vine_farming
      # animal_productions => animal_farming
      # auxiliary_productions => tool_maintaining, administering
      # processing_productions => processing, wine_making
      # service_productions => service_delivering

      query <<-SQL
        INSERT INTO master_productions (reference_name, activity_family, specie, usage, started_on, stopped_on, agroedi_crop_code, season, life_duration, idea_botanic_family, idea_specie_family, idea_output_family, color, translation_id)
          SELECT reference_name, activity_family, specie, usage, TO_DATE(started_on, 'DD/MM/YY'), TO_DATE(stopped_on, 'DD/MM/YY'), agroedi_crop_code, season,
          CASE WHEN life_duration IS NOT NULL THEN CONCAT(life_duration, ' years')::INTERVAL ELSE NULL END,
          idea_botanic_family, idea_specie_family, idea_output_family, color, CONCAT('crop_productions_', reference_name)
          FROM productions.crop_productions;

        INSERT INTO master_productions (reference_name, activity_family, specie, usage, started_on, stopped_on, life_duration, translation_id)
          SELECT reference_name, activity_family, specie, usage, TO_DATE(started_on, 'DD/MM/YY'), TO_DATE(stopped_on, 'DD/MM/YY'),
          CASE WHEN life_duration IS NOT NULL THEN CONCAT(life_duration, ' years')::INTERVAL ELSE NULL END,
          CONCAT('animal_productions_', reference_name)
          FROM productions.animal_productions;

        INSERT INTO master_productions (reference_name, activity_family, specie, usage, started_on, stopped_on, life_duration, translation_id)
          SELECT reference_name, activity_family, specie, usage, TO_DATE(started_on, 'DD/MM/YY'), TO_DATE(stopped_on, 'DD/MM/YY'),
          CASE WHEN life_duration IS NOT NULL THEN CONCAT(life_duration, ' years')::INTERVAL ELSE NULL END,
          CONCAT('auxiliary_productions_', reference_name)
          FROM productions.auxiliary_productions;

        INSERT INTO master_productions (reference_name, activity_family, specie, usage, started_on, stopped_on, life_duration, translation_id)
          SELECT reference_name, activity_family, specie, usage, TO_DATE(started_on, 'DD/MM/YY'), TO_DATE(stopped_on, 'DD/MM/YY'),
          CASE WHEN life_duration IS NOT NULL THEN CONCAT(life_duration, ' years')::INTERVAL ELSE NULL END,
          CONCAT('processing_productions_', reference_name)
          FROM productions.processing_productions;

        INSERT INTO master_productions (reference_name, activity_family, specie, usage, started_on, stopped_on, life_duration, translation_id)
          SELECT reference_name, activity_family, specie, usage, TO_DATE(started_on, 'DD/MM/YY'), TO_DATE(stopped_on, 'DD/MM/YY'),
          CASE WHEN life_duration IS NOT NULL THEN CONCAT(life_duration, ' years')::INTERVAL ELSE NULL END,
          CONCAT('service_productions_', reference_name)
          FROM productions.service_productions;

        INSERT INTO master_production_start_states (production, year, key)
          SELECT production, year::INTEGER, key
          FROM productions.start_states
      SQL

      insert_translations('productions', 'crop_productions', 'crop_productions')
      insert_translations('productions', 'animal_productions', 'animal_productions')
      insert_translations('productions', 'auxiliary_productions', 'auxiliary_productions')
      insert_translations('productions', 'processing_productions', 'processing_productions')
      insert_translations('productions', 'service_productions', 'service_productions')

      query "INSERT INTO master_crop_production_tfi_codes (tfi_code, tfi_label, production, tfi_crop_group, campaign)
        SELECT tfi_code, tfi_label, production, tfi_crop_group, 2020
        FROM productions.tfi_2020"

      YEARS.each do |year|
        query "INSERT INTO master_crop_production_cap_codes (cap_code, cap_label, production, year, cap_precision, is_seed)
        SELECT cap_code, cap_label, production, #{year}, cap_precision, (CASE is_seed WHEN '1' THEN true ELSE false END)
        FROM productions.cap_#{year}"
      end

      # SNA_CODES
      query "DELETE FROM master_translations WHERE id LIKE 'sna_codes%'"

      query "INSERT INTO master_crop_production_cap_sna_codes (reference_name, nature, parent, translation_id)
        SELECT reference_name, nature, parent, CONCAT('sna_codes_', reference_name)
        FROM productions.sna_codes"

      insert_translations('productions', 'sna_codes', 'sna_codes')

      query "INSERT INTO master_production_yields (department_zone, specie, production, yield_value, yield_unit, campaign)
        SELECT pdr.department, pcy.specie, pcy.production, ROUND(REPLACE(pcy.yield_value, ',', '.')::NUMERIC, 2), pcy.yield_unit, pcy.campaign::INTEGER
        FROM productions.crop_yields pcy JOIN productions.departments_regions pdr ON pcy.zone = pdr.region"

      # crop price
      [2019, 2020, 2021].each do |year|
        query "INSERT INTO master_production_prices (department_zone, nature, started_on, price_duration, specie,
          waiting_price, final_price, currency, price_unit, product_output_specie, campaign, label)
          SELECT pdr.department, 'farmer_price', TO_DATE(CONCAT(pcp.year, LPAD(pcp.month, 2, '0'), '01'), 'YYYYMMDD'), ('1 month')::INTERVAL,
          pcp.specie, ROUND(REPLACE(pcp.waiting_price, ',', '.')::NUMERIC, 2),
          ROUND(REPLACE(pcp.final_price, ',', '.')::NUMERIC, 2),
          'EUR', pcp.price_unit, pcp.product_output_specie, #{year}, pcp.production_label
          FROM productions.crop_price_#{year} pcp JOIN productions.departments_regions pdr ON UPPER(pcp.zone) = pdr.region"
      end

      # matif price
      query "INSERT INTO master_production_prices (department_zone, nature, started_on, price_duration, specie,
        waiting_price, final_price, currency, price_unit, product_output_specie, campaign, label)
        SELECT pdr.department, 'matif_price', TO_DATE(CONCAT(pcp.year, LPAD(pcp.month, 2, '0'), '01'), 'YYYYMMDD'), ('1 month')::INTERVAL,
        pcp.specie, ROUND(REPLACE(pcp.waiting_price, ',', '.')::NUMERIC, 2),
        ROUND(REPLACE(pcp.final_price, ',', '.')::NUMERIC, 2),
        'EUR', pcp.price_unit, pcp.product_output_specie, pcp.campaign::INTEGER, pcp.production_label
        FROM productions.crop_matif_price pcp JOIN productions.departments_regions pdr ON UPPER(pcp.zone) = pdr.region"

      # shipping price
      query "INSERT INTO master_production_prices (department_zone, nature, started_on, price_duration, specie,
        waiting_price, final_price, currency, price_unit, product_output_specie, campaign, label)
        SELECT pdr.department, 'shipping_price', TO_DATE(pcp.started_on, 'DD/MM/YYYY'), ('1 day')::INTERVAL,
        pcp.specie, ROUND(REPLACE(pcp.waiting_price, ',', '.')::NUMERIC, 2),
        ROUND(REPLACE(pcp.final_price, ',', '.')::NUMERIC, 2),
        'EUR', pcp.price_unit, pcp.product_output_specie, pcp.campaign::INTEGER, pcp.production_label
        FROM productions.crop_shipping_price pcp JOIN productions.departments_regions pdr ON UPPER(pcp.zone) = pdr.region"

      # milk price
      # clean blank price
      query "DELETE FROM productions.milk_cow_prices pcp
              WHERE pcp.waiting_price = 'S.'
                OR pcp.final_price = 'S.'
                OR pcp.waiting_price IS NULL
                OR pcp.final_price IS NULL"

      query "INSERT INTO master_production_prices (department_zone, started_on, price_duration, specie,
      waiting_price, final_price, currency, price_unit, product_output_specie, label, organic)
        SELECT pdr.department, TO_DATE(CONCAT(pcp.year, LPAD(pcp.month, 2, '0'), '01'), 'YYYYMMDD'), ('1 month')::INTERVAL,
        pcp.specie, ROUND(REPLACE(pcp.waiting_price, ',', '.')::NUMERIC, 2),
        ROUND(REPLACE(pcp.final_price, ',', '.')::NUMERIC, 2),
        'EUR', pcp.price_unit, pcp.product_output_specie, pcp.production_label, pcp.organic::BOOLEAN
        FROM productions.milk_cow_prices pcp JOIN productions.departments_regions pdr ON UPPER(pcp.zone) = pdr.region"

    end

  end
end
