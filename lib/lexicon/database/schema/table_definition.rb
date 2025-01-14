# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class TableDefinition
        # @return [String]
        attr_reader :name, :sql
        # @return [Array<ForeignKey>]
        attr_reader :constraints

        # @param [String] name
        # @param [String] sql
        def initialize(name, sql)
          @name = name
          @sql = sql
          @constraints = []
        end

        def references(**constraints)
          @constraints = constraints.map do |column, (target_table, target_column)|
            ForeignKey.new(
              table: name,
              column: column.to_s,
              target_table: target_table.to_s,
              target_column: target_column.to_s
            )
          end
        end
      end
    end
  end
end
