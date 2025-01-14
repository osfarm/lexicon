# frozen_string_literal: true

module Lexicon
  module Database
    module Validation
      class DatasourceValidationResult
        attr_reader :validations, :name

        # @param [Hash{Lexicon::Database::Schema::TableDefinition => Symbol}] validations
        def initialize(name, validations)
          @name = name
          @validations = validations
        end

        # @return [Boolean]
        def valid?
          validations.values.all? { |e| e == :ok }
        end
      end
    end
  end
end
