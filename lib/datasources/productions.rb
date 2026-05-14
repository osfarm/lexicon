module Datasources
  class Productions < Base
    description 'Production database'
    credits name: 'Productions de références', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-09-10"

    YIELDS_DEPARTMENTS_CSV      = 'raw/productions/productions - yields - departments.csv'.freeze
    YIELDS_DEPARTMENTS_LONG_CSV = 'raw/productions/productions - yields - departments-long.csv'.freeze
    FAM_YIELDS_XLSX             = 'FAM/STA-GRC-surface_prod_rend_dep-A26.xlsx'.freeze
    FAM_YIELDS_HEADER           = %w[department production_label specie production 2021 2022 2023 2024 2025 2026 yield_unit].freeze
    FAM_YIELDS_LONG_HEADER      = %w[campaign zone production_label specie production yield_value yield_unit].freeze
    FAM_YIELDS_YEARS            = %w[2022 2023 2024 2025 2026].freeze
    FAM_YIELDS_LONG_YEARS       = %w[2021 2022 2023 2024 2025 2026].freeze

    # Rendement(qx/ha) values live in columns H..L of every per-crop sheet (2022..2026).
    FAM_RENDEMENT_COLS = { '2022' => 'H', '2023' => 'I', '2024' => 'J', '2025' => 'K', '2026' => 'L' }.freeze

    # The 'MAÏS GRAIN' sheet is an empty placeholder in this snapshot — real data lives in
    # 'MAÏS (GRAIN ET SEMENCE)'. Keep this mapping in sync with sheet renames upstream.
    FAM_SHEET_TO_PRODUCTION = {
      "AVOINE D-HIVER"          => { label: "Avoine d'hiver",     specie: "avena_sativa",         production: "winter_oat" },
      "BLÉ DUR D-HIVER"         => { label: "Blé dur d'hiver",    specie: "triticum_durum",       production: "winter_hard_wheat" },
      "BLÉ TENDRE D-HIVER"      => { label: "Blé tendre d'hiver", specie: "triticum_aestivum",    production: "winter_common_wheat" },
      "COLZA D-HIVER"           => { label: "Colza d'hiver",      specie: "brassica_napus_napus", production: "winter_rape" },
      "MAÏS (GRAIN ET SEMENCE)" => { label: "Maïs grain",         specie: "zea_mays",             production: "grain_corn" },
      "ORGE D-HIVER"            => { label: "Orge d'hiver",       specie: "hordeum_vulgare",      production: "winter_barley" },
      "POIS PROTÉAGINEUX"       => { label: "Pois protéagineux",  specie: "pisum_sativum",        production: "winter_proteaginous_pea" },
      "SOJA"                    => { label: "Soja",               specie: "glycine_max",          production: "soy" },
      "SORGHO"                  => { label: "Sorgho",             specie: "sorghum",              production: "sorghum" },
      "TOURNESOL"               => { label: "Tournesol",          specie: "helianthus_annuus",    production: "sunflower" },
      "TRITICALE"               => { label: "Triticale",          specie: "x_triticosecale",      production: "winter_triticale" },
    }.freeze

    def collect
      FileUtils.cp Dir.glob('data/productions/*.csv'), dir
      refresh_yields_from_fam
    end

    YEARS = %w[2017 2018 2019 2020 2021 2022 2023 2024 2025].freeze

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
      load_csv(dir.join('productions - yields - departments-long.csv'), 'crop_yields')
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
        SELECT pcy.zone, pcy.specie, pcy.production, ROUND(REPLACE(pcy.yield_value, ',', '.')::NUMERIC, 2), pcy.yield_unit, pcy.campaign::INTEGER
        FROM productions.crop_yields pcy"

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

    private

      # Refreshes data/productions/productions - yields - departments.csv from the FranceAgriMer
      # Agreste GRC xlsx (Surfaces / Productions / Rendements par département). Called from collect
      # so a fresh xlsx dropped under raw/productions/FAM/ is picked up automatically; if the xlsx is
      # missing the CSV is left untouched and the existing static data flows through unchanged.
      # 2021 values are preserved from the previous CSV since FAM only publishes 2022 onwards.
      def refresh_yields_from_fam
        xlsx_path = dir.join(FAM_YIELDS_XLSX)
        unless File.exist?(xlsx_path)
          logger.debug "FAM yields xlsx not found at #{xlsx_path}; keeping existing #{YIELDS_DEPARTMENTS_CSV}"
          return
        end

        logger.debug "Refreshing #{YIELDS_DEPARTMENTS_CSV} from #{xlsx_path}..."
        existing_2021 = read_existing_2021_yields(YIELDS_DEPARTMENTS_CSV)
        rows = extract_fam_yields(xlsx_path, existing_2021)

        require 'csv'
        CSV.open(YIELDS_DEPARTMENTS_CSV, 'w', write_headers: true, headers: FAM_YIELDS_HEADER) do |out|
          rows.each { |r| out << r }
        end
        logger.debug "Wrote #{rows.size} yield rows."

        write_long_yields_csv(rows)
      end

      # Pivots the wide per-department CSV (one row per dep × production, year columns) into a tall
      # CSV (one row per dep × production × campaign) matching the schema of `productions - yields.csv`.
      # Eases downstream loading: each yield observation is a single row, no per-year column gymnastics.
      def write_long_yields_csv(wide_rows)
        require 'csv'
        prod_order = FAM_SHEET_TO_PRODUCTION.values.each_with_index.to_h { |meta, i| [meta[:production], i] }
        long_rows = []

        wide_rows.each do |r|
          dep, label, specie, production = r[0], r[1], r[2], r[3]
          unit = r[-1]
          FAM_YIELDS_LONG_YEARS.each_with_index do |year, idx|
            value = r[4 + idx]
            next if value.nil? || value.to_s.strip.empty?

            long_rows << [year.to_i, dep, label, specie, production, value, unit]
          end
        end

        long_rows.sort_by! { |lr| [lr[0], prod_order.fetch(lr[4], prod_order.size), dep_sort_key(lr[1])] }

        CSV.open(YIELDS_DEPARTMENTS_LONG_CSV, 'w', write_headers: true, headers: FAM_YIELDS_LONG_HEADER) do |out|
          long_rows.each { |lr| out << lr }
        end
        logger.debug "Wrote #{long_rows.size} long-format yield rows to #{YIELDS_DEPARTMENTS_LONG_CSV}."
      end

      def read_existing_2021_yields(path)
        require 'csv'
        result = {}
        return result unless File.exist?(path)

        CSV.foreach(path, headers: true) do |row|
          value = row['2021']
          next if value.nil? || value.strip.empty?

          result[[row['department'], row['production']]] = value
        end
        result
      end

      def extract_fam_yields(xlsx_path, existing_2021)
        book = Roo::Excelx.new(xlsx_path.to_s)
        prod_order = FAM_SHEET_TO_PRODUCTION.values.each_with_index.to_h { |meta, i| [meta[:production], i] }
        rows = []

        FAM_SHEET_TO_PRODUCTION.each do |sheet_name, meta|
          sheet = book.sheet(sheet_name)
          (7..sheet.last_row).each do |r|
            code = sheet.cell('A', r).to_s.strip
            dep = normalize_department_code(code)
            next unless dep

            yields = FAM_YIELDS_YEARS.map { |y| sheet.cell(FAM_RENDEMENT_COLS[y], r) }
            next if yields.all? { |v| v.nil? || v.to_f.zero? }

            formatted = yields.map { |v| format_yield(v) }
            rows << [
              dep,
              meta[:label],
              meta[:specie],
              meta[:production],
              existing_2021[[dep, meta[:production]]],
              *formatted,
              'quintal_per_hectare',
            ]
          end
        end

        rows.sort_by! { |r| [prod_order.fetch(r[3], prod_order.size), dep_sort_key(r[0])] }
        rows
      end

      # Keeps mainland departments (01..95, with Corse as 2A/2B) and DOM (971..976);
      # filters out region codes (3-digit like 100) and Agreste subtotals (99 = DOM, 101 = France).
      def normalize_department_code(code)
        return nil if code.empty?
        return code if %w[2A 2B].include?(code)

        return nil unless code =~ /\A\d+\z/
        n = code.to_i
        return format('%02d', n) if (1..95).cover?(n)
        return n.to_s if (971..976).cover?(n)

        nil
      end

      def dep_sort_key(dep)
        case dep
        when '2A' then 20
        when '2B' then 21
        else dep.to_i
        end
      end

      def format_yield(value)
        return nil if value.nil?

        num = value.to_f
        return nil if num.zero?

        format('%.1f', num).tr('.', ',')
      end
  end
end
