# frozen_string_literal: true

module Lexicon
  module Datasource
    class LocalResource < Resource
      attr_reader :source

      def initialize(name, source:)
        super(name)

        @source = source
      end
    end
  end
end
