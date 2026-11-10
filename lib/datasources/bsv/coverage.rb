# frozen_string_literal: true

require 'csv'

module Datasources
  class Bsv
    # The editions a region publishes (`data/bsv/editions.csv`) against the bulletins read: an edition expected this
    # year (column pdf_2026) with nothing yet is missing, one that has published nothing for LATE days while in
    # season is late. A bulletin no edition takes is counted by its region, sector, zone and subsector, so that a
    # name to add shows.
    #
    # In `editions.csv` sector, zone and subsector may list several names separated by « | », the way bulletins
    # write them (« Champagne-Ardenne|Champagne », « olivier|oléiculture »); an empty name among them takes the
    # bulletins that give none. A subsector is looked for in the label, title and file name of the bulletin too.
    class Coverage
      FILE = Pathname.new('data/bsv/editions.csv')
      LATE = 15

      Edition = Struct.new(:region, :sector, :zone, :subsector, :months, :expected, :dates, keyword_init: true) do
        def name
          [region, sector, zone, subsector].reject(&:empty?).join(' / ')
        end

        def last
          dates.max
        end
      end

      attr_reader :editions, :unmatched

      # @param [Zones] zones
      # @param [Pathname] file
      # @param [Date] today
      def initialize(zones, file = FILE, today: Date.today)
        @zones = zones
        @today = today
        @editions = CSV.read(file, headers: true).map do |row|
          Edition.new(region: row['region'], sector: row['sector'].to_s, zone: row['zone'].to_s,
                      subsector: row['subsector'].to_s, months: row['months'].to_s,
                    expected: row['pdf_2026'].to_i, dates: [])
        end
        @unmatched = Hash.new(0)
      end

      # @param [Array<Hash>] bulletins rows of `Rows::BULLETINS`
      # @return [self]
      def build(bulletins)
        bulletins.each do |bulletin|
          next if bulletin['sector'].to_s.empty? || bulletin['status'] == 'superseded'

          found = @editions.select { |edition| match?(edition, bulletin) }
          date = Date.iso8601(bulletin['published_on'].to_s.empty? ? bulletin['first_seen_on'] : bulletin['published_on'])
          found.each { |edition| edition.dates << date }
          next unless found.empty? && bulletin['nature'] == 'bulletin'

          @unmatched[bulletin.values_at('region', 'sector', 'zone', 'subsector').map(&:to_s)] += 1
        end
        self
      end

      # @return [String] missing, late or ok
      def state(edition)
        this_year = edition.dates.select { |date| date.year == @today.year }
        return 'missing' if this_year.empty? && edition.expected.positive? && started?(edition)
        return 'late' if in_season?(edition, @today) && (edition.last.nil? || edition.last < @today - LATE)

        'ok'
      end

      # @return [Hash{String => Array<Edition>}]
      def by_state
        @editions.group_by { |edition| state(edition) }
      end

      private

        # Same region; the subsector named anywhere in what the bulletin says of itself (« pomme de terre » in
        # the label of a bulletin of grandes cultures), or for an edition with none, the same sector; the same zone,
        # by name or by departments, or named in the label
        def match?(edition, bulletin)
          return false unless [bulletin['region'], *bulletin['regions'].to_s.split('|')].include?(edition.region)

          text = Extraction.plain(bulletin.values_at('subsector', 'label', 'page_title', 'section').join(' ') + " #{File.basename(bulletin['pdf_url'].to_s)}")
          subsector = alternatives(edition.subsector).any? do |name|
            name.empty? ? alternatives(edition.sector).any? { |sector| Zones.key(sector) == Zones.key(bulletin['sector'].to_s) } : named?(name, text)
          end
          subsector && zone?(edition, bulletin['zone'].to_s, text)
        end

        def zone?(edition, zone, text)
          alternatives(edition.zone).any? do |name|
            next zone.strip.empty? if name.empty?

            Zones.key(name) == Zones.key(zone) || named?(Zones.key(name), text) ||
              ((departments = @zones.find(edition.region, zone)) && @zones.find(edition.region, name) == departments)
          end
        end

        def named?(name, text)
          plain = Extraction.plain(name)
          text.include?(plain) || text.include?(plain.delete_suffix('s'))
        end

        def alternatives(names)
          names.empty? ? [''] : names.split('|', -1)
        end

        # The months of an edition (« 3-9 », « 11-2 » over the new year) hold the month of `date`
        def in_season?(edition, date)
          first, last = edition.months.split('-').map(&:to_i)
          return true if first.nil? || last.nil? || first.zero?

          first <= last ? date.month.between?(first, last) : (date.month >= first || date.month <= last)
        end

        # The first month of the season is past
        def started?(edition)
          first = edition.months.split('-').first.to_i
          first.zero? || @today.month >= first
        end
    end
  end
end
