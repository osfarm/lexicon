# frozen_string_literal: true

module Lexicon
  module Datasource
    class SimpleRunner
      include Common::Mixin::LoggerAware

      # @return [Database::Schema::TableDefinitionsFactory]
      attr_reader :table_definition_factory

      # @param [Database::Schema::TableDefinitionsFactory] table_definition_factory
      # @param [ResourceCollector] resource_collector
      # @param [Database::Schema::ForeignKeyManager] fk_manager
      def initialize(table_definition_factory:, resource_collector:, fk_manager:)
        @table_definition_factory = table_definition_factory
        @resource_collector = resource_collector
        @fk_manager = fk_manager
      end

      # @param [Datasources::Base] datasource
      # @param [Symbol] action
      def handle(datasource, action: :run)
        datasource.database.prepend_search_path(datasource.name, :postgis) do
          case action
          when :collect
            collect(datasource)
          when :load
            load_data(datasource)
          when :normalize
            normalize(datasource)
          when :run
            run(datasource)
          else
            raise StandardError.new("Unknown action #{action}")
          end
        end
      end

      private

        # @return [Database::Schema::ForeignKeyManager]
        attr_reader :fk_manager

        # @param [Datasources::Base] datasource
        def run(datasource)
          collect(datasource)
          load_data(datasource)
          normalize(datasource)
        end

        # @param [Datasources::Base] datasource
        def collect(datasource)
          start = Time.now

          if datasource.class.resources.empty?
            datasource.collect
          else
            collect_resources(datasource)
            log 'Collect OK'.green + " #{datasource.name.to_s.yellow} in #{(Time.now - start).round(2)}s"
          end

          log 'Collect OK'.green + " #{datasource.name.to_s.yellow} in #{(Time.now - start).round(2)}s"
        end

        # @param [Datasources::Base] datasource
        def collect_resources(datasource)
          base_dir = datasource.downloader.base_dir

          cache = Cache::ResourceCache.new(root: base_dir, file_hasher: Cache::FileHasher.new)
          cached = CachedResourceCollector.new(collector: @resource_collector, cache: cache)

          datasource.class.resources.each { |r| cached.collect(r, to: base_dir) }
        end

        # @param [Datasources::Base] datasource
        def load_data(datasource)
          start = Time.now

          datasource.database.ensure_schema_empty(datasource.name)

          datasource.load

          log 'Load OK'.green + " #{datasource.name.to_s.yellow} in #{(Time.now - start).round(2)}s"
        end

        # @param [Datasources::Base] datasource
        def normalize(datasource)
          database = datasource.database
          start = Time.now

          definition_set = table_definition_factory.build(datasource.name.to_s, datasource.class)
          return if definition_set.nil? # TODO: Display a meaningful error message

          database.prepend_search_path(:lexicon) do
            begin
              disable_fk_on(database, definition_set)

              backup_tables(database, definition_set)

              datasource.query(definition_set.create_sql)

              datasource.normalize

              begin
                definition_set.definitions.flat_map(&:constraints).each { |fk| fk_manager.create(database, fk) }
              rescue StandardError
                raise StandardError.new("Unable to activate foreign key constraint for datasource #{datasource.name}")
              end

              log 'Normalize OK'.green + " #{datasource.name.to_s.yellow} in #{(Time.now - start).round(2)}s"
            rescue StandardError
              log("Error while normalizing #{datasource.name}".red)

              raise
            ensure
              begin
                attempt_fk_activation_on(database, definition_set)
              rescue PG::ForeignKeyViolation => e
                create_error_schema(database, definition_set)
                restore_backup(database, definition_set)
                attempt_fk_activation_on(database, definition_set)

                log(e)
              end
            end

            clear_backup(database, definition_set)
            clear_error(database, definition_set)
          end
        end

        # @param [Database::Schema::TableDefinitionSet] definition_set
        def backup_schema(definition_set)
          "#{definition_set.name.downcase}__backup"
        end

        # @param [Database::Schema::TableDefinitionSet] definition_set
        def error_schema(definition_set)
          "#{definition_set.name.downcase}__error"
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def backup_tables(database, definition_set)
          present_tables = definition_set.definitions.select { |definition| database.table_exists?(definition.name, schema: :lexicon) }
          return if present_tables.empty?

          backup_schema_name = backup_schema(definition_set)
          log("Backuping #{present_tables.size} tables from 'lexicon' to '#{backup_schema_name}'")

          database.ensure_schema_empty(backup_schema_name)

          present_tables.each do |definition|
            log(" -> #{definition.name}")
            database.query <<~SQL
              ALTER TABLE "lexicon"."#{definition.name}"
                SET SCHEMA "#{backup_schema_name}"
            SQL
          end
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def disable_fk_on(database, definition_set)
          log("Disabling foreign keys on '#{definition_set.name}' for #{definition_set.definitions.map(&:name).join(', ')}")
          definition_set.definitions.each do |table_definition|
            fk_manager.foreign_keys_on(table_definition.name).each do |foreign_key|
              fk_manager.drop(database, foreign_key)
            end
          end
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def attempt_fk_activation_on(database, definition_set)
          log("Enabling foreign keys on '#{definition_set.name}' for #{definition_set.definitions.map(&:name).join(', ')}")
          definition_set.definitions
                        .each do |table_definition|
                          fk_manager.foreign_keys_on(table_definition.name).each do |foreign_key|
                            if database.table_exists?(foreign_key.table)
                              fk_manager.create(database, foreign_key)
                            end
                          end
                        end
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def create_error_schema(database, definition_set)
          error_schema_name = error_schema(definition_set)
          database.ensure_schema_empty(error_schema_name)

          definition_set.definitions.each do |definition|
            database.query <<~SQL
              ALTER TABLE "lexicon"."#{definition.name}"
                SET SCHEMA "#{error_schema_name}"
            SQL
          end
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def restore_backup(database, definition_set)
          backup_schema_name = backup_schema(definition_set)
          return if !database.schema_exists?(backup_schema_name)

          definition_set.definitions.each do |definition|
            database.query <<~SQL
              ALTER TABLE "#{backup_schema_name}"."#{definition.name}"
                SET SCHEMA "lexicon"
            SQL
          end
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def clear_backup(database, definition_set)
          backup_schema_name = backup_schema(definition_set)
          database.drop_schema(backup_schema_name, cascade: true, if_exists: true)
        end

        # @param [Database::Database] database
        # @param [Database::Schema::TableDefinitionSet] definition_set
        def clear_error(database, definition_set)
          error_schema_name = error_schema(definition_set)
          database.drop_schema(error_schema_name, cascade: true, if_exists: true)
        end
    end
  end
end
