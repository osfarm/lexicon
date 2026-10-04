# frozen_string_literal: true

module Lexicon
  module Common
    module Mixin
      module SchemaNamer
        protected

          # @param [Semantic::Version] version
          # @return [String]
          def version_to_schema(version)
            "lexicon__#{version.to_s.gsub('.', '_')}"
          end

          # @param [String] schema
          # @return [Semantic::Version, nil]
          def schema_to_version(schema)
            Semantic::Version.new(schema.sub(/\Alexicon__/, '').gsub('_', '.'))
          end
      end
    end
  end
end
