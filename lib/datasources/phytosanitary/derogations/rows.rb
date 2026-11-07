# frozen_string_literal: true

module Datasources
  class Phytosanitary
    module Derogations
      # The decisions kept, as the rows of the raw tables `normalize` reads. Usages get the columns of E-Phy; the
      # crop, the target and the treatment are drawn from the phrase the way `__init__.py` draws them, and replaced
      # in `normalize` by those of an E-Phy usage of the same code when there is one.
      class Rows
        PRODUCT_HEADERS = %w[id reference_name name active_compounds firm_name mix_category_codes in_field_reentry_hours
                             state started_on stopped_on].freeze
        USAGE_HEADERS = %w[id lib_court product_id ephy_usage_phrase crop_label_fra target_name_label_fra treatment
                           dose_quantity dose_unit dose_unit_name dose_unit_factor pre_harvest_days applications_count
                           development_stage_min development_stage_max usage_conditions untreated_buffer_aquatic
                           decision_date state started_on stopped_on url].freeze
        RISK_HEADERS = %w[product_id risk_code risk_phrase].freeze
        REFUSED_HEADERS = %w[sha amm name pdf_url reasons].freeze

        # A usage with no pre-harvest delay gets 3 days, as in `__init__.py`
        DEFAULT_PRE_HARVEST_DAYS = 3
        # Mix category of each danger statement, and re-entry delays, as in `__init__.py`
        MIX_CATEGORIES = {
          'H341' => 2, 'H351' => 2, 'H371' => 2, 'H361d' => 3, 'H361f' => 3, 'H361fd' => 3, 'H362' => 3, 'H373' => 4,
          'H300' => 5, 'H301' => 5, 'H310' => 5, 'H311' => 5, 'H330' => 5, 'H331' => 5, 'H340' => 5, 'H350' => 5,
          'H350i' => 5, 'H360F' => 5, 'H360D' => 5, 'H360FD' => 5, 'H360Fd' => 5, 'H360Df' => 5, 'H370' => 5, 'H372' => 5
        }.freeze
        REENTRY_48 = %w[H317 H334].freeze
        REENTRY_24 = %w[H315 H318 H319].freeze
        TRANSCODING_WORDS = ['Désherbage', 'Dévitalisation', 'Trt Sol*Avt Plantation'].freeze

        attr_reader :decisions, :refused

        # @param [Array<Decision>] decisions every decision read
        # @param [Date] today the day the state of a derogation is told for
        # @param [Hash] units `units.yml`: unit => { label => factor }
        def initialize(decisions, today:, units:)
          @today = today
          @units = units
          @refused = decisions.reject(&:valid?)
          @decisions = self.class.kept(decisions.select(&:valid?))
        end

        # Two PDF of the same decision (a corrected one): the one the page listed last wins, then the latest read
        # @return [Array<Decision>]
        def self.kept(decisions)
          decisions.group_by(&:key).values.map do |same|
            same.max_by { |decision| [decision.last_seen_on || Date.new(0), decision.sha] }
          end.sort_by { |decision| [decision.amm, decision.started_on] }
        end

        # One row per number: the fields of its latest decision, the dates of all of them
        def products
          decisions.group_by(&:amm).map do |amm, all|
            latest = all.max_by(&:started_on)
            codes = latest.danger_statements.map(&:first)
            [amm, reference_name(amm, latest.name), latest.name, latest.active_compounds.join(' | '), latest.firm_name,
             mix_categories(codes).join(','), reentry_hours(codes),
             all.any? { |decision| decision.in_force_on?(@today) } ? 'authorized' : 'withdrawn',
             all.map(&:started_on).min, all.map(&:stopped_on).max]
          end
        end

        def usages
          decisions.flat_map do |decision|
            ids = Hash.new(0)
            decision.usages.map do |usage|
              id = "DEROG:#{decision.amm}:#{usage.code}:#{usage.milieu}:#{decision.started_on.strftime('%Y%m%d')}"
              ids[id] += 1
              id = "#{id}:#{ids[id]}" if ids[id] > 1
              usage_row(id, decision, usage)
            end
          end
        end

        def risks
          decisions.group_by(&:amm).flat_map do |amm, all|
            all.max_by(&:started_on).danger_statements.map { |code, phrase| [amm, code, phrase] }
          end
        end

        def refused_rows
          refused.map do |decision|
            [decision.sha, decision.amm || decision.notice['amm'], decision.name, decision.pdf_url, decision.errors.join(' ; ')]
          end
        end

        # @return [Array(String, String, String)] crop, treatment and function of a phrase « crop*treatment*function »
        def self.parse_phrase(phrase)
          words = TRANSCODING_WORDS.any? { |word| phrase.include?(word) } ? phrase.split('*', 2) : phrase.split('*')
          words.size > 2 ? [words[0], words[1], words[2]] : [words[0], nil, words[1]]
        end

        def self.clean_crop(crop)
          crop = crop.capitalize unless crop.include?('PPAM') || crop.include?('Porte graine')
          crop.gsub('graminees', 'graminées').gsub('écossées', 'écossés').gsub(' - abricotier', '')
              .gsub('Chataignier', 'Châtaignier').gsub('Mais', 'Maïs').rstrip
        end

        def self.clean_target(target)
          target = target.to_s.sub(/\A /, '')
          return nil if target.empty?

          target = 'Rhizoctone' if %w[RHIZOCTONIA Rhizoctoniose].include?(target)
          target = 'Sclérotiniose' if target == 'SCLEROTINIA'
          target = target == target.upcase ? target.capitalize.gsub('couronnee', 'couronnée') : target[0].upcase + target[1..]
          target = target.delete(')').gsub(' ( ', ' ').delete('(').gsub(' 1', '').tr('-', ' ')
          %w[floraison ramification hybridation naturelles].each { |word| target = target.gsub(word, word.capitalize) }
          %w[Ensilage Grains].each { |word| target = target.gsub(word, word.downcase) }
          target = target.gsub('ion sur la', '.')
          target = target[0..-2] if [' ', '.'].include?(target[-1])
          target.gsub(/\.(?=[^ ])/, '. ')
        end

        private

          def usage_row(id, decision, usage)
            crop, treatment, function = self.class.parse_phrase(usage.phrase)
            unit, factor = unit(usage.dose_unit_name)
            [id, usage.code, decision.amm, usage.phrase, self.class.clean_crop(crop), self.class.clean_target(function),
             treatment, usage.dose&.to_s('F'), unit, usage.dose_unit_name, factor,
             usage.pre_harvest_days || DEFAULT_PRE_HARVEST_DAYS, usage.applications_count, usage.stage_min,
             usage.stage_max, conditions(decision, usage), decision.untreated_buffer_aquatic, decision.started_on,
             decision.in_force_on?(@today) ? 'authorized' : 'withdrawn', decision.started_on, decision.stopped_on,
             decision.pdf_url]
          end

          # The restriction to a crop and its setting, the number of applications as written, then the conditions
          def conditions(decision, usage)
            restriction = usage.crop_restriction
            setting = { 'plein_champ' => 'plein champ', 'sous_abri' => 'sous abri' }[usage.milieu]
            parts = []
            parts << "Autorisé uniquement sur : #{[restriction, setting && "(#{setting})"].compact.join(' ')}." if restriction || setting
            parts << "Applications : #{usage.applications_phrase}." if usage.applications_phrase
            parts << "Dérogation (article 53) du #{decision.started_on.strftime('%d/%m/%Y')} au #{decision.stopped_on.strftime('%d/%m/%Y')}."
            (parts + decision.conditions).join(' ')
          end

          def unit(label)
            return [nil, nil] if label.nil?

            @units.each do |unit, labels|
              labels&.each { |known, factor| return [unit, factor] if known == label }
            end
            [nil, nil]
          end

          # As `__init__.py`: the AMM, '_', the name with every other character replaced, a last one dropped
          def reference_name(amm, name)
            "#{amm}_#{name.downcase.gsub(/[^a-zA-Z0-9]/, '_')}".sub(/[^a-zA-Z0-9]\z/, '')
          end

          def mix_categories(codes)
            ([1] + codes.filter_map { |code| MIX_CATEGORIES[code] }).uniq.sort
          end

          def reentry_hours(codes)
            if codes.intersect?(REENTRY_48)
              48
            elsif codes.intersect?(REENTRY_24)
              24
            else
              6
            end
          end
      end
    end
  end
end
