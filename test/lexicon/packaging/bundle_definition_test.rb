# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class BundleDefinitionTest < Minitest::Test
      def setup
        sets = [
          definition_set('units') { |b| b.table(:master_units, sql: '') },
          definition_set('variants') { |b| b.table(:master_variants, sql: '').references(unit: %i[master_units reference_name]) },
          definition_set('prices') { |b| b.table(:master_prices, sql: '').references(variant: %i[master_variants reference_name]) }
        ]
        @definitions = sets.map { |set| [set.name, set] }.to_h
        @resolver = DependencyResolver.new(sets)
      end

      def test_a_tracked_flavor_gives_its_datasources_in_order
        definition = define(flavor(%w[variants units]))

        assert_equal 'farm', definition.name
        assert_equal %w[units variants], definition.datasources
      end

      def test_a_foreign_key_leaving_the_bundle_is_refused_and_named
        error = assert_raises(ArgumentError) { define(flavor(%w[prices units])) }

        assert_match(/prices references variants/, error.message)
      end

      def test_an_unknown_datasource_is_refused
        error = assert_raises(ArgumentError) { define(flavor(%w[units weather])) }

        assert_match(/weather/, error.message)
      end

      def test_a_flavor_that_is_not_tracked_defines_no_bundle
        assert_raises(ArgumentError) { define(Flavor::LexiconFlavor.new('light', only: ['units'])) }
      end

      def test_it_is_read_back_as_it_was_written
        dir = Pathname.new(Dir.mktmpdir)
        written = define(flavor(%w[units variants]), now: Time.utc(2026, 10, 13, 9))

        read = BundleDefinition.load(written.write(dir))

        assert_equal written.to_h, read.to_h
        assert_equal 'bundle.json', BundleDefinition::FILE_NAME
      ensure
        FileUtils.rm_rf(dir)
      end

      def test_a_file_that_is_not_a_definition_is_an_error
        dir = Pathname.new(Dir.mktmpdir)
        dir.join('bundle.json').write('{"format": 1}')
        dir.join('other.json').write('not json')

        assert_raises(ArgumentError) { BundleDefinition.load(dir.join('bundle.json')) }
        assert_raises(ArgumentError) { BundleDefinition.load(dir.join('other.json')) }
      ensure
        FileUtils.rm_rf(dir)
      end

      private

        def flavor(only)
          Flavor::LexiconFlavor.new('farm', only: only, tracked: true)
        end

        def define(flavor, now: Time.now)
          BundleDefinition.from_flavor(flavor, definitions: @definitions, resolver: @resolver, now: now)
        end

        def definition_set(name)
          builder = Database::Schema::TableBuilder.new
          yield builder

          Database::Schema::TableDefinitionSet.new(name, builder.tables)
        end
    end
  end
end
