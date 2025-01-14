# frozen_string_literal: true

module Lexicon
  class Container
    include Dry::Container::Mixin

    class Resolver < Dry::Container::Resolver
      def call(container, key)
        item = super(container, key)

        if item.is_a? Common::Mixin::ContainerAware
          item.container = container
        end

        if item.is_a? Common::Mixin::LoggerAware
          item.logger = container.fetch('logger').call
        end

        item
      end
    end

    config.resolver = Resolver.new

    def get(service)
      resolve(service)
    end
  end
end
