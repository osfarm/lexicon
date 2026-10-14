# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Server
    # No database here: what is in service is told by a stand-in for Meta.
    class BundlesTest < Minitest::Test
      Installed = Struct.new(:name, :version)
      InService = Struct.new(:all_installed)

      def setup
        @root = Pathname.new(Dir.mktmpdir)
        @repository = Packaging::Repository.new(@root)
        @area = @root.join('_bundles')
      end

      def teardown
        FileUtils.rm_rf(@root)
      end

      def test_a_bundle_designates_what_is_in_service_not_what_the_index_designates
        build('units', '2026.10.01.1')
        build('units', '2026.10.02.1')
        @repository.set_current('units', '2026.10.02.1')
        define('farm', %w[units])

        results = bundles('units' => '2026.10.01.1').assemble_all

        assert_equal ['farm'], results.map(&:name)
        assert_equal ['units@2026.10.01.1'], results.first.outcome.linked
        assert_equal '2026.10.01.1', Packaging::Repository.new(@area.join('farm')).designated('units')
      end

      def test_a_bundle_sent_whole_is_left_as_it_is
        @area.join('around/units/2026.10.01.1').mkpath
        @area.join('around/index.json').write('{}')

        assert_empty bundles({}).assemble_all
        assert_equal '{}', @area.join('around/index.json').read
        assert @area.join('around/units/2026.10.01.1').directory?
      end

      def test_a_definition_that_cannot_be_read_does_not_stop_the_others
        build('units', '2026.10.01.1')
        define('farm', %w[units])
        @area.join('broken').mkpath
        @area.join('broken/bundle.json').write('not json')
        define('stolen', %w[units], name: 'farm')

        results = bundles('units' => '2026.10.01.1').assemble_all.map { |result| [result.name, result] }.to_h

        assert_nil results['broken'].outcome
        assert_match(/cannot be read/, results['broken'].error)
        assert_match(/defines farm, not stolen/, results['stolen'].error)
        assert_equal ['units@2026.10.01.1'], results['farm'].outcome.linked
      end

      def test_no_private_area_means_no_bundle
        assert_empty bundles({}).assemble_all
      end

      private

        def bundles(in_service)
          Bundles.new(repository: @repository, meta: InService.new(in_service.map { |name, version| Installed.new(name, version) }))
        end

        def define(directory, names, name: directory)
          @area.join(directory).mkpath
          Packaging::BundleDefinition.new(name: name, datasources: names, defined_at: Time.now).write(@area.join(directory))
        end

        def build(name, version)
          dir = @repository.package_dir(name, version)
          dir.join('data').mkpath
          dir.join('data', "#{name}_0.csv.gz").write('rows')
          dir.join('structure.sql').write('')
          dir.join('indexes.sql').write('')
          Packaging::Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now, tool_version: 'test',
            credits: [], depends_on: [], foreign_keys: [],
            tables: [{ name: name, rows: 1, files: [{ path: "data/#{name}_0.csv.gz", sha256: '0', bytes: 4 }] }]
          ).write(dir)
        end
    end
  end
end
