# frozen_string_literal: true

require 'cgi'
require 'csv'

module Datasources
  class BsvArchive
    # What a file of the PestObserver corpus says of itself: its region, its sector and its date, taken from its name,
    # its header and its first lines, null when they cannot be told.
    #
    # Two kinds of files:
    #
    # - TEI XML of the Avertissements agricoles (1960-2010): `AA_<sector>_<regions>_<year>_<n°>.xml`; AA for the
    #   Avertissements agricoles, BT for bulletins techniques, BP for bulletins of a department. The sector is a code
    #   (GC, TC, AF...), sometimes two (`AA_AF_VG_Rhone-Alpes_...`); the regions are former ones, sometimes several
    #   (`Pays_de_la_Loire_Poitou_Charentes`), or a department, or a vineyard (`Bas-Vivarais`). The date is read in
    #   the title (« Le 16 Octobre 1984 »).
    # - text of the BSV of 2009 to 2016, named as the sites of the time named them: the domain of the site when it
    #   is in the name (`draaf.corse.agriculture.gouv.fr_IMG_pdf_...`), else the name of a region in the file name or
    #   in the first lines; the date in the name (`09_03_2010`, `20140707`, `2013.07.03`) or the first lines
    #   (« 09 MARS 2010 », spaced out or not).
    #
    # Regions, former and of today, with their departments: `data/bsv/old_regions.csv`.
    class Documents
      FILE = Pathname.new('data/bsv/old_regions.csv')
      COLUMNS = %w[id file_name kind old_regions regions department_codes sectors published_on year title text].freeze

      SECTORS = {
        'GC' => 'grandes cultures', 'TC' => 'toutes cultures', 'AF' => 'arboriculture', 'VG' => 'viticulture',
        'CL' => 'cultures légumières', 'PDT' => 'pomme de terre', 'POIS' => 'grandes cultures'
      }.freeze
      # Words of a file name or of a header, first found first kept
      SECTOR_WORDS = [
        [/\b(?:vigne|viti\w*|vitic\w*)/, 'viticulture'],
        [/\b(?:arbo\w*|fruits?|pommier|chataigne\w*|noix|noyer|olivier|oleic\w*|agrumes?|kiwi)/, 'arboriculture'],
        [/\b(?:fraises?|framboises?|petits fruits|myrtilles?|cassis)\b/, 'petits fruits'],
        [/\b(?:pdt|pomme de terre|pommes de terre)\b/, 'pomme de terre'],
        [/\b(?:maraich\w*|leg|legumes?|melons?|ail|oignons?|carottes?|salades?|endives?|asperges?)\b/, 'maraîchage'],
        [/\b(?:horti\w*|ornement\w*|pepini\w*|zna|jevi|espaces verts)/, 'horticulture'],
        [/\b(?:prairies?|fourrag\w*)\b/, 'prairies'],
        [/\b(?:gc|grandes cultures|cereales?|ble|colza|oleagineux|proteagineux|mais|lin|tournesol|betteraves?|orge)\b/, 'grandes cultures']
      ].freeze
      MONTHS = %w[janvier fevrier mars avril mai juin juillet aout septembre octobre novembre decembre].freeze
      # Years the corpus covers
      YEARS = (1950..2016)
      # The first characters of a text, where the header is
      HEAD = 1500

      Region = Struct.new(:keys, :region, :department_codes, :kind, :text_names, keyword_init: true)

      def initialize(file = FILE)
        @regions = CSV.read(file, headers: true).map do |row|
          Region.new(keys: row['key'].split('|'), region: row['region'], department_codes: row['department_codes'].split('|'),
                     kind: row['kind'], text_names: row['text_names'].to_s.split('|'))
        end
      end

      # @param [String] path in the zip
      # @param [String] content
      # @return [Array] a row of COLUMNS
      def row(path, content)
        content = content.dup.force_encoding(Encoding::UTF_8).scrub('')
        file = File.basename(path).dup.force_encoding(Encoding::UTF_8).scrub('')
        stem = File.basename(file, '.*')
        found = file.end_with?('.xml') ? xml(stem, content) : txt(file, content)
        regions = found[:regions]
        [stem, file, found[:kind], regions.map { |region| region.keys.first }.join('|'),
         regions.map(&:region).uniq.join('|'), regions.flat_map(&:department_codes).uniq.sort.join('|'),
         found[:sectors].uniq.join('|'), found[:date]&.iso8601, found[:date]&.year || found[:year], found[:title],
         found[:text]]
      end

      # @return [String] lower case, without accents nor punctuation
      def self.plain(text)
        Bsv::Extraction.plain(text.to_s.dup.force_encoding(Encoding::UTF_8))
      end

      private

        def xml(stem, content)
          match = stem.match(/\A([A-Z]+)_([A-Za-z]+)[-_](.+)_(\d{4})_(\d+)\z/)
          kind = { 'AA' => 'avertissement', 'BT' => 'bulletin_technique', 'BP' => 'bulletin_departemental' }.fetch(match&.[](1), 'avertissement')
          title = CGI.unescapeHTML(content[%r{<title>(.*?)</title>}m, 1].to_s).gsub(/\s+/, ' ').strip
          text = CGI.unescapeHTML(content.sub(%r{\A.*?<text>}m, '').gsub(%r{</(?:p|head)>}, "\n").gsub(/<[^>]+>/, ''))
          return { kind: kind, regions: [], sectors: [], title: title, text: clean(text) } unless match

          codes = [match[2]]
          places = match[3].split('_')
          codes << places.shift while SECTORS.key?(places.first)
          year = match[4].to_i
          date = date_in(Documents.plain(title), year)
          { kind: kind, regions: named(Documents.plain(places.join(' '))), sectors: codes.filter_map { |code| SECTORS[code] },
            date: date, year: year, title: title, text: clean(text) }
        end

        def txt(file, content)
          text = clean(content)
          head = Documents.plain(text[0, HEAD])
          name = Documents.plain(file.sub(/\.txt\z/, ''))
          domain = file[/\A((?:[\w-]+\.)+(?:fr|com))_/, 1]
          regions = domain ? compact_named(Documents.plain(domain)) : compact_named(name)
          regions = in_text(head) if regions.empty?
          regions = in_sites(text) if regions.empty?
          kind = name.match?(/\Anote\b/) ? 'note' : 'bsv'
          year = name.scan(/(?<!\d)(20[01]\d)(?!\d)/).flatten.map(&:to_i).find { |one| YEARS.cover?(one) }
          date = date_in_name(file) || date_in(head, year) || date_in(head.delete(' '), year, compact: true)
          { kind: kind, regions: regions, sectors: sectors_of(name).then { |found| found.empty? ? sectors_of(head[0, 400]) : found }, date: date,
            year: year || head[/\b(20[01]\d)\b/, 1]&.to_i, title: file.sub(/\.txt\z/, '').tr('_', ' ').squeeze(' ').strip,
            text: text }
        end

        # Places of a file name of the Avertissements agricoles: the longest names first
        def named(plain)
          words = plain.split
          found = []
          until words.empty?
            region = words.size.downto(1).lazy.filter_map { |size| key_of(words.first(size).join(' ')) }.first
            if region
              found << region
              words = words.drop(region.keys.map(&:split).find { |key| key == words.first(key.size) }.size)
            else
              words = words.drop(1)
            end
          end
          found
        end

        def key_of(name)
          @regions.find { |region| region.keys.include?(name) }
        end

        # Regions whose name, spaces removed, is in a file name or a domain: the longest first, then any other that
        # is not part of it (« alsacechampagneardennelorraine » is one region)
        def compact_named(plain)
          compact = plain.delete(' ')
          candidates = @regions.select { |region| %w[région ancienne\ région].include?(region.kind) }
                               .flat_map { |region| region.keys.map { |key| [key.delete(' '), region] } }
                               .select { |key, _| key.size >= 3 && compact.include?(key) }
                               .sort_by { |key, _| -key.size }
          kept = []
          candidates.each { |key, region| kept << [key, region] unless kept.any? { |longer, _| longer.include?(key) } }
          kept.map(&:last).uniq
        end

        # The region named first in the header; at the same place, the longest name
        def in_text(head)
          found = @regions.flat_map do |region|
            region.text_names.filter_map do |name|
              at = head =~ /\b#{Regexp.escape(name)}\b/
              [at, -name.size, region] if at
            end
          end
          first = found.min_by { |at, size, _| [at, size] }
          first ? [first.last] : []
        end

        # The region of the sites of a DRAAF or a chamber the text names most (« draaf.bretagne.agriculture.gouv.fr »)
        def in_sites(text)
          sites = text.downcase.scan(/\b(?:www\.)?([\w-]+(?:\.[\w-]+)*\.(?:fr|com))\b/).flatten
                      .select { |site| site.match?(/draaf|driaaf|chambagri|synagri|chambre|fredon|agri\w*\.fr/) }
          counts = sites.flat_map { |site| compact_named(Documents.plain(site)) }.tally
          best = counts.max_by { |_, n| n }
          best ? [best.first] : []
        end

        def sectors_of(text)
          SECTOR_WORDS.filter_map { |pattern, sector| sector if text.match?(pattern) }.first(1)
        end

        # « 16 octobre 1984 », « 1er mars 2010 », « 09/03/2010 »; spaced out letters read once the spaces removed
        def date_in(plain, year, compact: false)
          months = MONTHS.join('|')
          pattern = compact ? /(\d{1,2})(?:er)?(#{months})(\d{4})/ : /\b(\d{1,2})(?:er)? (#{months}) (\d{4})\b/
          plain.to_enum(:scan, pattern).each do
            day, month, found_year = Regexp.last_match.captures
            date = valid(found_year.to_i, MONTHS.index(month) + 1, day.to_i, year)
            return date if date
          end
          slashed = plain.match(%r{\b(\d{1,2}) (\d{1,2}) (\d{4})\b}) unless compact
          slashed && valid(slashed[3].to_i, slashed[2].to_i, slashed[1].to_i, year)
        end

        # `09_03_2010`, `25042014`, `2013.07.03`, `20140707`, `100928_` (yymmdd)
        def date_in_name(file)
          name = file.sub(/\.txt\z/, '')
          [[/(?<!\d)(\d{2})[_.-](\d{2})[_.-](20[01]\d)(?!\d)/, %i[d m y]],
           [/(?<!\d)(20[01]\d)[_.-](\d{2})[_.-](\d{2})(?!\d)/, %i[y m d]],
           [/(?<!\d)(20[01]\d)(\d{2})(\d{2})(?!\d)/, %i[y m d]],
           [/(?<!\d)(\d{2})(\d{2})(20[01]\d)(?!\d)/, %i[d m y]],
           [/\A(1[0-6]|09)(\d{2})(\d{2})_/, %i[y m d]]].each do |pattern, order|
            match = name.match(pattern) or next
            parts = order.zip(match.captures.map(&:to_i)).to_h
            parts[:y] += 2000 if parts[:y] < 100
            date = valid(parts[:y], parts[:m], parts[:d], nil)
            return date if date
          end
          nil
        end

        def valid(year, month, day, expected)
          return nil unless YEARS.cover?(year) && (expected.nil? || (year - expected).abs <= 1)

          Date.new(year, month, day)
        rescue Date::Error
          nil
        end

        # No NUL (PostgreSQL refuses it), runs of spaces and of empty lines made single
        def clean(text)
          text.to_s.scrub('').delete("\u0000").gsub(/[ \t ]+/, ' ').gsub(/ ?\n ?/, "\n").gsub(/\n{3,}/, "\n\n").strip
        end
    end
  end
end
