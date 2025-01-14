# frozen_string_literal: true

module Lexicon
  class LexiconVersion
    # @return [Semantic::Version]
    attr_reader :version
    attr_reader :root_path, :datasources

    def initialize(version, root_path, datasources)
      @version = version
      @root_path = root_path
      @datasources = datasources
    end
  end
end
