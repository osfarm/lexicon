# frozen_string_literal: true

module Lexicon
  module Packaging
    # Local directory of packages, laid out as <root>/<datasource>/<version>/
    class Repository
      VERSION_FORMAT = /\A\d{4}\.\d{2}\.\d{2}\.\d+\z/.freeze

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
        return nil if version.nil?

        Manifest.load(package_dir(name, version).join(Manifest::FILE_NAME))
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

        def sort_key(version)
          version.split('.').map(&:to_i)
        end
    end
  end
end
