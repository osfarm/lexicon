# frozen_string_literal: true

module Lexicon
  module Common
    module Schema
      class ValidatorFactory
        # @param [Pathname] schema_path
        def initialize(schema_path)
          @schema_path = schema_path
        end

        # @return [JSONSchemer::Schema::Base]
        def build
          JSONSchemer.schema(schema_path)
        end

        private

          # @return [Pathname]
          attr_reader :schema_path
      end
    end
  end
end
