# frozen_string_literal: true

module Lexicon
  module Common
    module Production
      class TableLocker
        include Mixin::SchemaNamer

        # @param [Database::Factory] database_factory
        # @param [String] database_url
        def initialize(database_factory:, database_url:)
          @database_factory = database_factory
          @database_url = database_url
        end

        # @param [Package::Package] package
        # @param [Array<String>] tables
        def lock_tables(package:, tables: [])
          database = database_factory.new_instance(url: database_url)

          schema = version_to_schema(package.version)

          database.prepend_search_path schema do
            database.query <<~SQL
              CREATE OR REPLACE FUNCTION #{schema}.deny_changes()
                RETURNS TRIGGER
              AS $$
                BEGIN
                  RAISE EXCEPTION '% denied on % (master data)', TG_OP, TG_RELNAME;
                END;
              $$
              LANGUAGE plpgsql;
            SQL
            tables.each do |table_name|
              database.query <<~SQL
                CREATE TRIGGER deny_changes
                  BEFORE INSERT
                      OR UPDATE
                      OR DELETE
                      OR TRUNCATE
                  ON #{schema}.#{table_name}
                  FOR EACH STATEMENT
                    EXECUTE PROCEDURE #{schema}.deny_changes()
              SQL
            end
          end
        end

        private

          # @return [Database::Factory]
          attr_reader :database_factory
          # @return [String]
          attr_reader :database_url
      end
    end
  end
end
