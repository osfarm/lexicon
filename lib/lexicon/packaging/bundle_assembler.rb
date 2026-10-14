# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module Lexicon
  module Packaging
    # Makes a tracked bundle out of the packages of a repository, without copying them: each file of the
    # bundle is a hard link to the file of the package. A package of the bundle is the published one.
    class BundleAssembler
      STATE_FILE = 'state.json'
      WORK_PREFIX = '.assembling-'
      PRIVATE_DIRECTORY = 0o700

      # What a run did. :linked and :pruned are name@version, :missing gives :name and :reason
      Outcome = Struct.new(:name, :linked, :missing, :pruned, :removed, keyword_init: true) do
        # @return [Boolean] whether the run changed nothing
        def unchanged?
          linked.empty? && pruned.empty? && removed.empty?
        end
      end

      # @param [Repository] source the repository the packages come from
      # @param [Pathname] root directory holding one bundle per sub-directory
      def initialize(source:, root:)
        @source = source
        @root = root
      end

      # @param [BundleDefinition] definition
      # @param [Hash{String => String}] versions the version to designate for each datasource
      # @return [Outcome]
      def assemble(definition, versions:)
        bundle = Repository.new(root.join(definition.name))
        FileUtils.mkdir_p(bundle.root, mode: PRIVATE_DIRECTORY)

        missing = missing_packages(definition, versions)
        present = definition.datasources - missing.keys
        linked = present.select { |name| link_package(bundle, name, versions.fetch(name)) }
        entries, pruned = entries_of(bundle, definition, versions, present)

        # The index goes last: who downloads meanwhile sees the previous bundle, whole
        bundle.write_index(entries)
        pruned.each { |name, version| FileUtils.rm_rf(bundle.package_dir(name, version)) }
        removed = remove_strangers(bundle, definition)
        write_state(bundle, missing)

        Outcome.new(
          name: definition.name, linked: linked.map { |name| "#{name}@#{versions.fetch(name)}" },
          missing: missing.map { |name, reason| { name: name, reason: reason } },
          pruned: pruned.map { |name, version| "#{name}@#{version}" }, removed: removed
        )
      end

      # @param [String] name name of a bundle
      # @return [Hash] what the last run could not put in the bundle, empty when there was none
      def state(name)
        file = root.join(name, STATE_FILE)

        file.file? ? JSON.parse(file.read, symbolize_names: true) : {}
      end

      private

        # @return [Repository]
        attr_reader :source
        # @return [Pathname]
        attr_reader :root

        # @return [Hash{String => String}] why each datasource that cannot enter the bundle cannot
        def missing_packages(definition, versions)
          missing = definition.datasources.each_with_object({}) do |name, reasons|
            version = versions[name]
            if version.nil?
              reasons[name] = 'not in service'
            elsif source.manifest(name, version).nil?
              reasons[name] = "#{version} is not in the repository"
            end
          end

          # A package whose foreign keys point to an absent one would not load: it waits with it
          loop do
            blocked = (definition.datasources - missing.keys).map do |name|
              absent = references(name, versions.fetch(name))
                       .find { |other| missing.key?(other) || !definition.datasources.include?(other) }

              [name, "references #{absent}, absent from the bundle"] unless absent.nil?
            end.compact.to_h
            return missing if blocked.empty?

            missing.merge!(blocked)
          end
        end

        def references(name, version)
          source.manifest(name, version).depends_on
                .select { |dependency| dependency[:kind] == DependencyResolver::FOREIGN_KEY }
                .map { |dependency| dependency[:name] }
        end

        # @return [Boolean] false when the bundle already has the package
        def link_package(bundle, name, version)
          destination = bundle.package_dir(name, version)
          return false if published?(bundle, name, version)

          origin = source.package_dir(name, version)
          work = bundle.datasource_dir(name).join("#{WORK_PREFIX}#{version}")
          FileUtils.rm_rf([work, destination])
          FileUtils.mkdir_p(work.join(Builder::DATA_DIR), mode: PRIVATE_DIRECTORY)
          files_of(source.manifest(name, version)).each { |path| link(origin.join(path), work.join(path)) }
          File.rename(work, destination)

          true
        end

        def files_of(manifest)
          [Builder::STRUCTURE_FILE, Builder::INDEXES_FILE, *manifest.tables.flat_map { |table| table[:files] }.map { |file| file[:path] },
           Manifest::FILE_NAME]
        end

        # A copy when the bundle is on another file system, or when the files belong to someone else
        def link(origin, destination)
          File.link(origin, destination)
        rescue Errno::EXDEV, Errno::EPERM, Errno::EMLINK
          FileUtils.cp(origin, destination, preserve: true)
        end

        # The bundle keeps the versions the repository still has: its retention is the one of the repository.
        #
        # @return [Array(Hash, Array)] the entries of the index, and the name and version of what leaves the bundle
        def entries_of(bundle, definition, versions, present)
          pruned = []
          entries = definition.datasources.map do |name|
            current = present.include?(name) ? versions.fetch(name) : bundle.designated(name)
            next if current.nil?

            kept, gone = bundle.versions(name).partition do |version|
              !present.include?(name) || published?(bundle, name, version)
            end
            pruned.concat(gone.map { |version| [name, version] })

            [name, { current: current, versions: kept }]
          end

          [entries.compact.to_h, pruned]
        end

        # A version of the bundle is the package of the repository, not one of the same number made otherwise
        # (a bundle once exported from the build database)
        def published?(bundle, name, version)
          mine = bundle.package_dir(name, version).join(Manifest::FILE_NAME)
          theirs = source.package_dir(name, version).join(Manifest::FILE_NAME)

          mine.file? && theirs.file? && FileUtils.compare_file(mine, theirs)
        end

        # @return [Array<String>] datasources the definition no longer names, taken out of the bundle
        def remove_strangers(bundle, definition)
          bundle.root.children.select(&:directory?)
                .reject { |dir| dir.basename.to_s.start_with?('.', '_') || definition.datasources.include?(dir.basename.to_s) }
                .each { |dir| FileUtils.rm_rf(dir) }
                .map { |dir| dir.basename.to_s }.sort
        end

        # Rewritten only when what is missing changes: a run that changes nothing writes nothing
        def write_state(bundle, missing)
          entries = missing.map { |name, reason| { name: name, reason: reason } }
          return if state(bundle.root.basename.to_s).fetch(:missing, nil) == entries

          temporary = bundle.root.join(".#{STATE_FILE}.tmp")
          temporary.write("#{JSON.pretty_generate(assembled_at: Time.now.utc.iso8601, missing: entries)}\n")
          File.rename(temporary, bundle.root.join(STATE_FILE))
        end
    end
  end
end
