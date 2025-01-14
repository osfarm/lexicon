# frozen_string_literal: true

using Corindon::Result::Ext

module Lexicon
  module Flavor
    class FlavorLoader
      # @param [Pathname] dir
      # @param [JSONSchemer::Schema::Base] validator
      def initialize(dir:, validator:)
        @dir = dir
        @validator = validator
      end

      # @param [String] name
      # @return [Corindon::Result::Result<LexiconFlavor>]
      def load(name)
        file = dir.join("#{name}.yml")

        if file.exist?
          load_file(file)
        else
          Failure(StandardError.new("The file for flavor #{name} could not be found"))
        end
      end

      private

        # @return [Pathname]
        attr_reader :dir
        # @return [JSONSchemer::Schema::Base]
        attr_reader :validator

        # @param [Pathname] file
        # @return [Corindon::Result::Result<LexiconFlavor>]
        def load_file(file)
          rescue_failure do
            data = YAML.safe_load(file.read)

            if validator.valid?(data)
              Success(
                LexiconFlavor.new(
                  data.fetch('name'),
                  only: data.fetch('only', nil),
                  without: data.fetch('without', []),
                  datasources: load_datasources(data.fetch('datasources', {}))
                )
              )
            else
              Failure(StandardError.new('The content of the flavor file seems invalid'))
            end
          end
        end

        # @return [Hash{String=>DatasourceFlavor}]
        def load_datasources(data)
          data.map do |name, datasource_data|
            [
              name,
              DatasourceFlavor.new(
                name,
                tables: load_tables(datasource_data)
              )
            ]
          end.to_h
        end

        # @param [Hash{String=>String}] data
        # @return [Hash{String=>FlavorTable}]
        def load_tables(data)
          data.map { |name, table_data| [name, FlavorTable.new(name, filter: table_data.fetch('filter'))] }
              .to_h
        end
    end
  end
end
