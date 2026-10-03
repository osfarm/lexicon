# frozen_string_literal: true

require 'open3'
require 'digest'

module Lexicon
  module Packaging
    # Exports a table of the lexicon schema, or a query on it, as a compressed CSV without header.
    class TableExporter
      SCHEMA = 'lexicon'
      # Flavor filters name their tables and the PostGIS functions without schema
      SEARCH_PATH = "#{SCHEMA},postgis"

      class ExportError < StandardError; end

      # @param [String] db_url
      def initialize(db_url:)
        @db_url = db_url
      end

      # @param [String] table
      # @return [String] what to export to get the whole table
      def self.whole(table)
        %("#{SCHEMA}"."#{table}")
      end

      # @param [String] source a table, or a query between parentheses
      # @param [Pathname] file
      # @return [Hash] :rows, :sha256, :bytes
      def export(source, file)
        command = %(\\copy #{source.gsub(/\s+/, ' ')} TO PROGRAM 'pigz > #{file}' WITH csv)
        environment = { 'PGOPTIONS' => "-c search_path=#{SEARCH_PATH}" }
        output, error, status = Open3.capture3(environment, 'psql', db_url, '-v', 'ON_ERROR_STOP=1', '-c', command)
        rows = output[/^COPY (\d+)$/, 1]

        if !status.success? || rows.nil?
          raise ExportError.new("Export of #{source} failed: #{error.strip.presence || output.strip}")
        end

        { rows: rows.to_i, sha256: Digest::SHA256.file(file).hexdigest, bytes: file.size }
      end

      private

        # @return [String]
        attr_reader :db_url
    end
  end
end
