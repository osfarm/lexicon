# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class FetcherTest < Minitest::Test
      BASE = 'https://lexicon.test/bundles/demo'

      def setup
        @remote = Pathname.new(Dir.mktmpdir)
        @local = Pathname.new(Dir.mktmpdir)
        @requests = []
        build('units', '2026.10.01.1', 'rows')
        Repository.new(@remote).set_current('units', '2026.10.01.1')
      end

      def teardown
        FileUtils.rm_rf([@remote, @local])
      end

      def test_fetches_the_designated_packages_and_checks_them
        names = fetcher.fetch(@local)

        local = Repository.new(@local)
        assert_equal ['units'], names
        assert_equal ['2026.10.01.1'], local.versions('units')
        assert_equal '2026.10.01.1', local.current('units')
        assert_equal 'rows', @local.join('units/2026.10.01.1/data/units_0.csv.gz').read
        assert_equal "#{BASE}/index.json", @requests.first
      end

      def test_a_package_already_fetched_is_not_downloaded_again
        fetcher.fetch(@local)
        @requests.clear

        fetcher.fetch(@local)

        assert_equal ["#{BASE}/index.json"], @requests
      end

      def test_a_file_that_does_not_match_its_checksum_is_refused
        @remote.join('units/2026.10.01.1/data/units_0.csv.gz').write('tampered')

        error = assert_raises(Fetcher::FetchError) { fetcher.fetch(@local) }

        assert_match(/does not match its checksum/, error.message)
        assert_empty Repository.new(@local).versions('units')
        refute @local.join('index.json').exist?
        assert_empty @local.join('units').children
      end

      def test_a_refused_download_leaves_nothing_behind
        refusing = Fetcher.new(base_url: BASE, download: ->(url, _file) { raise Fetcher::FetchError.new("#{url}: HTTP 403") })

        assert_raises(Fetcher::FetchError) { refusing.fetch(@local) }
        assert_empty @local.children
      end

      private

        def fetcher
          Fetcher.new(base_url: BASE, download: lambda do |url, destination|
            @requests << url
            source = @remote.join(url.delete_prefix("#{BASE}/"))
            raise Fetcher::FetchError.new("#{url}: HTTP 404") unless source.file?

            FileUtils.cp(source, destination)
          end)
        end

        def build(name, version, content)
          dir = @remote.join(name, version)
          dir.join('data').mkpath
          file = dir.join('data', "#{name}_0.csv.gz")
          file.write(content)
          dir.join('structure.sql').write('')
          dir.join('indexes.sql').write('')
          Manifest.new(
            name: name, version: version, schema_revision: 1, structure_hash: 'sha256:0', built_at: Time.now,
            tool_version: 'test', credits: [], depends_on: [], foreign_keys: [],
            tables: [{ name: name, rows: 1, files: [{ path: "data/#{name}_0.csv.gz", sha256: Digest::SHA256.file(file).hexdigest, bytes: file.size }] }]
          ).write(dir)
        end
    end
  end
end
