# frozen_string_literal: true

require 'json'
require 'time'
require 'tmpdir'

module Lexicon
  module Packaging
    # Sends packages to the repository of the serving side, then designates them in its index.
    class Publisher
      BUNDLES_DIR = '_bundles'

      # @param [Repository] repository local repository
      # @param [String] target remote repository, as rsync names it: a directory or host:path
      # @param [Rsync] transfer
      def initialize(repository:, target:, transfer: Rsync.new)
        @repository = repository
        @target = target.chomp('/')
        @transfer = transfer
      end

      # @param [String] name
      # @param [String, nil] version the latest local one by default
      # @return [String] the version published
      def publish(name, version: nil)
        version ||= repository.versions(name).last
        if version.nil? || repository.manifest(name, version).nil?
          raise ArgumentError.new("No package #{name}@#{version} in #{repository.root}")
        end

        send_package(name, version)
        designate(name, version)

        version
      end

      # Sends a bundle, a whole repository of packages, to the private area of the serving side. Its files
      # are only handed out by the API, to the keys carrying the scope of the bundle.
      #
      # @param [Pathname] dir local repository of the bundle
      # @param [String] flavor
      def publish_bundle(dir, flavor)
        raise ArgumentError.new("No bundle in #{dir}") unless dir.join(Repository::INDEX_FILE).file?

        destination = "#{target}/#{BUNDLES_DIR}/#{flavor}"
        transfer.copy_directory(dir, destination, exclude: [Repository::INDEX_FILE], permissions: Rsync::PRIVATE)
        transfer.copy_file(dir.join(Repository::INDEX_FILE), "#{destination}/#{Repository::INDEX_FILE}",
                           permissions: Rsync::PRIVATE)
      end

      # @return [Hash{String => Hash}] for each datasource of the remote index, :current and :versions
      def published
        remote_index.fetch(:datasources, {}).transform_keys(&:to_s)
      end

      # @return [Hash{String => Hash}] for each package the serving side reports in service, :version,
      #   :loaded_at and :stale. Empty when it reports nothing
      def in_service
        remote_json(Server::StatusFile::FILE_NAME).fetch(:packages, {}).transform_keys(&:to_s)
      end

      private

        # @return [Repository]
        attr_reader :repository
        # @return [String]
        attr_reader :target
        # @return [Rsync]
        attr_reader :transfer

        # The manifest goes last: a version without manifest does not exist for the serving side
        def send_package(name, version)
          source = repository.package_dir(name, version)
          destination = "#{target}/#{name}/#{version}"
          # A package reserved to key holders is loaded by the serving side, but not downloadable
          permissions = repository.manifest(name, version).open? ? Rsync::PUBLIC : Rsync::PRIVATE

          transfer.copy_directory(source, destination, exclude: [Manifest::FILE_NAME], permissions: permissions)
          transfer.copy_file(source.join(Manifest::FILE_NAME), "#{destination}/#{Manifest::FILE_NAME}",
                             permissions: permissions)

          differences = transfer.differences(source, destination)
          raise Rsync::TransferError.new("#{name}@#{version} differs once sent: #{differences.join(', ')}") if differences.any?
        end

        # The index is the only file changed in place; rsync replaces it atomically
        def designate(name, version)
          data = remote_index
          entry = data.fetch(:datasources, {}).fetch(name.to_sym, {})
          versions = (entry.fetch(:versions, []) | [version]).sort_by { |other| other.split('.').map(&:to_i) }
          data[:datasources] = data.fetch(:datasources, {}).merge(name.to_sym => { current: version, versions: versions })
          data[:updated_at] = Time.now.utc.iso8601

          Dir.mktmpdir do |dir|
            file = Pathname.new(dir).join(Repository::INDEX_FILE)
            file.write("#{JSON.pretty_generate(data)}\n")
            transfer.copy_file(file, "#{target}/#{Repository::INDEX_FILE}")
          end
        end

        # @return [Hash]
        def remote_index
          remote_json(Repository::INDEX_FILE)
        end

        # @return [Hash] empty when the file does not exist
        def remote_json(name)
          Dir.mktmpdir do |dir|
            file = Pathname.new(dir).join(name)

            transfer.fetch_file("#{target}/#{name}", file) ? JSON.parse(file.read, symbolize_names: true) : {}
          end
        end
    end
  end
end
