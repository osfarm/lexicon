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
    end
  end
end
