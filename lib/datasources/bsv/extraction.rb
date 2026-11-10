# frozen_string_literal: true

module Datasources
  class Bsv
    # Checks what the API answered for a bulletin before anything is written from it. A line is refused, with its
    # reason, when:
    #
    # - its quote is not found in the text of the pages (lower case, without accents nor punctuation), unless the
    #   PDF has no text (scanned): the model read the images, there is nothing to check against. The model reads the
    #   page as it is laid out, pdftotext mixes columns, tables and captions: a quote is found too when its words
    #   come in its order within a short stretch of the text (QUOTE_SPAN), one word in ten at most missing;
    # - its crop is its pest;
    # - a BBCH or Zadoks code is out of 0 to 99, or its minimum is over its maximum;
    # - its level is out of the scale.
    #
    # A bilan or a note keeps no line (decision of 2026-11-08: catalogue only).
    class Extraction
      Refusal = Struct.new(:index, :reason)
      # The stretch of text the words of a quote must come in: three words of text for one of the quote, and 40 more
      QUOTE_SPAN = [3, 40].freeze

      attr_reader :answer, :lines, :refusals

      # @param [Hash] answer the JSON of the answer
      # @param [Array<String>] pages the text of each page
      def initialize(answer, pages)
        @answer = answer
        joined = pages.join(' ')
        @text = self.class.plain(joined)
        # « déve-\nloppement »: a word cut at the end of a line
        @unhyphenated = self.class.plain(joined.gsub(/-[ \t]*\n\s*/, ''))
        @scanned = Pages.scanned?(pages)
        @lines = []
        @refusals = []
        check
      end

      # @return [Boolean] true when the risks of the bulletin are published (a bulletin, not a bilan nor a note)
      def risks?
        answer['nature'] == 'bulletin'
      end

      # @return [Date, nil] the date of the header
      def published_on
        Date.iso8601(answer['date'].to_s)
      rescue Date::Error
        nil
      end

      # @return [String] lower case, without accents nor punctuation, spaces made single
      def self.plain(text)
        text.to_s.scrub.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub('œ', 'oe').gsub('æ', 'ae')
            .gsub(/[^a-z0-9]+/, ' ').strip
      end

      private

        def check
          return unless risks?

          Array(answer['lignes']).each_with_index do |line, index|
            reason = refusal(line)
            reason ? @refusals << Refusal.new(index, reason) : @lines << [index, line]
          end
        end

        def refusal(line)
          crop = self.class.plain(line['culture'])
          return 'no crop' if crop.empty?
          return 'crop is the pest' if crop == self.class.plain(line['bioagresseur'])
          return "level #{line['niveau']}" unless Schema::LEVELS.include?(line['niveau'])
          return 'BBCH out of 0-99' unless codes?(line['bbch_min'], line['bbch_max'])
          return 'Zadoks out of 0-99' unless codes?(line['zadoks_min'], line['zadoks_max'])
          return if @scanned

          quote = self.class.plain(line['extrait'])
          'quote not in the text' if quote.empty? || !found?(quote)
        end

        def found?(quote)
          @text.include?(quote) || @unhyphenated.include?(quote) || in_order?(quote.split)
        end

        # The words of the quote in its order within QUOTE_SPAN, one in ten at most missing
        def in_order?(words)
          missing = words.size / 10
          span = (words.size * QUOTE_SPAN.first) + QUOTE_SPAN.last
          words.first(missing + 1).each_with_index do |word, skipped|
            positions.fetch(word, []).each do |start|
              return true if follows?(words.drop(skipped + 1), start + 1, start + span, missing - skipped)
            end
          end
          false
        end

        def follows?(words, from, limit, missing)
          limit = [limit, text_words.size].min
          words.each do |word|
            index = (from...limit).find { |at| text_words[at] == word }
            if index
              from = index + 1
            else
              missing -= 1
              return false if missing.negative?
            end
          end
          true
        end

        def text_words
          @text_words ||= @text.split
        end

        def positions
          @positions ||= text_words.each_with_index.with_object(Hash.new { |hash, key| hash[key] = [] }) do |(word, at), all|
            all[word] << at
          end
        end

        def codes?(min, max)
          [min, max].compact.all? { |code| code.is_a?(Integer) && code.between?(0, 99) } &&
            (min.nil? || max.nil? || min <= max)
        end
    end
  end
end
