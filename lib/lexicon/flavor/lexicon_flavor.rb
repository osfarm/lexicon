# frozen_string_literal: true

module Lexicon
  module Flavor
    class LexiconFlavor
      # @return [Hash{String=>DatasourceFlavor}]
      attr_reader :datasources
      # @return [String]
      attr_reader :name
      # @return [Array<String>, nil]
      attr_reader :only
      # @return [Array<String>]
      attr_reader :without

      # @param [String] name
      # @param [Array<String>, nil] only
      # @param [Array<String>] without
      # @param [Hash{String=>DatasourceFlavor}] datasources
      def initialize(name, only: nil, without: [], datasources: [])
        @name = name
        @only = only
        @without = without
        @datasources = datasources
      end

      # @param [Array<String>, nil] only
      # @return [self]
      def merge(only: nil)
        merged_only = if self.only.nil? && only.nil?
                        nil
                      else
                        [*(self.only || []), *(only || [])]
                      end

        LexiconFlavor.new(
          name,
          only: merged_only,
          without: without,
          datasources: datasources
        )
      end

      # @param [String]
      # @return [DatasourceFlavor, nil]
      def datasource(name)
        datasources.fetch(name, nil)
      end

      PLACEHOLDER = /%\{([a-z_]+)\}/.freeze
      # Values end up in SQL filters: numbers, words and coordinates only
      SAFE_VALUE = /\A[\w .,-]+\z/.freeze

      # @return [Array<String>] names of the parameters the filters expect, such as a point and a radius
      def parameters
        datasources.to_h.values.flat_map { |datasource| datasource.tables.values }
                   .flat_map { |table| table.filter.scan(PLACEHOLDER).flatten }.uniq.sort
      end

      # Gives the flavor whose filters have their %{parameters} replaced by the values.
      #
      # @param [Hash{String => String}] values
      # @param [String, nil] name name of the resulting flavor
      # @return [LexiconFlavor]
      def with_parameters(values, name: nil)
        missing = parameters - values.keys
        raise ArgumentError.new("Missing parameters: #{missing.join(', ')}") if missing.any?

        unsafe = values.reject { |_key, value| value.to_s.match?(SAFE_VALUE) }.keys
        raise ArgumentError.new("Invalid value for: #{unsafe.join(', ')}") if unsafe.any?

        filled = datasources.to_h.transform_values do |datasource|
          tables = datasource.tables.transform_values do |table|
            FlavorTable.new(table.name, filter: table.filter.gsub(PLACEHOLDER) { values.fetch(Regexp.last_match(1)).to_s })
          end

          DatasourceFlavor.new(datasource.name, tables: tables)
        end

        LexiconFlavor.new(name || self.name, only: only, without: without, datasources: filled)
      end
    end
  end
end
