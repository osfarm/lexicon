# frozen_string_literal: true

module Lexicon
  module Server
    # Reads the state of the served schema in the Postgres catalog.
    class Catalog
      # @param [PG::Connection] connection
      def initialize(connection)
        @connection = connection
      end

      # @param [Array<String>] tables
      # @return [Array<String>] the ones existing in the served schema
      def existing_tables(tables)
        connection.exec_params(<<~SQL, [Meta::SERVED_SCHEMA, encode(tables)]).map { |row| row['tablename'] }
          SELECT tablename::varchar FROM pg_tables WHERE schemaname = $1 AND tablename = ANY($2::varchar[]) ORDER BY 1
        SQL
      end

      # Foreign keys of served tables that are not replaced, pointing to tables that are.
      #
      # @param [Array<String>] replaced
      # @return [Array<Hash>] with 'referencing' (qualified table), 'table', 'column', 'name', 'definition',
      #   'target' and 'target_column'
      def inbound_foreign_keys(replaced)
        return [] if replaced.empty?

        connection.exec_params(<<~SQL, [Meta::SERVED_SCHEMA, encode(replaced)]).to_a
          SELECT pg_catalog.format('%I.%I', referencing_namespace.nspname, referencing.relname) AS referencing,
                 referencing.relname::text AS table,
                 referencing_column.attname::text AS column,
                 pg_constraint.conname::text AS name,
                 pg_catalog.pg_get_constraintdef(pg_constraint.oid) AS definition,
                 target.relname::text AS target,
                 target_column.attname::text AS target_column
            FROM pg_catalog.pg_constraint
            JOIN pg_catalog.pg_class target ON target.oid = pg_constraint.confrelid
            JOIN pg_catalog.pg_namespace target_namespace ON target_namespace.oid = target.relnamespace
            JOIN pg_catalog.pg_class referencing ON referencing.oid = pg_constraint.conrelid
            JOIN pg_catalog.pg_namespace referencing_namespace ON referencing_namespace.oid = referencing.relnamespace
            JOIN pg_catalog.pg_attribute referencing_column
              ON referencing_column.attrelid = referencing.oid AND referencing_column.attnum = pg_constraint.conkey[1]
            JOIN pg_catalog.pg_attribute target_column
              ON target_column.attrelid = target.oid AND target_column.attnum = pg_constraint.confkey[1]
           WHERE pg_constraint.contype = 'f'
             AND target_namespace.nspname = $1
             AND target.relname = ANY($2::varchar[])
             AND NOT (referencing_namespace.nspname = $1 AND referencing.relname = ANY($2::varchar[]))
           ORDER BY 1, 4
        SQL
      end

      # Views that would be dropped with the tables, or left pointing to them.
      #
      # @param [Array<String>] tables
      # @param [Array<String>] except views of the served schema the loader rebuilds itself
      # @return [Array<Hash>] with 'view' and 'table'
      def dependent_views(tables, except: [])
        connection.exec_params(<<~SQL, [Meta::SERVED_SCHEMA, encode(tables), encode(except)]).to_a
          SELECT DISTINCT pg_catalog.format('%s.%s', dependent_namespace.nspname, dependent.relname) AS view,
                 source.relname::text AS table
            FROM pg_catalog.pg_depend
            JOIN pg_catalog.pg_rewrite ON pg_rewrite.oid = pg_depend.objid
            JOIN pg_catalog.pg_class dependent ON dependent.oid = pg_rewrite.ev_class
            JOIN pg_catalog.pg_namespace dependent_namespace ON dependent_namespace.oid = dependent.relnamespace
            JOIN pg_catalog.pg_class source ON source.oid = pg_depend.refobjid
            JOIN pg_catalog.pg_namespace source_namespace ON source_namespace.oid = source.relnamespace
           WHERE pg_depend.classid = 'pg_catalog.pg_rewrite'::regclass
             AND pg_depend.refclassid = 'pg_catalog.pg_class'::regclass
             AND source_namespace.nspname = $1
             AND source.relname = ANY($2::varchar[])
             AND dependent.oid <> source.oid
             AND NOT (dependent_namespace.nspname = $1 AND dependent.relname = ANY($3::varchar[]))
           ORDER BY 1, 2
        SQL
      end

      private

        # @return [PG::Connection]
        attr_reader :connection

        def encode(values)
          PG::TextEncoder::Array.new.encode(values)
        end
    end
  end
end
