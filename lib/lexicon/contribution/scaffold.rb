# frozen_string_literal: true

module Lexicon
  module Contribution
    # Writes the skeleton of a new datasource.
    class Scaffold
      VALID_NAME = /\A[a-z][a-z0-9_]*\z/.freeze
      # What the sheet says where the contributor has to write; a sheet that still says it is not filled in
      PLACEHOLDERS = {
        'description' => 'Une phrase qui dit ce que contient le jeu, affichée au catalogue',
        'author' => 'Prénom Nom, organisme',
        'source.name' => "Nom du jeu de données d'origine",
        'source.url' => 'https://adresse-de-la-source',
        'source.provider' => 'Qui le publie'
      }.freeze

      # @return [Hash] a sheet with nothing but what can be proposed by default: the web interface asks for the rest
      def blank
        { 'source' => { 'licence' => 'Licence Ouverte 2.0',
                        'licence_url' => 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
                        'date' => Date.today.iso8601 },
          'tables' => [] }
      end

      # @param [String] name snake_case name of the dataset
      # @return [String] the sheet of a tabular contribution, data/contributions/<name>/dataset.yml
      def sheet(name)
        raise ArgumentError.new("#{name.inspect} is not a valid name: use snake_case, such as soil_moisture") unless name.match?(VALID_NAME)

        <<~YAML
          # Fiche du jeu de données « #{name} ». À placer avec ses fichiers CSV dans data/contributions/#{name}/,
          # puis : ./lexicon contribute #{name}
          description: #{PLACEHOLDERS['description']}
          author: #{PLACEHOLDERS['author']}
          source:
            name: #{PLACEHOLDERS['source.name']}
            url: #{PLACEHOLDERS['source.url']}
            provider: #{PLACEHOLDERS['source.provider']}
            licence: Licence Ouverte 2.0
            licence_url: https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf
            date: #{Date.today.iso8601}
          # Pour réserver le jeu aux adhérents d'OSFarm, retirer le # de la ligne suivante
          # scope: members
          tables:
            - file: #{name}.csv
              # La colonne qui identifie chaque ligne : jamais vide, jamais deux fois la même valeur
              key: id
              # Chaque colonne du fichier et ce qu'elle contient : text, integer, number, date (AAAA-MM-JJ), boolean (true, false)
              columns:
                id: text
                name: text
                insee_code: text
                measured_on: date
                value: number
              # Colonnes qui portent un identifiant partagé avec d'autres jeux : #{Packaging::Pivots::KEYS.keys.join(', ')}
              pivots:
                insee_code: commune
        YAML
      end

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
              # A source without a named open licence, published openly all the same: say why
              # licence_exception 'published by its author for anyone to use; terms checked on YYYY-MM-DD'

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
