# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class TableBuilder
        attr_reader :tables

        def initialize
          @tables = []
        end

        # @param [#to_s] name
        # @param [String] sql
        def table(name, sql:)
          definition = TableDefinition.new(name.to_s, sql)

          @tables << definition

          definition
        end
      end
    end
  end
end
