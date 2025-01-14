# frozen_string_literal: true

module Lexicon
  module Commands
    module Compute
      extend ActiveSupport::Concern

      included do
        desc 'run', 'Run datasources (collect, load, normalize)'
        method_option :names, default: [], type: :array
        def run_(*names)
          do_run(:run, names)
        end

        desc 'collect', 'Collect datasources'
        method_option :names, default: [], type: :array
        def collect(*names)
          do_run(:collect, names)
        end

        desc 'load', 'Load datasources'
        method_option :names, default: [], type: :array
        def load(*names)
          do_run(:load, names)
        end

        desc 'normalize', 'Normalize datasources'
        method_option :names, default: [], type: :array
        def normalize(*names)
          do_run(:normalize, names)
        end
      end

      private

        def do_run(action, datasource_names)
          runner = get('datasource.name_runner')

          runner.run datasource_names, action: action
        end
    end
  end
end
