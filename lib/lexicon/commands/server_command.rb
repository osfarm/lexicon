# frozen_string_literal: true

module Lexicon
  module Commands
    class ServerCommand < ContainerAwareCommand
      desc 'sync [NAMES]', 'Put the current packages of the repository in service (name or name@version)'
      method_option :force, type: :boolean, default: false, desc: 'Reload versions already in service, accept drops of volume'
      method_option :together, type: :boolean, default: false, desc: 'Swap all the packages at once: all or none'

      def sync(*names)
        refusing_failures do
          prepare
          outcomes = get('server.loader').sync(names, force: options['force'], together: options['together']) do |outcome|
            print_outcome(outcome)
          end

          get('server.meta').record_repository(get('packaging.repository'))

          exit 1 if outcomes.any? { |outcome| outcome.state == :failed }
        end
      end

      desc 'watch', 'Keep the packages the index designates in service'
      method_option :interval, type: :numeric, default: 300, desc: 'Seconds between two looks at the repository'

      def watch
        $stdout.sync = true
        loader = get('server.loader')
        prepare

        loop do
          begin
            loader.sync { |outcome| print_outcome(outcome) unless outcome.state == :up_to_date }
            # Before the status file: when it says a version is in service, the bundles already designate it
            assemble_bundles(quiet: true)
            get('server.status_file').write
            get('server.meta').record_repository(get('packaging.repository'))
          rescue Server::LoadFailure => e
            puts '[ NOK ] '.red + e.message
          end
          sleep options['interval']
        end
      end

      desc 'bundles', 'Make the tracked bundles of the repository out of the packages in service'

      def bundles
        refusing_failures do
          get('server.meta').setup
          results = assemble_bundles(quiet: false)
          puts 'No tracked bundle in the repository' if results.empty?

          exit 1 if results.any? { |result| result.outcome.nil? || result.outcome.missing.any? }
        end
      end

      desc 'rollback NAME', 'Put back in service the version a package replaced'

      def rollback(name)
        refusing_failures do
          outcome = get('server.loader').rollback(name)
          print_outcome(outcome)

          exit 1 if outcome.state == :failed
        end
      end

      desc 'prune', 'List old versions and packages no longer in the repository; remove them with --apply'
      method_option :apply, type: :boolean, default: false

      def prune
        refusing_failures do
          pruner = get('server.pruner')
          plan = pruner.plan
          plan.versions.each { |name, version| puts "#{name.yellow} #{version}: version beyond retention" }
          plan.packages.each { |name| puts "#{name.yellow}: in service but no longer in the repository" }

          if plan.empty?
            puts 'Nothing to prune'
          elsif options['apply']
            pruner.apply(plan)
            puts '[  OK ] '.green + "#{plan.versions.size} versions deleted, #{plan.packages.size} packages taken out of service"
          else
            puts 'Nothing done: run again with --apply to remove them'
          end
        end
      end

      desc 'status', 'Versions in service and last loads'

      def status
        refusing_failures { print_status }
      end

      private

        # What the serving database needs besides the packages
        def prepare
          get('server.meta').setup
          get('server.api_role')&.ensure
        end

        # @param [Boolean] quiet say nothing of a bundle that did not change
        # @return [Array<Server::Bundles::Result>]
        def assemble_bundles(quiet:)
          get('server.bundles').assemble_all.each { |result| print_bundle(result, quiet: quiet) }
        rescue SystemCallError => e
          puts '[ NOK ] '.red + "bundles: #{e.message}"

          []
        end

        # @param [Server::Bundles::Result] result
        def print_bundle(result, quiet:)
          label = "bundle #{result.name.yellow}"
          return puts('[ NOK ] '.red + "#{label}: #{result.error}") if result.outcome.nil?

          outcome = result.outcome
          puts "[  == ] #{label} already made of the packages in service" if outcome.unchanged? && outcome.missing.empty? && !quiet
          outcome.linked.each { |package| puts '[  OK ] '.green + "#{label}: #{package}" }
          outcome.pruned.each { |package| puts "        #{label}: #{package} removed, no longer in the repository" }
          outcome.removed.each { |name| puts "        #{label}: #{name} removed, no longer in its definition" }
          return if quiet && outcome.unchanged?

          outcome.missing.each { |entry| puts '[ NOK ] '.red + "#{label}: #{entry[:name]} #{entry[:reason]}" }
        end

        def refusing_failures
          yield
        rescue Server::LoadFailure => e
          puts '[ NOK ] '.red + e.message
          exit 1
        end

        def print_status
          meta = get('server.meta')
          meta.setup
          repository = get('packaging.repository')
          installed = meta.all_installed

          installed.each do |package|
            current = repository.current(package.name)
            behind = current && current != package.version ? " (repository: #{current})".red : ''
            stale = package.stale ? ' stale'.red : ''
            puts "#{package.name.ljust(32).yellow} #{package.version}  #{package.loaded_at.strftime('%Y-%m-%d %H:%M')}#{stale}#{behind}"
          end
          (repository.names - installed.map(&:name)).each do |name|
            puts "#{name.ljust(32).yellow} #{'not in service'.red} (repository: #{repository.current(name)})"
          end

          puts "\nLast loads:"
          meta.recent_loads.each do |load|
            state = load['state'] == 'swapped' ? load['state'].green : load['state'].red
            puts "#{load['started_at'][0, 16]}  #{load['name'].ljust(32)} #{load['version']}  #{state}"
          end
        end

        # @param [Server::Loader::Outcome] outcome
        def print_outcome(outcome)
          label = "#{outcome.name.yellow} #{outcome.version}"

          case outcome.state
          when :swapped
            puts '[  OK ] '.green + label + (outcome.previous ? " replaces #{outcome.previous}" : ' in service')
          when :up_to_date
            puts "[  == ] #{label} already in service"
          else
            puts '[ NOK ] '.red + label + ': ' + outcome.reasons.join(' ; ')
          end
        end
    end
  end
end
