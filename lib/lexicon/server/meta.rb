# frozen_string_literal: true

require 'json'

module Lexicon
  module Server
    # Tracks which version of each package is in service, and the history of loads.
    class Meta
      SCHEMA = 'lexicon_meta'
      SERVED_SCHEMA = 'lexicon'
      STAGING_SCHEMA = 'lexicon_staging'

      Installed = Struct.new(:name, :version, :schema_revision, :structure_hash, :loaded_at, :stale, :manifest, keyword_init: true)

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

          CREATE TABLE IF NOT EXISTS #{SCHEMA}.repository_versions (
            name       varchar NOT NULL,
            version    varchar NOT NULL,
            is_current boolean NOT NULL DEFAULT false,
            PRIMARY KEY (name, version)
          );

          CREATE OR REPLACE VIEW "#{SERVED_SCHEMA}".datasource_credits AS
            SELECT packages.name AS datasource,
                   credit->>'name' AS name,
                   credit->>'url' AS url,
                   credit->>'provider' AS provider,
                   credit->>'licence' AS licence,
                   credit->>'licence_url' AS licence_url,
                   (credit->>'updated_at')::timestamptz AS updated_at
              FROM #{SCHEMA}.packages, jsonb_array_elements(packages.manifest->'credits') AS credit;
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
            stale: row['stale'] == 't',
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

      # Records which versions the repository holds, for those who can only reach the database.
      #
      # @param [Packaging::Repository] repository
      def record_repository(repository)
        rows = repository.names.flat_map do |name|
          current = repository.current(name)

          repository.versions(name).map { |version| [name, version, version == current] }
        end

        connection.transaction do
          connection.exec("DELETE FROM #{SCHEMA}.repository_versions")
          rows.each do |row|
            connection.exec_params("INSERT INTO #{SCHEMA}.repository_versions (name, version, is_current) VALUES ($1, $2, $3)", row)
          end
        end
      end

      # @param [String] role
      # @return [Array<String>] tables having that role in the packages in service
      def tables_with_role(role)
        connection.exec_params(<<~SQL, [role]).map { |row| row['name'] }
          SELECT entry->>'name' AS name
            FROM #{SCHEMA}.packages, jsonb_array_elements(packages.manifest->'tables') AS entry
           WHERE entry->>'role' = $1
           ORDER BY 1
        SQL
      end

      # A package is stale when one it depends on is no longer at the version it was built against.
      # To call in the transaction that swaps tables.
      def refresh_stale
        connection.exec(<<~SQL)
          UPDATE #{SCHEMA}.packages
             SET stale = EXISTS (
                   SELECT 1
                     FROM jsonb_array_elements(packages.manifest->'depends_on') AS dependency
                     JOIN #{SCHEMA}.packages AS depended ON depended.name = dependency->>'name'
                    WHERE dependency->>'built_against' IS NOT NULL
                      AND dependency->>'built_against' <> depended.version
                 )
        SQL
      end

      # @param [String] name
      def remove_package(name)
        connection.exec_params("DELETE FROM #{SCHEMA}.package_tables WHERE package = $1", [name])
        connection.exec_params("DELETE FROM #{SCHEMA}.packages WHERE name = $1", [name])
      end

      # @param [String] name
      # @return [Hash, nil] the load that put the version in service: 'id', 'version', 'previous'
      def load_in_service(name)
        connection.exec_params(<<~SQL, [name]).first
          SELECT loads.id, loads.version, loads.previous
            FROM #{SCHEMA}.loads
            JOIN #{SCHEMA}.packages ON packages.name = loads.name AND packages.version = loads.version
           WHERE loads.name = $1 AND loads.state = 'swapped'
           ORDER BY loads.id DESC
           LIMIT 1
        SQL
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
