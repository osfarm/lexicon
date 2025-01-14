# frozen_string_literal: true

module Lexicon
  module Database
    class DumperBase
      include Common::Mixin::LoggerAware

      def initialize(target_dir:)
        @target_dir = target_dir
      end

      def ensure_data_dir(version)
        dir = ensure_version_dir(version).join('data')
        FileUtils.mkdir_p(dir)

        dir
      end

      def ensure_version_dir(version)
        dir = @target_dir.join(version)
        FileUtils.mkdir_p(dir)

        dir
      end
    end
  end
end
