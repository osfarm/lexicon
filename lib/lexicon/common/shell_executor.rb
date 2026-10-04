# frozen_string_literal: true

module Lexicon
  module Common
    class ShellExecutor
      include Mixin::Finalizable

      def initialize
        @command_dir = Dir.mktmpdir
      end

      # @param [String] command
      # @return [String]
      def execute(command)
        cmd = Tempfile.new('command-', @command_dir)
        cmd.write <<~BASH
          #!/usr/bin/env bash
          set -e

          #{command}
        BASH
        cmd.close

        `bash #{cmd.path}`
      ensure
        cmd.close
        cmd.unlink
      end

      def finalize
        if !@command_dir.nil?
          FileUtils.rm_rf(@command_dir)
        end
      end
    end
  end
end
