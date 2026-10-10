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

    # Not `load`: that name is the load phase of a datasource (Commands::Compute)
    desc 'load_package', 'Load a local package into a remote database (via SSH)'
    subcommand 'load_package', Commands::LoadCommand

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
    method_option :production, type: :boolean, default: false,
                               desc: 'Send to LEXICON_PRODUCTION_TARGET what is already in service at LEXICON_PUBLISH_TARGET'
    method_option :force, type: :boolean, default: false, desc: 'With --production: do not ask for the package to be in service locally'

    def publish(*targets)
      repository = get('packaging.repository')
      publisher = get(options['production'] ? 'packaging.production_publisher' : 'packaging.publisher')
      puts "Target: #{publisher.target.yellow}#{' (production)' if options['production']}"

      if options['bundle']
        publisher.publish_bundle(get('parameter.bundles.root').join(options['bundle']), options['bundle'])
        puts '[  OK ] '.green + "bundle #{options['bundle'].yellow} published"

        return
      end

      packages = (targets.empty? ? repository.names : targets).map { |target| target.split('@', 2) }
      refuse_packages_not_tried_locally(packages) if options['production'] && !options['force']

      packages.each do |name, version|
        puts '[  OK ] '.green + name.yellow + " #{publisher.publish(name, version: version)} published"
      end
    rescue Packaging::Rsync::TransferError, ArgumentError => e
      puts '[ NOK ] '.red + e.message
      exit 1
    end

    desc 'status', 'Latest local version of each package, the one published and the one in service'
    method_option :production, type: :boolean, default: false, desc: 'Look at LEXICON_PRODUCTION_TARGET instead of LEXICON_PUBLISH_TARGET'

    def status
      repository = get('packaging.repository')
      publisher = get(options['production'] ? 'packaging.production_publisher' : 'packaging.publisher')
      puts "Target: #{publisher.target.yellow}#{' (production)' if options['production']}"
      published = publisher.published
      in_service = publisher.in_service

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
    method_option :tabular, type: :boolean, default: false,
                            desc: 'Print the sheet of a tabular contribution instead, for data/contributions/NAME/dataset.yml'

    def new(name)
      if get('datasource.all').transform_keys(&:to_s).key?(name)
        warn "The datasource #{name} already exists"
        exit 1
      end

      puts options['tabular'] ? Contribution::Scaffold.new.sheet(name) : Contribution::Scaffold.new.datasource(name)
    rescue ArgumentError => e
      warn e.message
      exit 1
    end

    desc 'contribute [NAME]', 'Read the tabular contribution of data/contributions/NAME as a maintainer would, and say what to correct'
    method_option :web, type: :boolean, default: false,
                        desc: 'Open the local web interface instead: every contribution, read again as its files change'
    method_option :port, type: :numeric, default: 8787, desc: 'Port the web interface listens on'
    method_option :hosted, type: :boolean, default: false,
                           desc: 'With --web, on the serving side: answer the API only, one workspace per API key'
    method_option :proposed, type: :boolean, default: false, desc: 'List the datasets proposed online'
    method_option :fetch, type: :string, banner: 'WORKSPACE/NAME',
                          desc: 'Bring a dataset proposed online into data/contributions/NAME'
    method_option :production, type: :boolean, default: false,
                               desc: 'With --proposed or --fetch: look at LEXICON_PRODUCTION_CONTRIBUTIONS_TARGET'
    method_option :force, type: :boolean, default: false, desc: 'With --fetch: replace the dataset already there'

    def contribute(name = nil)
      return contribute_online if options['web'] && options['hosted']
      return contribute_on_the_web if options['web']
      return proposed_contributions if options['proposed']
      return fetch_contribution(options['fetch']) if options['fetch']

      if name.nil?
        puts '[ NOK ] '.red + 'Quel jeu relire ? ./lexicon contribute <nom>, ou ./lexicon contribute --web pour l’interface web.'
        exit 1
      end

      dir = get('parameter.contributions.root').join(name)
      unless dir.join(Contribution::Sheet::FILE).file?
        puts '[ NOK ] '.red + "Pas de fiche #{Contribution::Sheet::FILE} dans #{dir}. " \
                             "Pour en créer une : ./lexicon new #{name} --tabular"
        exit 1
      end

      sheet = Contribution::Sheet.load(dir, raw: get('parameter.raw.root'))
      findings = Contribution::Review.new(sheet).findings
      errors, warnings = findings.partition { |finding| finding.level == :error }
      errors.each { |finding| puts '  à corriger : '.red + finding.message }
      warnings.each { |finding| puts '  à savoir   : ' + finding.message }

      if errors.any?
        puts '[ NOK ] '.red + "#{name} : #{errors.size} #{errors.one? ? 'point' : 'points'} à corriger avant de proposer le jeu."
        exit 1
      end
      rows = sheet.tables.map { |table| "#{table.file} → #{table.name}" }.join(', ')
      puts '[  OK ] '.green + "#{name} peut être proposé (#{rows}). Un mainteneur le construit et le publie avec ./lexicon ship #{name}"
    rescue Psych::Exception => e
      puts '[ NOK ] '.red + "La fiche ne se lit pas : #{e.message.lines.first.to_s.strip}"
      exit 1
    end

    no_commands do
      # The address is the one of the host when the wrapper says so: the port it publishes may differ
      def contribute_on_the_web
        app = Contribution::Web::App.new(root: get('parameter.contributions.root'), raw: get('parameter.raw.root'),
                                         taken: get('datasource.all').keys.map(&:to_s))
        address = ENV.fetch('LEXICON_CONTRIBUTE_URL', "http://localhost:#{options['port']}")

        puts "Interface de contribution : #{address.green}  (Ctrl-C pour l'arrêter)"
        puts 'Le dossier des contributions est en lecture seule : la relecture seule est proposée.' unless app.writable?
        Contribution::Web::Server.new(app, host: ENV.fetch('LEXICON_CONTRIBUTE_BIND', '0.0.0.0'), port: options['port']).run
      end

      # The same interface on the serving side: the API relays to it the holders of a key
      def contribute_online
        root = Pathname.new(ENV.fetch('LEXICON_CONTRIBUTIONS_ROOT') { raise Thor::Error.new('LEXICON_CONTRIBUTIONS_ROOT is not set') })
        megabytes = Integer(ENV.fetch('LEXICON_CONTRIBUTE_MAXIMUM_MB', '50'), 10)
        app = Contribution::Web::Hosted.new(
          root: root, secret: ENV.fetch('LEXICON_CONTRIBUTE_SECRET', ''), taken: get('datasource.all').keys.map(&:to_s),
          prefix: ENV.fetch('LEXICON_CONTRIBUTE_PREFIX', '/contribute/outil'), maximum_upload: megabytes * 1024 * 1024
        )

        puts "Contributions kept in #{root}, served to the API on port #{options['port']}, tables up to #{megabytes} MB"
        Contribution::Web::Server.new(app, host: '0.0.0.0', port: options['port'],
                                           maximum_body: Contribution::Web::Server::HOSTED_MAXIMUM_BODY).run
      rescue ArgumentError => e
        raise Thor::Error.new("#{e.message}: set LEXICON_CONTRIBUTE_SECRET, the same as the API")
      end

      def contribution_inbox
        variable = options['production'] ? 'LEXICON_PRODUCTION_CONTRIBUTIONS_TARGET' : 'LEXICON_CONTRIBUTIONS_TARGET'
        target = ENV.fetch(variable) do
          raise Thor::Error.new("#{variable} is not set") if options['production']

          get('parameter.root').join('out', 'contributions').to_s
        end
        puts "Contributions: #{target.yellow}#{' (production)' if options['production']}"

        Contribution::Inbox.new(target: target)
      end

      def proposed_contributions
        proposed = contribution_inbox.proposed
        puts 'Aucun jeu proposé.' if proposed.empty?
        proposed.each do |entry|
          puts "#{"#{entry[:workspace]}/#{entry[:name]}".yellow}  proposé le #{entry[:proposed_on]}  #{entry[:author]}"
          puts "    #{entry[:description]}" unless entry[:description].nil?
        end
        return if proposed.empty?

        puts "\nPour en rapatrier un : ./lexicon contribute --fetch <espace>/<nom>#{' --production' if options['production']}"
      rescue Packaging::Rsync::TransferError => e
        raise Thor::Error.new(e.message)
      end

      def fetch_contribution(designation)
        workspace, name = designation.to_s.split('/', 2)
        dir = contribution_inbox.fetch(workspace, name, into: get('parameter.contributions.root'), force: options['force'])

        puts '[  OK ] '.green + "#{name} est dans #{dir}. Le relire : ./lexicon contribute #{name}"
      rescue ArgumentError, Packaging::Rsync::TransferError, SystemCallError => e
        raise Thor::Error.new(e.message)
      end
    end

    desc 'ship NAMES', 'Take datasources all the way: check, build, check the data, package, publish locally and wait for the loader'
    method_option :production, type: :boolean, default: false, desc: 'Then publish to LEXICON_PRODUCTION_TARGET and wait there too'
    method_option :build, type: :boolean, default: true, desc: 'Run collect, load and normalize; --no-build ships what is already built'
    method_option :jobs, type: :numeric, default: 4, desc: 'Tables exported at once'
    method_option :validate, type: :boolean, default: true, desc: 'Refuse datasources with empty tables or missing foreign keys'
    method_option :timeout, type: :numeric, default: 900, desc: 'Seconds to wait for the loader'

    def ship(*names)
      stop_shipping('give at least one datasource') if names.empty?
      datasources = packaged_datasources
      unknown = names - datasources.keys
      stop_shipping("unknown or not packaged datasources: #{unknown.join(', ')}") if unknown.any?

      shipping_step('Declarations') { names.all? { |name| passes_check?(name, datasources.fetch(name), data: false) } }
      shipping_step('Build') { get('datasource.name_runner').run(names, action: :run) || true } if options['build']
      shipping_step('Built data') { names.all? { |name| passes_check?(name, datasources.fetch(name), data: true) } }
      shipping_step('Packages') do
        names.all? { |name| package_datasource(get('packaging.builder'), datasources.fetch(name), packaged_definitions.fetch(name)) }
      end
      deliver(names, get('packaging.publisher'), 'local')
      deliver(names, get('packaging.production_publisher'), 'production') if options['production']
      puts '[  OK ] '.green + "#{names.join(', ')} shipped#{' to production' if options['production']}"
    rescue Packaging::Rsync::TransferError, ArgumentError => e
      stop_shipping(e.message)
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
      # The production only receives what the local serving side has loaded and put in service
      #
      # @param [Array<Array(String, String)>] packages name and version, the latest local version when nil
      def refuse_packages_not_tried_locally(packages)
        local = get('packaging.publisher')
        missing = packages.reject { |name, version| local.in_service?(name, version: version) }
        return if missing.empty?

        missing.each do |name, version|
          version ||= get('packaging.repository').versions(name).last
          puts '[ NOK ] '.red + name.yellow + " #{version || '(no local package)'} is not in service at #{local.target}: " \
               'publish it there first, wait for the loader, or pass --force'
        end
        exit 1
      end

      def stop_shipping(reason)
        puts '[ NOK ] '.red + reason
        exit 1
      end

      # A step that does not pass stops everything: nothing goes further than what was verified
      def shipping_step(title)
        puts "── #{title}".cyan
        stop_shipping("stopped at: #{title}") unless yield
      end

      def passes_check?(name, datasource, data:)
        baseline = get('parameter.resources.root').join('check_baseline.yml')
        tolerated = baseline.file? ? YAML.safe_load(baseline.read).fetch('tolerated', []) : []
        checker = Contribution::Checker.new(datasources: get('datasource.all').transform_keys(&:to_s), definitions: packaged_definitions,
                                            tolerated: tolerated)
        findings = data ? built_data_findings(checker, name, datasource) : checker.static(name)
        print_findings(name, findings)

        findings.none? { |finding| finding.level == :error }
      end

      # Sends the latest packages, then waits until the serving side says they are in service, or why not
      def deliver(names, publisher, place)
        shipping_step("Publication (#{place}: #{publisher.target})") do
          names.each { |name| puts "        #{name} #{publisher.publish(name)} sent" }
        end
        shipping_step("In service (#{place})") do
          deadline = Time.now + options['timeout']
          since = Time.now.utc
          waiting = names
          until waiting.empty?
            waiting = waiting.reject { |name| publisher.in_service?(name) }
            refused = publisher.failures.select do |failure|
              waiting.include?(failure[:name].to_s) && Time.parse(failure[:at].to_s) >= since - 60
            end
            refused.each do |failure|
              puts "        #{failure[:name]} #{failure[:version]} refused: #{Array(failure[:reasons]).join('; ')}".red
            end
            break if refused.any? || Time.now > deadline

            sleep 10 unless waiting.empty?
          end
          puts "        still waiting for #{waiting.join(', ')} after #{options['timeout']} s" if waiting.any? && Time.now > deadline
          waiting.empty?
        end
      end

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

        started = Time.now
        manifest = builder.build(datasource, definition_set, jobs: options['jobs'], now: started, flavor: flavor) do |table|
          puts "        #{name}: #{table} exported" if options['verbose']
        end
        rows = manifest.tables.sum { |table| table[:rows] }
        # The builder hands back the latest package when the data has not changed since
        unchanged = manifest.built_at.to_i != started.to_i
        puts '[  OK ] '.green + name.yellow + " #{manifest.version} (#{manifest.tables.size} tables, #{rows} rows)" \
             "#{' unchanged, no new version' if unchanged}"

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
