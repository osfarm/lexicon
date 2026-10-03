# frozen_string_literal: true

require 'digest'

module Lexicon
  module Server
    # Replaces the tables in service by the staged ones, in a single transaction.
    class Swapper
      ATTEMPTS = 5
      LOCK_TIMEOUT = '5s'

      # @param [PG::Connection] connection
      # @param [Float] retry_delay seconds between two attempts to take the locks
      # @param [String] lock_timeout how long an attempt waits for the readers of the tables
      def initialize(connection, retry_delay: 2.0, lock_timeout: LOCK_TIMEOUT)
        @connection = connection
        @retry_delay = retry_delay
        @lock_timeout = lock_timeout
      end

      # @param [Packaging::Manifest] manifest
      # @param [Array<String>] previous_tables tables of the version in service
      # @yield in the transaction, once the tables are swapped
      def swap(manifest, previous_tables: [], &block)
        attempt = 1

        begin
          connection.transaction { swap_tables(manifest, previous_tables, &block) }
        rescue PG::LockNotAvailable
          raise LoadFailure.new("tables are in use: locks not obtained after #{ATTEMPTS} attempts") if attempt >= ATTEMPTS

          attempt += 1
          sleep(@retry_delay)
          retry
        rescue PG::ForeignKeyViolation => e
          raise LoadFailure.new("a foreign key does not hold with the new data: #{e.message.lines.first(2).map(&:strip).join(' ')}")
        end
      end

      private

        # @return [PG::Connection]
        attr_reader :connection

        def swap_tables(manifest, previous_tables)
          # An empty search path makes Postgres print every name qualified
          connection.exec("SET LOCAL lock_timeout TO '#{@lock_timeout}'; SET LOCAL search_path TO pg_catalog")

          tables = manifest.tables.map { |table| table[:name] }
          replaced = existing_tables((previous_tables + tables).uniq)
          inbound = inbound_foreign_keys(replaced)

          inbound.each { |key| connection.exec(%(ALTER TABLE #{key['referencing']} DROP CONSTRAINT "#{key['name']}")) }
          connection.exec("DROP TABLE #{replaced.map { |table| served(table) }.join(', ')}") if replaced.any?
          tables.each do |table|
            connection.exec(%(ALTER TABLE "#{Meta::STAGING_SCHEMA}"."#{table}" SET SCHEMA "#{Meta::SERVED_SCHEMA}"))
          end

          manifest.foreign_keys.each { |key| add_foreign_key(key) }
          inbound.each do |key|
            connection.exec(%(ALTER TABLE #{key['referencing']} ADD CONSTRAINT "#{key['name']}" #{key['definition']}))
          end

          yield if block_given?
        end

        def served(table)
          %("#{Meta::SERVED_SCHEMA}"."#{table}")
        end

        def existing_tables(tables)
          connection.exec_params(<<~SQL, [Meta::SERVED_SCHEMA, PG::TextEncoder::Array.new.encode(tables)]).map { |row| row['tablename'] }
            SELECT tablename::varchar FROM pg_tables WHERE schemaname = $1 AND tablename = ANY($2::varchar[]) ORDER BY 1
          SQL
        end

        # Foreign keys of tables that stay in service, pointing to tables about to be replaced
        def inbound_foreign_keys(replaced)
          return [] if replaced.empty?

          connection.exec_params(<<~SQL, [Meta::SERVED_SCHEMA, PG::TextEncoder::Array.new.encode(replaced)]).to_a
            SELECT pg_constraint.conrelid::regclass::text AS referencing,
                   pg_constraint.conname::text AS name,
                   pg_get_constraintdef(pg_constraint.oid) AS definition
              FROM pg_constraint
              JOIN pg_class target ON target.oid = pg_constraint.confrelid
              JOIN pg_namespace target_namespace ON target_namespace.oid = target.relnamespace
              JOIN pg_class referencing ON referencing.oid = pg_constraint.conrelid
              JOIN pg_namespace referencing_namespace ON referencing_namespace.oid = referencing.relnamespace
             WHERE pg_constraint.contype = 'f'
               AND target_namespace.nspname = $1
               AND target.relname = ANY($2::varchar[])
               AND NOT (referencing_namespace.nspname = $1 AND referencing.relname = ANY($2::varchar[]))
             ORDER BY 1, 2
          SQL
        end

        def add_foreign_key(key)
          connection.exec(<<~SQL)
            ALTER TABLE #{served(key[:table])}
              ADD CONSTRAINT "#{foreign_key_name(key)}"
              FOREIGN KEY ("#{key[:column]}") REFERENCES #{served(key[:references_table])} ("#{key[:references_column]}")
          SQL
        end

        # Same naming as Database::Schema::ForeignKeyManager, so that both sides agree
        def foreign_key_name(key)
          "fk_#{Digest::MD5.hexdigest(key.values_at(:table, :column, :references_table, :references_column).map(&:downcase).join('__'))}"
        end
    end
  end
end
