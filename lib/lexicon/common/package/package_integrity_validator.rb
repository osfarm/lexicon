# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      class PackageIntegrityValidator
        # @param [ShellExecutor] shell
        def initialize(shell:)
          @shell = shell
        end

        # @param [Package] package
        # @return [Boolean]
        def valid?(package)
          integrity_states(package).values.all? { |v| v == true }
        end

        # @param [Package] package
        # @return [Hash{String => Boolean}]
        def integrity_states(package)
          sumstr = shell.execute <<~BASH
            (cd "#{package.dir}" && sha256sum -c #{package.checksum_file.basename} 2>/dev/null)
          BASH

          sumstr.scan(/(.*?): (.*?)\n/)
                .to_h
                .transform_values { |value| value == 'OK' }
        end

        protected

          # @return [ShellExecutor]
          attr_reader :shell
      end
    end
  end
end
