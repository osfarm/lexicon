# frozen_string_literal: true

module Datasources
  class Seeds
    # Reads what a merchant calls a seed: "Seigle fourrager TURBOGREEN non traité", "Avoine VODKA blanche AB
    # non traité", "Mélange PERMA'TOP". The species comes first, the variety is written in capitals.
    class Label
      Reading = Struct.new(:species_id, :variety, :organic, :treated, :mixture, keyword_init: true)

      MIXTURE = /\A(melange|meteil|couvert|prairie|association)\b/.freeze
      ORGANIC = /\b(AB|UAB|BIO|Bio|bio|biologique)\b/.freeze
      # Capitals that are not a variety: labels, seed treatments, units
      NOT_A_VARIETY = %w[AB UAB BIO NT VIBRANCE GOLD CELEST REDIGO DIFEND EXTRA PREMIUM TS KG PMG RGI RGA RGH].freeze
      VARIETY = /(?<![\p{L}'’-])\p{Lu}[\p{Lu}\d'’.-]{2,}(?:\s+\p{Lu}[\p{Lu}\d'’.-]{2,})*(?![\p{L}])/.freeze

      # @param [Array<Hash>] species rows of data/seeds/species.csv, the most precise names first
      def initialize(species)
        @species = species.map { |row| [/\A(semences? (de |d.)?)?(#{row['pattern']})/, row['id']] }
      end

      # @param [String] label
      # @param [Boolean] several whether the card lists several species with their share
      # @return [Reading]
      def read(label, several: false)
        plain = self.class.plain(label)
        mixture = several || plain.match?(MIXTURE)

        Reading.new(
          species_id: mixture ? nil : @species.find { |pattern, _| plain.match?(pattern) }&.last,
          variety: mixture ? nil : variety(label), organic: label.match?(ORGANIC),
          treated: plain.include?('non traite') ? false : nil, mixture: mixture
        )
      end

      # @return [String] lower case, without accents
      def self.plain(text)
        text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/\s+/, ' ').strip
      end

      private

        # A name all in capitals does not tell the variety from the species
        def variety(label)
          return nil if label == label.upcase

          words = label.scan(VARIETY).flat_map(&:split).reject { |word| NOT_A_VARIETY.include?(word) }

          words.empty? ? nil : words.join(' ')
        end
    end
  end
end
