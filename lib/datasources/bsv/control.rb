# frozen_string_literal: true

require 'csv'

module Datasources
  class Bsv
    # Measures Haiku against Opus on the bulletins both read. Lines are paired by crop and pest (lower case, without
    # accents nor punctuation); for each bulletin: lines of Opus, those Haiku found too, and among them those of the
    # same level. Opus measures, it never replaces: the lines published are those of Haiku.
    class Control
      COLUMNS = %w[checked_on bulletin_id opus_lines found compared same_level].freeze
      # Below these shares, the collect warns
      FOUND = 0.80
      SAME_LEVEL = 0.85

      # @param [Hash] haiku answer
      # @param [Hash] opus answer
      # @return [Hash{String => Integer}] opus_lines, found, compared (both gave a level), same_level
      def self.compare(haiku, opus)
        mine = lines(haiku)
        theirs = lines(opus)
        pairs = theirs.filter_map do |line|
          match = mine.find { |other| same?(line[:crop], other[:crop]) && same?(line[:pest], other[:pest]) }
          [line[:level], mine.delete(match)[:level]] if match
        end
        compared = pairs.reject { |levels| levels.include?('non_precise') }
        { 'opus_lines' => theirs.size, 'found' => pairs.size, 'compared' => compared.size,
          'same_level' => compared.count { |theirs_level, mine_level| theirs_level == mine_level } }
      end

      # @return [Array<Hash>] the words of the crop and of the pest of each line, and its level
      def self.lines(answer)
        Array(answer['lignes']).map do |line|
          { crop: words(line['culture']), pest: words(line['bioagresseur']), level: line['niveau'] }
        end
      end

      # Two names are the same when the words of one hold those of the other: « black rot » and « black rot
      # (Guignardia bidwellii) », « mouche des semis » and « mouches des semis », « buddleia » and « Buddleia davidii »
      def self.same?(one, other)
        return one.empty? && other.empty? if one.empty? || other.empty?

        one.subset?(other) || other.subset?(one)
      end

      # @return [Set<String>] the words of a name, in the singular
      def self.words(name)
        Extraction.plain(name).split.map { |word| word.length > 3 ? word.sub(/[sx]\z/, '') : word }.to_set
      end

      # Compares the bulletins of `shas` that have both answers, adds them to `file` and says what they give
      # @param [Archive] archive
      # @param [Array<String>] shas
      # @param [Pathname] file controls.csv
      # @param [#call] say
      def self.run(archive, shas, file, say:)
        rows = shas.uniq.filter_map do |sha|
          haiku, opus = %w[haiku opus].map { |key| archive.answer(sha, key)&.dig('answer') }
          next unless haiku && opus

          compare(haiku, opus).merge('checked_on' => Date.today.iso8601, 'bulletin_id' => sha)
        end
        return if rows.empty?

        new_file = !file.exist?
        CSV.open(file, 'a') do |csv|
          csv << COLUMNS if new_file
          rows.each { |row| csv << row.values_at(*COLUMNS) }
        end
        say.call(summary(rows))
      end

      # @return [String] what a set of comparisons gives, in red under the thresholds
      def self.summary(rows)
        sums = %w[opus_lines found compared same_level].to_h { |key| [key, rows.sum { |row| row[key] }] }
        found = sums['found'].fdiv([sums['opus_lines'], 1].max)
        same = sums['same_level'].fdiv([sums['compared'], 1].max)
        text = format('BSV control on %<n>d bulletins: Haiku finds %<found>.0f %% of the lines of Opus, same level ' \
                      'for %<same>.0f %% of %<compared>d', n: rows.size, found: found * 100, same: same * 100,
                                                           compared: sums['compared'])
        found < FOUND || same < SAME_LEVEL ? text.red : text
      end
    end
  end
end
