# frozen_string_literal: true

module Lexicon
  module Database
    module Validation
      class TableValidationResult
        attr_reader :name, :state
        # @return [Hash{Lexicon::Database::Schema::ForeignKey => Symbol}]
        attr_reader :foreign_keys

        # @param [String] name
        # @param [Symbol] state
        # @param [Hash{Lexicon::Database::Schema::ForeignKey => Symbol}] foreign_keys
        def initialize(name, state, foreign_keys)
          @name = name
          @state = state
          @foreign_keys = foreign_keys
        end

        # @return [Boolean]
        def valid?
          state == :ok && foreign_keys.values.all? { |e| e == :ok }
        end
      end
    end
  end
end
