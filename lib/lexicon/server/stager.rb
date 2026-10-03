# frozen_string_literal: true

require 'digest'
require 'zlib'

module Lexicon
  module Server
    # Loads a package in the staging schema: tables, data, then indexes. Nothing served is touched.
    class Stager
      SCHEMA = Meta::STAGING_SCHEMA
      CHUNK_SIZE = 1 << 20

      # @param [PG::Connection] connection
      def initialize(connection)
        @connection = connection
      end

      # @param [Pathname] dir directory of the package
      # @param [Packaging::Manifest] manifest
      # @return [Hash{String => Integer}] rows loaded in each table
      def stage(dir, manifest)
        verify_files(dir, manifest)

        connection.transaction do
          # Tables created and filled in the same transaction skip the WAL when wal_level is minimal
          connection.exec(%(SET LOCAL search_path TO "#{SCHEMA}", postgis))
          drop_tables(manifest)
          connection.exec(dir.join(Packaging::Builder::STRUCTURE_FILE).read)

          rows = manifest.tables.map { |table| [table[:name], copy_table(dir, table)] }.to_h

          indexes = dir.join(Packaging::Builder::INDEXES_FILE).read
          connection.exec(indexes) unless indexes.strip.empty?
          manifest.tables.each { |table| connection.exec(%(ANALYZE "#{SCHEMA}"."#{table[:name]}")) }

          rows
        end
      end

      # @param [Packaging::Manifest] manifest
      def discard(manifest)
        drop_tables(manifest)
      end

      private

        # @return [PG::Connection]
        attr_reader :connection

        def drop_tables(manifest)
          manifest.tables.each do |table|
            connection.exec(%(DROP TABLE IF EXISTS "#{SCHEMA}"."#{table[:name]}" CASCADE))
          end
        end

        def verify_files(dir, manifest)
          corrupted = manifest.tables.flat_map { |table| table[:files] }.reject do |file|
            path = dir.join(file[:path])

            path.file? && Digest::SHA256.file(path).hexdigest == file[:sha256]
          end

          raise LoadFailure.new(corrupted.map { |file| "#{file[:path]} is missing or corrupted" }) if corrupted.any?
        end

        # @return [Integer] rows loaded
        def copy_table(dir, table)
          table[:files].sum do |file|
            result = connection.copy_data(%(COPY "#{SCHEMA}"."#{table[:name]}" FROM STDIN WITH (FORMAT csv))) do
              Zlib::GzipReader.open(dir.join(file[:path]).to_s) do |gzip|
                while (chunk = gzip.read(CHUNK_SIZE))
                  connection.put_copy_data(chunk)
                end
              end
            end

            result.cmd_tuples
          end
        end
    end
  end
end
