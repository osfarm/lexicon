# frozen_string_literal: true

module Lexicon
  module Datasource
    module Executor
      class SequentialExecutor < Base
        def initialize(runner:, **options)
          super(**options)

          @runner = runner
        end

        def run(*datasource_classes, action: :run)
          datasource_classes.each do |klass|
            @runner.handle(build_datasource(klass), action: action)
          end
        end
      end
    end
  end
end
