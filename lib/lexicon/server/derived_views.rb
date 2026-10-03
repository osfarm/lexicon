# frozen_string_literal: true

module Lexicon
  module Server
    # Views of the served schema built from the packages in service. They depend on tables that get
    # replaced, so they are dropped and rebuilt in the transaction of each swap.
    class DerivedViews
      TRANSLATIONS = 'master_translations'
      NAMES = [TRANSLATIONS].freeze

      # @param [PG::Connection] connection
      # @param [Meta] meta
      def initialize(connection, meta:)
        @connection = connection
        @meta = meta
      end

      def drop
        connection.exec(%(DROP VIEW IF EXISTS #{qualified(TRANSLATIONS)}))
      end

      # The union of the translations each package in service ships
      def create
        selects = meta.tables_with_role(Packaging::Builder::TRANSLATIONS_ROLE).map do |table|
          "SELECT id, fra, eng FROM #{qualified(table)}"
        end
        selects << 'SELECT NULL::varchar AS id, NULL::varchar AS fra, NULL::varchar AS eng WHERE false' if selects.empty?

        connection.exec("CREATE VIEW #{qualified(TRANSLATIONS)} AS #{selects.join(' UNION ALL ')}")
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [Meta]
        attr_reader :meta

        def qualified(name)
          %("#{Meta::SERVED_SCHEMA}"."#{name}")
        end
    end
  end
end
