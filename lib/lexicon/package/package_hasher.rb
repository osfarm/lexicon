# frozen_string_literal: true

module Lexicon
  module Package
    class PackageHasher
      # @param [ShellExecutor] shell
      def initialize(shell:)
        @shell = shell
      end

      # @param [Common::Package::PackageBuilder] builder
      def compute_package_hash(builder)
        shell.execute <<~BASH
          (cd "#{builder.dir}" && sha256sum "lexicon.json" data/* > "#{builder.checksum_file}")
        BASH
      end

      private

        # @return [ShellExecutor]
        attr_reader :shell
    end
  end
end
