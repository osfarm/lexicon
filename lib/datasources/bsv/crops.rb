# frozen_string_literal: true

require 'csv'

module Datasources
  class Bsv
    # The productions of Lexicon (`master_productions`) a crop name of a bulletin stands for, from
    # `data/bsv/cultures.csv`. A name the file does not hold is read again:
    #
    # 1. without what only says how the crop is grown (« tomate sous abri », « melon plein champ », « ail violet » is
    #    not stripped: only the words of QUALIFIERS);
    # 2. in the singular (« choux », « rosiers »);
    # 3. split into the crops it lists (« poivron / piment », « choux et brocolis »), when each of them is known.
    class Crops
      FILE = Pathname.new('data/bsv/cultures.csv')
      QUALIFIERS = [
        /\s(?:sous|en) (?:abris?|serres?|tunnels?|chenilles?|grands? abris?|verre)\b.*\z/,
        /\s(?:de|d) serres?\z/, /\s(?:plein|pleins) champs?\z/, /\shors sol\z/, /\sen (?:conteneurs?|pots?)\z/,
        /\sen pleine terre\z/, /\s(?:en )?(?:agriculture )?biologique\z/, /\sbio\z/
      ].freeze

      # @param [Pathname] file
      def initialize(file = FILE)
        @names = CSV.read(file, headers: true).to_h { |row| [Extraction.plain(row['crop']), row['production_names']] }
        @singular = @names.transform_keys { |name| self.class.singular(name) }
      end

      # @param [String] name as the bulletin writes it
      # @return [String, nil] production names separated by |, nil when the name is unknown
      def productions(name)
        plain = Extraction.plain(name)
        return if plain.empty?

        one(plain) || several(name)
      end

      # @return [String] each word in the singular (a final s or x dropped from words of more than three letters)
      def self.singular(plain)
        plain.split.map { |word| word.length > 3 ? word.sub(/[sx]\z/, '') : word }.join(' ')
      end

      private

        def one(plain)
          stripped = QUALIFIERS.reduce(plain) { |text, qualifier| text.sub(qualifier, '') }
          [plain, stripped].uniq.each do |text|
            found = @names[text] || @singular[self.class.singular(text)]
            return found if found
          end
          nil
        end

        def several(name)
          parts = name.to_s.split(%r{\s*(?:/|,|\+|;|\bet\b|&)\s*}i).map { |part| Extraction.plain(part) }.reject(&:empty?)
          return if parts.size < 2

          found = parts.map { |part| one(part) }
          return if found.include?(nil)

          found.flat_map { |productions| productions.split('|') }.uniq.join('|')
        end
    end
  end
end
