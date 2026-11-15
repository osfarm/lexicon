# frozen_string_literal: true

require 'csv'

module Datasources
  class Bsv
    # The lines of the raw tables, from the archive alone (no network): one per bulletin, one per risk of a
    # bulletin read and checked (`Extraction`), as its correction (`Correction`) leaves it, one per place a risk names. What could not be used is counted, so
    # that `load` says it.
    class Rows
      BULLETINS = %w[id region regions department_codes zone sector subsector number published_on first_seen_on
                     last_seen_on nature label page_title section article_url pdf_url pages_count scanned status
                     superseded_by model instructions_version citation].freeze
      RISKS = %w[id bulletin_id crop production_names pest pest_type stage bbch_min bbch_max level level_text
                 conditional condition risk_period threshold observations page source_quote].freeze
      PLACES = %w[risk_id name department_code].freeze
      CROPS = Crops::FILE

      # Status of a bulletin
      #   extracted       its risks are published
      #   catalogue_only  a bilan or a note: catalogue and text only
      #   pending         not read yet by the API
      #   refused         the API refused, was cut short, or failed three times; or the PDF is too large for it
      #   unreadable      pdftotext could not open it: no text, not sent
      #   superseded      another PDF of the same bulletin (corrected version) was seen later

      # A line with no pest says the stage of the crop: its type is `stade`
      STAGE = 'stade'
      # No bulletin de santé du végétal is older (the network began in 2009)
      FIRST_YEAR = 2009
      # « stade phénologique », « stades et état des cultures »: a heading the model took for a pest
      STAGE_HEADING = /\Astades?\b/i

      attr_reader :bulletins, :risks, :places, :refusals, :unknown_crops, :unknown_zones, :statuses, :levels_changed, :levels_corrected,
                  :lines_dropped

      # @param [Archive] archive
      # @param [Zones] zones
      def initialize(archive, zones)
        @archive = archive
        @zones = zones
        @crops = Crops.new
        @bulletins = []
        @risks = []
        @places = []
        @refusals = Hash.new(0)
        @unknown_crops = Hash.new(0)
        @unknown_zones = Hash.new(0)
        @statuses = Hash.new(0)
        @levels_changed = 0
        @levels_corrected = 0
        @lines_dropped = 0
      end

      # A date read in the header, unless it cannot be: before FIRST_YEAR, or more than a month after the bulletin
      # was first seen (« 7777-07-07 », a bilan dated the end of a year still to come)
      def self.plausible(date, first_seen_on)
        date if date && date.year >= FIRST_YEAR && date <= Date.iso8601(first_seen_on) + 31
      end

      def build
        read = @archive.entries.map { |entry| read(entry) }
        winners = supersede(read)
        read.each do |bulletin|
          winner = winners[bulletin[:edition]]
          if winner && winner != bulletin[:row]['id']
            bulletin[:row]['status'] = 'superseded'
            bulletin[:row]['superseded_by'] = winner
          elsif bulletin[:extraction]
            add_risks(bulletin[:row]['id'], bulletin[:extraction])
          end
          @statuses[bulletin[:row]['status']] += 1
          @bulletins << bulletin[:row].values_at(*BULLETINS)
        end
        self
      end

      private

        def read(entry)
          notice = entry.notice || {}
          listed = Array(notice['regions'])
          seen = notice['first_seen_on'] || entry.pdf.mtime.to_date.iso8601
          row = {
            'id' => entry.sha, 'region' => listed.first || 'unknown', 'regions' => listed.join('|'),
            'label' => notice['label'], 'page_title' => notice['page_title'], 'section' => notice['section'],
            'article_url' => Array(notice['page_urls']).first, 'pdf_url' => Array(notice['pdf_urls']).first,
            'pages_count' => entry.pages&.size.to_i, 'first_seen_on' => seen, 'last_seen_on' => notice['last_seen_on'] || seen,
            'scanned' => entry.pages ? Pages.scanned?(entry.pages) : nil
          }
          answer = @archive.answer(entry.sha, 'haiku')
          extraction = (Extraction.new(corrected(entry, answer), entry.pages) if usable(answer))
          row['status'] = status(entry, answer, extraction)
          describe(row, listed, answer, extraction)
          { row: row, extraction: (extraction if row['status'] == 'extracted'), edition: edition(row, extraction) }
        end

        # The answer as its correction leaves it, when there is one of that very extraction
        def corrected(entry, answer)
          fix = @archive.answer(entry.sha, Correction::KEY)
          return answer['answer'] unless usable(fix) && fix['of'] == answer['batch_id'] && fix['answer']['corrections'].is_a?(Array)

          corrected, changed, dropped = Correction.apply(answer['answer'], fix['answer']['corrections'])
          @levels_corrected += changed
          @lines_dropped += dropped
          corrected
        end

        def usable(answer)
          answer && answer['result'] == 'succeeded' && answer['stop_reason'] == 'end_turn' && answer['answer'].is_a?(Hash)
        end

        def status(entry, answer, extraction)
          return 'unreadable' unless entry.pages
          return extraction.risks? ? 'extracted' : 'catalogue_only' if extraction
          return 'pending' if answer.nil?
          return 'pending' if Extractor::RETRIED.include?(answer['result']) && answer['attempts'].to_i < Extractor::ATTEMPTS

          'refused'
        end

        # What the header of the bulletin says, and the departments it covers
        def describe(row, listed, answer, extraction)
          departments = listed.flat_map { |region| @zones.departments(region) || [] }
          if extraction
            header = extraction.answer
            row.merge!('zone' => header['zone'], 'sector' => header['filiere'], 'subsector' => header['sous_filiere'],
                       'number' => header['numero'], 'published_on' => Rows.plausible(extraction.published_on, row['first_seen_on'])&.iso8601,
                       'nature' => header['nature'], 'model' => answer['model'], 'instructions_version' => answer['version'])
            departments = territory(row['region'], header, departments)
          end
          row['department_codes'] = departments.uniq.sort.join('|')
          row['citation'] = citation(row, extraction&.answer&.dig('region'))
        end

        # The zone of the bulletin when it is smaller than its region, and the regions it says it covers too
        def territory(region, header, departments)
          if header['zone'].to_s.strip != ''
            zone = @zones.find(region, header['zone'])
            @unknown_zones["#{region} #{header['zone']}"] += 1 unless zone
            departments = zone if zone
          end
          cited = Array(header['regions_citees']).flat_map { |name| @zones.departments(Zones.slug(name)) || [] }
          departments + cited
        end

        # @param [String] region as the header of the bulletin writes it
        def citation(row, region)
          return row['label'].to_s if row['sector'].nil?

          date = row['published_on'] && Date.iso8601(row['published_on']).strftime('%d/%m/%Y')
          ['Bulletin de santé du végétal', region, row['sector'],
           row['zone'], row['subsector'], row['number'] && "n° #{row['number']}", date && "du #{date}"].compact.join(' ')
        end

        # Two PDF of one bulletin: same region, sector, zone, subsector, number and year
        def edition(row, extraction)
          return unless extraction&.risks? && row['number'].to_s.strip != '' && row['published_on']

          [row['region'], row['sector'], row['zone'], row['subsector'], row['number'].to_s.strip, row['published_on'][0, 4]]
        end

        # @return [Hash{Array => String}] the bulletin each edition keeps: the one seen last
        def supersede(read)
          read.select { |bulletin| bulletin[:edition] }.group_by { |bulletin| bulletin[:edition] }.to_h do |edition, same|
            [edition, same.max_by { |bulletin| [bulletin[:row]['first_seen_on'], bulletin[:row]['id']] }[:row]['id']]
          end
        end

        def add_risks(bulletin_id, extraction)
          extraction.refusals.each { |refusal| @refusals[refusal.reason] += 1 }
          extraction.lines.each do |index, line|
            next if line['supprimee']

            id = "#{bulletin_id}:#{index + 1}"
            @risks << risk(id, bulletin_id, line).values_at(*RISKS)
            Array(line['lieux']).each { |name| @places << place(id, name) }
          end
        end

        def risk(id, bulletin_id, line)
          productions = @crops.productions(line['culture'])
          @unknown_crops[line['culture'].to_s.downcase.strip] += 1 unless productions
          # The BBCH scale of cereals is the decimal code of Zadoks: Z30 is BBCH 30
          bbch_min, bbch_max = line['bbch_min'] || line['bbch_max'] ? [line['bbch_min'], line['bbch_max']] : [line['zadoks_min'], line['zadoks_max']]
          pest, pest_type = pest(line)
          level = Levels.checked(line['niveau'], line['niveau_texte'])
          @levels_changed += 1 if level != line['niveau']
          {
            'id' => id, 'bulletin_id' => bulletin_id, 'crop' => line['culture'].to_s.strip.downcase,
            'production_names' => productions, 'pest' => pest, 'pest_type' => pest_type,
            'stage' => line['stade'], 'bbch_min' => bbch_min, 'bbch_max' => bbch_max, 'level' => level,
            'level_text' => line['niveau_texte'], 'conditional' => line['conditionnel'] ? 'true' : 'false',
            'condition' => line['condition'], 'risk_period' => line['periode_risque'], 'threshold' => line['seuil'],
            'observations' => line['observations'], 'page' => line['page'], 'source_quote' => line['extrait']
          }
        end

        # @return [Array(String, String)] the pest and its type; a line of stage has none and the type `stade`
        def pest(line)
          pest = line['bioagresseur'].to_s.strip
          return [nil, STAGE] if line['type'].nil? && (pest.empty? || pest.match?(STAGE_HEADING))

          [pest.empty? ? nil : pest, line['type']]
        end

        # « Issigeac 24 », « Asques (33) »: the name, and the department when it is written
        def place(risk_id, name)
          text = name.to_s.strip
          department = text[/[\s(]((?:0[1-9]|[1-8]\d|9[0-5]|2[AB]))\)?\z/i, 1]
          text = text.sub(/[\s(]+(?:0[1-9]|[1-8]\d|9[0-5]|2[AB])\)?\z/i, '').strip if department
          [risk_id, text, department&.upcase]
        end
    end
  end
end
