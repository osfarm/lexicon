# frozen_string_literal: true

module Lexicon
  module Dsl
    module Packaging
      extend ActiveSupport::Concern

      module ClassMethods
        # Revision of the tables structure. Bump it when a published table changes shape.
        #
        # @param [Integer, nil] revision
        # @return [Integer]
        def schema_revision(revision = nil)
          @schema_revision = revision unless revision.nil?

          @schema_revision || 1
        end

        # Datasources read during normalize that no foreign key reveals.
        #
        # @param [Array<#to_s>] names
        def depends_on(*names)
          @dependencies = (get_dependencies + names.map(&:to_s)).uniq
        end

        # @return [Array<String>]
        def get_dependencies
          @dependencies || []
        end

        # Prefixes of the identifiers this datasource writes in master_translations: its package ships
        # them in a table of its own.
        #
        # @param [Array<#to_s>] prefixes
        def translations(*prefixes)
          @translation_prefixes = (get_translation_prefixes + prefixes.map(&:to_s)).uniq
        end

        # @return [Array<String>]
        def get_translation_prefixes
          @translation_prefixes || []
        end

        # A datasource that is not packaged only exists on the build side.
        #
        # @param [Boolean] value
        def packaged(value)
          @packaged = value
        end

        # @return [Boolean]
        def packaged?
          @packaged != false
        end
      end
    end
  end
end
