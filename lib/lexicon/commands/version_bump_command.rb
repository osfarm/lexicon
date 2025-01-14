# frozen_string_literal: true

module Lexicon
  module Commands
    class VersionBumpCommand < ContainerAwareCommand
      default_command :patch

      desc 'patch', 'Bumps the patch version'
      def patch
        bump(:patch)
      end

      desc 'minor', 'Bumps the minor version'
      def minor
        bump(:minor)
      end

      desc 'major', 'Bumps the major version'
      def major
        bump(:major)
      end

      private

        def bump(part)
          puts "Lexicon is now at version #{get('version.bumper').bump(part)}"
        end
    end
  end
end
