# frozen_string_literal: true

require 'open3'
require 'digest'

module Lexicon
  module Packaging
    # Exports one table of the lexicon schema as a compressed CSV, without header.
    class TableExporter
      SCHEMA = 'lexicon'

      class ExportError < StandardError; end

      # @param [String] db_url
      def initialize(db_url:)
        @db_url = db_url
      end

      # @param [String] table
      # @param [Pathname] file
      # @return [Hash] :rows, :sha256, :bytes
      def export(table, file)
        command = %(\\copy "#{SCHEMA}"."#{table}" TO PROGRAM 'pigz > #{file}' WITH csv)
        output, error, status = Open3.capture3('psql', db_url, '-v', 'ON_ERROR_STOP=1', '-c', command)
        rows = output[/^COPY (\d+)$/, 1]

        if !status.success? || rows.nil?
          raise ExportError.new("Export of #{table} failed: #{error.strip.presence || output.strip}")
        end

        { rows: rows.to_i, sha256: Digest::SHA256.file(file).hexdigest, bytes: file.size }
      end

      private

        # @return [String]
        attr_reader :db_url
    end
  end
end
