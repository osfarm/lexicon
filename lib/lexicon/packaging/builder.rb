# frozen_string_literal: true

require 'digest'

module Lexicon
  module Packaging
    # Builds the package of one datasource from the local lexicon schema.
    class Builder
      STRUCTURE_FILE = 'structure.sql'
      INDEXES_FILE = 'indexes.sql'
      DATA_DIR = 'data'
      TRANSLATIONS_ROLE = 'translations'
      TRANSLATIONS_TABLE = 'master_translations'

      Export = Struct.new(:table, :source, :role, keyword_init: true)

      # @param [Repository] repository
      # @param [TableExporter] exporter
      # @param [DependencyResolver] dependency_resolver
      # @param [StructureSplitter] splitter
      # @param [String] tool_version
      # @param [PivotMeter, nil] pivot_meter
      def initialize(repository:, exporter:, dependency_resolver:, splitter:, tool_version:, pivot_meter: nil)
        @repository = repository
        @exporter = exporter
        @dependency_resolver = dependency_resolver
        @splitter = splitter
        @tool_version = tool_version
        @pivot_meter = pivot_meter
      end

      # @param [Class<Datasources::Base>] datasource
      # @param [Database::Schema::TableDefinitionSet] definition_set
      # @param [Integer] jobs maximum number of tables exported at once
      # @param [Time] now
      # @param [Flavor::LexiconFlavor, nil] flavor filters applied to the tables
      # @yieldparam [String] table name of a table once exported
      # @return [Manifest]
      def build(datasource, definition_set, jobs: 4, now: Time.now, flavor: nil, &on_table)
        name = definition_set.name
        version = repository.next_version(name, now.to_date)
        work_dir = repository.datasource_dir(name).join(".building-#{version}")

        FileUtils.rm_rf(work_dir)
        FileUtils.mkdir_p(work_dir.join(DATA_DIR))

        manifest = Manifest.new(
          name: name,
          version: version,
          schema_revision: datasource.schema_revision,
          structure_hash: write_structure(datasource, definition_set, work_dir),
          built_at: now,
          tool_version: tool_version,
          flavor: flavor&.name,
          scope: datasource.scope,
          description: datasource.description,
          credits: credits(datasource),
          depends_on: dependencies(datasource, definition_set),
          tables: export_tables(exports(datasource, definition_set, flavor), work_dir, jobs: jobs, &on_table),
          foreign_keys: foreign_keys(definition_set),
          # Match rates describe the whole datasource: they are not measured for a filtered bundle
          pivots: flavor.nil? && @pivot_meter ? @pivot_meter.measure(datasource.get_pivots) : []
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
        def write_structure(datasource, definition_set, dir)
          parts = splitter.split(definition_set.create_sql)
          structure = to_script([*parts.structure, *translations_structure(datasource, definition_set)])
          indexes = to_script(parts.indexes)

          dir.join(STRUCTURE_FILE).write(structure)
          dir.join(INDEXES_FILE).write(indexes)

          "sha256:#{Digest::SHA256.hexdigest(structure + indexes)}"
        end

        def to_script(statements)
          statements.map { |statement| "#{statement};\n" }.join("\n")
        end

        # @return [Array<Export>] the tables of the datasource, then the one of its translations
        def exports(datasource, definition_set, flavor)
          tables = definition_set.definitions.map do |definition|
            filter = flavor&.datasource(definition_set.name)&.table(definition.name)&.filter
            whole = TableExporter.whole(definition.name)

            Export.new(table: definition.name, source: filter.nil? ? whole : "(SELECT * FROM #{whole} #{filter})")
          end

          [*tables, *translations_export(datasource, definition_set)]
        end

        def translations_table(definition_set)
          "#{definition_set.name}__translations"
        end

        def translations_structure(datasource, definition_set)
          return [] if datasource.get_translation_prefixes.empty?

          [<<~SQL.strip]
            CREATE TABLE #{translations_table(definition_set)} (
              id character varying PRIMARY KEY NOT NULL,
              fra character varying NOT NULL,
              eng character varying NOT NULL
            )
          SQL
        end

        def translations_export(datasource, definition_set)
          prefixes = datasource.get_translation_prefixes
          return [] if prefixes.empty?

          # An underscore is a wildcard for LIKE
          conditions = prefixes.map { |prefix| "id LIKE '#{prefix.gsub('_', '\\_')}\\_%'" }.join(' OR ')
          source = "(SELECT id, fra, eng FROM #{TableExporter.whole(TRANSLATIONS_TABLE)} WHERE #{conditions} ORDER BY id)"

          [Export.new(table: translations_table(definition_set), source: source, role: TRANSLATIONS_ROLE)]
        end

        # @param [Array<Export>] exports
        # @return [Array<Hash>] in the order of the exports
        def export_tables(exports, dir, jobs:, &on_table)
          queue = Queue.new
          exports.each { |export| queue << export }
          results = Concurrent::Hash.new

          workers = Array.new([jobs, exports.size].min) do
            Thread.new do
              Thread.current.report_on_exception = false
              loop do
                export = queue.pop(true)
                results[export.table] = export_table(export, dir)
                on_table&.call(export.table)
              rescue ThreadError
                break
              end
            end
          end
          workers.each(&:join)

          exports.map { |export| results.fetch(export.table) }
        end

        # @return [Hash]
        def export_table(export, dir)
          path = "#{DATA_DIR}/#{export.table}_0.csv.gz"
          exported = exporter.export(export.source, dir.join(path))
          file = { path: path, sha256: exported[:sha256], bytes: exported[:bytes] }

          { name: export.table, rows: exported[:rows], files: [file], role: export.role }.compact
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
