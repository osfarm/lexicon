# frozen_string_literal: true

require 'json'
require 'time'

module Lexicon
  module Packaging
    # What a tracked bundle is made of: the names of its datasources. The build side sends it to the
    # serving side, which assembles the bundle from the packages in service.
    class BundleDefinition
      FILE_NAME = 'bundle.json'
      FORMAT = 1

      # @return [String]
      attr_reader :name
      # @return [Array<String>]
      attr_reader :datasources
      # @return [Time]
      attr_reader :defined_at

      class << self
        # @param [Flavor::LexiconFlavor] flavor
        # @param [Hash{String => Database::Schema::TableDefinitionSet}] definitions the packaged datasources
        # @param [DependencyResolver] resolver
        # @param [Time] now
        # @return [BundleDefinition]
        # @raise [ArgumentError] when the flavor cannot make a bundle that loads
        def from_flavor(flavor, definitions:, resolver:, now: Time.now)
          raise ArgumentError.new("The flavor #{flavor.name} is not tracked") unless flavor.tracked?

          names = flavor.only.uniq.sort
          unknown = names - definitions.keys
          raise ArgumentError.new("Unknown or not packaged datasources in #{flavor.name}: #{unknown.join(', ')}") if unknown.any?

          missing = names.flat_map { |name| unmet_references(name, names, definitions, resolver) }
          raise ArgumentError.new("The bundle #{flavor.name} would not load: #{missing.join('; ')}") if missing.any?

          new(name: flavor.name, datasources: names, defined_at: now)
        end

        # @param [Pathname] file
        # @return [BundleDefinition]
        def load(file)
          data = JSON.parse(file.read, symbolize_names: true)
          raise ArgumentError.new("Unsupported bundle format #{data[:format].inspect} in #{file}") if data[:format] != FORMAT

          new(name: data.fetch(:name), datasources: data.fetch(:datasources), defined_at: Time.iso8601(data.fetch(:defined_at)))
        rescue JSON::ParserError, KeyError => e
          raise ArgumentError.new("#{file} cannot be read: #{e.message}")
        end

        private

          # Only foreign keys count: a datasource read during normalize is not needed to load the package
          def unmet_references(name, names, definitions, resolver)
            resolver.resolve(definitions.fetch(name))
                    .select { |dependency| dependency[:kind] == DependencyResolver::FOREIGN_KEY }
                    .reject { |dependency| names.include?(dependency[:name]) }
                    .map { |dependency| "#{name} references #{dependency[:name]}, which the flavor does not name" }
          end
      end

      # @param [String] name
      # @param [Array<String>] datasources
      # @param [Time] defined_at
      def initialize(name:, datasources:, defined_at:)
        @name = name
        @datasources = datasources
        @defined_at = defined_at
      end

      # @return [Hash]
      def to_h
        { format: FORMAT, name: name, datasources: datasources, defined_at: defined_at.utc.iso8601 }
      end

      # @param [Pathname] dir
      # @return [Pathname] the file written
      def write(dir)
        dir.join(FILE_NAME).tap { |file| file.write("#{JSON.pretty_generate(to_h)}\n") }
      end
    end
  end
end
