# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Flavor
    class LexiconFlavorTest < Minitest::Test
      def setup
        tables = {
          'parcels' => FlavorTable.new('parcels', filter: "WHERE ST_DWithin(centroid, 'POINT(%{longitude} %{latitude})', %{radius})"),
          'cities' => FlavorTable.new('cities', filter: "WHERE name LIKE '%ville%'")
        }
        @flavor = LexiconFlavor.new('around', without: ['weather'], datasources: { 'cadastre' => DatasourceFlavor.new('cadastre', tables: tables) })
      end

      def test_lists_the_parameters_its_filters_expect
        assert_equal %w[latitude longitude radius], @flavor.parameters
      end

      def test_values_replace_the_parameters_and_nothing_else
        filled = @flavor.with_parameters({ 'longitude' => '-0.78', 'latitude' => '45.81', 'radius' => '0.1' }, name: 'farm')

        assert_equal 'farm', filled.name
        assert_equal ['weather'], filled.without
        assert_equal "WHERE ST_DWithin(centroid, 'POINT(-0.78 45.81)', 0.1)", filled.datasource('cadastre').table('parcels').filter
        assert_equal "WHERE name LIKE '%ville%'", filled.datasource('cadastre').table('cities').filter
        assert_includes @flavor.datasource('cadastre').table('parcels').filter, '%{radius}'
      end

      def test_a_missing_parameter_is_an_error
        error = assert_raises(ArgumentError) { @flavor.with_parameters({ 'longitude' => '-0.78' }) }

        assert_match(/latitude, radius/, error.message)
      end

      def test_a_value_that_could_change_the_query_is_refused
        values = { 'longitude' => '0', 'latitude' => '0', 'radius' => "1); DROP TABLE parcels; --" }

        assert_raises(ArgumentError) { @flavor.with_parameters(values) }
        assert_raises(ArgumentError) { @flavor.with_parameters(values.merge('radius' => "1' OR '1'='1")) }
      end

      def test_a_flavor_without_parameter_is_unchanged
        plain = LexiconFlavor.new('light', without: ['cadastre'])

        assert_empty plain.parameters
        assert_equal 'light', plain.with_parameters({}).name
      end
    end
  end
end
