# frozen_string_literal: true

module Lexicon
  module Database
    class DataDumper
      include Common::Mixin::LoggerAware
      include Common::Mixin::SchemaNamer

      def initialize(shell:, db_url:, datasource_classes:, database_factory:, credits_builder:, table_definitions:, package_creator:, psql:)
        @shell = shell
        @db_url = db_url
        @datasource_classes = datasource_classes
        @database_factory = database_factory
        @credits_builder = credits_builder
        @table_definitions = table_definitions
        @package_creator = package_creator
        @psql = psql
      end

      # @param [Flavor::LexiconFlavor, nil] base
      # @param [Array<String>, nil] only
      # @return [Flavor::LexiconFlavor]
      def make_custom_flavor(base: nil, only: nil)
        if base.nil?
          Flavor::LexiconFlavor.new('Custom', only: only)
        else
          base.merge(only: only)
        end
      end

      # @return [PsqlWrapper]
      attr_reader :psql

      # @param [Flavor::LexiconFlavor] flavor
      # @param [String] set_name
      # @param [String] table_name
      # @return [Flavor::FlavorTable, nil]
      def fetch_flavor_table(flavor, set_name:, table_name:)
        flavor.datasource(set_name.to_s)&.table(table_name.to_s)
      end

      # @param [Semantic::Version] version
      # @param [Array<String>, nil] only
      #   If nil, data from all sources is included
      #   If present, only listed listed sources have their data.
      #   Structure for all sources are always included
      # @param [Boolean] force
      # @param [Flavor::LexiconFlavor, nil] flavor
      # @return [Common::Package::Package, nil]
      def make_package(version, only: nil, force: false, flavor: nil)
        specific_flavor = make_custom_flavor(base: flavor, only: only)

        database = database_factory.new_instance(url: db_url)

        package_creator.create_package(version, force: force) do |package, temp_dir|
          data_files = Concurrent::Hash.new

          build_credits(database, filter_classes(only))

          with_renamed_schema(database, :lexicon, to: version_to_schema(version)) do |version_schema|
            definition_sets = filter_definitions(specific_flavor)
            table_definitions = make_dump_presets(definition_sets, specific_flavor)

            remaining = Concurrent::Set.new(table_definitions.map(&:definition))
            threads = table_definitions.map do |tddp|
              table = tddp.definition

              Thread.new do
                puts "Dumping #{table.name.to_s.yellow}..."

                file = Pathname.new(Tempfile.new('', temp_dir))

                psql.execute_raw(<<~PSQL)
                  \\copy (SELECT * FROM "#{version_schema}"."#{table.name}" #{filter_from_table_flavor(tddp.flavor_table)}) TO PROGRAM 'pigz > #{file}' WITH csv
                PSQL

                data_files[table.name] = file

                remaining.delete(table)
                puts "Done #{table.name.to_s.green}, #{remaining_message(remaining)}"
              end
            end

            threads.each(&:join)
          end

          table_definitions.each do |definition|
            structure_file = Pathname.new(Tempfile.new('', temp_dir))
            structure_file.open('w') do |f|
              f.write(definition.reset_sql)
            end

            tables_files = definition.definitions.flat_map do |table|
              file = data_files[table.name]

              if file&.exist?
                [[table.name, [file]]]
              else
                []
              end
            end

            package.add_file_set(
              definition.name,
              name: definition.name,
              structure: structure_file,
              tables: tables_files.to_h
            )
          end
        end
      end

      private

        # @return [Array<Schema::TableDefinitionSet>]
        attr_reader :table_definitions
        # @return [Package::PackageCreator]
        attr_reader :package_creator
        # @return [Common::Database::Factory]
        attr_reader :database_factory
        # @return [String]
        attr_reader :db_url

        # @param [FLavor::TableFlavor] table_flavor
        def filter_from_table_flavor(table_flavor)
          if table_flavor.nil?
            ''
          else
            table_flavor.filter
          end
        end

        def remaining_message(remaining)
          if remaining.size > 5
            "#{remaining.size} remaining"
          else
            "Remaining: #{remaining.to_a.map(&:name).join(', ')}"
          end
        end

        def build_credits(database, datasources)
          log("Building credits for #{datasources.map(&:name).join(', ')}")
          database.prepend_search_path :lexicon do
            credits_definition = table_definitions.detect { |d| d.name == 'datasource_credits' }
            database.query(credits_definition.reset_sql)

            datasources.each do |datasource|
              @credits_builder.build(datasource, database: database)
            end
          end
        end

        # @param [Array<Database::Schema::TableDefinitionSet>] definition_sets
        # @param [Flavor::LexiconFlavor] specific_flavor
        # @return [Array<Database::Schema::TableDefinitionDumpPreset>]
        def make_dump_presets(definition_sets, specific_flavor)
          definition_sets.flat_map do |set|
            set.definitions.map do |definition|
              Schema::TableDefinitionDumpPreset.new(
                definition: definition,
                flavor_table: fetch_flavor_table(specific_flavor, set_name: set.name, table_name: definition.name)
              )
            end
          end
        end

        # @param [Schema::TableDefinitionSet] definition
        # @param [Pathname] data_dir
        # @return [Pathname]
        def create_structure_file(definition, data_dir)
          structure_file_name = "#{definition.name}__structure.sql"
          # @type [Pathname] structure_file_path
          structure_file_path = data_dir.join(structure_file_name)

          File.write(structure_file_path, definition.reset_sql)

          structure_file_path
        end

        # @deprecated
        def lexicon_schema_name(version)
          "lexicon__#{version.gsub('.', '_')}"
        end

        def with_renamed_schema(database, name, to:, &block)
          database.query <<~SQL
            ALTER SCHEMA "#{name}" RENAME TO "#{to}"
          SQL
          block.call(to)
        ensure
          database.query <<~SQL
            ALTER SCHEMA "#{to}" RENAME TO "#{name}"
          SQL
        end

        # @param [Flavor::LexiconFlavor] flavor
        # @return [Array<Schema::TableDefinitionSet>]
        def filter_definitions(flavor)
          selected = if flavor.only.nil?
                       @table_definitions
                     else
                       indexed = @table_definitions.map { |d| [d.name, d] }.to_h

                       nameset = Set.new([*flavor.only, 'datasource_credits'])

                       nameset.to_a.map { |name| indexed[name] }.compact
                     end

          selected.reject { |tds| flavor.without.include?(tds.name) }
        end

        # @return [Array<Class<Datasources::Base>>]
        def filter_classes(names)
          if names.nil?
            @datasource_classes.values
          else
            names.map { |name| @datasource_classes[name] }.compact
          end
        end

        # @return [{Boolean, String, Pathname}]
        def dump_table_definition(definition, dir:, schema:, flavor: nil)
          file_path = Pathname.new(Tempfile.new('', dir))
          tables = definition.definitions.map { |table| "-t '#{schema}.#{table.name}'" }

          if tables.length <= 0
            [tables.length, nil, nil]
          else
            table_commands = tables.map do |name|
              "<(pg_dump '#{@db_url}' -x --no-security-labels -n '#{schema}' #{name})"
            end

            @shell.execute <<-BASH
              cat #{table_commands.join(' ')} | pigz > '#{file_path}'
            BASH

            [tables.length.positive?, file_path.basename, file_path]
          end
        end
    end
  end
end
