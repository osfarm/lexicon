# frozen_string_literal: true

module Lexicon
  module Contribution
    # The datasource of a tabular contribution: everything a hand-written datasource declares and does is
    # drawn from the sheet. One class is made per contribution, at start, under `Datasources`.
    class TabularDatasource < Datasources::Base
      class << self
        # @return [Sheet]
        attr_reader :sheet

        # Defines `Datasources::<Name>` for each contribution of a directory. A sheet that cannot be read
        # is left aside: `./lexicon contribute <name>` tells what is wrong with it.
        #
        # @param [Pathname] root
        # @param [Pathname, nil] raw root of the raw directories, where a large table is kept
        # @return [Array<Class>]
        def define_all(root, raw: nil)
          Sheet.directories(root).map do |dir|
            define(Sheet.load(dir, raw: raw))
          rescue Psych::Exception
            nil
          end.compact
        end

        # @param [Sheet] sheet
        # @return [Class, nil] nil when a datasource of that name exists, or when the sheet is not complete enough
        def define(sheet)
          constant = sheet.name.camelize
          return nil unless sheet.name.match?(Review::NAME) && !Datasources.const_defined?(constant, false) && complete?(sheet)

          # Named first: a datasource takes its name from its constant
          Datasources.const_set(constant, Class.new(self)).tap { |datasource| datasource.configure(sheet) }
        rescue StandardError
          # A contribution never keeps Lexicon from starting
          Datasources.send(:remove_const, constant) if Datasources.const_defined?(constant, false)
          nil
        end

        def configure(sheet)
          @sheet = sheet
          source = sheet.source

          description sheet.description
          # The contributor is credited with the source: a dataset keeps who brought it
          credits name: "#{source['name']} (contribution : #{sheet.author})", url: source['url'], provider: source['provider'],
                  licence: source['licence'], licence_url: source['licence_url'], updated_at: source['date']
          scope sheet.scope unless sheet.scope.nil?
          personal_data sheet.personal_data unless sheet.personal_data.nil?
          sheet.tables.each { |table| table.keys.each { |column, key| pivot key, table: table.name, column: column } }
          located = sheet.tables.select(&:place)
          located.each { |table| pivot :commune, table: table.name, column: table.place[:column] }
          depends_on :postal_codes if located.any?
        end

        def table_definitions(builder)
          sheet.tables.each { |table| builder.table(table.name.to_sym, sql: create_sql(table)) }
        end

        # @param [Sheet::Table] table
        # @return [String]
        def create_sql(table)
          columns = table.columns.map do |column, type|
            %("#{column}" #{Sheet::TYPES.fetch(type)}#{' PRIMARY KEY NOT NULL' if column == table.key})
          end

          columns << %("#{table.place[:column]}" character varying) if table.place

          "CREATE TABLE #{table.name} (\n  #{columns.join(",\n  ")}\n);"
        end

        # @param [Sheet::Table] table
        # @param [String] schema working schema the file was loaded in
        # @return [String] every value is loaded as text: an empty one is no value, the others take their type
        def insert_sql(table, schema)
          values = table.columns.map { |column, type| value_sql(column, type) }

          names = table.columns.keys
          if table.place
            names += [table.place[:column]]
            values << commune_sql(table.place)
          end

          %(INSERT INTO #{table.name} (#{names.map { |column| %("#{column}") }.join(', ')})\n) +
            %(  SELECT #{values.join(', ')}\n    FROM #{schema}.#{raw_table(table)} AS source\n   ORDER BY "#{table.key}")
        end

        # @return [String] the value of a column, loaded as text, in its type
        def value_sql(column, type)
          filled = %(NULLIF(trim("#{column}"), ''))

          case type
          when 'text' then %(NULLIF("#{column}", ''))
          # Written latitude first, as people say it; a point takes its longitude first
          when 'point'
            "postgis.ST_SetSRID(postgis.ST_MakePoint(split_part(#{filled}, ',', 2)::float8, split_part(#{filled}, ',', 1)::float8), 4326)"
          else "#{filled}::#{Sheet::TYPES.fetch(type)}"
          end
        end

        # @param [Hash] place columns holding the postal code and the name of a commune
        # @return [String] the INSEE code of the one commune of that postal code that bears that name; failing
        #   that, of the one known by that name where mail is delivered. No code when there is none, or more than
        #   one. The name of the commune comes first: « Paris » is Paris, « Paris 15 » its arrondissement.
        def commune_sql(place)
          "COALESCE(#{named_sql(place, %w[city_name])}, #{named_sql(place, %w[city_name city_delivery_name city_delivery_detail])})"
        end

        def named_sql(place, columns)
          names = columns.map { |column| plain_sql("place.#{column}") }

          <<~SQL.strip
            (SELECT min(place.code)
                       FROM registered_postal_codes AS place
                      WHERE place.postal_code = trim(source."#{place[:postal_code]}")
                        AND trim(coalesce(source."#{place[:name]}", '')) <> ''
                        AND #{plain_sql(%(source."#{place[:name]}"))} IN (#{names.join(', ')})
                     HAVING count(DISTINCT place.code) = 1)
          SQL
        end

        # @return [String] a name the way the postal reference writes it: capitals, no accent, no punctuation, ST for SAINT
        def plain_sql(expression)
          bare = "regexp_replace(upper(postgis.unaccent(coalesce(#{expression}, ''))), '[^A-Z0-9]+', ' ', 'g')"

          "trim(regexp_replace(regexp_replace(#{bare}, '\\mSAINTE\\M', 'STE', 'g'), '\\mSAINT\\M', 'ST', 'g'))"
        end

        def raw_table(table)
          File.basename(table.file, '.*').downcase.gsub(/[^a-z0-9]+/, '_')
        end

        private

          # Enough to declare the datasource; whether it can be accepted is the matter of Review
          def complete?(sheet)
            source = sheet.source

            described = sheet.tables.any? && sheet.tables.all? do |table|
              table.columns.key?(table.key) && table.columns.values.all? { |type| Sheet::TYPES.key?(type) }
            end

            credited = %w[name url provider licence date].none? { |field| source[field].nil? }

            described && credited && !sheet.description.nil? && !sheet.author.nil?
          end
      end

      # A table kept in the raw directory is already where it is read
      def collect
        files = self.class.sheet.tables.map { |table| self.class.sheet.path(table) }

        FileUtils.cp(files.reject { |file| file.dirname.expand_path == Pathname.new(dir).expand_path }, dir)
      end

      def load
        self.class.sheet.tables.each { |table| load_csv(dir.join(table.file), self.class.raw_table(table)) }
      end

      def normalize
        self.class.sheet.tables.each { |table| query(self.class.insert_sql(table, name)) }
      end
    end
  end
end
