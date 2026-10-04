# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    # rsync treats a local directory like a remote one: the target here is a directory.
    class PublisherTest < Minitest::Test
      def setup
        @local = Pathname.new(Dir.mktmpdir)
        @remote = Pathname.new(Dir.mktmpdir).join('packages')
        @repository = Repository.new(@local)
        @publisher = Publisher.new(repository: @repository, target: @remote.to_s)
      end

      def teardown
        FileUtils.rm_rf([@local, @remote.dirname])
      end

      def test_publishes_the_latest_version_and_designates_it
        build('units', '2026.10.01.1')
        build('units', '2026.10.02.1')

        assert_equal '2026.10.02.1', @publisher.publish('units')

        remote = Repository.new(@remote)
        assert_equal ['2026.10.02.1'], remote.versions('units')
        assert_equal '2026.10.02.1', remote.current('units')
        assert_equal 'rows', @remote.join('units/2026.10.02.1/data/units_0.csv.gz').read
        assert_equal({ 'units' => { current: '2026.10.02.1', versions: ['2026.10.02.1'] } }, @publisher.published)
      end

      def test_index_keeps_the_other_datasources_and_versions
        build('units', '2026.10.01.1')
        build('taxonomy', '2026.10.01.1')
        @publisher.publish('units')
        @publisher.publish('taxonomy')
        build('units', '2026.10.02.1')

        @publisher.publish('units')

        published = @publisher.published
        assert_equal %w[taxonomy units], published.keys.sort
        assert_equal %w[2026.10.01.1 2026.10.02.1], published['units'][:versions]
        assert_equal '2026.10.02.1', published['units'][:current]
        assert_equal '2026.10.01.1', published['taxonomy'][:current]
      end

      def test_older_version_can_be_designated_again
        build('units', '2026.10.01.1')
        build('units', '2026.10.02.1')
        @publisher.publish('units')

        @publisher.publish('units', version: '2026.10.01.1')

        assert_equal '2026.10.01.1', Repository.new(@remote).current('units')
        assert_equal %w[2026.10.01.1 2026.10.02.1], Repository.new(@remote).versions('units')
      end

      def test_in_service_comes_from_the_status_file_of_the_serving_side
        assert_empty @publisher.in_service

        @remote.mkpath
        @remote.join('status.json').write({ packages: { units: { version: '2026.10.01.1', stale: false } } }.to_json)

        assert_equal({ 'units' => { version: '2026.10.01.1', stale: false } }, @publisher.in_service)
      end

      def test_unknown_package_is_refused_and_nothing_is_published
        assert_raises(ArgumentError) { @publisher.publish('units') }
        build('units', '2026.10.01.1')
        assert_raises(ArgumentError) { @publisher.publish('units', version: '2026.01.01.1') }

        assert_empty @publisher.published
      end

      def test_failed_transfer_does_not_designate_the_version
        build('units', '2026.10.01.1')
        publisher = Publisher.new(repository: @repository, target: '/proc/nowhere/packages')

        assert_raises(Rsync::TransferError) { publisher.publish('units') }
      end

      private

        def build(name, version)
          dir = @repository.package_dir(name, version)
          dir.join('data').mkpath
          dir.join('data', "#{name}_0.csv.gz").write('rows')
          dir.join('structure.sql').write('')
          dir.join('indexes.sql').write('')
          Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now,
            tool_version: 'test', credits: [], depends_on: [], tables: [], foreign_keys: []
          ).write(dir)
        end
    end
  end
end
