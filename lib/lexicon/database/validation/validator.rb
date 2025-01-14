# frozen_string_literal: true

module Lexicon
  module Database
    module Validation
      class Validator
        # @return [Schema::ForeignKeyManager]
        attr_reader :database_factory, :definitions, :fk_manager, :db_url

        # @param [Schema::ForeignKeyManager] fk_manager
        def initialize(database_factory:, definitions:, fk_manager:, db_url:)
          @database_factory = database_factory
          @definitions = definitions
          @fk_manager = fk_manager
          @db_url = db_url
        end

        def validate_datasources
          database = database_factory.new_instance(url: db_url)

          definitions.map { |definition| validate_definition(database, definition) }
        end

        # @param [Database] database
        # @param [Schema::TableDefinitionSet] definition
        # @return [DatasourceValidationResult]
        def validate_definition(database, definition)
          DatasourceValidationResult.new(
            definition.name,
            definition
              .definitions
              .map { |table| [table, validate_table(database, table)] }
              .to_h
          )
        end

        # @param [Common::Database::Database] database
        # @param [Schema::TableDefinition] table
        # @return [TableValidationResult]
        def validate_table(database, table)
          res = database.query <<~SQL
            SELECT * FROM lexicon.#{table.name} LIMIT 1;
          SQL

          state = if res.cmd_tuples.zero?
                    :empty
                  else
                    :ok
                  end

          TableValidationResult.new(
            table.name,
            state,
            table.constraints
                 .map { |foreign_key| [foreign_key, validate_foreign_key(database, foreign_key)] }
                 .to_h
          )
        rescue PG::UndefinedTable => e
          TableValidationResult.new(table.name, :missing, {})
        end

        # @param [Database] database
        # @param [Schema::ForeignKey] foreign_key
        # @return [Symbol]
        def validate_foreign_key(database, foreign_key)
          database.prepend_search_path('lexicon') do
            fk_manager.fk_exists?(database, foreign_key) ? :ok : :missing
          end
        end

      end
    end
  end
end
