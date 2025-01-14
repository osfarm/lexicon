# frozen_string_literal: true

module Lexicon
  class VersionBumper
    def initialize(version:, file:)
      @version = version
      @file = file
    end

    def bump(part)
      File.write(@file, (version = bump_version(@version, part)))

      version
    end

    private

      def bump_version(version, part)
        Semantic::Version.new(version).increment!(part).to_s
      end
  end
end
