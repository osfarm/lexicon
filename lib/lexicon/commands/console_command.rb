# frozen_string_literal: true

module Lexicon
  module Commands
    class ConsoleCommand < ContainerAwareCommand
      default_command :exec_command

      desc 'run console', ''

      def exec_command
        # rubocop:disable Lint/Debugger
        binding.pry
        # rubocop:enable Lint/Debugger
      end

      private

        %i[collect load normalize].each do |meth|
          define_method meth do |*names|
            get('datasource.name_runner').run(names, action: meth)
          end
        end

        def version_bump(part)
          get('version.bumper').bump(part)
        end

        def release(*names)
          get('database.dumper').dump(get('version'), datasource_names: names)
        end

        def load_package(version = nil)
          version ||= get('version')

          get('production.package.loader').load_package(version)
        end
    end
  end
end
