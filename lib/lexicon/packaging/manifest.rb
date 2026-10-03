# frozen_string_literal: true

require 'json'
require 'time'

module Lexicon
  module Packaging
    # Describes one version of one datasource package. Written last in the package directory:
    # a directory without manifest is not a package.
    class Manifest
      FORMAT = 3
      FILE_NAME = 'manifest.json'

      # @return [String]
      attr_reader :name, :version, :structure_hash, :tool_version
      # @return [Integer]
      attr_reader :schema_revision
      # @return [Time]
      attr_reader :built_at
      # @return [String, nil]
      attr_reader :flavor
      # @return [Array<Hash>]
      attr_reader :credits, :depends_on, :tables, :foreign_keys

      class << self
        # @param [Pathname] file
        # @return [Manifest]
        def load(file)
          data = JSON.parse(file.read, symbolize_names: true)
          if data[:format] != FORMAT
            raise ArgumentError.new("Unsupported package format #{data[:format].inspect} in #{file}")
          end

          new(**data.except(:format), built_at: Time.iso8601(data.fetch(:built_at)))
        end
      end

      def initialize(name:, version:, schema_revision:, structure_hash:, built_at:, tool_version:,
                     credits:, depends_on:, tables:, foreign_keys:, flavor: nil)
        @name = name
        @version = version
        @schema_revision = schema_revision
        @structure_hash = structure_hash
        @built_at = built_at
        @tool_version = tool_version
        @flavor = flavor
        @credits = credits
        @depends_on = depends_on
        @tables = tables
        @foreign_keys = foreign_keys
      end

      # @return [Hash]
      def to_h
        {
          format: FORMAT,
          name: name,
          version: version,
          schema_revision: schema_revision,
          structure_hash: structure_hash,
          built_at: built_at.utc.iso8601,
          tool_version: tool_version,
          flavor: flavor,
          credits: credits,
          depends_on: depends_on,
          tables: tables,
          foreign_keys: foreign_keys
        }
      end

      # @return [String]
      def to_json(*_args)
        JSON.pretty_generate(to_h)
      end

      # @param [Pathname] dir
      def write(dir)
        dir.join(FILE_NAME).write("#{to_json}\n")
      end
    end
  end
end
