# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class TableDefinitionDumpPreset
        # @return [TableDefinition]
        attr_reader :definition
        # @return [Flavor::FlavorTable, nil]
        attr_reader :flavor_table

        # @param [TableDefinition] definition
        # @param [Flavor::FlavorTable, nil] flavor_table
        def initialize(definition:, flavor_table:)
          @definition = definition
          @flavor_table = flavor_table
        end
      end
    end
  end
end
