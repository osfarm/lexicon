# frozen_string_literal: true

module Lexicon
  module Server
    # Puts packages of the repository in service, one datasource at a time.
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
      # @yieldparam [Outcome] outcome of each package, as soon as known
      # @return [Array<Outcome>]
      def sync(targets = [], force: false)
        meta.setup

        with_lock do
          ordered(manifests(targets)).map do |manifest|
            outcome = load_package(manifest, force: force)
            yield outcome if block_given?

            outcome
          end
        end
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

        # @return [Outcome]
        def load_package(manifest, force:)
          installed = meta.installed(manifest.name)
          outcome = Outcome.new(name: manifest.name, version: manifest.version, previous: installed&.version, reasons: [])

          if !force && installed&.version == manifest.version
            outcome.state = :up_to_date
            return outcome
          end

          load_id = meta.start_load(manifest.name, manifest.version, installed&.version)
          replace(manifest, installed, load_id, force: force)
          outcome.state = :swapped

          outcome
        rescue LoadFailure, PG::Error => e
          stager.discard(manifest)
          outcome.state = :failed
          outcome.reasons = e.is_a?(LoadFailure) ? e.reasons : [e.message.strip]
          meta.update_load(load_id, 'failed', detail: { reasons: outcome.reasons }) unless load_id.nil?

          outcome
        end

        def replace(manifest, installed, load_id, force:)
          started_at = Time.now
          refuse(checker.before_staging(manifest, installed: installed, force: force))

          loaded = stager.stage(repository.package_dir(manifest.name, manifest.version), manifest)
          staged_at = Time.now
          meta.update_load(load_id, 'checking')
          refuse(checker.after_staging(manifest, loaded: loaded))

          swapper.swap(manifest, previous_tables: meta.tables_of(manifest.name)) do
            meta.record_package(manifest)
            meta.update_load(load_id, 'swapped', detail: {
                               rows: loaded,
                               staging_seconds: (staged_at - started_at).round(1),
                               total_seconds: (Time.now - started_at).round(1)
                             })
          end
        end

        def refuse(reasons)
          raise LoadFailure.new(reasons) if reasons.any?
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
