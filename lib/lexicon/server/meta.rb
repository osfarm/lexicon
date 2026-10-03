# frozen_string_literal: true

require 'json'

module Lexicon
  module Server
    # Tracks which version of each package is in service, and the history of loads.
    class Meta
      SCHEMA = 'lexicon_meta'
      SERVED_SCHEMA = 'lexicon'
      STAGING_SCHEMA = 'lexicon_staging'

      Installed = Struct.new(:name, :version, :schema_revision, :structure_hash, :loaded_at, :manifest, keyword_init: true)

      # @param [PG::Connection] connection
      def initialize(connection)
        @connection = connection
      end

      def setup
        connection.exec(<<~SQL)
          SET client_min_messages TO WARNING;

          CREATE SCHEMA IF NOT EXISTS "#{SERVED_SCHEMA}";
          CREATE SCHEMA IF NOT EXISTS "#{STAGING_SCHEMA}";
          CREATE SCHEMA IF NOT EXISTS "#{SCHEMA}";

          CREATE TABLE IF NOT EXISTS #{SCHEMA}.packages (
            name            varchar PRIMARY KEY,
            version         varchar NOT NULL,
            schema_revision integer NOT NULL,
            structure_hash  varchar NOT NULL,
            loaded_at       timestamptz NOT NULL,
            stale           boolean NOT NULL DEFAULT false,
            manifest        jsonb NOT NULL
          );

          CREATE TABLE IF NOT EXISTS #{SCHEMA}.package_tables (
            table_name varchar PRIMARY KEY,
            package    varchar NOT NULL REFERENCES #{SCHEMA}.packages(name)
          );

          CREATE TABLE IF NOT EXISTS #{SCHEMA}.loads (
            id          bigserial PRIMARY KEY,
            name        varchar NOT NULL,
            version     varchar NOT NULL,
            previous    varchar,
            started_at  timestamptz NOT NULL,
            finished_at timestamptz,
            state       varchar NOT NULL
                        CHECK (state IN ('loading', 'checking', 'swapped', 'failed', 'rolled_back')),
            detail      jsonb
          );
        SQL
      end

      # @param [String] name
      # @return [Installed, nil]
      def installed(name)
        all_installed.detect { |package| package.name == name }
      end

      # @return [Array<Installed>] ordered by name
      def all_installed
        connection.exec("SELECT * FROM #{SCHEMA}.packages ORDER BY name").map do |row|
          Installed.new(
            name: row['name'],
            version: row['version'],
            schema_revision: row['schema_revision'].to_i,
            structure_hash: row['structure_hash'],
            loaded_at: Time.parse(row['loaded_at']),
            manifest: JSON.parse(row['manifest'], symbolize_names: true)
          )
        end
      end

      # @param [Array<String>] tables
      # @return [Hash{String => String}] owning package of each table that has one
      def owners(tables)
        connection.exec_params(<<~SQL, [encode_array(tables)]).map { |row| [row['table_name'], row['package']] }.to_h
          SELECT table_name, package FROM #{SCHEMA}.package_tables WHERE table_name = ANY($1::varchar[])
        SQL
      end

      # @param [String] name
      # @return [Array<String>]
      def tables_of(name)
        connection.exec_params("SELECT table_name FROM #{SCHEMA}.package_tables WHERE package = $1 ORDER BY 1", [name])
                  .map { |row| row['table_name'] }
      end

      # Puts a package in the registry. To call in the transaction that swaps its tables.
      #
      # @param [Packaging::Manifest] manifest
      def record_package(manifest)
        values = [manifest.name, manifest.version, manifest.schema_revision, manifest.structure_hash, manifest.to_json]
        connection.exec_params(<<~SQL, values)
          INSERT INTO #{SCHEMA}.packages (name, version, schema_revision, structure_hash, loaded_at, stale, manifest)
          VALUES ($1, $2, $3, $4, now(), false, $5)
          ON CONFLICT (name) DO UPDATE
            SET version = EXCLUDED.version, schema_revision = EXCLUDED.schema_revision,
                structure_hash = EXCLUDED.structure_hash, loaded_at = EXCLUDED.loaded_at,
                stale = false, manifest = EXCLUDED.manifest
        SQL
        connection.exec_params("DELETE FROM #{SCHEMA}.package_tables WHERE package = $1", [manifest.name])
        manifest.tables.each do |table|
          connection.exec_params(<<~SQL, [table[:name], manifest.name])
            INSERT INTO #{SCHEMA}.package_tables (table_name, package) VALUES ($1, $2)
          SQL
        end
      end

      # @return [Integer] identifier of the load
      def start_load(name, version, previous)
        connection.exec_params(<<~SQL, [name, version, previous]).getvalue(0, 0).to_i
          INSERT INTO #{SCHEMA}.loads (name, version, previous, started_at, state)
          VALUES ($1, $2, $3, now(), 'loading') RETURNING id
        SQL
      end

      # @param [Integer] id
      # @param [String] state
      # @param [Hash, nil] detail
      def update_load(id, state, detail: nil)
        finished = %w[swapped failed rolled_back].include?(state)

        connection.exec_params(<<~SQL, [id, state, detail&.to_json])
          UPDATE #{SCHEMA}.loads
             SET state = $2,
                 detail = COALESCE(detail, '{}'::jsonb) || COALESCE($3::jsonb, '{}'::jsonb),
                 finished_at = #{finished ? 'now()' : 'finished_at'}
           WHERE id = $1
        SQL
      end

      # @param [Integer] limit
      # @return [Array<Hash>] most recent first
      def recent_loads(limit = 10)
        connection.exec_params("SELECT * FROM #{SCHEMA}.loads ORDER BY id DESC LIMIT $1", [limit]).to_a
      end

      private

        # @return [PG::Connection]
        attr_reader :connection

        def encode_array(values)
          PG::TextEncoder::Array.new.encode(values)
        end
    end
  end
end
