# frozen_string_literal: true

module Datasources
  class Phytosanitary
    module Derogations
      # One decision read by Mistral OCR, checked before anything is built from it. The fields the model filled
      # (`document_annotation`) are compared with the text of the pages and with what the page of the ministry said:
      # a decision whose number, dates or usages do not agree is refused, never guessed.
      class Decision
        Usage = Struct.new(:code, :phrase, :crop_restriction, :milieu, :dose, :dose_unit_name, :applications_count,
                           :applications_phrase, :stage_min, :stage_max, :pre_harvest_days, keyword_init: true)

        AMM_IN_TEXT = /Num[ée]ro d[’'`]\s*AMM\W{0,40}?(\d{7})/i.freeze
        DATES_IN_TEXT = %r{délivrée\s+en\s+France\s+du\s+(\d{1,2}/\d{1,2}/\d{4})\s+au\s+(\d{1,2}/\d{1,2}/\d{4})}im.freeze
        AQUATIC_BUFFER = /zone\s+non\s+trait[ée]e\s+de\s+(\d+)\s*m/i.freeze

        attr_reader :sha, :notice, :errors

        # @param [String] sha fingerprint of the PDF
        # @param [Hash, nil] notice what the page said (nil for a PDF dropped by hand)
        # @param [Hash] ocr the answer kept by `Reader`
        def initialize(sha:, notice:, ocr:)
          @sha = sha
          @notice = notice || {}
          @ocr = ocr || {}
          @fields = @ocr['document_annotation'] || {}
          @errors = []
          check
        end

        def valid?
          errors.empty?
        end

        # @return [Array] what makes two PDF the same decision: a corrected one replaces it, another season does not
        def key
          [amm, started_on]
        end

        def amm
          digits(@fields['amm'])
        end

        def name
          text(@fields['name']) || text(@notice['name'])
        end

        def firm_name
          text(@fields['titulaire'].to_s.split(%r{\n|<br\s*/?>}i).first)
        end

        def started_on
          date(@fields['derogation_start'])
        end

        def stopped_on
          date(@fields['derogation_end'])
        end

        def pdf_url
          @notice['pdf_url']
        end

        # @return [Date, nil] the last day the page listed it
        def last_seen_on
          @notice['last_seen_on'] && Date.parse(@notice['last_seen_on'])
        end

        # @return [Array<String>] « substance teneur unité », the way E-Phy writes active compounds
        def active_compounds
          Array(@fields['substances']).filter_map do |substance|
            next if text(substance['substance']).nil?

            [substance['substance'], substance['value']&.tr(',', '.'), substance['unit']].filter_map { |part| text(part) }.join(' ')
          end
        end

        # @return [Array<Array(String, String)>] code and phrase of each danger statement
        def danger_statements
          Array(@fields['danger_statements']).filter_map do |statement|
            code = text(statement['code'])&.delete(' ')
            code && [code, text(statement['phrase']) || code]
          end.uniq(&:first)
        end

        # @return [Array<String>]
        def conditions
          Array(@fields['conditions']).filter_map { |condition| text(condition) }
        end

        # @return [Integer, nil] metres of untreated buffer zone next to water, from « SPe 3 »
        def untreated_buffer_aquatic
          conditions.join(' ')[AQUATIC_BUFFER, 1]&.to_i
        end

        # @return [Array<Usage>]
        def usages
          @usages ||= Array(@fields['usages']).map { |usage| read_usage(usage) }
        end

        # @return [Boolean] whether the decision is in force on a day
        def in_force_on?(day)
          started_on <= day && day <= stopped_on
        end

        private

          def check
            if @fields.empty?
              errors << 'no fields read by Mistral OCR'
              return
            end

            check_number
            check_dates
            check_usages
            errors << "#{pages.size} pages, Mistral reads #{MAX_PAGES} at most" if pages.size > MAX_PAGES
          end

          def check_number
            return errors << "AMM number '#{@fields['amm']}' is not 7 digits" unless amm&.size == 7

            errors << "AMM #{amm} read, #{@notice['amm']} on the page" if @notice['amm'] && @notice['amm'] != amm
            in_text = page_text[AMM_IN_TEXT, 1]
            errors << "AMM #{amm} read, #{in_text || 'none'} in the text" if in_text != amm
          end

          def check_dates
            return errors << 'dates of the derogation not read' if started_on.nil? || stopped_on.nil?

            errors << "derogation ends (#{stopped_on}) before it starts (#{started_on})" if stopped_on < started_on
            errors << "derogation of #{(stopped_on - started_on).to_i} days" if stopped_on - started_on > MAX_DAYS

            from, to = page_text.match(DATES_IN_TEXT)&.captures&.map { |value| date(value) }
            if from.nil?
              errors << 'dates « délivrée en France du … au … » not found in the text'
            elsif [from, to] != [started_on, stopped_on]
              errors << "dates #{started_on}..#{stopped_on} read, #{from}..#{to} in the text"
            end
          end

          def check_usages
            return errors << 'no usage' if usages.empty?

            usages.each_with_index do |usage, index|
              where = "usage #{index + 1}"
              errors << "#{where}: code '#{usage.code}' is not a number" unless usage.code&.match?(/\A\d+\z/)
              errors << "#{where}: phrase '#{usage.phrase}' is not « crop*…* »" unless usage.phrase&.include?('*')
              errors << "#{where}: dose #{usage.dose}" if usage.dose && !usage.dose.positive?
              [usage.stage_min, usage.stage_max].compact.each do |stage|
                errors << "#{where}: BBCH stage #{stage}" unless (0..99).cover?(stage)
              end
              if usage.stage_min && usage.stage_max && usage.stage_min > usage.stage_max
                errors << "#{where}: BBCH stages #{usage.stage_min} > #{usage.stage_max}"
              end
            end
          end

          def read_usage(usage)
            applications = text(usage['max_application_phrase'])
            Usage.new(
              code: digits(usage['code_usage']),
              # The OCR breaks « loc.* Champignons »: the catalogue phrase has no space around the asterisks
              phrase: text(usage['libelle'])&.gsub(/\s*\*\s*/, '*'),
              crop_restriction: text(usage['crop_restriction']),
              milieu: milieu(usage['milieu'], usage['crop_restriction']),
              dose: usage['dose_max'] && BigDecimal(usage['dose_max'].to_s),
              dose_unit_name: text(usage['unite_dose_max']),
              applications_count: applications&.[](/\d+/)&.to_i,
              applications_phrase: applications,
              stage_min: integer(usage['bbch_min']),
              stage_max: integer(usage['bbch_max']),
              pre_harvest_days: integer(usage['dar_jour'])
            )
          end

          # @return [String] plein_champ, sous_abri or na
          def milieu(*values)
            value = values.compact.join(' ').downcase
            if value.include?('abri') || value.include?('serre')
              'sous_abri'
            elsif value.include?('plein') || value.include?('champ')
              'plein_champ'
            else
              'na'
            end
          end

          def pages
            Array(@ocr['pages'])
          end

          def page_text
            @page_text ||= pages.map { |page| page['markdown'].to_s }.join("\n").gsub(/[*_|]/, ' ')
          end

          def text(value)
            value = value.to_s.gsub(/[[:space:]]+/, ' ').strip
            value.empty? ? nil : value
          end

          def digits(value)
            text(value)&.delete('^0-9')&.then { |found| found.empty? ? nil : found }
          end

          def integer(value)
            value.nil? ? nil : Integer(value.to_s, exception: false)
          end

          def date(value)
            value = text(value)
            return nil if value.nil?

            if (match = value.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z}))
              Date.new(match[3].to_i, match[2].to_i, match[1].to_i)
            else
              Date.iso8601(value)
            end
          rescue Date::Error
            nil
          end
      end
    end
  end
end
