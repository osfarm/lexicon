# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class BundleAssemblerTest < Minitest::Test
      def setup
        @root = Pathname.new(Dir.mktmpdir)
        @source = Repository.new(@root.join('packages'))
        @bundles = @root.join('packages/_bundles')
        @assembler = BundleAssembler.new(source: @source, root: @bundles)
        @bundle = Repository.new(@bundles.join('farm'))
      end

      def teardown
        FileUtils.rm_rf(@root)
      end

      def test_a_package_of_the_bundle_is_the_published_one
        build('units', '2026.10.01.1')

        outcome = assemble(%w[units], 'units' => '2026.10.01.1')

        assert_equal ['units@2026.10.01.1'], outcome.linked
        assert_empty outcome.missing
        assert_equal '2026.10.01.1', @bundle.designated('units')
        %w[manifest.json structure.sql indexes.sql data/units_0.csv.gz].each do |path|
          assert_equal @source.package_dir('units', '2026.10.01.1').join(path).stat.ino,
                       @bundle.package_dir('units', '2026.10.01.1').join(path).stat.ino, "#{path} is not a link"
        end
        assert_equal '700', format('%o', @bundle.root.stat.mode & 0o777)
        refute_includes @source.names, '_bundles'
      end

      def test_the_version_asked_for_is_designated_not_the_latest
        build('units', '2026.10.01.1')
        build('units', '2026.10.02.1')

        assemble(%w[units], 'units' => '2026.10.01.1')

        assert_equal '2026.10.01.1', @bundle.designated('units')
        assert_equal ['2026.10.01.1'], @bundle.versions('units')
      end

      def test_a_second_run_touches_nothing
        build('units', '2026.10.01.1')
        assemble(%w[units], 'units' => '2026.10.01.1')
        before = @bundles.glob('farm/**/*').map { |path| [path.to_s, path.stat.mtime, path.stat.ino] }

        outcome = assemble(%w[units], 'units' => '2026.10.01.1')

        assert outcome.unchanged?
        assert_equal before, @bundles.glob('farm/**/*').map { |path| [path.to_s, path.stat.mtime, path.stat.ino] }
      end

      def test_a_new_version_joins_the_previous_one_while_the_repository_keeps_it
        build('units', '2026.10.01.1')
        assemble(%w[units], 'units' => '2026.10.01.1')
        build('units', '2026.10.02.1')

        outcome = assemble(%w[units], 'units' => '2026.10.02.1')

        assert_equal ['units@2026.10.02.1'], outcome.linked
        assert_empty outcome.pruned
        assert_equal '2026.10.02.1', @bundle.designated('units')
        assert_equal %w[2026.10.01.1 2026.10.02.1], @bundle.versions('units')
      end

      def test_a_version_gone_from_the_repository_leaves_the_bundle
        build('units', '2026.10.01.1')
        assemble(%w[units], 'units' => '2026.10.01.1')
        build('units', '2026.10.02.1')
        @source.delete('units', '2026.10.01.1')

        outcome = assemble(%w[units], 'units' => '2026.10.02.1')

        assert_equal ['units@2026.10.01.1'], outcome.pruned
        assert_equal ['2026.10.02.1'], @bundle.versions('units')
        assert_equal ['2026.10.02.1'], index.dig('datasources', 'units', 'versions')
      end

      def test_a_datasource_not_in_service_keeps_what_the_bundle_had
        build('units', '2026.10.01.1')
        build('prices', '2026.10.01.1')
        assemble(%w[prices units], 'units' => '2026.10.01.1', 'prices' => '2026.10.01.1')

        outcome = assemble(%w[prices units], 'units' => '2026.10.01.1')

        assert_equal [{ name: 'prices', reason: 'not in service' }], outcome.missing
        assert_equal '2026.10.01.1', @bundle.designated('prices')
        assert_equal [{ name: 'prices', reason: 'not in service' }], @assembler.state('farm')[:missing]
      end

      def test_a_version_absent_from_the_repository_is_missing
        outcome = assemble(%w[units], 'units' => '2026.10.01.1')

        assert_equal [{ name: 'units', reason: '2026.10.01.1 is not in the repository' }], outcome.missing
        assert_nil @bundle.designated('units')
      end

      def test_a_package_waits_with_the_one_its_foreign_keys_reference
        build('units', '2026.10.01.1')
        build('variants', '2026.10.01.1', references: ['units'])
        build('prices', '2026.10.01.1', references: ['variants'])

        outcome = assemble(%w[prices units variants], 'prices' => '2026.10.01.1', 'variants' => '2026.10.01.1')

        assert_equal %w[prices units variants], outcome.missing.map { |entry| entry[:name] }.sort
        assert_match(/references units/, outcome.missing.find { |entry| entry[:name] == 'variants' }[:reason])
        assert_match(/references variants/, outcome.missing.find { |entry| entry[:name] == 'prices' }[:reason])
        assert_empty outcome.linked
      end

      def test_a_datasource_read_during_normalize_is_not_waited_for
        build('prices', '2026.10.01.1', reads: ['fertilizers'])

        outcome = assemble(%w[prices], 'prices' => '2026.10.01.1')

        assert_empty outcome.missing
      end

      def test_a_datasource_out_of_the_definition_leaves_the_bundle
        build('units', '2026.10.01.1')
        build('prices', '2026.10.01.1')
        versions = { 'units' => '2026.10.01.1', 'prices' => '2026.10.01.1' }
        assemble(%w[prices units], versions)

        outcome = assemble(%w[units], versions)

        assert_equal ['prices'], outcome.removed
        refute @bundle.datasource_dir('prices').exist?
        assert_equal ['units'], index.fetch('datasources').keys
        assert @bundles.join('farm/state.json').file?
      end

      def test_the_missing_ones_are_forgotten_once_they_arrive
        build('units', '2026.10.01.1')
        assemble(%w[units], {})

        assemble(%w[units], 'units' => '2026.10.01.1')

        assert_empty @assembler.state('farm')[:missing]
      end

      private

        def assemble(names, versions)
          @assembler.assemble(BundleDefinition.new(name: 'farm', datasources: names, defined_at: Time.now), versions: versions)
        end

        def index
          JSON.parse(@bundle.root.join('index.json').read)
        end

        def build(name, version, references: [], reads: [])
          dir = @source.package_dir(name, version)
          dir.join('data').mkpath
          dir.join('data', "#{name}_0.csv.gz").write('rows')
          dir.join('structure.sql').write('')
          dir.join('indexes.sql').write('')
          depends_on = references.map { |other| { name: other, kind: 'foreign_key' } } + reads.map { |other| { name: other, kind: 'normalize' } }
          Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now, tool_version: 'test',
            credits: [], depends_on: depends_on, foreign_keys: [],
            tables: [{ name: name, rows: 1, files: [{ path: "data/#{name}_0.csv.gz", sha256: '0', bytes: 4 }] }]
          ).write(dir)
        end
    end
  end
end
