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

    # Micro-data variable => typed native column of registered_rica_holdings.
    # Everything else is preserved in the `data` JSONB payload.
    #
    # The FMD is an anonymised publication: many of its variables are ordinal
    # band codes, not measurements, and the dictionary says so through its
    # `data_type`. Promoting one of those to a numeric column named after a
    # unit is how `sauti` once ended up in a `sau_ha numeric` column holding
    # codes 0..30. `check_promotions!` audits this table against the yearly
    # dictionary on every normalize; see doc/datasources/rica.md.
    PROMOTED_COLUMNS = {
      'idnum'  => :idnum,
      'milex'  => :year,
      'regio'  => :region_code,
      'nreg'   => :new_region_code,
      'otexe'  => :ote_17,
      'ote64f' => :ote_64,
      'cdexe'  => :economic_dimension_class,
      'fjuri'  => :legal_form,
      'zalti'  => :altitude_zone,
      'zdefa'  => :less_favoured_zone,
      'zenvi'  => :environmental_zone,
      'dclotc' => :closing_date,
      'sauti'  => :sau_band,
      'sutot'  => :total_area_band,
      'pbrto'  => :gross_product,
      'ebexp'  => :gross_operating_surplus,
      'resex'  => :operating_result,
      'extr2'  => :extrapolation_coefficient,
    }.freeze

    # Raw variables stripped from the `data` JSONB payload because they already
    # have a native column.
    NATIVE_RAW_COLUMNS = PROMOTED_COLUMNS.keys.freeze

    # A band code may only be promoted to a numeric column whose name carries
    # the `_band` suffix, so that no consumer can mistake it for a measurement.
    BAND_COLUMN_SUFFIX = '_band'.freeze

    def collect
      missing = SOURCES.flat_map do |year, src|
        [src[:data], src[:dict], src[:modalities]].compact.reject { |p| File.exist?(dir.join(p)) }
      end
      unless missing.empty?
        raise "Missing RICA file(s) in #{dir}: #{missing.join(', ')}"
      end

      SOURCES.each do |year, src|
        next unless src[:dict_format] == :txt

        logger.debug "Cleaning dictionary/modalities #{year} (outer quotes, trailing separators)"
        clean_legacy_file(dir.join(src[:dict]), dir.join("dictionary_#{year}.csv"))
        clean_legacy_file(dir.join(src[:modalities]), dir.join("modalities_#{year}.csv"))
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
          load_csv(dir.join("dictionary_#{year}.csv"), src[:dict_table], col_sep: ';')

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
          sau_band integer,
          total_area_band integer,
          gross_product numeric(14,2),
          gross_operating_surplus numeric(14,2),
          operating_result numeric(14,2),
          extrapolation_coefficient numeric(14,4),
          data jsonb,
          UNIQUE (idnum, year)
        );
        COMMENT ON COLUMN registered_rica_holdings.sau_band IS
          'SAUTI: ordinal band code, NOT hectares. Join registered_rica_modalities on (year, ''SAUTI'', sau_band) for bounds.';
        COMMENT ON COLUMN registered_rica_holdings.total_area_band IS
          'SUTOT: ordinal band code, NOT hectares. Join registered_rica_modalities on (year, ''SUTOT'', total_area_band) for bounds.';
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
          lower_bound numeric,
          upper_bound numeric,
          bound_unit character varying,
          PRIMARY KEY (year, variable_code, modality_code)
        );
        COMMENT ON COLUMN registered_rica_modalities.lower_bound IS
          'Inclusive lower bound of the band, NULL when the modality is not quantitative.';
        COMMENT ON COLUMN registered_rica_modalities.upper_bound IS
          'Exclusive upper bound of the band, NULL when the band is open-ended or the modality is not quantitative.';
        CREATE INDEX registered_rica_modalities_variable_code ON registered_rica_modalities(variable_code);
      SQL
    end

    def normalize
      # The dictionary is what tells a band code apart from a measurement, so it
      # is loaded before anything is promoted to a native column.
      SOURCES.each do |year, src|
        logger.debug "Normalizing RICA variables #{year}..."
        insert_variables(year, src)

        logger.debug "Normalizing RICA modalities #{year}..."
        insert_modalities(year, src)
      end

      logger.debug "Deriving RICA modality bounds..."
      fill_modality_bounds

      SOURCES.each_key do |year|
        check_promotions!(year)

        logger.debug "Normalizing RICA holdings #{year}..."
        insert_holdings(year)
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
            closing_date, sau_band, total_area_band,
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
            NULLIF(t.sauti, '')::integer,
            NULLIF(t.sutot, '')::integer,
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
        # Some legacy dictionary rows carry a comment in the length column
        # ("2- supprimée à compter de 2015"), so only the leading digits are cast.
        length_expr = c[:length] ? "NULLIF(substring(#{c[:length]} from '^[0-9]+'), '')::integer" : "NULL"

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

      # Refuses to promote a variable the dictionary declares as characters into
      # a numeric column, unless that column is explicitly named as a band.
      # This is the check that would have rejected `sauti` => `sau_ha numeric`.
      def check_promotions!(year)
        types = dictionary_types
        columns = holdings_column_types
        offences = []

        PROMOTED_COLUMNS.each do |variable, column|
          declared = types.dig(year, variable.upcase) || nearest_declared_type(types, year, variable.upcase)
          if declared.nil?
            logger.warn "RICA #{year}: #{variable.upcase} is absent from every dictionary, promotion to #{column} unchecked"
            next
          end
          next if declared == :num

          column_type = columns.fetch(column.to_s)
          next unless numeric_column?(column_type)

          if !column.to_s.end_with?(BAND_COLUMN_SUFFIX)
            offences << "#{variable.upcase} is declared '#{declared}' by the #{year} dictionary but is promoted to " \
                        "the numeric column #{column} (#{column_type}); an ordinal band code must land in a " \
                        "'*#{BAND_COLUMN_SUFFIX}' column, never in one named after a unit"
          elsif column_type != 'integer'
            offences << "#{variable.upcase} is promoted to the band column #{column} typed #{column_type}; " \
                        "band codes are ordinals and must be integer"
          end
        end

        return if offences.empty?

        raise "RICA #{year}: refusing to load holdings.\n  - #{offences.join("\n  - ")}"
      end

      # @return [Hash{Integer => Hash{String => Symbol}}] year => variable code =>
      #   :num or :char. The SSP renamed the two data types in 2023
      #   (num/char became numérique/caractères), so both spellings are accepted.
      def dictionary_types
        @dictionary_types ||= begin
          rows = query(<<~SQL).to_a
            SELECT year, code, data_type FROM registered_rica_variables WHERE data_type IS NOT NULL
          SQL

          rows.each_with_object({}) do |row, acc|
            kind = case row['data_type'].to_s.strip.downcase
                   when /\Anum/ then :num
                   when /\A(?:car|char)/ then :char
                   end
            next if kind.nil?

            (acc[row['year'].to_i] ||= {})[row['code']] = kind
          end
        end
      end

      # A vintage may ship without a dictionary; fall back on the closest year
      # that declares the variable rather than silently dropping the check.
      def nearest_declared_type(types, year, code)
        candidate = types.keys.select { |y| types[y].key?(code) }.min_by { |y| [(y - year).abs, y] }
        return nil if candidate.nil?

        logger.warn "RICA #{year}: no dictionary entry for #{code}, falling back on #{candidate}"
        types[candidate][code]
      end

      def holdings_column_types
        @holdings_column_types ||= begin
          rows = query(<<~SQL).to_a
            SELECT column_name, data_type FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = 'registered_rica_holdings'
          SQL

          rows.each_with_object({}) { |row, acc| acc[row['column_name']] = row['data_type'] }
        end
      end

      def numeric_column?(data_type)
        %w(smallint integer bigint numeric real).include?(data_type) ||
          data_type.to_s.start_with?('double')
      end

      # Turns the French band labels of registered_rica_modalities into machine
      # readable bounds. Parsing belongs here rather than in every consumer: a
      # regex over "Surface égale ou supérieure à 15 ha et inférieure à 20 ha"
      # duplicated downstream is the next bug waiting to happen.
      def fill_modality_bounds
        rows = query(<<~SQL).to_a
          SELECT m.year, m.variable_code, m.modality_code, m.label, v.label AS variable_label
          FROM registered_rica_modalities m
          LEFT JOIN registered_rica_variables v
            ON v.year = m.year AND v.code = m.variable_code
          WHERE m.label IS NOT NULL
        SQL

        updates = []
        rows.group_by { |row| [row['year'].to_i, row['variable_code']] }.each do |(year, variable), group|
          labels = group.each_with_object({}) { |row, acc| acc[row['modality_code']] = row['label'] }
          bounds = BandBounds.parse_variable(labels, variable_label: group.first['variable_label'])
          bounds.each { |modality, (lower, upper, unit)| updates << [year, variable, modality, lower, upper, unit] }
        end

        banded = updates.group_by { |year, variable, _, _, _, _| [year, variable] }.size
        logger.debug "RICA: #{updates.size} modalities of #{banded} banded variable-years carry bounds"

        updates.each_slice(1_000) { |slice| apply_modality_bounds(slice) }

        report_unparsed_band_modalities
      end

      def apply_modality_bounds(updates)
        values = updates.map do |year, variable, modality, lower, upper, unit|
          "(#{year}, #{quote(variable)}, #{quote(modality)}, #{number(lower)}, #{number(upper)}, #{quote(unit)})"
        end

        query <<~SQL
          UPDATE registered_rica_modalities AS m
          SET lower_bound = v.lower_bound, upper_bound = v.upper_bound, bound_unit = v.bound_unit
          FROM (VALUES #{values.join(', ')})
            AS v(year, variable_code, modality_code, lower_bound, upper_bound, bound_unit)
          WHERE m.year = v.year
            AND m.variable_code = v.variable_code
            AND m.modality_code = v.modality_code
        SQL
      end

      # A label the parser does not understand inside an otherwise banded
      # variable means the SSP changed its wording — the signal that the rules
      # in BandBounds need extending. "Sans objet" is the one expected miss: it
      # marks an inapplicable modality, not a zero.
      def report_unparsed_band_modalities
        rows = query(<<~SQL).to_a
          SELECT m.year, m.variable_code, m.modality_code, m.label
          FROM registered_rica_modalities m
          WHERE m.lower_bound IS NULL
            AND lower(trim(m.label)) <> 'sans objet'
            AND EXISTS (
              SELECT 1 FROM registered_rica_modalities b
              WHERE b.year = m.year AND b.variable_code = m.variable_code AND b.lower_bound IS NOT NULL
            )
          ORDER BY m.year, m.variable_code, m.modality_code
        SQL

        return if rows.empty?

        rows.each do |row|
          logger.warn "RICA #{row['year']} #{row['variable_code']}/#{row['modality_code']}: " \
                      "band label left unparsed — #{row['label'].inspect}"
        end
      end

      def quote(value)
        value.nil? ? 'NULL' : "'#{value.to_s.gsub("'", "''")}'"
      end

      # Always cast: a slice whose upper bounds are all open would otherwise give
      # the VALUES column a text type and break the assignment to numeric.
      def number(value)
        return 'NULL::numeric' if value.nil?

        "#{value.is_a?(BigDecimal) ? value.to_s('F') : value}::numeric"
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

      # The 2016-2018 dictionary and modalities .txt files break CSV parsing in
      # three ways: some lines are wrapped in outer double quotes, some carry a
      # trailing separator (giving them one field too many), and the file ends
      # on a blank line. Left alone, the COPY fails and the whole vintage lands
      # empty — which is why registered_rica_variables used to start at 2019.
      # Bytes are copied verbatim so the source encoding is preserved for the
      # loader to detect.
      def clean_legacy_file(src, dst, col_sep: ';')
        trailing_separators = /#{Regexp.escape(col_sep)}+\z/
        fields = nil

        File.open(dst, 'wb') do |out|
          File.foreach(src, mode: 'rb') do |line|
            line = line.chomp.rstrip
            next if line.empty?

            # The header sets how many fields a row may have. Separators past
            # that are the SSP's, not real empty columns, so they are dropped —
            # an honestly empty trailing field keeps its separator.
            fields ||= line.count(col_sep) + 1
            line = line.sub(trailing_separators, '') while line.count(col_sep) >= fields && line.end_with?(col_sep)

            line = line[1..-2] if line.start_with?('"') && line.end_with?('"')
            out.puts line
          end
        end
      end

      # Parses an FMD modality label into machine readable bounds.
      #
      # Conventions, uniform across every family:
      #   * `lower_bound` is inclusive, `upper_bound` exclusive.
      #   * an open-ended top band has a NULL `upper_bound`.
      #   * a "non nul" band starts at 0 — the zero itself is a separate
      #     modality of the same variable, so the two do not overlap in practice.
      #   * a label that is not quantitative yields nothing, and its modality
      #     keeps NULL bounds.
      module BandBounds
        # Quantitative subjects a band label can open with, longest first so
        # that "Effectif moyen" wins over "Effectif". The value is the unit
        # emitted; `hectare`, `head`, `hour` and `liter` are
        # master_units.reference_name, the rest are RICA-specific.
        SUBJECTS = [
          ['Surface',         'hectare'],
          ['Effectif moyen',  'head'],
          ['Effectif primé',  'head'],
          ['Effectif',        'head'],
          ["Nombre d'UGB",    'livestock_unit'],
          ["Nombre d'UTA",    'annual_work_unit'],
          ["Nombre d'UTH",    'human_work_unit'],
          ["Nombre d'heures", 'hour'],
          ['Nombre de DPU',   'payment_entitlement'],
          ['Quota laitier',   'liter'],
        ].sort_by { |subject, _| -subject.length }.freeze

        NUM  = '(\d+(?:,\d+)?)'.freeze
        # "égale ou supérieure à" — the "à" is missing from a handful of SSP
        # labels, and the strict form ("supérieur à 300") is used for the open
        # top band of a series whose previous band ends exactly at 300.
        GE   = '(?:égale?\s+ou\s+supérieure?|supérieure?)\s*(?:à\s*)?'.freeze
        LT   = '(?:strictement\s+)?inférieure?\s+à\s+'.freeze
        UNIT = '(?:\s*ha)?'.freeze

        ZERO  = /\Anul(?:le)?\z/.freeze
        BELOW = /\Anon\s+nul(?:le)?\s+et\s+#{LT}#{NUM}#{UNIT}\z/.freeze
        RANGE = /\A#{GE}#{NUM}#{UNIT}\s+et\s+#{LT}#{NUM}#{UNIT}\z/.freeze
        ABOVE = /\A#{GE}#{NUM}#{UNIT}\z/.freeze

        # CDEXE — economic dimension class, the only euro denominated family.
        PBS_RANGE = /\APBS\s+de\s+#{NUM}\s+à\s+moins\s+de\s+#{NUM}\s+euros\z/.freeze
        PBS_ABOVE = /\APBS\s+#{GE}#{NUM}\s+euros\z/.freeze

        # TRA05 — age of the holder, counted in complete years, so "21 à 25 ans"
        # covers [21, 26) and "Plus de 80 ans" starts at 81.
        AGE_BELOW = /\AMoins\s+de\s+#{NUM}\s+ans\z/.freeze
        AGE_RANGE = /\A#{NUM}\s+à\s+#{NUM}\s+ans\z/.freeze
        AGE_ABOVE = /\APlus\s+de\s+#{NUM}\s+ans\z/.freeze

        # Zero band written as an absence instead of a number ("Pas de DPU",
        # "Pas de main d'œuvre permanente salariée"). Only meaningful once the
        # other modalities of the variable have been parsed, since that is where
        # the unit comes from. "Sans objet" is deliberately excluded: it marks a
        # modality that does not apply, not a zero.
        ABSENCE = /\APas d(?:e\s|'|es\s)/i.freeze

        # When the dictionary label of the variable names a unit, it wins over
        # whatever the modality wording suggests. From 2020 the SSP reworded the
        # work-time bands without saying what they measure — TOUTA became
        # "Effectif …" and TVUTA "Nombre d'UTH …" — while both variable labels
        # kept "(UTA)". The dictionary is the authority, here as everywhere else
        # in this datasource.
        VARIABLE_LABEL_UNITS = {
          /\(UTA\)/ => 'annual_work_unit',
          /\(UTH\)/ => 'human_work_unit',
          /\(heures\)/i => 'hour',
        }.freeze

        class << self
          # Parses every modality of one variable at once, which is what lets an
          # absence label be recognised as that variable's zero band and the
          # variable's own label settle the unit.
          #
          # @param modalities [Hash{String => String}] modality code => label
          # @param variable_label [String, nil] the dictionary label of the variable
          # @return [Hash{String => Array(Numeric, Numeric, String)}] modality
          #   code => [lower, upper, unit], holding only the quantitative ones.
          def parse_variable(modalities, variable_label: nil)
            bounds = modalities.each_with_object({}) do |(code, label), acc|
              parsed = parse(label)
              acc[code] = parsed if parsed
            end
            return bounds if bounds.empty?

            unit = declared_unit(variable_label) || bounds.values.first.last
            bounds.each_value { |band| band[2] = unit }

            modalities.each do |code, label|
              next if bounds.key?(code)
              next unless label.to_s.strip.match?(ABSENCE)

              bounds[code] = [0, 0, unit]
            end
            bounds
          end

          # @return [Array(Numeric, Numeric, String), nil]
          def parse(label)
            text = label.to_s.gsub(/\s+/, ' ').strip
            return nil if text.empty?

            parse_age(text) || parse_pbs(text) || parse_subject(text)
          end

          private

            # @return [String, nil]
            def declared_unit(variable_label)
              return nil if variable_label.nil?

              VARIABLE_LABEL_UNITS.find { |pattern, _| variable_label.match?(pattern) }&.last
            end

            def parse_subject(text)
              SUBJECTS.each do |subject, unit|
                next unless text.start_with?(subject)

                bounds = parse_rest(text[subject.length..].strip)
                return [bounds[0], bounds[1], unit] if bounds
              end
              nil
            end

            def parse_rest(rest)
              case rest
              when ZERO  then [0, 0]
              when BELOW then [0, num($1)]
              when RANGE then [num($1), num($2)]
              when ABOVE then [num($1), nil]
              end
            end

            def parse_pbs(text)
              case text
              when PBS_RANGE then [num($1), num($2), 'euro']
              when PBS_ABOVE then [num($1), nil, 'euro']
              end
            end

            def parse_age(text)
              case text
              when AGE_BELOW then [0, num($1), 'year']
              when AGE_RANGE then [num($1), num($2) + 1, 'year']
              when AGE_ABOVE then [num($1) + 1, nil, 'year']
              end
            end

            def num(str)
              value = str.tr(',', '.')
              value.include?('.') ? BigDecimal(value) : Integer(value)
            end
        end
      end
  end
end
