# frozen_string_literal: true

require 'uri'
require 'progress_bar'

module Lexicon
  class Downloader
    include Common::Mixin::LoggerAware

    attr_reader :base_dir

    def initialize(base_dir, executor:)
      @base_dir = Pathname.new(base_dir)
      @executor = executor
    end

    def absolute_path_for(*path)
      @base_dir.join(*path)
    end

    def curl(url, out:)
      path = absolute_path_for out

      if_missing path do
        @executor.execute <<~BASH
          curl -C - -L -o '#{path}' '#{url}'
        BASH
      end
    end

    private

      def if_missing(path, &block)
        if path.exist?
          log "File exist: #{path}, Skipping"
          false
        else
          block.call unless path.exist?
        end
      end
  end
end
