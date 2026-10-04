# frozen_string_literal: true

require 'date'

module Lexicon
  module Contribution
    # Tells whether a datasource can be accepted: what it declares, and, when its data is built, what it
    # contains. An error blocks the contribution; a warning asks for a human look.
    class Checker
      Finding = Struct.new(:level, :message, keyword_init: true)

      # Licences letting anyone reuse the data, commercially included
      OPEN_LICENCES = [
        /licence ouverte/i, /open licen[cs]e/i, /etalab/i, /\bCC0\b/i, /public domain/i, /domaine public/i,
        /\bCC[- ]BY(?![- ](NC|ND))/i, /\bODbL\b/i, /\bMIT\b/i, /apache/i,
        # Usual abbreviations of the French open licence
        /\ALO ?2(\.0)?\z/i, /\ALOOL\z/i
      ].freeze
      RESTRICTIVE_LICENCE = /\b(NC|ND)\b/i.freeze
      SHARE_ALIKE_LICENCE = /\bODbL\b|[- ]SA\b/i.freeze
      # Column names that usually hold data about natural persons
      PERSONAL_COLUMN = /(?:\A|_)(first_?name|firstname|last_?name|lastname|surname|prenom|nom_naissance|birth\w*|
                                  naissance\w*|e?mail|phone\w*|telephone\w*|iban|social_security\w*)(?:_|\z)/ix.freeze
      MINIMUM_ROWS_RATIO = 0.7

      # @param [Hash{String => Class<Datasources::Base>}] datasources every datasource, by name
      # @param [Hash{String => Database::Schema::TableDefinitionSet}] definitions
      # @param [Array<String>] tolerated datasources whose errors are known and being dealt with: they are
      #   reported as warnings, so that they do not hide the errors of a new contribution
      def initialize(datasources:, definitions:, tolerated: [])
        @datasources = datasources
        @definitions = definitions
        @tolerated = tolerated
      end

      # What can be said from the declarations alone, without any data.
      #
      # @param [String] name
      # @return [Array<Finding>]
      def static(name)
        datasource = @datasources.fetch(name)
        definition = @definitions[name]

        findings = [
          *description(datasource),
          *credits(datasource),
          *licence(datasource),
          *tables(datasource, definition),
          *personal_data(datasource, definition),
          *dependencies(name, datasource),
          *translations(name, datasource),
          *pivot_tables(datasource, definition)
        ]
        return findings unless @tolerated.include?(name)

        findings.map { |finding| finding.level == :error ? warning("known issue: #{finding.message}") : finding }
      end

      # What the built data says: to call once the datasource has been run.
      #
      # @param [String] name
      # @param [Array<Hash>] pivots measured by Packaging::PivotMeter
      # @param [Hash{String => Integer}] rows rows of each table
      # @param [Packaging::Manifest, nil] previous latest package of the datasource
      # @return [Array<Finding>]
      def data(name, pivots:, rows:, previous: nil)
        [
          *rows.select { |_table, count| count.zero? }.keys.map { |table| error("#{table} is empty") },
          *pivot_rates(pivots),
          *volume(rows, previous)
        ].tap { |findings| findings.unshift(error("#{name} declares no table")) if rows.empty? && @datasources.fetch(name).packaged? }
      end

      private

        def error(message)
          Finding.new(level: :error, message: message)
        end

        def warning(message)
          Finding.new(level: :warning, message: message)
        end

        def description(datasource)
          datasource.description.to_s.strip.empty? ? [error('no description')] : []
        end

        def credits(datasource)
          credits = datasource.get_credits
          return [error('no credits: provider, licence and date of the source are required')] if credits.empty?

          credits.flat_map do |credit|
            [
              *(credit.provider.to_s.strip.empty? ? [error('credits without provider')] : []),
              *(credit.licence.to_s.strip.empty? ? [error('credits without licence')] : []),
              *(valid_date?(credit.updated_at) ? [] : [error("credits with an invalid date: #{credit.updated_at.inspect}")])
            ]
          end
        end

        def valid_date?(value)
          Date.iso8601(value.to_s[0, 10])
          true
        rescue ArgumentError
          false
        end

        # An open datasource needs an open licence; a restrictive one must be reserved to key holders
        def licence(datasource)
          datasource.get_credits.map(&:licence).compact.uniq.flat_map do |licence|
            reserved = datasource.scope != Packaging::Manifest::OPEN_SCOPE

            if licence.match?(RESTRICTIVE_LICENCE) || OPEN_LICENCES.none? { |open| licence.match?(open) }
              reserved ? [] : [error("licence '#{licence}' is not an open licence: reserve the datasource with `scope :members`")]
            elsif licence.match?(SHARE_ALIKE_LICENCE)
              [warning("licence '#{licence}' is share-alike: what is derived from it must keep that licence")]
            else
              []
            end
          end
        end

        def tables(datasource, definition)
          return [] unless datasource.packaged?

          definition.nil? || definition.definitions.empty? ? [error('declares no table (table_definitions)')] : []
        end

        def personal_data(datasource, definition)
          return [] if definition.nil?

          columns = definition.definitions.flat_map do |table|
            column_names(table.sql).select { |column| column.match?(PERSONAL_COLUMN) }
                                   .map { |column| "#{table.name}.#{column}" }
          end
          return [] if columns.empty?

          if datasource.personal_data.nil?
            [error("columns that look like personal data: #{columns.join(', ')}. Remove them, or state with " \
                   '`personal_data "..."` why they can be published')]
          else
            [warning("publishes #{columns.join(', ')}: #{datasource.personal_data}")]
          end
        end

        # @return [Array<String>] names of the columns of the tables a script creates
        def column_names(sql)
          sql.scan(/CREATE\s+(?:UNLOGGED\s+)?TABLE[^(]*\((.*?)\)\s*;/mi).flatten.flat_map do |body|
            # Commas inside parentheses, as in numeric(10,2), do not separate columns
            body.gsub(/\([^()]*\)/, '').split(',').map { |part| part.strip[/\A"?(\w+)"?/, 1] }.compact
                .reject { |word| %w[primary constraint unique check foreign].include?(word.downcase) }
          end
        end

        def dependencies(name, datasource)
          unknown = datasource.get_dependencies - @datasources.keys

          [
            *(unknown.any? ? [error("depends on unknown datasources: #{unknown.join(', ')}")] : []),
            *(datasource.get_dependencies.include?(name) ? [error('depends on itself')] : [])
          ]
        end

        # Two datasources writing the same translation prefix would ship each other's rows
        def translations(name, datasource)
          datasource.get_translation_prefixes.flat_map do |prefix|
            others = @datasources.select { |other, klass| other != name && klass.get_translation_prefixes.include?(prefix) }.keys

            others.any? ? [error("translation prefix '#{prefix}' is also declared by #{others.join(', ')}")] : []
          end
        end

        def pivot_tables(datasource, definition)
          return [] if definition.nil?

          owned = definition.definitions.map(&:name)

          datasource.get_pivots.reject { |pivot| owned.include?(pivot[:table]) }.map do |pivot|
            error("pivot #{pivot[:key]} is declared on #{pivot[:table]}, which this datasource does not define")
          end
        end

        def pivot_rates(pivots)
          pivots.flat_map do |pivot|
            label = "#{pivot[:table]}.#{pivot[:column]} → #{pivot[:key]}"

            if pivot[:rate].nil?
              [warning("#{label}: match rate not measurable (no value, or reference not built)")]
            elsif pivot[:minimum] && pivot[:rate] < pivot[:minimum]
              [error("#{label}: #{(pivot[:rate] * 100).round(1)} % of values match, #{(pivot[:minimum] * 100).round(1)} % required")]
            else
              []
            end
          end
        end

        def volume(rows, previous)
          return [] if previous.nil?

          before = previous.tables.map { |table| [table[:name], table[:rows]] }.to_h

          rows.select { |table, count| before.fetch(table, 0) * MINIMUM_ROWS_RATIO > count }.map do |table, count|
            error("#{table}: #{count} rows, #{before[table]} in the latest package")
          end
        end
    end
  end
end
