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

    desc 'server', 'Serving side: put packages in service'
    subcommand 'server', Commands::ServerCommand

    desc 'load', 'Load a local package into a remote database (via SSH)'
    subcommand 'load', Commands::LoadCommand

    desc 'package [NAMES]', 'Build one versioned package per datasource in out/packages'
    method_option :jobs, type: :numeric, default: 4, desc: 'Tables exported at once'
    method_option :validate, type: :boolean, default: true, desc: 'Refuse datasources with empty tables or missing foreign keys'

    def package(*names)
      datasources = packaged_datasources

      unknown = names - datasources.keys
      if unknown.any?
        puts '[ NOK ] '.red + "Unknown or not packaged datasources: #{unknown.join(', ')}"
        exit 1
      end

      builder = get('packaging.builder')
      failed = (names.empty? ? datasources.keys.sort : names).reject do |name|
        package_datasource(builder, datasources.fetch(name), packaged_definitions.fetch(name))
      end

      exit 1 if failed.any?
    end

    desc 'publish [NAMES]', 'Send the latest packages to the serving side and designate them (name or name@version)'
    method_option :bundle, type: :string, desc: 'Send the bundle of this flavor instead, to the private area'

    def publish(*targets)
      repository = get('packaging.repository')
      publisher = get('packaging.publisher')

      if options['bundle']
        publisher.publish_bundle(get('parameter.bundles.root').join(options['bundle']), options['bundle'])
        puts '[  OK ] '.green + "bundle #{options['bundle'].yellow} published"

        return
      end

      (targets.empty? ? repository.names : targets).each do |target|
        name, version = target.split('@', 2)
        puts '[  OK ] '.green + name.yellow + " #{publisher.publish(name, version: version)} published"
      end
    rescue Packaging::Rsync::TransferError, ArgumentError => e
      puts '[ NOK ] '.red + e.message
      exit 1
    end

    desc 'status', 'Latest local version of each package, the one published and the one in service'

    def status
      repository = get('packaging.repository')
      published = get('packaging.publisher').published
      in_service = get('packaging.publisher').in_service

      (repository.names | published.keys | in_service.keys).sort.each do |name|
        local = repository.versions(name).last
        current = published.dig(name, :current)
        served = in_service.dig(name, :version)
        notes = [
          (' to publish'.red if !local.nil? && local != current),
          (' not in service yet'.red if in_service.any? && !current.nil? && served != current),
          (' stale'.red if in_service.dig(name, :stale))
        ].compact.join

        puts "#{name.ljust(30).yellow} local #{(local || '-').ljust(13)} published #{(current || '-').ljust(13)} " \
             "in service #{served || (in_service.any? ? '-' : '?')}#{notes}"
      end
    rescue Packaging::Rsync::TransferError => e
      puts '[ NOK ] '.red + e.message
      exit 1
    end

    desc 'check [NAMES]', 'Tell whether datasources can be accepted: declarations, then built data'
    method_option :static, type: :boolean, default: false, desc: 'Only what the declarations say, without any data'

    def check(*names)
      datasources = get('datasource.all').transform_keys(&:to_s)
      unknown = names - datasources.keys
      if unknown.any?
        puts '[ NOK ] '.red + "Unknown datasources: #{unknown.join(', ')}"
        exit 1
      end

      baseline = get('parameter.resources.root').join('check_baseline.yml')
      tolerated = baseline.file? ? YAML.safe_load(baseline.read).fetch('tolerated', []) : []
      checker = Contribution::Checker.new(datasources: datasources, definitions: packaged_definitions, tolerated: tolerated)
      failed = (names.empty? ? datasources.keys.sort : names).reject do |name|
        findings = checker.static(name)
        findings += built_data_findings(checker, name, datasources.fetch(name)) unless options['static']
        print_findings(name, findings)

        findings.none? { |finding| finding.level == :error }
      end

      exit 1 if failed.any?
    end

    desc 'new NAME', 'Print the skeleton of a new datasource: ./lexicon new soil_moisture > lib/datasources/soil_moisture.rb'

    def new(name)
      if get('datasource.all').transform_keys(&:to_s).key?(name)
        warn "The datasource #{name} already exists"
        exit 1
      end

      puts Contribution::Scaffold.new.datasource(name)
    rescue ArgumentError => e
      warn e.message
      exit 1
    end

    desc 'fetch URL', 'Download a repository of packages served over HTTP, such as a private bundle'
    method_option :to, type: :string, desc: 'Directory to fill (default: out/bundles/<last part of the URL>)'

    def fetch(url)
      to = Pathname.new(options['to'] || get('parameter.bundles.root').join(url.chomp('/').split('/').last).to_s)
      fetcher = Packaging::Fetcher.new(base_url: url, api_key: ENV['LEXICON_API_KEY'])

      names = fetcher.fetch(to) { |name, version| puts '[  OK ] '.green + name.yellow + " #{version}" }
      puts "#{names.size} packages in #{to}. Load them with LEXICON_PACKAGES_ROOT=#{to} ./lexicon server sync"
    rescue Packaging::Fetcher::FetchError => e
      puts '[ NOK ] '.red + e.message
      exit 1
    end

    desc 'bundle FLAVOR [NAMES]', 'Build in out/bundles/FLAVOR a repository of packages filtered by a flavor'
    method_option :jobs, type: :numeric, default: 4, desc: 'Tables exported at once'
    method_option :validate, type: :boolean, default: true, desc: 'Refuse datasources with empty tables or missing foreign keys'
    method_option :set, type: :hash, default: {}, desc: 'Values of the parameters of the flavor: --set longitude:-0.78 latitude:45.81'
    method_option :as, type: :string, desc: 'Name of the bundle, when it differs from the flavor'

    def bundle(flavor_name, *only)
      flavor = get('flavor.loader').load(flavor_name).unwrap!
                                   .with_parameters(options['set'], name: options['as'])
      repository = Packaging::Repository.new(get('parameter.bundles.root').join(flavor.name))
      builder = get('packaging.builder_factory').call(repository)

      names = packaged_datasources.keys.sort - flavor.without
      names &= flavor.only unless flavor.only.nil?
      names &= only if only.any?
      failed = names.reject do |name|
        built = package_datasource(builder, packaged_datasources.fetch(name), packaged_definitions.fetch(name), flavor: flavor)
        repository.set_current(name, repository.versions(name).last) if built

        built
      end

      puts "Bundle #{flavor.name.yellow}: #{names.size - failed.size} packages in #{repository.root}"
      exit 1 if failed.any?
    rescue ArgumentError => e
      puts '[ NOK ] '.red + e.message
      exit 1
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

      # @return [Hash{String => Database::Schema::TableDefinitionSet}]
      def packaged_definitions
        @packaged_definitions ||= get('database.schema.definitions').map { |set| [set.name, set] }.to_h
      end

      # @return [Hash{String => Class<Datasources::Base>}] datasources defining tables and shipped as packages
      def packaged_datasources
        @packaged_datasources ||= get('datasource.all').transform_keys(&:to_s)
                                                       .slice(*packaged_definitions.keys)
                                                       .select { |_name, datasource| datasource.packaged? }
      end

      # @return [Array<Contribution::Checker::Finding>]
      def built_data_findings(checker, name, datasource)
        definition = packaged_definitions[name]
        return [] if definition.nil? || !datasource.packaged?

        database = get('database')
        rows = definition.definitions.map do |table|
          [table.name, database.query(%(SELECT count(*) FROM "lexicon"."#{table.name}")).getvalue(0, 0).to_i]
        end.to_h

        checker.data(
          name,
          pivots: Packaging::PivotMeter.new(database).measure(datasource.get_pivots),
          rows: rows,
          previous: get('packaging.repository').latest(name)
        )
      rescue PG::UndefinedTable => e
        [Contribution::Checker::Finding.new(level: :error, message: "not built: #{e.message.lines.first.strip}")]
      end

      def print_findings(name, findings)
        errors, warnings = findings.partition { |finding| finding.level == :error }
        label = errors.any? ? '[ NOK ] '.red : '[  OK ] '.green

        puts label + name.yellow
        errors.each { |finding| puts "        #{'error'.red}: #{finding.message}" }
        warnings.each { |finding| puts "        warning: #{finding.message}" }
      end

      # @return [Boolean] whether the package has been built
      def package_datasource(builder, datasource, definition_set, flavor: nil)
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

        manifest = builder.build(datasource, definition_set, jobs: options['jobs'], flavor: flavor) do |table|
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
