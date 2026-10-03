# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class ManifestTest < Minitest::Test
      def test_written_manifest_is_read_back_identical
        Dir.mktmpdir do |dir|
          dir = Pathname.new(dir)
          manifest = Manifest.new(
            name: 'units', version: '2026.10.03.1', schema_revision: 2, structure_hash: 'sha256:abc',
            built_at: Time.utc(2026, 10, 3, 17, 15), tool_version: '6.1.0',
            credits: [{ name: 'Units', provider: 'Ekylibre', url: 'https://ekylibre.com', licence: 'CC-BY-SA 4.0', licence_url: nil, updated_at: '2022-02-23' }],
            depends_on: [{ name: 'taxonomy', kind: 'foreign_key', built_against: nil }],
            tables: [{ name: 'master_units', rows: 3, files: [{ path: 'data/master_units_0.csv.gz', sha256: 'def', bytes: 42 }] }],
            foreign_keys: []
          )
          manifest.write(dir)

          loaded = Manifest.load(dir.join('manifest.json'))

          assert_equal manifest.to_h, loaded.to_h
          assert_equal 3, JSON.parse(dir.join('manifest.json').read)['format']
        end
      end

      def test_other_formats_are_refused
        Dir.mktmpdir do |dir|
          file = Pathname.new(dir).join('manifest.json')
          file.write('{"format": 2, "name": "units"}')

          assert_raises(ArgumentError) { Manifest.load(file) }
        end
      end
    end
  end
end
