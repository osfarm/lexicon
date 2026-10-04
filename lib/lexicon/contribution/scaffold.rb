# frozen_string_literal: true

module Lexicon
  module Contribution
    # Writes the skeleton of a new datasource.
    class Scaffold
      VALID_NAME = /\A[a-z][a-z0-9_]*\z/.freeze

      # @param [String] name snake_case name of the datasource
      # @return [String] the Ruby source of lib/datasources/<name>.rb
      def datasource(name)
        raise ArgumentError.new("#{name.inspect} is not a valid name: use snake_case, such as soil_moisture") unless name.match?(VALID_NAME)

        <<~RUBY
          module Datasources
            # TODO: say in one or two sentences what this datasource brings and where it comes from.
            class #{name.camelize} < Base
              description 'TODO: one sentence shown in the catalogue'
              credits name: 'TODO: name of the source dataset',
                      url: 'https://TODO',
                      provider: 'TODO: who publishes it',
                      licence: 'Licence Ouverte 2.0',
                      licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
                      updated_at: '#{Date.today.iso8601}'

              # Bump it when a published table changes shape.
              schema_revision 1
              # Datasources read during normalize, when no foreign key says so:
              # depends_on :postal_codes
              # Columns carrying a shared identifier (see Lexicon::Packaging::Pivots::KEYS):
              # pivot :commune, table: :registered_#{name}, column: :insee_code, minimum: 0.95
              # Only for data reserved to API key holders:
              # scope :members

              # Download the raw files into `dir`. No transformation here.
              def collect
                # execute "curl -sSL 'https://TODO/file.csv' -o \#{dir.join('#{name}.csv')}"
              end

              # Load the raw files into the working schema `#{name}`.
              def load
                # load_csv(dir.join('#{name}.csv'), '#{name}', col_sep: ';')
              end

              # The tables this datasource publishes. A table belongs to one datasource only.
              def self.table_definitions(builder)
                builder.table(:registered_#{name}, sql: <<~SQL)
                  CREATE TABLE registered_#{name} (
                    id character varying PRIMARY KEY NOT NULL,
                    name character varying NOT NULL
                  );
                SQL
              end

              # Fill the published tables from the raw ones.
              def normalize
                query <<~SQL
                  INSERT INTO registered_#{name} (id, name)
                    SELECT id, name FROM \#{name}.#{name}
                SQL
              end
            end
          end
        RUBY
      end
    end
  end
end
