# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class DependencyResolverTest < Minitest::Test
      def setup
        @taxonomy = definition_set('taxonomy') { |b| b.table(:master_taxonomy, sql: '') }
        @units = definition_set('units') { |b| b.table(:master_units, sql: '') }
        @productions = definition_set('productions') do |b|
          b.table(:master_productions, sql: '').references(support_unit: %i[master_units reference_name])
          b.table(:master_production_yields, sql: '').references(
            production: %i[master_productions reference_name],
            specie: %i[master_taxonomy reference_name]
          )
        end
        @resolver = DependencyResolver.new([@taxonomy, @units, @productions])
      end

      def test_foreign_keys_give_dependencies_without_the_datasource_itself
        assert_equal(
          [{ name: 'taxonomy', kind: 'foreign_key' }, { name: 'units', kind: 'foreign_key' }],
          @resolver.resolve(@productions)
        )
      end

      def test_declared_dependencies_are_added_once
        dependencies = @resolver.resolve(@productions, declared: %w[open_nomenclature taxonomy productions])

        assert_equal(
          [
            { name: 'open_nomenclature', kind: 'normalize' },
            { name: 'taxonomy', kind: 'foreign_key' },
            { name: 'units', kind: 'foreign_key' }
          ],
          dependencies
        )
      end

      def test_datasource_without_reference_has_no_dependency
        assert_empty @resolver.resolve(@units)
      end

      def test_foreign_key_to_an_undefined_table_is_an_error
        orphan = definition_set('orphan') { |b| b.table(:things, sql: '').references(unit: %i[nowhere id]) }

        assert_raises(ArgumentError) { DependencyResolver.new([orphan]).resolve(orphan) }
      end

      private

        def definition_set(name)
          builder = Database::Schema::TableBuilder.new
          yield builder

          Database::Schema::TableDefinitionSet.new(name, builder.tables)
        end
    end
  end
end
