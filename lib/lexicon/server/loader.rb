# frozen_string_literal: true

module Lexicon
  module Server
    # Puts packages of the repository in service.
    class Loader
      # Any constant works, as long as every loader of a database uses the same
      ADVISORY_LOCK = 5_394_201

      Outcome = Struct.new(:name, :version, :previous, :state, :reasons, keyword_init: true)

      # @param [PG::Connection] connection
      # @param [Packaging::Repository] repository
      # @param [Meta] meta
      # @param [Stager] stager
      # @param [Checker] checker
      # @param [Swapper] swapper
      def initialize(connection:, repository:, meta:, stager:, checker:, swapper:)
        @connection = connection
        @repository = repository
        @meta = meta
        @stager = stager
        @checker = checker
        @swapper = swapper
      end

      # @param [Array<String>] targets names, or name@version. All the repository if empty
      # @param [Boolean] force reload a version already in service, accept drops of volume
      # @param [Boolean] together swap all the packages at once: all are put in service, or none
      # @yieldparam [Outcome] outcome of each package, as soon as known
      # @return [Array<Outcome>]
      def sync(targets = [], force: false, together: false, &block)
        meta.setup

        with_lock do
          manifests = ordered(manifests(targets))
          groups = together ? [manifests] : manifests.map { |manifest| [manifest] }

          groups.flat_map { |group| load_group(group, force: force).each { |outcome| block&.call(outcome) } }
        end
      end

      # Puts back in service the version a package replaced.
      #
      # @param [String] name
      # @return [Outcome]
      def rollback(name)
        meta.setup
        undone = meta.load_in_service(name)
        raise LoadFailure.new("#{name} is not in service") if undone.nil?
        raise LoadFailure.new("#{name} #{undone['version']} did not replace any version") if undone['previous'].nil?
        if repository.manifest(name, undone['previous']).nil?
          raise LoadFailure.new("the package #{name}@#{undone['previous']} is no longer in #{repository.root}")
        end

        outcome = sync(["#{name}@#{undone['previous']}"], force: true).first
        if outcome.state == :swapped
          meta.update_load(undone['id'].to_i, 'rolled_back')
          repository.set_current(name, undone['previous'])
        end

        outcome
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [Packaging::Repository]
        attr_reader :repository
        # @return [Meta]
        attr_reader :meta
        # @return [Stager]
        attr_reader :stager
        # @return [Checker]
        attr_reader :checker
        # @return [Swapper]
        attr_reader :swapper

        # @return [Array<Packaging::Manifest>]
        def manifests(targets)
          targets = repository.names if targets.empty?

          targets.map do |target|
            name, version = target.split('@', 2)
            version ||= repository.current(name)
            manifest = version && repository.manifest(name, version)
            raise LoadFailure.new("no package #{target} in #{repository.root}") if manifest.nil?

            manifest
          end
        end

        # Referenced packages first
        def ordered(manifests)
          by_name = manifests.map { |manifest| [manifest.name, manifest] }.to_h
          result = []
          visit = lambda do |manifest|
            next if result.include?(manifest)

            manifest.depends_on.each do |dependency|
              visit.call(by_name[dependency[:name]]) if by_name.key?(dependency[:name]) && dependency[:name] != manifest.name
            end
            result << manifest unless result.include?(manifest)
          end
          manifests.each { |manifest| visit.call(manifest) }

          result
        end

        # @param [Array<Packaging::Manifest>] group packages to swap in one transaction
        # @return [Array<Outcome>]
        def load_group(group, force:)
          installed = group.map { |manifest| [manifest.name, meta.installed(manifest.name)] }.to_h
          outcomes = group.map do |manifest|
            previous = installed[manifest.name]&.version
            state = !force && previous == manifest.version ? :up_to_date : nil

            Outcome.new(name: manifest.name, version: manifest.version, previous: previous, state: state, reasons: [])
          end
          pending = group.zip(outcomes).reject { |_manifest, outcome| outcome.state == :up_to_date }.map(&:first)
          replace(pending, installed, outcomes, force: force) if pending.any?

          outcomes
        end

        def replace(manifests, installed, outcomes, force:)
          pending = outcomes.select { |outcome| outcome.state.nil? }
          load_ids = manifests.map { |manifest| meta.start_load(manifest.name, manifest.version, installed[manifest.name]&.version) }

          put_in_service(manifests, installed, load_ids, force: force)
          pending.each { |outcome| outcome.state = :swapped }
        rescue LoadFailure, PG::Error => e
          manifests.each { |manifest| stager.discard(manifest) }
          reasons = e.is_a?(LoadFailure) ? e.reasons : [e.message.strip]
          load_ids&.each { |load_id| meta.update_load(load_id, 'failed', detail: { reasons: reasons }) }
          pending.each do |outcome|
            outcome.state = :failed
            outcome.reasons = reasons
          end
        end

        def put_in_service(manifests, installed, load_ids, force:)
          started_at = Time.now
          names = manifests.map(&:name)
          refuse(manifests.flat_map do |manifest|
            checker.before_staging(manifest, installed: installed[manifest.name], force: force, together: names)
          end)

          loaded = manifests.map { |manifest| stager.stage(repository.package_dir(manifest.name, manifest.version), manifest) }
                            .reduce({}, :merge)
          staged_at = Time.now
          load_ids.each { |load_id| meta.update_load(load_id, 'checking') }
          refuse(checker.after_staging(manifests, loaded: loaded))

          swapper.swap(manifests, previous_tables: names.flat_map { |name| meta.tables_of(name) }) do
            manifests.each { |manifest| meta.record_package(manifest) }
            meta.refresh_stale
            detail = { staging_seconds: (staged_at - started_at).round(1), total_seconds: (Time.now - started_at).round(1) }
            manifests.zip(load_ids).each do |manifest, load_id|
              rows = manifest.tables.map { |table| [table[:name], loaded[table[:name]]] }.to_h
              meta.update_load(load_id, 'swapped', detail: detail.merge(rows: rows, together: names - [manifest.name]))
            end
          end
        end

        def refuse(reasons)
          raise LoadFailure.new(reasons.uniq) if reasons.any?
        end

        def with_lock
          locked = connection.exec_params('SELECT pg_try_advisory_lock($1)', [ADVISORY_LOCK]).getvalue(0, 0) == 't'
          raise LoadFailure.new('another load is running on this database') unless locked

          begin
            yield
          ensure
            connection.exec_params('SELECT pg_advisory_unlock($1)', [ADVISORY_LOCK])
          end
        end
    end
  end
end
