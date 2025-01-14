# frozen_string_literal: true

module Lexicon
  module Commands
    class VersionCommand < ContainerAwareCommand
      default_command :print

      desc 'print', 'Displays the version'
      def print
        puts "Lexicon version #{get('version').green}"
      end

      desc 'bump [majon/minor/PATCH]', 'Bumps the lexicon version'
      subcommand 'bump', VersionBumpCommand
    end
  end
end
