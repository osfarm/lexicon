# frozen_string_literal: true

module Lexicon
  module Datasource
    class NameRunner
      include Common::Mixin::LoggerAware
      attr_reader :datasource_provider, :executor

      def initialize(datasource_provider:, executor:)
        @datasource_provider = datasource_provider
        @executor = executor
      end

      def run(datasource_names, action:)
        datasource_classes, unknown = classes_from_names(datasource_names)
        puts("Unknown datasources: #{unknown.join(', ')}") if unknown.any?

        executor.run(*datasource_classes, action: action)
      end

      private

        def classes_from_names(names)
          if names.empty?
            [datasource_provider.values, []]
          else
            datasources, unknown = names
                                   .map { |n| [n, datasource_provider.get(n)] }
                                   .partition{ |(_k, v)| v.present? }

            [datasources.map(&:second), unknown.map(&:first)]
          end
        end
    end
  end
end
