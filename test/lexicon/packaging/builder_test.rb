# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class BuilderTest < Minitest::Test
      # Writes the rows it was given instead of reading a database
      class FakeExporter
        attr_accessor :rows

        def export(_source, file)
          file.write(rows)

          { rows: rows.lines.size, sha256: Digest::SHA256.hexdigest(rows), bytes: rows.bytesize }
        end
      end

      class FakeResolver
        def resolve(_definition_set, declared:)
          declared.map { |name| { name: name, kind: 'normalize' } }
        end

        def foreign_keys(_definition_set)
          []
        end
      end

      class FakeDatabase
        attr_accessor :date

        def prepend_search_path(*)
          yield
        end

        def query(_sql)
          [{ 'max' => date }]
        end
      end

      Definition = Struct.new(:name)
      DefinitionSet = Struct.new(:name, :create_sql, :definitions)

      def setup
        @root = Pathname.new(Dir.mktmpdir)
        @repository = Repository.new(@root)
        @exporter = FakeExporter.new
        @exporter.rows = "a\nb\n"
        @database = FakeDatabase.new
        @database.date = '2026-10-02'
        @builder = Builder.new(repository: @repository, exporter: @exporter, dependency_resolver: FakeResolver.new,
                               splitter: StructureSplitter.new, tool_version: 'test', database: @database)
        @definitions = DefinitionSet.new('fuel_prices', 'CREATE TABLE registered_fuel_prices (id character varying)',
                                         [Definition.new('registered_fuel_prices')])
      end

      def teardown
        FileUtils.rm_rf(@root)
      end

      def test_same_data_does_not_make_a_new_version
        first = build(Time.utc(2026, 10, 5, 14))

        again = build(Time.utc(2026, 10, 12, 14))

        assert_equal '2026.10.05.1', again.version
        assert_equal first.to_h, again.to_h
        assert_equal ['2026.10.05.1'], @repository.versions('fuel_prices')
        assert_empty @root.join('fuel_prices').children.map { |child| child.basename.to_s }.grep(/building/)
      end

      def test_new_data_makes_a_new_version
        build(Time.utc(2026, 10, 5, 14))
        @exporter.rows = "a\nb\nc\n"

        manifest = build(Time.utc(2026, 10, 12, 14))

        assert_equal '2026.10.12.1', manifest.version
        assert_equal %w[2026.10.05.1 2026.10.12.1], @repository.versions('fuel_prices')
      end

      def test_date_of_the_source_comes_from_the_data_when_the_datasource_says_how
        manifest = build(Time.utc(2026, 10, 5, 14))

        assert_equal ['2026-10-02'], manifest.credits.map { |credit| credit[:updated_at] }
      end

      def test_date_of_the_credits_is_kept_otherwise
        manifest = build(Time.utc(2026, 10, 5, 14), datasource: datasource(source_date: nil))

        assert_equal ['2020-01-01'], manifest.credits.map { |credit| credit[:updated_at] }
      end

      private

        def build(now, datasource: self.datasource)
          @builder.build(datasource, @definitions, now: now)
        end

        def datasource(source_date: 'SELECT max(observed_on) FROM registered_fuel_prices')
          Class.new do
            include Dsl::CreditsRecorder
            include Dsl::Description
            include Dsl::Packaging

            def self.datasource_name
              'fuel_prices'
            end

            description 'Fuel prices'
            credits name: 'Prices', url: 'https://example.org', provider: 'DGEC', licence: 'Licence Ouverte 2.0',
                    licence_url: 'https://example.org/licence', updated_at: '2020-01-01'
            source_date source_date unless source_date.nil?
          end
        end
    end
  end
end
