# frozen_string_literal: true

module Lexicon
  module Database
    module Schema
      class ForeignKeyManager
        include Common::Mixin::LoggerAware
        # @param [Array<TableDefinitionSet>] definitions
        def initialize(definitions)
          @definitions = definitions
        end

        # @param [String] target_table
        # @return [Array<ForeignKey>]
        def foreign_keys_on(target_table)
          foreign_keys = []

          definitions.each do |definition_set|
            definition_set.definitions.each do |table_definition|
              table_definition.constraints.each do |foreign_key|
                if foreign_key.target_table == target_table
                  foreign_keys << foreign_key
                end
              end
            end
          end

          foreign_keys
        end

        # @param [Database::Datatase] database
        # @param [ForeignKey] foreign_key
        def drop(database, foreign_key)
          if fk_exists?(database, foreign_key)
            database.query <<~SQL
              ALTER TABLE "#{foreign_key.table}"
              DROP CONSTRAINT "#{fk_name(foreign_key)}"
            SQL
          end
        end

        # @param [Database::Database] database
        # @param [ForeignKey] foreign_key
        def create(database, foreign_key)
          log("Start Creating FK #{fk_name(foreign_key)}".green)
          if fk_exists?(database, foreign_key)
            log("FK already exist #{fk_name(foreign_key)}".green)
          else
            database.query <<~SQL
              ALTER TABLE "#{foreign_key.table}"
              ADD CONSTRAINT "#{fk_name(foreign_key)}"
              FOREIGN KEY ("#{foreign_key.column}")
              REFERENCES "#{foreign_key.target_table}"("#{foreign_key.target_column}")
            SQL
          end
        end

        # @param [Database::Database] database
        # @param [ForeignKey] foreign_key
        # @return [Boolean]
        def fk_exists?(database, foreign_key)
          database.query(<<~SQL, fk_name(foreign_key), database.search_path.first).count > 0
            SELECT constraint_name
            FROM "information_schema"."constraint_column_usage"
            WHERE constraint_name = $1 AND table_schema = $2
          SQL
        end

        private

          # @param [ForeignKey] foreign_key
          # @return [String]
          def fk_name(foreign_key)
            computed_name = "#{foreign_key.table.downcase}__#{foreign_key.column.downcase}"
            computed_name += "__#{foreign_key.target_table.downcase}__#{foreign_key.target_column.downcase}"
            hash = Digest::MD5.hexdigest(computed_name)

            "fk_#{hash}"
          end

          def table_to_definition
            @table_to_definition ||=
              definitions.reduce({}) do |coll, definition|
                definition.definitions.each do |table_definition|
                  coll[table_definition.name] = definition
                end
              end
          end

          # @return [Array<TableDefinitionSet>]
          attr_reader :definitions
      end
    end
  end
end
