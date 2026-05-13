module Datasources
  class Rica < Base
    LAST_UPDATED = "2025-04-07"
    description 'RICA (Réseau d Information Comptable Agricole) — microdonnées comptables agricoles annuelles'
    credits name: 'RICA — Microdonnées',
            url: "https://agreste.agriculture.gouv.fr/agreste-web/disaron/!searchurl/searchUiid/search/",
            provider: "SSP / Agreste",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: LAST_UPDATED

    SCHEMA = 'rica'.freeze
    YEARS = (2016..2024).to_a.freeze

    # Column-name mappings per dictionary/modalities format generation.
    DICT_COLS_LEGACY  = { code: 'variable',  label: 'libelle',                  type: '"type"', length: 'longueur' }.freeze
    DICT_COLS_NO_LEN  = { code: 'variable',  label: 'libelle',                  type: '"type"', length: nil }.freeze
    DICT_COLS_MODERN  = { code: 'variables', label: 'libelles_de_la_variable',  type: '"type"', length: nil }.freeze

    MOD_COLS_LEGACY = { variable: 'variable',  code: 'mod',        label: 'libmod' }.freeze
    MOD_COLS_MODERN = { variable: 'variables', code: 'modalites',  label: 'libelles_de_la_modalite' }.freeze

    SOURCES = {
      2016 => {
        data: 'RicaMicroDonnées2016/RICA2016.txt',
        dict_format: :txt,
        dict: 'RicaMicroDonnées2016/Rica_France_micro_donnees_dictionnaire_2016.txt',
        modalities: 'RicaMicroDonnées2016/Rica_France_micro_donnees_modalites_2016.txt',
        dict_table: 'dictionary_2016', mod_table: 'modalities_2016',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2017 => {
        data: 'RicaMicroDonnées2017/RICA2017.csv',
        dict_format: :txt,
        dict: 'RicaMicroDonnées2017/Rica_France_micro_donnees_dictionnaire_2017.txt',
        modalities: 'RicaMicroDonnées2017/Rica_France_micro_donnees_modalites_2017.txt',
        dict_table: 'dictionary_2017', mod_table: 'modalities_2017',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2018 => {
        data: 'RicaMicroDonnées2018/Rica2018MicroDonnées/RICA2018.csv',
        dict_format: :txt,
        dict: 'RicaMicroDonnées2018/Rica2018MicroDonnées/Rica_France_micro_donnees_dictionnaire_2018.txt',
        modalities: 'RicaMicroDonnées2018/Rica2018MicroDonnées/Rica_France_micro_donnees_modalites_2018.txt',
        dict_table: 'dictionary_2018', mod_table: 'modalities_2018',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2019 => {
        data: 'RicaMicrodonnées2019/Rica_France_micro_Donnees_ex2019.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2019/RICA2019_dictionnaire_modalite_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2019', mod_table: 'modalite_fmd_2019',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2020 => {
        data: 'RicaMicrodonnées2020/Rica_France_micro_Donnees_ex2020.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2020/RICA2020_dictionnaire_modalite_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2020', mod_table: 'modalite_fmd_2020',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2021 => {
        data: 'RicaMicrodonnées2021/RicaMicrodonnées2021/Rica_France_micro_Donnees_ex2021.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2021/RicaMicrodonnées2021/RICA2021_dictionnaire_modalite_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2021', mod_table: 'modalite_fmd_2021',
        dict_cols: DICT_COLS_LEGACY, mod_cols: MOD_COLS_LEGACY,
      },
      2022 => {
        data: 'RicaMicrodonnées2022/RicaMicrodonnées2022/Rica_France_micro_Donnees_ex2022_corrige.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2022/RicaMicrodonnées2022/RICA2022_dictionnaire_modalite_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2022', mod_table: 'modalite_fmd_2022',
        dict_cols: DICT_COLS_NO_LEN, mod_cols: MOD_COLS_LEGACY,
      },
      2023 => {
        data: 'RicaMicrodonnées2023/RicaMicrodonnées2023/Rica_France_micro_Donnees_ex2023.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2023/RicaMicrodonnées2023/RICA2023_dictionnaire_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2023', mod_table: 'modalites_fmd_2023',
        dict_cols: DICT_COLS_MODERN, mod_cols: MOD_COLS_MODERN,
      },
      2024 => {
        data: 'RicaMicrodonnées2024/RicaMicrodonnées 2024/Rica_France_micro_Donnees_ex2024.csv',
        dict_format: :xlsx,
        dict: 'RicaMicrodonnées2024/RicaMicrodonnées 2024/RICA2024_dictionnaire_FMD.xlsx',
        dict_table: 'dictionnaire_fmd_2024', mod_table: 'modalites_fmd_2024',
        dict_cols: DICT_COLS_MODERN, mod_cols: MOD_COLS_MODERN,
      },
    }.freeze

    # Variables extracted as typed native columns in registered_rica_holdings.
    # Everything else is preserved in the `data` JSONB payload.
    NATIVE_RAW_COLUMNS = %w(
      idnum milex regio nreg otexe ote64f cdexe fjuri zalti zdefa zenvi
      dclotc sauti sutot pbrto ebexp resex extr2
    ).freeze

    def collect
      missing = SOURCES.flat_map do |year, src|
        [src[:data], src[:dict], src[:modalities]].compact.reject { |p| File.exist?(dir.join(p)) }
      end
      unless missing.empty?
        raise "Missing RICA file(s) in #{dir}: #{missing.join(', ')}"
      end

      SOURCES.each do |year, src|
        next unless src[:dict_format] == :txt

        cleaned = dir.join("modalities_#{year}.csv")
        logger.debug "Cleaning #{src[:modalities]} → #{cleaned} (strip outer quotes)"
        strip_outer_quotes(dir.join(src[:modalities]), cleaned)
      end
    end

    def load
      database.ensure_schema(SCHEMA)

      SOURCES.each do |year, src|
        logger.debug "Loading RICA data #{year} into #{SCHEMA}.rica_#{year}..."
        load_csv(dir.join(src[:data]), "rica_#{year}", col_sep: ';')
        normalize_raw_column_names("rica_#{year}")

        if src[:dict_format] == :txt
          logger.debug "Loading dictionary #{year} into #{SCHEMA}.#{src[:dict_table]}..."
          load_csv(dir.join(src[:dict]), src[:dict_table], col_sep: ';')

          logger.debug "Loading modalities #{year} into #{SCHEMA}.#{src[:mod_table]}..."
          load_csv(dir.join("modalities_#{year}.csv"), src[:mod_table], col_sep: ';')
        else
          logger.debug "Loading dictionary/modalities xlsx #{year}..."
          load_xlsx(dir.join(src[:dict]))
        end
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_rica_holdings, sql: <<-SQL
        CREATE TABLE registered_rica_holdings (
          id SERIAL PRIMARY KEY NOT NULL,
          idnum integer NOT NULL,
          year integer NOT NULL,
          region_code character varying,
          new_region_code character varying,
          ote_17 character varying,
          ote_64 character varying,
          economic_dimension_class character varying,
          legal_form character varying,
          altitude_zone character varying,
          less_favoured_zone character varying,
          environmental_zone character varying,
          closing_date date,
          sau_ha numeric(14,2),
          total_area_ha numeric(14,2),
          gross_product numeric(14,2),
          gross_operating_surplus numeric(14,2),
          operating_result numeric(14,2),
          extrapolation_coefficient numeric(14,4),
          data jsonb,
          UNIQUE (idnum, year)
        );
        CREATE INDEX registered_rica_holdings_year ON registered_rica_holdings(year);
        CREATE INDEX registered_rica_holdings_ote_17 ON registered_rica_holdings(ote_17);
        CREATE INDEX registered_rica_holdings_ote_64 ON registered_rica_holdings(ote_64);
        CREATE INDEX registered_rica_holdings_region_code ON registered_rica_holdings(region_code);
        CREATE INDEX registered_rica_holdings_data ON registered_rica_holdings USING GIN (data);
      SQL

      builder.table :registered_rica_variables, sql: <<-SQL
        CREATE TABLE registered_rica_variables (
          year integer NOT NULL,
          code character varying NOT NULL,
          label character varying,
          data_type character varying,
          length integer,
          PRIMARY KEY (year, code)
        );
        CREATE INDEX registered_rica_variables_code ON registered_rica_variables(code);
      SQL

      builder.table :registered_rica_modalities, sql: <<-SQL
        CREATE TABLE registered_rica_modalities (
          year integer NOT NULL,
          variable_code character varying NOT NULL,
          modality_code character varying NOT NULL,
          label character varying,
          PRIMARY KEY (year, variable_code, modality_code)
        );
        CREATE INDEX registered_rica_modalities_variable_code ON registered_rica_modalities(variable_code);
      SQL
    end

    def normalize
      SOURCES.each do |year, src|
        logger.debug "Normalizing RICA holdings #{year}..."
        insert_holdings(year)

        logger.debug "Normalizing RICA variables #{year}..."
        insert_variables(year, src)

        logger.debug "Normalizing RICA modalities #{year}..."
        insert_modalities(year, src)
      end
    end

    private

      def insert_holdings(year)
        jsonb_payload = "to_jsonb(t.*)" + NATIVE_RAW_COLUMNS.map { |c| " - '#{c}'" }.join

        query <<~SQL
          INSERT INTO registered_rica_holdings (
            idnum, year, region_code, new_region_code,
            ote_17, ote_64, economic_dimension_class, legal_form,
            altitude_zone, less_favoured_zone, environmental_zone,
            closing_date, sau_ha, total_area_ha,
            gross_product, gross_operating_surplus, operating_result,
            extrapolation_coefficient, data
          )
          SELECT
            t.idnum::integer,
            t.milex::integer,
            NULLIF(t.regio, ''),
            NULLIF(t.nreg, ''),
            NULLIF(t.otexe, ''),
            NULLIF(t.ote64f, ''),
            NULLIF(t.cdexe, ''),
            NULLIF(t.fjuri, ''),
            NULLIF(t.zalti, ''),
            NULLIF(t.zdefa, ''),
            NULLIF(t.zenvi, ''),
            CASE WHEN NULLIF(t.dclotc, '') IS NOT NULL AND length(t.dclotc) = 8
                 THEN TO_DATE(t.dclotc, 'DDMMYYYY') END,
            NULLIF(t.sauti, '')::numeric(14,2),
            NULLIF(t.sutot, '')::numeric(14,2),
            NULLIF(t.pbrto, '')::numeric(14,2),
            NULLIF(t.ebexp, '')::numeric(14,2),
            NULLIF(t.resex, '')::numeric(14,2),
            NULLIF(t.extr2, '')::numeric(14,4),
            #{jsonb_payload}
          FROM #{SCHEMA}.rica_#{year} AS t
          ON CONFLICT (idnum, year) DO NOTHING
        SQL
      end

      def insert_variables(year, src)
        c = src[:dict_cols]
        length_expr = c[:length] ? "NULLIF(#{c[:length]}, '')::integer" : "NULL"

        query <<~SQL
          INSERT INTO registered_rica_variables (year, code, label, data_type, length)
          SELECT
            #{year},
            upper(trim(#{c[:code]})),
            NULLIF(#{c[:label]}, ''),
            NULLIF(#{c[:type]}, ''),
            #{length_expr}
          FROM #{SCHEMA}.#{src[:dict_table]}
          WHERE #{c[:code]} IS NOT NULL AND trim(#{c[:code]}) <> ''
          ON CONFLICT (year, code) DO NOTHING
        SQL
      end

      def insert_modalities(year, src)
        c = src[:mod_cols]

        query <<~SQL
          INSERT INTO registered_rica_modalities (year, variable_code, modality_code, label)
          SELECT
            #{year},
            upper(trim(#{c[:variable]})),
            trim(#{c[:code]}),
            NULLIF(#{c[:label]}, '')
          FROM #{SCHEMA}.#{src[:mod_table]}
          WHERE #{c[:variable]} IS NOT NULL AND trim(#{c[:variable]}) <> ''
            AND #{c[:code]} IS NOT NULL AND trim(#{c[:code]}) <> ''
          ON CONFLICT (year, variable_code, modality_code) DO NOTHING
        SQL
      end

      # Rails' `underscore` (used by csv_loader for header symbolization) inserts
      # an underscore between a digit and a following uppercase letter, so a 2019+
      # uppercase header like `OTE64F` becomes `ote64_f` while the 2016-2018
      # lowercase header `ote64f` stays `ote64f`. This renames the raw columns to
      # the no-underscore form so the schema is consistent across years.
      def normalize_raw_column_names(table_name)
        cols = query(<<~SQL)
          SELECT column_name FROM information_schema.columns
          WHERE table_schema = '#{SCHEMA}' AND table_name = '#{table_name}'
        SQL

        cols.each do |row|
          old_name = row['column_name']
          new_name = old_name.gsub(/(\d)_([a-z])/, '\1\2')
          next if new_name == old_name

          query(%(ALTER TABLE #{SCHEMA}.#{table_name} RENAME COLUMN "#{old_name}" TO "#{new_name}"))
        end
      end

      # Modalities .txt files (2016-2018) wrap each line in outer double quotes,
      # which breaks CSV parsing. This writes a cleaned copy with the wrapping
      # quotes stripped.
      def strip_outer_quotes(src, dst)
        File.open(dst, 'wb') do |out|
          File.foreach(src) do |line|
            line = line.chomp
            line = line[1..-2] if line.start_with?('"') && line.end_with?('"')
            out.puts line
          end
        end
      end
  end
end
