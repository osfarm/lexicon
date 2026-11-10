# frozen_string_literal: true

require 'digest'
require 'json'

module Datasources
  class Bsv
    # A second reading, cheaper than a new extraction, of the lines Haiku extracted under former instructions: Haiku
    # reads the text of the pages (pdftotext, no PDF) and the lines already kept, numbered, and answers only what to
    # correct, by the rules on levels of the instructions of today (`data/bsv/consigne.md`). The answer is kept in
    # `<sha>.fix.json` beside the extraction it corrects, which stays as it was.
    #
    # A correction never makes a level `non_precise`: the text has no gauge, no cursor, no colour, and a level read
    # from them on the PDF would be lost. It may raise a line out of `non_precise`, change one level for another, or
    # drop a line that has no reason to be (an empty cell of a table, « stade phénologique » taken for a pest).
    module Correction
      KEY = 'fix'
      # The bullet on levels of the instructions, up to the next field
      RULES = /^- `niveau` :.*?(?=^- `niveau_texte`)/m

      SCHEMA = {
        type: 'object', additionalProperties: false, required: ['corrections'],
        properties: { corrections: { type: 'array', items: {
          type: 'object', additionalProperties: false,
          required: %w[ligne action niveau conditionnel condition niveau_texte],
          properties: {
            ligne: { type: 'integer' }, action: { type: 'string', enum: %w[niveau supprimer] },
            niveau: { anyOf: [{ type: 'string', enum: Schema::LEVELS }, { type: 'null' }] },
            conditionnel: { type: 'boolean' }, condition: { type: %w[string null] },
            niveau_texte: { type: %w[string null] }
          }
        } } }
      }.freeze

      # @return [String] the system prompt
      def self.instructions
        <<~TXT
          Tu relis les lignes extraites d'un Bulletin de santé du végétal (BSV). Chaque ligne est une culture × un
          bioagresseur (ou une ligne de stade, bioagresseur null) avec le niveau de risque retenu. Tu reçois le texte
          du bulletin, page par page, puis les lignes numérotées.

          Corrige seulement ce qui est faux, selon ces règles :

          #{Schema.instructions[RULES]}
          Une ligne est à supprimer si elle n'a pas lieu d'être : un nom seul dans un tableau ou un sommaire aux
          cases vides, un bioagresseur « stade phénologique » (c'est une ligne de stade), un doublon exact d'une autre
          ligne.

          Réponds uniquement par la liste des corrections, vide si tout est juste. Pour un changement de niveau, donne
          le nouveau `niveau`, `conditionnel`, `condition` (null si non conditionnel) et `niveau_texte` (la phrase
          d'évaluation du bulletin, recopiée et raccourcie). Ne propose pas une correction qui redonne le même niveau.
        TXT
      end

      # @return [String] 12 characters that change with the instructions of the correction, and so with the rules
      #   on levels of the extraction
      def self.version
        Digest::SHA256.hexdigest(instructions + JSON.generate(SCHEMA))[0, 12]
      end

      # @param [Array<String>] pages
      # @param [Hash] extraction the answer of the extraction
      # @return [String] the message: the pages, then the lines, numbered from 1
      def self.message(pages, extraction)
        text = Array(pages).each_with_index.map do |page, index|
          "=== page #{index + 1}\n#{page.gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n")}"
        end.join("\n")
        lines = Array(extraction['lignes']).each_with_index.map do |line, index|
          condition = line['conditionnel'] ? " (si : #{line['condition']})" : ''
          "#{index + 1}. p#{line['page']} | #{line['culture']} | #{line['bioagresseur'] || '(stade)'} | #{line['type']} | " \
            "#{line['niveau']}#{condition} | #{line['niveau_texte'].to_s[0, 160]}"
        end
        "<bulletin>\n#{text}\n</bulletin>\n\n<lignes>\n#{lines.join("\n")}\n</lignes>\n\nDonne les corrections."
      end

      # @param [Hash] extraction the answer of the extraction, left as it is
      # @param [Array<Hash>] corrections
      # @return [Array(Hash, Integer, Integer)] the answer corrected, whose dropped lines say `supprimee`
      #   (a line keeps its number), the number of levels changed and of lines dropped
      def self.apply(extraction, corrections)
        lines = Array(extraction['lignes']).map(&:dup)
        changed = dropped = 0
        Array(corrections).each do |correction|
          index = correction['ligne'].to_i - 1
          line = lines[index] if index >= 0
          next unless line && !line['supprimee']

          if correction['action'] == 'supprimer'
            line['supprimee'] = true
            dropped += 1
          elsif Schema::LEVELS.include?(correction['niveau']) && correction['niveau'] != 'non_precise' && correction['niveau'] != line['niveau']
            line.merge!(correction.slice('niveau', 'conditionnel', 'condition', 'niveau_texte'))
            changed += 1
          end
        end
        [extraction.merge('lignes' => lines), changed, dropped]
      end
    end
  end
end
