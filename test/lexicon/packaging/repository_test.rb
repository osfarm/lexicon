# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class RepositoryTest < Minitest::Test
      def setup
        @root = Pathname.new(Dir.mktmpdir)
        @repository = Repository.new(@root)
      end

      def teardown
        FileUtils.rm_rf(@root)
      end

      def test_first_version_of_a_day
        assert_equal '2026.10.03.1', @repository.next_version('units', Date.new(2026, 10, 3))
      end

      def test_next_version_follows_the_highest_rank_of_the_day
        publish('units', '2026.10.02.4')
        publish('units', '2026.10.03.2')
        publish('units', '2026.10.03.10')

        assert_equal '2026.10.03.11', @repository.next_version('units', Date.new(2026, 10, 3))
        assert_equal '2026.10.04.1', @repository.next_version('units', Date.new(2026, 10, 4))
      end

      def test_versions_are_ordered_numerically_and_ignore_incomplete_packages
        publish('units', '2026.10.03.10')
        publish('units', '2026.10.03.9')
        publish('units', '2026.09.30.1')
        @root.join('units', '.building-2026.10.03.11').mkpath
        @root.join('units', '2026.10.03.12').mkpath

        assert_equal %w[2026.09.30.1 2026.10.03.9 2026.10.03.10], @repository.versions('units')
        assert_equal '2026.10.03.10', @repository.latest('units').version
      end

      def test_index_designates_the_current_version
        publish('units', '2026.10.02.1')
        publish('units', '2026.10.03.1')
        assert_equal '2026.10.03.1', @repository.current('units')

        @repository.set_current('units', '2026.10.02.1')

        assert_equal '2026.10.02.1', @repository.current('units')
        index = JSON.parse(@root.join('index.json').read)
        assert_equal %w[2026.10.02.1 2026.10.03.1], index.dig('datasources', 'units', 'versions')
        assert_raises(ArgumentError) { @repository.set_current('units', '2026.01.01.1') }
        assert_equal ['units'], @repository.names
      end

      def test_deleted_version_leaves_the_index_consistent
        publish('units', '2026.10.02.1')
        publish('units', '2026.10.03.1')
        @repository.set_current('units', '2026.10.03.1')

        @repository.delete('units', '2026.10.02.1')

        assert_equal ['2026.10.03.1'], @repository.versions('units')
        assert_equal ['2026.10.03.1'], JSON.parse(@root.join('index.json').read).dig('datasources', 'units', 'versions')
      end

      def test_unknown_datasource_has_no_version
        assert_empty @repository.versions('nothing')
        assert_nil @repository.latest('nothing')
      end

      private

        def publish(name, version)
          dir = @repository.package_dir(name, version)
          dir.mkpath
          Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now,
            tool_version: '0', credits: [], depends_on: [], tables: [], foreign_keys: []
          ).write(dir)
        end
    end
  end
end
