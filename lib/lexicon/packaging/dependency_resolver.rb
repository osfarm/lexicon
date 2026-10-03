# frozen_string_literal: true

module Lexicon
  module Packaging
    # Finds the datasources a datasource depends on: the owners of the tables its foreign keys
    # target, and the ones it declares reading during normalize.
    class DependencyResolver
      FOREIGN_KEY = 'foreign_key'
      NORMALIZE = 'normalize'

      # @param [Array<Database::Schema::TableDefinitionSet>] definitions
      def initialize(definitions)
        @owners = definitions.flat_map { |set| set.definitions.map { |table| [table.name, set.name] } }.to_h
      end

      # @param [Database::Schema::TableDefinitionSet] definition_set
      # @param [Array<String>] declared
      # @return [Array<Hash>] ordered by name, each with :name and :kind
      def resolve(definition_set, declared: [])
        by_foreign_key = foreign_keys(definition_set).map { |foreign_key| owner_of(foreign_key.target_table) }.uniq
        by_foreign_key.delete(definition_set.name)
        by_normalize = declared - by_foreign_key - [definition_set.name]

        [
          *by_foreign_key.map { |name| { name: name, kind: FOREIGN_KEY } },
          *by_normalize.map { |name| { name: name, kind: NORMALIZE } }
        ].sort_by { |dependency| dependency[:name] }
      end

      # @param [Database::Schema::TableDefinitionSet] definition_set
      # @return [Array<Database::Schema::ForeignKey>]
      def foreign_keys(definition_set)
        definition_set.definitions.flat_map(&:constraints)
      end

      private

        def owner_of(table)
          @owners.fetch(table) { raise ArgumentError.new("No datasource defines the table #{table}") }
        end
    end
  end
end
