# frozen_string_literal: true

module Lexicon
  module Server
    # Keeps the tracked bundles of the repository made of the packages in service. A bundle is tracked when
    # the build side sent its definition; a directory without one is a bundle sent whole, left as it is.
    class Bundles
      # :outcome is nil and :error says why when the bundle could not be assembled
      Result = Struct.new(:name, :outcome, :error, keyword_init: true)

      # @param [Packaging::Repository] repository the repository of the serving side
      # @param [Meta] meta
      # @param [Packaging::BundleAssembler, nil] assembler
      def initialize(repository:, meta:, assembler: nil)
        @root = repository.root.join(Packaging::Publisher::BUNDLES_DIR)
        @meta = meta
        @assembler = assembler || Packaging::BundleAssembler.new(source: repository, root: @root)
      end

      # A bundle that fails does not stop the others, and never a load.
      #
      # @return [Array<Result>]
      def assemble_all
        versions = @meta.all_installed.map { |package| [package.name, package.version] }.to_h

        definition_files.map do |file|
          name = file.dirname.basename.to_s
          begin
            Result.new(name: name, outcome: @assembler.assemble(definition(file, name), versions: versions))
          rescue ArgumentError, SystemCallError => e
            Result.new(name: name, error: e.message)
          end
        end
      end

      private

        # @return [Array<Pathname>]
        def definition_files
          return [] unless @root.directory?

          @root.children.select(&:directory?).map { |dir| dir.join(Packaging::BundleDefinition::FILE_NAME) }.select(&:file?).sort
        end

        # The directory names the bundle: a definition cannot write into the bundle of another
        def definition(file, name)
          Packaging::BundleDefinition.load(file).tap do |definition|
            raise ArgumentError.new("#{file} defines #{definition.name}, not #{name}") if definition.name != name
          end
        end
    end
  end
end
