# frozen_string_literal: true

module Lexicon
  module Datasource
    module Executor
      class ParallelExecutor < Base
        def initialize(runner:, **options)
          super(**options)

          @runner = runner
        end

        def run(*datasource_classes, action: :run)
          if action == :run
            run(*datasource_classes, action: :collect)
            run(*datasource_classes, action: :load)
            run(*datasource_classes, action: :normalize)
          else
            datasources = datasource_classes.map { |klass| build_datasource(klass) }

            begin
              threads = datasources.map do |datasource|
                Thread.new do
                  @runner.handle(datasource, action: action)
                end
              end
            ensure
              threads.each(&:join)
            end
          end
        end
      end
    end
  end
end
