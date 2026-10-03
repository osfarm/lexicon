# frozen_string_literal: true

module Lexicon
  module Server
    # Decides whether packages can replace the versions in service.
    class Checker
      # A new version keeping less than this share of the rows of a table is suspicious
      MINIMUM_ROWS_RATIO = 0.7
      # Orphan values shown for a broken reference
      SAMPLE_SIZE = 5

      # @param [PG::Connection] connection
      # @param [Meta] meta
      # @param [Catalog] catalog
      def initialize(connection, meta:, catalog:)
        @connection = connection
        @meta = meta
        @catalog = catalog
      end

      # Checks made before staging, to fail fast on packages that take hours to load.
      #
      # @param [Packaging::Manifest] manifest
      # @param [Meta::Installed, nil] installed
      # @param [Boolean] force accept a drop of volume
      # @param [Array<String>] together packages put in service in the same swap
      # @return [Array<String>] reasons to refuse the package
      def before_staging(manifest, installed:, force: false, together: [])
        [
          *foreign_owners(manifest),
          *missing_dependencies(manifest, together),
          *(force ? [] : volume_drops(manifest, installed)),
          *dependent_views(replaced_tables([manifest]))
        ]
      end

      # @param [Array<Packaging::Manifest>] manifests packages staged, to swap together
      # @param [Hash{String => Integer}] loaded rows loaded in staging for each table
      # @return [Array<String>]
      def after_staging(manifests, loaded:)
        staged = manifests.flat_map { |manifest| table_names(manifest) }

        [
          *manifests.flat_map { |manifest| row_counts(manifest, loaded) },
          *manifests.flat_map { |manifest| outbound_orphans(manifest, staged) },
          *inbound_orphans(replaced_tables(manifests), staged)
        ]
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [Meta]
        attr_reader :meta
        # @return [Catalog]
        attr_reader :catalog

        def table_names(manifest)
          manifest.tables.map { |table| table[:name] }
        end

        # Tables in service that the swap drops: the ones of the previous versions, and the new ones
        def replaced_tables(manifests)
          manifests.flat_map { |manifest| meta.tables_of(manifest.name) + table_names(manifest) }.uniq
        end

        def foreign_owners(manifest)
          meta.owners(table_names(manifest))
              .reject { |_table, package| package == manifest.name }
              .map { |table, package| "#{table} already belongs to the package #{package}" }
        end

        def missing_dependencies(manifest, together)
          manifest.depends_on
                  .select { |dependency| dependency[:kind] == Packaging::DependencyResolver::FOREIGN_KEY }
                  .reject { |dependency| together.include?(dependency[:name]) || meta.installed(dependency[:name]) }
                  .map { |dependency| "the package #{dependency[:name]} it references is not in service" }
        end

        def volume_drops(manifest, installed)
          return [] if installed.nil?

          previous = installed.manifest[:tables].map { |table| [table[:name], table[:rows]] }.to_h

          manifest.tables.select { |table| previous.fetch(table[:name], 0) * MINIMUM_ROWS_RATIO > table[:rows] }.map do |table|
            "#{table[:name]}: #{table[:rows]} rows, #{previous[table[:name]]} in service (use --force to accept)"
          end
        end

        def dependent_views(tables)
          catalog.dependent_views(tables, except: DerivedViews::NAMES).map do |row|
            "the view #{row['view']} depends on #{row['table']}"
          end
        end

        def row_counts(manifest, loaded)
          manifest.tables.reject { |table| loaded[table[:name]] == table[:rows] }.map do |table|
            "#{table[:name]}: #{loaded[table[:name]].inspect} rows loaded, #{table[:rows]} expected"
          end
        end

        # References of the staged tables, to staged tables or to tables in service
        def outbound_orphans(manifest, staged)
          manifest.foreign_keys.flat_map do |key|
            target_schema = staged.include?(key[:references_table]) ? Meta::STAGING_SCHEMA : Meta::SERVED_SCHEMA

            orphans(
              from: [Meta::STAGING_SCHEMA, key[:table], key[:column]],
              to: [target_schema, key[:references_table], key[:references_column]]
            )
          end
        end

        # References of tables that stay in service, to the tables about to be replaced
        def inbound_orphans(replaced, staged)
          catalog.inbound_foreign_keys(catalog.existing_tables(replaced)).flat_map do |key|
            if staged.include?(key['target'])
              orphans(
                from: [Meta::SERVED_SCHEMA, key['table'], key['column']],
                to: [Meta::STAGING_SCHEMA, key['target'], key['target_column']]
              )
            else
              ["#{key['table']}.#{key['column']} references #{key['target']}, which the new version removes"]
            end
          end
        end

        # @param [Array<String>] from schema, table and column of the reference
        # @param [Array<String>] to schema, table and column referenced
        # @return [Array<String>] one reason if some values have no match, none otherwise
        def orphans(from:, to:)
          source = %("#{from[0]}"."#{from[1]}")
          target = %("#{to[0]}"."#{to[1]}")
          values = connection.exec(<<~SQL).map { |row| row['value'] }
            SELECT DISTINCT source."#{from[2]}"::text AS value
              FROM #{source} AS source
             WHERE source."#{from[2]}" IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM #{target} AS target WHERE target."#{to[2]}" = source."#{from[2]}")
             ORDER BY 1
             LIMIT #{SAMPLE_SIZE + 1}
          SQL
          return [] if values.empty?

          sample = values.first(SAMPLE_SIZE).join(', ') + (values.size > SAMPLE_SIZE ? ', …' : '')

          ["#{from[1]}.#{from[2]} has values missing from #{to[1]}.#{to[2]}: #{sample}"]
        rescue PG::UndefinedTable
          ["#{from[1]}.#{from[2]} references #{to[1]}, which is not in service"]
        end
    end
  end
end
