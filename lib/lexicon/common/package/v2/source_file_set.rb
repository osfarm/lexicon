# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      module V2
        class SourceFileSet
          include Mixin::Nameable

          attr_reader :id, :name, :structure, :tables

          # @param [String] id
          # @param [String] name
          # @param [String] structure
          # @param [Hash{String=>Array<String>}] tables
          def initialize(id:, name:, structure:, tables:)
            @id = id
            @name = name
            @structure = structure
            @tables = tables.freeze
          end
        end
      end
    end
  end
end
