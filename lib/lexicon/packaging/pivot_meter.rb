# frozen_string_literal: true

module Lexicon
  module Packaging
    # Measures how well the pivot columns of a datasource match their reference: among the distinct values
    # of a column, how many exist in the reference table.
    class PivotMeter
      SCHEMA = 'lexicon'

      # @param [#query] database
      def initialize(database)
        @database = database
      end

      # @param [Array<Hash>] declarations each with :key, :table, :column and optionally :minimum
      # @return [Array<Hash>] the declarations with :values, :matched and :rate (nil when not measurable)
      def measure(declarations)
        declarations.map do |declaration|
          key = Pivots.fetch(declaration[:key])

          declaration.merge(count(declaration, key))
        end
      end

      private

        def count(declaration, key)
          row = begin
            @database.query(counting_query(declaration, key, cast: '')).first
          rescue PG::UndefinedFunction
            # The column and its reference have different types: compare them as text
            @database.query(counting_query(declaration, key, cast: '::text')).first
          end
          values = row['values'].to_i
          matched = row['matched'].to_i

          { values: values, matched: matched, rate: values.zero? ? nil : (matched.to_f / values).round(4) }
        rescue PG::UndefinedTable, PG::UndefinedColumn
          # The reference is not built on this machine: the rate is unknown, not zero
          { values: 0, matched: 0, rate: nil }
        end

        def counting_query(declaration, key, cast:)
          condition = key.where.nil? ? '' : " AND #{key.where}"

          # Two sets of distinct values joined together: Postgres hashes them, whatever the indexes are
          <<~SQL
            SELECT count(*) AS values, count(reference.value) AS matched
              FROM (
                SELECT DISTINCT "#{declaration[:column]}"#{cast} AS value
                  FROM "#{SCHEMA}"."#{declaration[:table]}"
                 WHERE "#{declaration[:column]}" IS NOT NULL
              ) AS carried
              LEFT JOIN (
                SELECT DISTINCT "#{key.column}"#{cast} AS value
                  FROM "#{SCHEMA}"."#{key.table}"
                 WHERE "#{key.column}" IS NOT NULL#{condition}
              ) AS reference ON reference.value = carried.value
          SQL
        end
    end
  end
end
