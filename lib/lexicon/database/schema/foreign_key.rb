# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class ForeignKey
        # @return [String]
        attr_reader :table, :column, :target_table, :target_column

        def initialize(table:, column:, target_table:, target_column:)
          @table = table
          @column = column
          @target_table = target_table
          @target_column = target_column
        end
      end
    end
  end
end
