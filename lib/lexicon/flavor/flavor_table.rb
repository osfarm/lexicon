# frozen_string_literal: true

module Lexicon
  module Flavor
    class FlavorTable
      # @return [String]
      attr_reader :name
      # @return [String]
      attr_reader :filter

      # @param [String] name
      # @param [String] filter
      def initialize(name, filter:)
        @filter = filter
        @name = name
      end
    end
  end
end
