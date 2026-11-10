# frozen_string_literal: true

module Datasources
  class Bsv
    # The level of a risk against the words the bulletin uses for it (`level_text`), for two mistakes of the model:
    #
    # - « très faible » read as tres_fort: when the text says « très faible » and nothing high, the level is faible;
    # - a range read low: « faible à moyen », « moyen à fort », « moyens à forts selon les secteurs » take the higher
    #   level, as the instructions say; a level under the highest range of the text is raised to it, unless the
    #   text places a cursor on a level (« curseur sur faible ») or the range is a gauge (« l'échelle faible à fort »).
    #
    # Any other disagreement is left to the model: bulletins name several levels in one sentence (« peu important »,
    # « risque théorique fort, très faibles contaminations »).
    module Levels
      SCALE = %w[nul faible moyen fort tres_fort].freeze
      LOWEST = /\btres faibles?\b/
      HIGH = /\b(?:forte?s?|elevee?s?|importante?s?|graves?|serieux|extremes?|maximal|maximum|rouges?)\b/
      WORD = '(?:tres )?(?:nul|nulle|faible|moyen|moyenne|modere|moderee|fort|forte|eleve|elevee|important|importante)s?'
      RANGE = /\b(#{WORD}) (?:a|voire) (#{WORD})\b/
      # « l'échelle faible à fort » describes a gauge; « curseur sur faible » says the level itself
      SCALE_NAMED = /\bechelle (?:de )?#{WORD} a/
      CURSOR = /\bcurseur (?:est )?(?:sur|au niveau|positionne sur) (?:le niveau |risque )?#{WORD}\b/

      # @param [String] level as the model gives it
      # @param [String, nil] text the words of the bulletin for the risk
      # @return [String] the level kept
      def self.checked(level, text)
        plain = Extraction.plain(text)
        return 'faible' if level == 'tres_fort' && plain.match?(LOWEST) && !plain.gsub(LOWEST, ' ').match?(HIGH)

        return level if plain.match?(CURSOR)

        highest = plain.gsub(SCALE_NAMED, ' ').scan(RANGE).flatten.filter_map { |word| level_of(word) }.max_by { |one| SCALE.index(one) }
        highest && SCALE.include?(level) && SCALE.index(level) < SCALE.index(highest) ? highest : level
      end

      # @param [String] word plain, as RANGE takes it
      # @return [String, nil]
      def self.level_of(word)
        very = word.start_with?('tres ')
        case word.delete_prefix('tres ').delete_suffix('s')
        when 'nul', 'nulle' then 'nul'
        when 'faible' then 'faible'
        when 'moyen', 'moyenne', 'modere', 'moderee' then 'moyen'
        when 'fort', 'forte', 'eleve', 'elevee', 'important', 'importante' then very ? 'tres_fort' : 'fort'
        end
      end
    end
  end
end
