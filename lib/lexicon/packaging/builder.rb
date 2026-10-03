# frozen_string_literal: true

require 'digest'

module Lexicon
  module Packaging
    # Builds the package of one datasource from the local lexicon schema.
    class Builder
      STRUCTURE_FILE = 'structure.sql'
      INDEXES_FILE = 'indexes.sql'
      DATA_DIR = 'data'

      # @param [Repository] repository
      # @param [TableExporter] exporter
      # @param [DependencyResolver] dependency_resolver
      # @param [StructureSplitter] splitter
      # @param [String] tool_version
      def initialize(repository:, exporter:, dependency_resolver:, splitter:, tool_version:)
        @repository = repository
        @exporter = exporter
        @dependency_resolver = dependency_resolver
        @splitter = splitter
        @tool_version = tool_version
      end

      # @param [Class<Datasources::Base>] datasource
      # @param [Database::Schema::TableDefinitionSet] definition_set
      # @param [Integer] jobs maximum number of tables exported at once
      # @param [Time] now
      # @yieldparam [String] table name of a table once exported
      # @return [Manifest]
      def build(datasource, definition_set, jobs: 4, now: Time.now, &on_table)
        name = definition_set.name
        version = repository.next_version(name, now.to_date)
        work_dir = repository.datasource_dir(name).join(".building-#{version}")

        FileUtils.rm_rf(work_dir)
        FileUtils.mkdir_p(work_dir.join(DATA_DIR))

        manifest = Manifest.new(
          name: name,
          version: version,
          schema_revision: datasource.schema_revision,
          structure_hash: write_structure(definition_set, work_dir),
          built_at: now,
          tool_version: tool_version,
          credits: credits(datasource),
          depends_on: dependencies(datasource, definition_set),
          tables: export_tables(definition_set, work_dir, jobs: jobs, &on_table),
          foreign_keys: foreign_keys(definition_set)
        )
        manifest.write(work_dir)
        File.rename(work_dir, repository.package_dir(name, version))

        manifest
      ensure
        FileUtils.rm_rf(work_dir) if work_dir&.exist?
      end

      private

        # @return [Repository]
        attr_reader :repository
        # @return [TableExporter]
        attr_reader :exporter
        # @return [DependencyResolver]
        attr_reader :dependency_resolver
        # @return [StructureSplitter]
        attr_reader :splitter
        # @return [String]
        attr_reader :tool_version

        # @return [String] hash of the structure, the same as long as the tables keep their shape
        def write_structure(definition_set, dir)
          parts = splitter.split(definition_set.create_sql)
          structure = to_script(parts.structure)
          indexes = to_script(parts.indexes)

          dir.join(STRUCTURE_FILE).write(structure)
          dir.join(INDEXES_FILE).write(indexes)

          "sha256:#{Digest::SHA256.hexdigest(structure + indexes)}"
        end

        def to_script(statements)
          statements.map { |statement| "#{statement};\n" }.join("\n")
        end

        # @return [Array<Hash>] in the order of the definitions
        def export_tables(definition_set, dir, jobs:, &on_table)
          tables = definition_set.definitions.map(&:name)
          queue = Queue.new
          tables.each { |table| queue << table }
          results = Concurrent::Hash.new

          workers = Array.new([jobs, tables.size].min) do
            Thread.new do
              Thread.current.report_on_exception = false
              loop do
                table = queue.pop(true)
                path = "#{DATA_DIR}/#{table}_0.csv.gz"
                exported = exporter.export(table, dir.join(path))
                file = { path: path, sha256: exported[:sha256], bytes: exported[:bytes] }
                results[table] = { name: table, rows: exported[:rows], files: [file] }
                on_table&.call(table)
              rescue ThreadError
                break
              end
            end
          end
          workers.each(&:join)

          tables.map { |table| results.fetch(table) }
        end

        def credits(datasource)
          datasource.get_credits.map do |credit|
            {
              name: credit.name,
              provider: credit.provider,
              url: credit.url,
              licence: credit.licence,
              licence_url: credit.licence_url,
              updated_at: credit.updated_at
            }
          end
        end

        def dependencies(datasource, definition_set)
          dependency_resolver.resolve(definition_set, declared: datasource.get_dependencies).map do |dependency|
            dependency.merge(built_against: repository.latest(dependency[:name])&.version)
          end
        end

        def foreign_keys(definition_set)
          dependency_resolver.foreign_keys(definition_set).map do |foreign_key|
            {
              table: foreign_key.table,
              column: foreign_key.column,
              references_table: foreign_key.target_table,
              references_column: foreign_key.target_column
            }
          end
        end
    end
  end
end
