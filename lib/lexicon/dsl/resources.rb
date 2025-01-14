# frozen_string_literal: true

module Lexicon
  module Dsl
    module Resources
      extend ActiveSupport::Concern

      module ClassMethods
        # @param [String] name
        # @option [String] url
        def resource(name, url: nil, source: nil)
          if url.nil?
            source = name if source.nil?

            add_resource Datasource::LocalResource.new(name, source: source)
          else
            add_resource Datasource::RemoteResource.new(name, url: url)
          end
        end

        # @return [Array<Datasource::Resource>]
        def resources
          [*@resources]
        end

        private

          def add_resource(resource)
            @resources ||= []

            @resources << resource
          end
      end
    end
  end
end
