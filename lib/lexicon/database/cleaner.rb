# frozen_string_literal: true

module Lexicon
  module Database
    class Cleaner
      def initialize(database)
        @database = database
      end

      def clean(*datasource_classes)
        datasource_classes.each { |klass| clean_schema(klass.datasource_name) }
      end

      def clean_lexicon(*datasources_class)
        datasources_class.each { |klass| @database.query(klass.table_builder.drop_sql) }
      end

      def clean_schema(schema)
        @database.query(<<-SQL)
          DROP SCHEMA IF EXISTS #{schema} CASCADE;
        SQL
      end
    end
  end
end
