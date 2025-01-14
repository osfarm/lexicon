# frozen_string_literal: true

module Lexicon
  module Datasource
    class CachedResourceCollector
      # @param [Cache::ResourceCache] cache
      # @param [ResourceCollector] collector
      def initialize(cache:, collector:)
        @cache = cache
        @collector = collector
      end

      # @param [Datasource::Resource] resource
      # @param [Pathname] to
      # @return [Boolean]
      def collect(resource, to:)
        dest = to.join(resource.name)

        @cache.fetch(resource) do
          @collector.collect(resource, to: to)

          dest
        end
      end
    end
  end
end
