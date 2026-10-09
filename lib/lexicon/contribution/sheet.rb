# frozen_string_literal: true

require 'yaml'

module Lexicon
  module Contribution
    # The sheet of a tabular contribution: a dataset given as CSV files, described by a `dataset.yml` beside
    # them, with no Ruby to write. It says what the data is, where it comes from, under which licence, and
    # what each column holds.
    class Sheet
      FILE = 'dataset.yml'
      TYPES = {
        'text' => 'character varying', 'integer' => 'integer', 'number' => 'numeric', 'date' => 'date', 'boolean' => 'boolean',
        'datetime' => 'timestamp with time zone', 'point' => 'postgis.geometry(Point,4326)'
      }.freeze
      # A day and a time, as ISO 8601 writes them: 2025-12-04T17:00:53+01:00. Seconds and offset may be left out.
      INSTANT = /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?\z/.freeze

      # @param [String] value
      # @return [Boolean] whether the value is a day that exists, at a time that exists
      def self.instant?(value)
        year, month, day, hours, minutes, seconds = value.to_s.strip.match(INSTANT)&.captures&.first(6)&.map(&:to_i)

        !year.nil? && Date.valid_date?(year, month, day) && hours < 24 && minutes < 60 && seconds < 60
      end
      # A point is written in one cell, latitude first: 48.811873,2.211849
      COORDINATE = /-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/.freeze
      POINT = /\A(#{COORDINATE}),\s*(#{COORDINATE})\z/.freeze

      # @param [String] value
      # @return [Array<Float>, nil] latitude and longitude, when the value is a point of the globe
      def self.point(value)
        latitude, longitude = value.to_s.strip.match(POINT)&.captures&.map(&:to_f)

        latitude && latitude.abs <= 90 && longitude.abs <= 180 ? [latitude, longitude] : nil
      end

      # Two columns that tell a commune together, when none carries its code: its postal code and its name.
      # They are written under `pivots` like a key, and Lexicon finds the INSEE code at build time.
      PLACE_PARTS = { 'commune_postal_code' => :postal_code, 'commune_name' => :name }.freeze
      # The column Lexicon adds with the code it found
      PLACE_COLUMN = 'insee_code'

      Table = Struct.new(:file, :name, :key, :columns, :pivots, keyword_init: true) do
        # @return [Hash{String => String}] columns that carry a key by themselves
        def keys
          pivots.reject { |_, key| PLACE_PARTS.key?(key) }
        end

        # @return [Hash, nil] the columns holding the postal code and the name of a commune, and the column
        #   that will hold its code; nil unless there is exactly one of each
        def place
          parts = PLACE_PARTS.map { |key, part| [part, pivots.select { |_, chosen| chosen == key }.keys] }.to_h
          return nil unless parts.values.all? { |columns| columns.size == 1 }

          column = columns.key?(PLACE_COLUMN) ? "commune_#{PLACE_COLUMN}" : PLACE_COLUMN
          parts.transform_values(&:first).merge(column: column)
        end
      end

      # @return [Pathname]
      attr_reader :dir
      # @return [Hash] the sheet as written, keys as strings
      attr_reader :data

      # @param [Pathname] dir directory of the contribution
      # @return [Sheet]
      def self.load(dir)
        new(dir, YAML.safe_load(dir.join(FILE).read, permitted_classes: [Date]) || {})
      end

      # @param [Hash] data the sheet, keys as strings
      # @return [String] the sheet as it is written in its file
      def self.dump(data)
        YAML.dump(data, line_width: -1).sub(/\A---\n/, '')
      end

      # @param [Pathname] dir directory of the contribution
      # @param [Hash] data
      def self.write(dir, data)
        dir.join(FILE).write(dump(data))
      end

      # @param [Pathname] root directory holding one directory per contribution
      # @return [Array<Pathname>] directories that hold a sheet
      def self.directories(root)
        root.directory? ? root.children.select { |child| child.directory? && child.join(FILE).file? }.sort : []
      end

      # @param [Pathname] dir
      # @param [Hash] data
      def initialize(dir, data)
        @dir = dir
        @data = data.is_a?(Hash) ? data : {}
      end

      # @return [String] name of the dataset: the one of its directory
      def name
        dir.basename.to_s
      end

      %w[description author scope personal_data].each do |field|
        define_method(field) { text(data[field]) }
      end

      # @return [Hash{String => String}] name, url, provider, licence, licence_url and date of the source
      def source
        (data['source'].is_a?(Hash) ? data['source'] : {}).transform_values { |value| text(value) }
      end

      # @return [Array<Table>]
      def tables
        entries = data['tables'].is_a?(Array) ? data['tables'].select { |entry| entry.is_a?(Hash) } : []

        entries.map do |entry|
          file = text(entry['file']).to_s
          Table.new(
            file: file, name: text(entry['table']) || default_table(file, entries.size), key: text(entry['key']),
            columns: hash_of(entry['columns']), pivots: hash_of(entry['pivots'])
          )
        end
      end

      private

        def text(value)
          value.nil? || value.to_s.strip.empty? ? nil : value.to_s.strip
        end

        def hash_of(value)
          value.is_a?(Hash) ? value.to_h { |key, content| [key.to_s, content.to_s.strip] } : {}
        end

        # One file gives the table of the dataset; several give one table each, named after their file
        def default_table(file, count)
          count == 1 ? "registered_#{name}" : "registered_#{name}_#{File.basename(file, '.*').downcase.gsub(/[^a-z0-9]+/, '_')}"
        end
    end
  end
end
