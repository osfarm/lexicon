# frozen_string_literal: true

module Lexicon
  module Packaging
    # Local directory of packages, laid out as <root>/<datasource>/<version>/
    class Repository
      VERSION_FORMAT = /\A\d{4}\.\d{2}\.\d{2}\.\d+\z/.freeze
      INDEX_FILE = 'index.json'

      # @return [Pathname]
      attr_reader :root

      # @param [Pathname] root
      def initialize(root)
        @root = root
      end

      # @param [String] name
      # @return [Pathname]
      def datasource_dir(name)
        root.join(name)
      end

      # @param [String] name
      # @param [String] version
      # @return [Pathname]
      def package_dir(name, version)
        datasource_dir(name).join(version)
      end

      # @return [Array<String>] datasources having at least one complete version
      def names
        return [] unless root.directory?

        root.children.select(&:directory?).map { |child| child.basename.to_s }.select { |name| versions(name).any? }.sort
      end

      # @param [String] name
      # @param [String] version
      # @return [Manifest, nil]
      def manifest(name, version)
        file = package_dir(name, version).join(Manifest::FILE_NAME)

        file.file? ? Manifest.load(file) : nil
      end

      # @param [String] name
      # @return [String, nil] the version to serve: the one the index designates, or else the latest
      def current(name)
        index.dig(:datasources, name.to_sym, :current) || versions(name).last
      end

      # @param [String] name
      # @return [Array<String>] complete versions, oldest first
      def versions(name)
        dir = datasource_dir(name)
        return [] unless dir.directory?

        dir.children
           .select { |child| child.directory? && child.join(Manifest::FILE_NAME).file? }
           .map { |child| child.basename.to_s }
           .grep(VERSION_FORMAT)
           .sort_by { |version| sort_key(version) }
      end

      # @param [String] name
      # @return [Manifest, nil]
      def latest(name)
        version = versions(name).last

        version && manifest(name, version)
      end

      # @param [String] name
      # @param [Date] date
      # @return [String] <year>.<month>.<day>.<n>, n being the next free rank for that day
      def next_version(name, date)
        prefix = date.strftime('%Y.%m.%d')
        ranks = versions(name).select { |version| version.start_with?("#{prefix}.") }
                              .map { |version| version.split('.').last.to_i }

        "#{prefix}.#{(ranks.max || 0) + 1}"
      end

      private

        # @return [Hash]
        def index
          file = root.join(INDEX_FILE)

          file.file? ? JSON.parse(file.read, symbolize_names: true) : {}
        end

        def sort_key(version)
          version.split('.').map(&:to_i)
        end
    end
  end
end
