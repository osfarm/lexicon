# frozen_string_literal: true

module Lexicon
  module Database
    # @deprecated
    class StructureDumper < DumperBase
      STRUCTURE_FILE_NAME = 'structure.sql'

      def initialize(target_dir:, db_url:, shell:, database_factory:, table_definitions:, datasource_classes:, credits_builder:)
        super(target_dir: target_dir)

        @credits_builder = credits_builder
        @datasource_classes = datasource_classes
        @database_factory = database_factory
        @db_url = db_url
        @shell = shell
        @table_definitions = table_definitions
      end

      def dump_structure(version)
        database = database_factory.new_instance(url: db_url)

        database.on_empty_schema(base_path: %i[postgis]) do |schema|
          @table_definitions.each { |td| database.query(td.create_sql) }
          @datasource_classes.values.each do |ds_class|
            @credits_builder.build(ds_class, database: database)
          end

          Dir.mktmpdir(nil, @target_dir) do |dir|
            dir = Pathname.new(dir)

            temp_structure_file = dir.join(STRUCTURE_FILE_NAME)
            do_dump_structure(temp_structure_file, schema: schema)

            FileUtils.mv(temp_structure_file, ensure_version_dir(version).join(STRUCTURE_FILE_NAME))
          end
        end
      end

      private

        # @return [Common::Database::Factory]
        attr_reader :database_factory
        # @return [String]
        attr_reader :db_url

        def do_dump_structure(file, schema:)
          @shell.execute <<-BASH
            pg_dump '#{@db_url}' -n '#{schema}' -s -O -x --no-security-labels | #{make_sed_command(schema: schema)} > #{file}
          BASH
        end

        def make_sed_command(schema:)
          commands = [
            's/CREATE UNLOGGED TABLE/CREATE TABLE/' # Make tables logged again
          ]

          if schema.to_s != 'lexicon'
            commands << "s/^CREATE SCHEMA #{schema};$/CREATE SCHEMA lexicon;/" # Rename schema, 1st part
            commands << "s/Schema: #{schema};/Schema: lexicon;/" # Rename schema 2nd parts: in comments
            commands << "s/Name: #{schema};/Name: lexicon;/" # Rename schema 3nd parts: in comments
            commands << "s/#{schema}\\./lexicon\\./" # Rename schema 4th part: in queries
          end

          commands = commands.map { |command| "-e '#{command}'" }.join(' ')

          "sed -r #{commands}"
        end
    end
  end
end
