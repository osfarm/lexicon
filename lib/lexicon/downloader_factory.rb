# frozen_string_literal: true

module Lexicon
  class DownloaderFactory
    attr_reader :root, :logger, :executor

    def initialize(root, logger:, executor:)
      @root = root
      @logger = logger
      @executor = executor
    end

    def create(destination)
      dir = @root.join(destination.to_s)

      ensure_raw_folder_present(dir)

      dl = Downloader.new(dir, executor: executor)
      dl.logger = logger

      dl
    end

    def ensure_raw_folder_present(dir)
      FileUtils.mkdir_p(dir.to_s)
    end
  end
end
