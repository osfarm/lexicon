# frozen_string_literal: true

module Lexicon
  module Database
    module Validation
      class DatasourceValidationResult
        attr_reader :validations, :name

        # @param [Hash{Lexicon::Database::Schema::TableDefinition => TableValidationResult}] validations
        def initialize(name, validations)
          @name = name
          @validations = validations
        end

        # @return [Boolean]
        def valid?
          invalid_tables.empty?
        end

        # @return [Array<TableValidationResult>]
        def invalid_tables
          validations.values.reject(&:valid?)
        end
      end
    end
  end
end
