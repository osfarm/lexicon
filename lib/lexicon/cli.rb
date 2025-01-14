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
          result.validations
                .reject(&:valid?)
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
