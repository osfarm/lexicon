# frozen_string_literal: true

module Lexicon
  module Server
    # Decides whether a package can replace the version in service.
    class Checker
      # A new version keeping less than this share of the rows of a table is suspicious
      MINIMUM_ROWS_RATIO = 0.7

      # @param [PG::Connection] connection
      # @param [Meta] meta
      def initialize(connection, meta:)
        @connection = connection
        @meta = meta
      end

      # Checks made before staging, to fail fast on packages that take hours to load.
      #
      # @param [Packaging::Manifest] manifest
      # @param [Meta::Installed, nil] installed
      # @param [Boolean] force accept a drop of volume
      # @return [Array<String>] reasons to refuse the package
      def before_staging(manifest, installed:, force: false)
        [
          *foreign_owners(manifest),
          *missing_dependencies(manifest),
          *(force ? [] : volume_drops(manifest, installed)),
          *foreign_dependents(replaced_tables(manifest, installed))
        ]
      end

      # @param [Packaging::Manifest] manifest
      # @param [Hash{String => Integer}] loaded rows loaded in staging for each table
      # @return [Array<String>]
      def after_staging(manifest, loaded:)
        manifest.tables.reject { |table| loaded[table[:name]] == table[:rows] }.map do |table|
          "#{table[:name]}: #{loaded[table[:name]].inspect} rows loaded, #{table[:rows]} expected"
        end
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [Meta]
        attr_reader :meta

        def replaced_tables(manifest, installed)
          previous = installed.nil? ? [] : installed.manifest[:tables].map { |table| table[:name] }

          (previous + manifest.tables.map { |table| table[:name] }).uniq
        end

        def foreign_owners(manifest)
          meta.owners(manifest.tables.map { |table| table[:name] })
              .reject { |_table, package| package == manifest.name }
              .map { |table, package| "#{table} already belongs to the package #{package}" }
        end

        def missing_dependencies(manifest)
          manifest.depends_on
                  .select { |dependency| dependency[:kind] == Packaging::DependencyResolver::FOREIGN_KEY }
                  .reject { |dependency| meta.installed(dependency[:name]) }
                  .map { |dependency| "the package #{dependency[:name]} it references is not in service" }
        end

        def volume_drops(manifest, installed)
          return [] if installed.nil?

          previous = installed.manifest[:tables].map { |table| [table[:name], table[:rows]] }.to_h

          manifest.tables.select { |table| previous.fetch(table[:name], 0) * MINIMUM_ROWS_RATIO > table[:rows] }.map do |table|
            "#{table[:name]}: #{table[:rows]} rows, #{previous[table[:name]]} in service (use --force to accept)"
          end
        end

        # Views that would be dropped or left pointing to the replaced tables
        def foreign_dependents(tables)
          connection.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(tables), Meta::SERVED_SCHEMA]).map { |row| row['message'] }
            SELECT DISTINCT format('the view %s.%s depends on %s', dependent_namespace.nspname, dependent.relname, source.relname) AS message
              FROM pg_depend
              JOIN pg_rewrite ON pg_rewrite.oid = pg_depend.objid
              JOIN pg_class dependent ON dependent.oid = pg_rewrite.ev_class
              JOIN pg_namespace dependent_namespace ON dependent_namespace.oid = dependent.relnamespace
              JOIN pg_class source ON source.oid = pg_depend.refobjid
              JOIN pg_namespace source_namespace ON source_namespace.oid = source.relnamespace
             WHERE pg_depend.classid = 'pg_rewrite'::regclass
               AND pg_depend.refclassid = 'pg_class'::regclass
               AND source_namespace.nspname = $2
               AND source.relname = ANY($1::varchar[])
               AND dependent.oid <> source.oid
             ORDER BY 1
          SQL
        end
    end
  end
end
