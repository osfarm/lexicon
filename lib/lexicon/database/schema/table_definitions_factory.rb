# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class TableDefinitionsFactory
        # @param [String] name
        # @param [Class<Datasources::Base>] klass
        # @return [TableDefinitionSet]
        def build(name, klass)
          if klass.respond_to?(:table_definitions)
            builder = TableBuilder.new
            klass.table_definitions(builder)

            TableDefinitionSet.new(name, builder.tables)
          else
            nil
          end
        end
      end
    end
  end
end
