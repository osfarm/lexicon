# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Packaging
    class RetentionTest < Minitest::Test
      VERSIONS = %w[2026.10.01.1 2026.10.02.1 2026.10.03.1 2026.10.04.1].freeze

      def test_keeps_the_latest_versions_of_a_datasource
        retention = Retention.new(default: 'all', datasources: { 'cadastre' => 1, 'rica' => 3 })

        assert_equal VERSIONS.first(3), retention.expired('cadastre', VERSIONS)
        assert_equal VERSIONS.first(1), retention.expired('rica', VERSIONS)
      end

      def test_keeps_everything_by_default
        assert_empty Retention.new.expired('units', VERSIONS)
      end

      def test_protected_versions_are_never_expired
        retention = Retention.new(default: 1)

        assert_equal %w[2026.10.02.1 2026.10.03.1], retention.expired('units', VERSIONS, protect: ['2026.10.01.1', nil])
      end

      def test_file_gives_default_and_exceptions
        Dir.mktmpdir do |dir|
          file = Pathname.new(dir).join('retention.yml')
          file.write("default: 2\ndatasources:\n  cadastre: 1\n")
          retention = Retention.load(file)

          assert_equal VERSIONS.first(2), retention.expired('units', VERSIONS)
          assert_equal VERSIONS.first(3), retention.expired('cadastre', VERSIONS)
          assert_empty Retention.load(Pathname.new(dir).join('missing.yml')).expired('units', VERSIONS)
        end
      end
    end
  end
end
