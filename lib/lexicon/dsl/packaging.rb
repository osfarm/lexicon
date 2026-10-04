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

        # Who may read the datasource: 'open' for everyone, 'members' for the holders of an API key.
        # A package that is not open is published unreadable by the public file server.
        #
        # @param [#to_s, nil] value
        # @return [String]
        def scope(value = nil)
          @scope = value.to_s unless value.nil?

          @scope || Lexicon::Packaging::Manifest::OPEN_SCOPE
        end

        # Declares that a column carries a pivot key (see Lexicon::Packaging::Pivots). The share of its
        # values found in the reference is measured at each build and published with the package.
        #
        # @param [#to_s] key
        # @param [#to_s] table
        # @param [#to_s] column
        # @param [Float, nil] minimum share of values that must match for the datasource to pass `check`
        def pivot(key, table:, column:, minimum: nil)
          Lexicon::Packaging::Pivots.fetch(key)
          @pivots = get_pivots + [{ key: key.to_s, table: table.to_s, column: column.to_s, minimum: minimum }.compact]
        end

        # @return [Array<Hash>]
        def get_pivots
          @pivots || []
        end

        # States why columns that look like personal data can be published: for instance because they only
        # hold legal entities, or because the source publishes them by law.
        #
        # @param [String, nil] reason
        # @return [String, nil]
        def personal_data(reason = nil)
          @personal_data = reason unless reason.nil?

          @personal_data
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
