# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class TableDefinitionSet
        # @return [Array<TableDefinition>]
        attr_reader :definitions
        # @return [String]
        attr_reader :name

        # @param [String] name
        # @param [Array<TableDefinition>] definitions
        def initialize(name, definitions)
          @name = name
          @definitions = definitions
        end

        # @return [String]
        def drop_sql
          definitions.map { |t| "DROP TABLE IF EXISTS #{t.name};" }.reverse.join("\n")
        end

        # @return [String]
        def create_sql
          definitions.map(&:sql).join("\n")
        end

        # @return [String]
        def reset_sql
          drop_sql + "\n\n" + create_sql
        end
      end
    end
  end
end
