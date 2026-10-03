# frozen_string_literal: true

require 'yaml'

module Lexicon
  module Packaging
    # How many versions of each datasource the repository keeps.
    class Retention
      ALL = 'all'

      # @param [Pathname] file
      # @return [Retention]
      def self.load(file)
        data = file.file? ? YAML.safe_load(file.read) : {}

        new(default: data.fetch('default', ALL), datasources: data.fetch('datasources', {}))
      end

      # @param [Integer, String] default
      # @param [Hash{String => Integer, String}] datasources
      def initialize(default: ALL, datasources: {})
        @default = default
        @datasources = datasources
      end

      # @param [String] name
      # @param [Array<String>] versions oldest first
      # @param [Array<String, nil>] protect versions kept whatever their age
      # @return [Array<String>] versions that can be deleted
      def expired(name, versions, protect: [])
        keep = @datasources.fetch(name, @default)
        return [] if keep == ALL

        versions - versions.last(Integer(keep)) - protect
      end
    end
  end
end
