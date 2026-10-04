# frozen_string_literal: true

module Lexicon
  module Server
    # The role the API connects with: it reads the data served and the registry of packages, and owns
    # the schema of API keys. It cannot change the data, whatever a request manages to make it run.
    class ApiRole
      ACCESS_SCHEMA = 'lexicon_access'
      READABLE_SCHEMAS = [Meta::SERVED_SCHEMA, Meta::SCHEMA].freeze
      # Tables are created in staging then moved to the served schema: they keep the rights given there
      DEFAULT_PRIVILEGES_SCHEMAS = [Meta::SERVED_SCHEMA, Meta::STAGING_SCHEMA, Meta::SCHEMA].freeze
      VALID_NAME = /\A[a-z_][a-z0-9_]*\z/.freeze

      # @param [PG::Connection] connection as the owner of the served schema
      # @param [String] name
      # @param [String] password
      def initialize(connection, name:, password:)
        raise ArgumentError.new("Invalid role name #{name.inspect}") unless name.match?(VALID_NAME)

        @connection = connection
        @name = name
        @password = password
      end

      # Creates the role or brings it up to date. Safe to run at each start.
      def ensure
        connection.exec('SET client_min_messages TO WARNING')
        create_or_update
        grant_reading
        hand_over_access_schema
      end

      private

        # @return [PG::Connection]
        attr_reader :connection
        # @return [String]
        attr_reader :name

        def role
          connection.quote_ident(name)
        end

        def create_or_update
          exists = connection.exec_params('SELECT 1 FROM pg_roles WHERE rolname = $1', [name]).any?
          password = connection.escape_literal(@password)

          connection.exec("#{exists ? 'ALTER' : 'CREATE'} ROLE #{role} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD #{password}")
          connection.exec("GRANT CONNECT ON DATABASE #{connection.quote_ident(connection.db)} TO #{role}")
        end

        def grant_reading
          connection.exec("GRANT USAGE ON SCHEMA postgis TO #{role}") if schema?('postgis')

          READABLE_SCHEMAS.each do |schema|
            connection.exec(%(GRANT USAGE ON SCHEMA "#{schema}" TO #{role}))
            connection.exec(%(GRANT SELECT ON ALL TABLES IN SCHEMA "#{schema}" TO #{role}))
          end
          DEFAULT_PRIVILEGES_SCHEMAS.each do |schema|
            connection.exec(%(ALTER DEFAULT PRIVILEGES IN SCHEMA "#{schema}" GRANT SELECT ON TABLES TO #{role}))
          end
        end

        # The API creates and migrates this schema itself: it has to own it, and everything in it
        def hand_over_access_schema
          connection.exec(%(CREATE SCHEMA IF NOT EXISTS "#{ACCESS_SCHEMA}"))
          connection.exec(%(ALTER SCHEMA "#{ACCESS_SCHEMA}" OWNER TO #{role}))

          connection.exec_params(<<~SQL, [ACCESS_SCHEMA]).each do |row|
            SELECT format('ALTER %s %I.%I OWNER TO %%s', CASE relkind WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, nspname, relname) AS statement
              FROM pg_class
              JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
             WHERE nspname = $1 AND relkind IN ('r', 'S')
             ORDER BY relkind DESC
          SQL
            connection.exec(format(row['statement'], role))
          end
        end

        def schema?(schema)
          connection.exec_params('SELECT 1 FROM pg_namespace WHERE nspname = $1', [schema]).any?
        end
    end
  end
end
