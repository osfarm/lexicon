# frozen_string_literal: true

module Lexicon
  class Cli < Commands::ContainerAwareCommand
    include Commands::Compute

    default_command :help
    class_option :verbose, type: :boolean, default: false, aliases: ['v']
    class_option :parallel, type: :boolean, default: false, aliases: ['P']

    def initialize(_args = [], local_options = {}, _config = {})
      super

      register_config(container, options)
    end

    desc 'clean', 'Cleans the database content'

    def clean
      datasources = get('datasource.all').values

      cleaner = get('database.cleaner')
      cleaner.clean(*datasources)
      cleaner.clean_lexicon(*datasources, Credits)
    end

    desc 'list', 'Lists all the datasources'

    def list
      list = get('datasource.all')

      max_len = list.keys.map(&:length).max
      list.sort.each do |name, ds|
        line = name.to_s
        unless ds.description.nil?
          line = (line.ljust(max_len + 5) + " # #{ds.description}").truncate(80)
        end
        puts line
      end
    end

    desc 'dump SUBCOMMAND', 'Dump lexicon data or structure'
    subcommand 'dump', Commands::DumpCommand

    desc 'console', 'Start a console'
    subcommand 'console', Commands::ConsoleCommand

    desc 'version', 'Display of manipulate the lexicon version'
    subcommand 'version', Commands::VersionCommand

    desc 'remote', 'Minio related commands'
    subcommand 'remote', Commands::RemoteCommand

    desc 'production', 'Production related commands'
    subcommand 'production', Commands::ProductionCommand

    desc 'load', 'Load a local package into a remote database (via SSH)'
    subcommand 'load', Commands::LoadCommand

    desc 'package [NAMES]', 'Build one versioned package per datasource in out/packages'
    method_option :jobs, type: :numeric, default: 4, desc: 'Tables exported at once'
    method_option :validate, type: :boolean, default: true, desc: 'Refuse datasources with empty tables or missing foreign keys'

    def package(*names)
      definitions = get('database.schema.definitions').map { |set| [set.name, set] }.to_h
      datasources = get('datasource.all').transform_keys(&:to_s).slice(*definitions.keys)

      unknown = names - datasources.keys
      if unknown.any?
        puts '[ NOK ] '.red + "Unknown datasources: #{unknown.join(', ')}"
        exit 1
      end

      failed = (names.empty? ? datasources.keys.sort : names).reject do |name|
        package_datasource(datasources.fetch(name), definitions.fetch(name))
      end

      exit 1 if failed.any?
    end

    desc 'validate', 'Validate lexicon schema'
    def validate
      # @type [Array<Database::Validation::DatasourceValidationResult>]
      results = get('database.validator').validate_datasources

      results
        .sort_by(&:name)
        .each do |result|
        if result.valid?
          puts '[  OK ] '.green + result.name.to_s.yellow
        else
          puts '[ NOK ] '.red + result.name.to_s.yellow
          result.invalid_tables
                .each do |table_validation|
                  puts('--> ' + table_validation.name.to_s.yellow + ' is ' + table_validation.state.to_s.red)
                  if table_validation.foreign_keys.any?
                    puts('---> Constraints')
                    table_validation.foreign_keys.each do |foreign_key, status|
                      puts("----> #{foreign_key.column} references #{foreign_key.target_table}(#{foreign_key.target_column}) is #{status}")
                    end
                  end
                end
        end
      end
    end

    private

      # @return [Boolean] whether the package has been built
      def package_datasource(datasource, definition_set)
        name = definition_set.name

        if options['validate']
          validator = get('database.validator')
          validation = validator.validate_definition(get('database'), definition_set)

          if !validation.valid?
            reasons = validation.invalid_tables.map do |table|
              "#{table.name} is #{table.state == :ok ? 'missing a foreign key' : table.state}"
            end
            puts '[ NOK ] '.red + name.yellow + ": #{reasons.join(', ')}"

            return false
          end
        end

        manifest = get('packaging.builder').build(datasource, definition_set, jobs: options['jobs']) do |table|
          puts "        #{name}: #{table} exported" if options['verbose']
        end
        rows = manifest.tables.sum { |table| table[:rows] }
        puts '[  OK ] '.green + name.yellow + " #{manifest.version} (#{manifest.tables.size} tables, #{rows} rows)"

        true
      rescue Packaging::TableExporter::ExportError => e
        puts '[ NOK ] '.red + name.yellow + ": #{e.message}"

        false
      end

      def register_config(container, options)
        verbose = options['verbose']
        parallel = options['parallel']
        jobs = options.fetch('jobs', parallel ? 4 : 1)

        container.namespace(:config) do
          register(:verbose) { verbose }
          register(:parallel) { parallel }
          register(:jobs) { jobs }
        end
      end
  end
end
