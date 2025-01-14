# frozen_string_literal: true

module Lexicon
  module Flavor
    class DatasourceFlavor
      # @return [String]
      attr_reader :name
      # @return [Hash{String=>FlavorTable}]
      attr_reader :tables

      # @param [String] name
      # @param [Hash{String=>FlavorTable}] tables
      def initialize(name, tables:)
        @name = name
        @tables = tables
      end

      # @param [String] name
      # @return [FlavorTable, nil]
      def table(name)
        tables.fetch(name, nil)
      end
    end
  end
end
