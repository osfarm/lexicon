# frozen_string_literal: true

module Lexicon
  module Datasource
    class RemoteResource < Resource
      attr_reader :url

      def initialize(name, url:)
        super(name)

        @url = url
      end

      alias key url
    end
  end
end
