# frozen_string_literal: true

module Lexicon
  module Datasource
    class Resource
      attr_reader :name

      # @param [String] name
      def initialize(name)
        @name = name
      end

      alias key name
    end
  end
end
