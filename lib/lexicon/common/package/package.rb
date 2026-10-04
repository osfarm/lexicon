# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      class Package
        SPEC_FILE_NAME = 'lexicon.json'
        CHECKSUM_FILE_NAME = 'lexicon.sum'

        # @return [Pathname]
        attr_reader :checksum_file, :spec_file
        # @return [Pathname]
        attr_reader :dir
        # @return [Semantic::Version]
        attr_reader :version
        # @return [Integer]
        attr_reader :schema_version

        # @param [Pathname] checksum_file
        # @param [Pathname] dir
        # @param [Integer] schema_version
        # @param [Pathname] spec_file
        # @param [Semantic::Version] version
        def initialize(checksum_file:, dir:, schema_version:, spec_file:, version:)
          @checksum_file = checksum_file
          @dir = dir
          @schema_version = schema_version
          @spec_file = spec_file
          @version = version
        end

        # @return [Boolean]
        def valid?
          checksum_file.exist? && dir.directory? && files.all? { |f| f.path.exist? rescue false }
        end

        # @return [Array<PackageFile>] Array of File of the package
        def files
          []
        end
      end
    end
  end
end
