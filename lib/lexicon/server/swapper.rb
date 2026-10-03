# frozen_string_literal: true

require 'digest'

module Lexicon
  module Server
    # Replaces tables in service by the staged ones, in a single transaction.
    class Swapper
      ATTEMPTS = 5
      LOCK_TIMEOUT = '5s'

      # @param [PG::Connection] connection
      # @param [Catalog] catalog
      # @param [DerivedViews] derived_views
      # @param [Float] retry_delay seconds between two attempts to take the locks
      # @param [String] lock_timeout how long an attempt waits for the readers of the tables
      def initialize(connection, catalog:, derived_views:, retry_delay: 2.0, lock_timeout: LOCK_TIMEOUT)
        @connection = connection
        @catalog = catalog
        @derived_views = derived_views
        @retry_delay = retry_delay
        @lock_timeout = lock_timeout
      end

      # @param [Array<Packaging::Manifest>] manifests packages staged, put in service together
      # @param [Array<String>] previous_tables tables of the versions in service
      # @yield in the transaction, once the tables are swapped: the place to record the packages
      def swap(manifests, previous_tables: [], &block)
        tables = manifests.flat_map { |manifest| manifest.tables.map { |table| table[:name] } }
        foreign_keys = manifests.flat_map(&:foreign_keys)

        exclusively do
          replaced = catalog.existing_tables((previous_tables + tables).uniq)
          inbound = catalog.inbound_foreign_keys(replaced)

          derived_views.drop
          drop_foreign_keys(inbound)
          connection.exec("DROP TABLE #{replaced.map { |table| served(table) }.join(', ')}") if replaced.any?
          tables.each do |table|
            connection.exec(%(ALTER TABLE "#{Meta::STAGING_SCHEMA}"."#{table}" SET SCHEMA "#{Meta::SERVED_SCHEMA}"))
          end
          foreign_keys.each { |key| add_foreign_key(key) }
          restore_foreign_keys(inbound)

          block&.call
          derived_views.create
        end
      end

      # Takes tables out of service.
      #
      # @param [Array<String>] tables
      # @yield in the transaction, once the tables are dropped
      def remove(tables, &block)
        exclusively do
          derived_views.drop
          existing = catalog.existing_tables(tables)
          connection.exec("DROP TABLE #{existing.map { |table| served(table) }.join(', ')}") if existing.any?

          block&.call
          derived_views.create
        end
      rescue PG::DependentObjectsStillExist => e
        raise LoadFailure.new("other tables depend on them: #{e.message.lines.first.strip}")
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [Catalog]
        attr_reader :catalog
        # @return [DerivedViews]
        attr_reader :derived_views

        # Runs the block in a transaction that gives up quickly when readers hold the tables
        def exclusively
          attempt = 1

          begin
            connection.transaction do
              # With an empty search path, Postgres prints the definitions of the foreign keys fully qualified
              connection.exec("SET LOCAL lock_timeout TO '#{@lock_timeout}'; SET LOCAL search_path TO pg_catalog")
              yield
            end
          rescue PG::LockNotAvailable
            raise LoadFailure.new("tables are in use: locks not obtained after #{ATTEMPTS} attempts") if attempt >= ATTEMPTS

            attempt += 1
            sleep(@retry_delay)
            retry
          rescue PG::ForeignKeyViolation => e
            raise LoadFailure.new("a foreign key does not hold with the new data: #{e.message.lines.first(2).map(&:strip).join(' ')}")
          end
        end

        def served(table)
          %("#{Meta::SERVED_SCHEMA}"."#{table}")
        end

        def drop_foreign_keys(keys)
          keys.each { |key| connection.exec(%(ALTER TABLE #{key['referencing']} DROP CONSTRAINT "#{key['name']}")) }
        end

        def restore_foreign_keys(keys)
          keys.each do |key|
            connection.exec(%(ALTER TABLE #{key['referencing']} ADD CONSTRAINT "#{key['name']}" #{key['definition']}))
          end
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
