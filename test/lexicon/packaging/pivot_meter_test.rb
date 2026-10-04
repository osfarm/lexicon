# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class PivotMeterTest < Minitest::Test
      # Answers the counting query with fixed figures, and remembers what was asked
      class FakeDatabase
        attr_reader :queries

        def initialize(row = nil, error: nil)
          @row = row
          @error = error
          @queries = []
        end

        def query(sql)
          @queries << sql
          raise @error unless @error.nil? || (@error.is_a?(PG::UndefinedFunction) && sql.include?('::text'))

          [@row]
        end
      end

      def test_gives_the_share_of_distinct_values_found_in_the_reference
        database = FakeDatabase.new({ 'values' => '200', 'matched' => '190' })

        result = PivotMeter.new(database).measure([{ key: 'commune', table: 'registered_enterprises', column: 'insee_code', minimum: 0.9 }])

        assert_equal [{ key: 'commune', table: 'registered_enterprises', column: 'insee_code', minimum: 0.9, values: 200, matched: 190, rate: 0.95 }], result
        assert_includes database.queries.first, 'SELECT DISTINCT "code" AS value'
        assert_includes database.queries.first, 'FROM "lexicon"."registered_postal_codes"'
        assert_includes database.queries.first, 'SELECT DISTINCT "insee_code" AS value'
        assert_includes database.queries.first, 'FROM "lexicon"."registered_enterprises"'
      end

      def test_restricts_the_reference_when_the_key_says_so
        database = FakeDatabase.new({ 'values' => '10', 'matched' => '10' })

        PivotMeter.new(database).measure([{ key: 'department', table: 'link_communes', column: 'department_code' }])

        assert_includes database.queries.first, "AND kind = 'department'"
      end

      def test_columns_of_different_types_are_compared_as_text
        database = FakeDatabase.new({ 'values' => '4', 'matched' => '2' }, error: PG::UndefinedFunction.new('operator does not exist'))

        result = PivotMeter.new(database).measure([{ key: 'commune', table: 't', column: 'code' }])

        assert_equal 0.5, result.first[:rate]
        assert_equal 2, database.queries.size
        assert_includes database.queries.last, 'SELECT DISTINCT "code"::text AS value'
      end

      def test_no_value_or_no_reference_gives_an_unknown_rate
        empty = PivotMeter.new(FakeDatabase.new({ 'values' => '0', 'matched' => '0' }))
        missing = PivotMeter.new(FakeDatabase.new(error: PG::UndefinedTable.new('relation does not exist')))
        declaration = [{ key: 'siren', table: 'registered_cap_beneficiaries', column: 'siren' }]

        assert_nil empty.measure(declaration).first[:rate]
        assert_nil missing.measure(declaration).first[:rate]
      end

      def test_an_unknown_key_is_an_error
        assert_raises(ArgumentError) { PivotMeter.new(FakeDatabase.new).measure([{ key: 'planet', table: 't', column: 'c' }]) }
        assert_raises(ArgumentError) { Pivots.fetch('planet') }
      end

      def test_datasources_declare_keys_that_exist
        declared = Datasources.constants.map { |name| Datasources.const_get(name) }
                              .select { |klass| klass.is_a?(Class) && klass < Datasources::Base }
                              .flat_map(&:get_pivots)

        refute_empty declared
        declared.each { |pivot| assert Pivots::KEYS.key?(pivot[:key]), "unknown pivot key #{pivot[:key]}" }
      end
    end
  end
end
