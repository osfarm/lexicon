# frozen_string_literal: true

require 'csv'
require 'date'

module Lexicon
  module Contribution
    # Reads a tabular contribution as a maintainer would before accepting it, and says in French, in the
    # words of someone who filled a spreadsheet, what has to be corrected. Needs no database.
    class Review
      Finding = Struct.new(:level, :message, keyword_init: true)

      NAME = /\A[a-z][a-z0-9_]*\z/.freeze
      VALUES = {
        'text' => ->(_value) { true },
        'integer' => ->(value) { value.match?(/\A-?\d+\z/) },
        'number' => ->(value) { value.match?(/\A-?\d+(\.\d+)?\z/) },
        'date' => ->(value) { value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.valid_date?(*value.split('-').map(&:to_i)) },
        'boolean' => ->(value) { %w[true false].include?(value) },
        'datetime' => ->(value) { Sheet.instant?(value) },
        'point' => ->(value) { !Sheet.point(value).nil? }
      }.freeze
      EXPECTED = {
        'integer' => 'un nombre entier, sans espace ni décimale', 'number' => 'un nombre, avec un point pour les décimales',
        'date' => 'une date écrite AAAA-MM-JJ', 'boolean' => 'true ou false',
        'datetime' => 'une date et une heure écrites AAAA-MM-JJTHH:MM:SS, comme 2025-12-04T17:00:53+01:00',
        'point' => 'un point écrit latitude,longitude, comme 48.811873,2.211849'
      }.freeze
      # Lines quoted for a mistake found many times
      QUOTED = 3

      # @param [Sheet] sheet
      # @param [Array<String>] pivot_keys names of the linking keys Lexicon knows
      # @param [Hash, nil] memo what was found in each table, kept by whoever reads the same contribution again
      #   and again: a table is only read anew when its file or its description changed
      def initialize(sheet, pivot_keys: Packaging::Pivots::KEYS.keys, memo: nil)
        @sheet = sheet
        @pivot_keys = pivot_keys
        @memo = memo
      end

      # @return [Array<Finding>] errors, which block the contribution, and warnings, which ask for a look
      def findings
        [*sheet_findings, *@sheet.tables.flat_map { |table| remembered(table) }]
      end

      # @return [Boolean]
      def accepted?
        findings.none? { |finding| finding.level == :error }
      end

      private

        def remembered(table)
          return table_findings(table) if @memo.nil?

          file = @sheet.dir.join(table.file)
          stamp = !table.file.empty? && file.file? ? [file.mtime.to_f, file.size] : nil
          @memo[[file.to_s, stamp, table.to_h, @sheet.personal_data]] ||= table_findings(table)
        end

        def error(message)
          Finding.new(level: :error, message: message)
        end

        def warning(message)
          Finding.new(level: :warning, message: message)
        end

        # @return [Array<Finding>] the error, when the condition holds
        def error_if(condition, message)
          condition ? [error(message)] : []
        end

        # @return [String] the count with its noun and what follows, in the singular for one
        def counted(count, singular, plural)
          "#{count} #{count == 1 ? singular : plural}"
        end

        # @return [String] « la colonne a » or « les colonnes a, b »
        def columns(names)
          "#{names.one? ? 'la colonne' : 'les colonnes'} #{names.join(', ')}"
        end

        def sheet_findings
          source = @sheet.source
          fields = { 'description' => @sheet.description, 'author' => @sheet.author, 'source.name' => source['name'],
                     'source.url' => source['url'], 'source.provider' => source['provider'], 'source.licence' => source['licence'],
                     'source.date' => source['date'] }
          untouched = fields.select { |field, value| !value.nil? && value == Scaffold::PLACEHOLDERS[field] }

          [
            *error_if(!@sheet.name.match?(NAME), "Le dossier s'appelle « #{@sheet.name} » : son nom doit être en minuscules, " \
                                                 'sans accent ni espace, comme releves_sol.'),
            *fields.select { |_, value| value.nil? }.keys.map { |field| error("La fiche ne renseigne pas « #{field} ».") },
            *untouched.map { |field, value| error("La fiche garde pour « #{field} » le texte du modèle, « #{value} » : le remplacer.") },
            *licence_findings(source['licence']),
            *error_if(!source['date'].nil? && !VALUES['date'].call(source['date']),
                      "La date de la source, « #{source['date']} », doit être écrite AAAA-MM-JJ."),
            *error_if(@sheet.tables.empty?, 'La fiche ne décrit aucun fichier : il en faut au moins un sous « tables ».')
          ]
        end

        def licence_findings(licence)
          return [] if licence.nil?

          open = Checker::OPEN_LICENCES.any? { |pattern| licence.match?(pattern) } && !licence.match?(Checker::RESTRICTIVE_LICENCE)
          reserved = @sheet.scope == 'members'

          if !open && !reserved
            [error("La licence « #{licence} » n'est pas une licence ouverte. Choisir une licence ouverte, " \
                   'ou écrire « scope: members » dans la fiche pour réserver le jeu aux adhérents.')]
          elsif licence.match?(Checker::SHARE_ALIKE_LICENCE)
            [warning("La licence « #{licence} » impose le partage à l'identique : ce qui en dérive doit garder cette licence.")]
          else
            []
          end
        end

        def table_findings(table)
          declared = declaration_findings(table)
          file = @sheet.dir.join(table.file)
          return [*declared, error("Le fichier « #{table.file} » n'est pas dans le dossier.")] unless !table.file.empty? && file.file?

          rows = read(file)
          unreadable = "Le fichier « #{table.file} » ne se lit pas comme un CSV en UTF-8, séparé par des virgules."
          return [*declared, error(unreadable)] if rows.nil?
          return [*declared, error("Le fichier « #{table.file} » est vide.")] if rows.empty?

          headers, *lines = rows
          [*declared, *header_findings(table, headers),
           *error_if(lines.empty?, "Le fichier « #{table.file} » n'a que sa ligne de titres."),
           *value_findings(table, headers, lines), *key_findings(table, headers, lines)]
        end

        def declaration_findings(table)
          file = "« #{table.file} »"
          unknown_types = table.columns.reject { |_, type| Sheet::TYPES.key?(type) }
          known = @pivot_keys + Sheet::PLACE_PARTS.keys
          unknown_pivots = table.pivots.reject { |column, key| table.columns.key?(column) && known.include?(key) }
          personal = table.columns.keys.select { |column| column.match?(Checker::PERSONAL_COLUMN) }

          [
            *error_if(!table.name.match?(/\Aregistered_[a-z0-9_]+\z/),
                      "La table « #{table.name} » doit s'appeler registered_… en minuscules."),
            *error_if(table.columns.empty?, "#{file} : la fiche ne décrit aucune colonne."),
            *table.columns.keys.reject { |column| column.match?(NAME) }.map do |column|
              error("#{file} : la colonne « #{column} » doit être en minuscules, sans accent ni espace.")
            end,
            *unknown_types.map do |column, type|
              error("#{file} : la colonne « #{column} » a le type « #{type} », inconnu. Types possibles : #{Sheet::TYPES.keys.join(', ')}.")
            end,
            *error_if(table.key.nil? || !table.columns.key?(table.key),
                      "#{file} : la fiche doit nommer sous « key » la colonne qui identifie chaque ligne."),
            *place_findings(table, file),
            *unknown_pivots.map do |column, key|
              error("#{file} : le lien « #{column}: #{key} » ne se comprend pas. Clés possibles : #{@pivot_keys.join(', ')}.")
            end,
            *error_if(personal.any? && @sheet.personal_data.nil?,
                      "#{file} : #{columns(personal)} #{personal.one? ? 'ressemble' : 'ressemblent'} à des données personnelles. " \
                      "#{personal.one? ? 'La' : 'Les'} retirer, ou dire sous « personal_data » pourquoi " \
                      "#{personal.one? ? 'elle peut être publiée' : 'elles peuvent être publiées'}.")
          ]
        end

        # A postal code tells several communes and a name several places: both are needed, once each
        def place_findings(table, file)
          postal, named = Sheet::PLACE_PARTS.keys.map { |key| table.pivots.select { |_, chosen| chosen == key }.keys }
          return [] if postal.empty? && named.empty?

          place = table.place
          return [warning(place_note(place, file))] if place

          [
            *error_if(postal.empty?, "#{file} : « #{named.first} » porte le nom d'une commune. Désigner aussi la colonne " \
                                     'qui porte son code postal : un nom seul désigne plusieurs communes.'),
            *error_if(named.empty?, "#{file} : « #{postal.first} » porte un code postal. Désigner aussi la colonne " \
                                    'qui porte le nom de la commune : un code postal seul couvre plusieurs communes.'),
            *error_if(postal.size > 1, "#{file} : plusieurs colonnes portent un code postal (#{postal.join(', ')}). N'en désigner qu'une."),
            *error_if(named.size > 1, "#{file} : plusieurs colonnes portent le nom d'une commune (#{named.join(', ')}). " \
                                      "N'en désigner qu'une.")
          ]
        end

        def place_note(place, file)
          "#{file} : le Lexicon ajoutera une colonne « #{place[:column]} », le code INSEE de la commune trouvé à partir de " \
            "« #{place[:postal_code]} » et de « #{place[:name]} ». Une ligne dont le nom n'est celui d'aucune commune de son " \
            'code postal reste sans code.'
        end

        def read(file)
          content = file.read(encoding: 'bom|utf-8')

          content.valid_encoding? ? CSV.parse(content) : nil
        rescue CSV::MalformedCSVError
          nil
        end

        def header_findings(table, headers)
          missing = table.columns.keys - headers
          extra = headers.compact - table.columns.keys

          [
            *error_if(missing.any?, "« #{table.file} » : il manque #{columns(missing)}, " \
                                    "#{missing.one? ? 'annoncée' : 'annoncées'} par la fiche."),
            *error_if(extra.any?, "« #{table.file} » : #{columns(extra)} " \
                                  "#{extra.one? ? "n'est pas décrite" : 'ne sont pas décrites'} dans la fiche.")
          ]
        end

        # Each value against the type of its column; line numbers are the ones a spreadsheet shows
        def value_findings(table, headers, lines)
          table.columns.select { |column, type| headers.include?(column) && EXPECTED.key?(type) }.flat_map do |column, type|
            index = headers.index(column)
            wrong = lines.each_with_index.reject { |line, _| line[index].to_s.strip.empty? || VALUES[type].call(line[index].to_s.strip) }
            next [] if wrong.empty?

            quoted = wrong.first(QUOTED).map { |line, number| "ligne #{number + 2} « #{line[index]} »" }.join(', ')
            [error("« #{table.file} », colonne « #{column} » : " \
                   "#{counted(wrong.size, "valeur n'est pas", 'valeurs ne sont pas')} #{EXPECTED[type]} (#{quoted}).")]
          end
        end

        def key_findings(table, headers, lines)
          index = table.key && headers.index(table.key)
          return [] if index.nil?

          keys = lines.map { |line| line[index].to_s.strip }
          empty = keys.count(&:empty?)
          repeated = keys.reject(&:empty?).tally.select { |_, count| count > 1 }.keys

          [
            *error_if(empty.positive?, "« #{table.file} » : #{counted(empty, "ligne n'a pas", "lignes n'ont pas")} de valeur " \
                                       "dans « #{table.key} », qui doit identifier chaque ligne."),
            *error_if(repeated.any?, "« #{table.file} » : #{counted(repeated.size, 'valeur', 'valeurs')} de « #{table.key} » " \
                                     "#{repeated.one? ? 'revient' : 'reviennent'} plusieurs fois (#{repeated.first(QUOTED).join(', ')}).")
          ]
        end
    end
  end
end
