# frozen_string_literal: true

require 'test_helper'

module Datasources
  class PhytosanitaryDerogationsTest < Minitest::Test
    Derogations = Phytosanitary::Derogations
    FIXTURES = Pathname.new(__dir__).join('../../fixtures/phytosanitary_derogations')
    UNITS = { 'liter_per_hectare' => { 'L/ha' => 1, 'mL/ha' => 0.001 } }.freeze

    # Page

    def test_cards_of_the_page_are_read_without_the_guidelines
      notices = Derogations::Page.parse(FIXTURES.join('page.html').read)

      assert_equal %w[2160752 2010023], notices.map(&:amm)
      onyx = notices.first
      assert_equal 'ONYX', onyx.name
      assert_equal 'Canne à sucre', onyx.crops
      assert_equal 'Adventices dicotylédones', onyx.pest
      assert_equal 'Pyridate', onyx.substance
      assert_equal Date.new(2026, 11, 7), onyx.issued_on
      assert_equal Date.new(2027, 3, 7), onyx.expires_on
      assert_equal 'https://agriculture.gouv.fr/telecharger/156840', onyx.pdf_url
      assert_equal 'Tomate plein champ', notices.last.crops
      assert_match(/\ACécidomyies: Contarinia/, notices.last.pest)
    end

    def test_a_page_with_no_card_gives_no_notice
      assert_empty Derogations::Page.parse('<html><a href="/telecharger/1">Lignes directrices</a></html>')
    end

    def test_notice_goes_through_json
      notice = Derogations::Page.parse(FIXTURES.join('page.html').read).first

      assert_equal notice, Derogations::Page::Notice.from_h(JSON.parse(JSON.generate(notice.to_h)))
    end

    # Archive

    def test_archive_keeps_a_pdf_once_and_remembers_when_it_was_seen
      Dir.mktmpdir do |dir|
        archive = Derogations::Archive.new(Pathname.new(dir).join('derogations'))
        notice = Derogations::Page::Notice.new(amm: '2160752', name: 'ONYX', pdf_url: 'https://example.org/telecharger/1')
        first = Pathname.new(dir).join('a.pdf').tap { |file| file.write('%PDF decision') }
        second = Pathname.new(dir).join('b.pdf').tap { |file| file.write('%PDF decision') }

        sha = archive.store(first)
        assert_equal sha, archive.store(second)
        archive.see(sha, notice, Date.new(2026, 11, 2))
        archive.see(sha, notice, Date.new(2026, 11, 9))
        archive.keep_ocr(sha, { 'pages' => [] })

        entry = only(archive.entries)
        assert_equal 24, entry.sha.size
        assert_equal '2026-11-02', entry.notice['first_seen_on']
        assert_equal '2026-11-09', entry.notice['last_seen_on']
        assert_equal({ 'pages' => [] }, entry.ocr)
        assert_equal Set['https://example.org/telecharger/1'], archive.known_urls
        refute second.exist?
      end
    end

    # Decision

    def test_santhal_gold_is_read_as_the_decision_says
      decision = santhal

      assert decision.valid?, decision.errors.join(' ; ')
      assert_equal '2230002', decision.amm
      assert_equal 'SANTHAL GOLD', decision.name
      assert_equal 'SYNGENTA France S.A.', decision.firm_name
      assert_equal [Date.new(2026, 7, 2), Date.new(2026, 10, 30)], [decision.started_on, decision.stopped_on]
      assert_equal ['Métalaxyl-M 465.2 g/L'], decision.active_compounds
      assert_equal %w[H302 H319], decision.danger_statements.map(&:first)
      assert_equal 5, decision.untreated_buffer_aquatic

      usages = decision.usages
      assert_equal 4, usages.size
      assert_equal 'Fraisier*Trt Irrigation loc.*Champignons (pythiacées)', usages.first.phrase
      assert_equal %w[plein_champ plein_champ sous_abri sous_abri], usages.map(&:milieu)
      assert_equal [BigDecimal('0.47'), BigDecimal('1')], usages.map(&:dose).uniq
      assert_equal [1, 11, 13, nil], [usages.first.applications_count, usages.first.stage_min, usages.first.stage_max,
                                      usages.first.pre_harvest_days]
    end

    def test_a_number_the_text_does_not_carry_is_refused
      assert_refused(/AMM 2230003 read, 2230002 in the text/) { |fields| fields['amm'] = '2230003' }
    end

    def test_a_number_other_than_the_one_of_the_page_is_refused
      decision = santhal(notice: { 'amm' => '2010023' })

      assert_includes decision.errors, 'AMM 2230002 read, 2010023 on the page'
    end

    def test_dates_the_text_does_not_carry_are_refused
      assert_refused(/dates 2026-07-02\.\.2026-10-31 read, 2026-07-02\.\.2026-10-30 in the text/) do |fields|
        fields['derogation_end'] = '2026-10-31'
      end
    end

    def test_a_derogation_longer_than_120_days_is_refused
      assert_refused(/derogation of 182 days/) { |fields| fields['derogation_end'] = '2026-12-31' }
    end

    def test_a_usage_with_no_code_or_out_of_bounds_stages_is_refused
      assert_refused(/usage 1: code '' is not a number/) { |fields| fields['usages'][0]['code_usage'] = nil }
      assert_refused(/usage 2: BBCH stage 130/) { |fields| fields['usages'][1]['bbch_max'] = 130 }
      assert_refused(/no usage/) { |fields| fields['usages'] = [] }
    end

    def test_nothing_read_is_refused
      decision = Derogations::Decision.new(sha: 'x', notice: nil, ocr: { 'pages' => [] })

      assert_equal ['no fields read by Mistral OCR'], decision.errors
    end

    # Rows

    def test_rows_of_santhal_gold
      rows = Derogations::Rows.new([santhal], today: Date.new(2026, 11, 7), units: UNITS)

      product = only(rows.products)
      assert_equal ['2230002', '2230002_santhal_gold', 'SANTHAL GOLD', 'Métalaxyl-M 465.2 g/L', 'SYNGENTA France S.A.', '1',
                    24, 'withdrawn', Date.new(2026, 7, 2), Date.new(2026, 10, 30)], product

      usages = rows.usages.map { |row| Derogations::Rows::USAGE_HEADERS.zip(row).to_h }
      ids = usages.map { |usage| usage['id'] }
      assert_equal %w[DEROG:2230002:16552204:plein_champ:20260702 DEROG:2230002:16551201:plein_champ:20260702
                      DEROG:2230002:16552204:sous_abri:20260702 DEROG:2230002:16551201:sous_abri:20260702],
                   ids
      first = usages.first
      assert_equal ['Fraisier', 'Champignons pythiacées', 'Trt Irrigation loc.'],
                   first.values_at('crop_label_fra', 'target_name_label_fra', 'treatment')
      assert_equal ['0.47', 'liter_per_hectare', 'L/ha', 1],
                   first.values_at('dose_quantity', 'dose_unit', 'dose_unit_name', 'dose_unit_factor')
      assert_equal [3, 1, 11, 13, 5], first.values_at('pre_harvest_days', 'applications_count', 'development_stage_min',
                                                      'development_stage_max', 'untreated_buffer_aquatic')
      assert_equal 'withdrawn', first['state']
      assert first['usage_conditions'].start_with?('Autorisé uniquement sur : Pépinière de Fraisier (plein champ). ' \
                                                   'Applications : 1 application tous les deux ans tous usages confondus. ' \
                                                   'Dérogation (article 53) du 02/07/2026 au 30/10/2026. SP 1 :')
      assert_equal [%w[2230002 H302 Nocif\ en\ cas\ d'ingestion], %w[2230002 H319 Provoque\ une\ sévère\ irritation\ des\ yeux]],
                   rows.risks
    end

    def test_a_derogation_in_force_is_authorized
      rows = Derogations::Rows.new([santhal], today: Date.new(2026, 8, 1), units: UNITS)

      assert_equal 'authorized', only(rows.products)[7]
      assert_equal ['authorized'], rows.usages.map { |row| row[18] }.uniq
    end

    def test_a_corrected_pdf_replaces_the_decision_and_another_season_does_not
      first = santhal(sha: 'a', notice: { 'last_seen_on' => '2026-07-10' })
      corrected = santhal(sha: 'b', notice: { 'last_seen_on' => '2026-07-20' }) { |fields| fields['name'] = 'SANTHAL GOLD bis' }
      next_season = santhal(sha: 'c', text: ['02/07/2026', '01/07/2027', '30/10/2026', '29/10/2027']) do |fields|
        fields['derogation_start'] = '2027-07-01'
        fields['derogation_end'] = '2027-10-29'
      end
      assert next_season.valid?, next_season.errors.join(' ; ')

      rows = Derogations::Rows.new([first, corrected, next_season], today: Date.new(2026, 11, 7), units: UNITS)

      assert_equal %w[b c], rows.decisions.map(&:sha)
      assert_equal 8, rows.usages.size
      assert_equal [Date.new(2026, 7, 2), Date.new(2027, 10, 29)], only(rows.products).last(2)
      assert_equal 'SANTHAL GOLD', only(rows.products)[2], 'the fields of the latest season'
    end

    def test_refused_decisions_are_listed
      refused = santhal(sha: 'z') { |fields| fields['usages'] = [] }

      rows = Derogations::Rows.new([santhal, refused], today: Date.new(2026, 11, 7), units: UNITS)

      assert_equal 1, rows.decisions.size
      assert_equal [['z', '2230002', 'SANTHAL GOLD', nil, 'no usage']], rows.refused_rows
    end

    def test_phrases_are_cut_as_in_the_python_of_ephy
      assert_equal ['Blé', 'Trt Part.Aer.', 'Pucerons'], Derogations::Rows.parse_phrase('Blé*Trt Part.Aer.*Pucerons')
      assert_equal ['Vigne', nil, 'Désherbage*Plantation'], Derogations::Rows.parse_phrase('Vigne*Désherbage*Plantation')
      assert_equal 'Maïs', Derogations::Rows.clean_crop('MAIS')
      assert_equal 'PPAM non alimentaires', Derogations::Rows.clean_crop('PPAM non alimentaires ')
      assert_equal 'Rhizoctone', Derogations::Rows.clean_target(' RHIZOCTONIA')
    end

    # Reader

    def test_request_sends_the_pdf_in_base64_with_the_schema
      body = Derogations::Reader.new(api_key: 'key').body('%PDF')

      assert_equal 'mistral-ocr-latest', body[:model]
      assert_equal 'data:application/pdf;base64,JVBERg==', body[:document][:document_url]
      assert_equal Derogations::SCHEMA, body[:document_annotation_format][:json_schema][:schema]
      assert body[:document_annotation_format][:json_schema][:strict]
    end

    def test_answer_keeps_fields_and_text_of_the_pages
      answer = Derogations::Reader.answer('model' => 'mistral-ocr-2512', 'document_annotation' => "```json\n{\"amm\": \"2230002\"}\n```",
                                          'pages' => [{ 'index' => 0, 'markdown' => 'texte', 'images' => [] }])

      assert_equal({ 'amm' => '2230002' }, answer['document_annotation'])
      assert_equal [{ 'index' => 0, 'markdown' => 'texte' }], answer['pages']
    end

    def test_answer_with_no_fields_is_a_failure
      assert_raises(Derogations::Reader::Failed) do
        Derogations::Reader.answer('document_annotation' => 'not json', 'pages' => [{ 'markdown' => 'x' }])
      end
    end

    private

      def only(list)
        assert_equal 1, list.size
        list.first
      end

      # The reading of SANTHAL GOLD, its fields changed by the block, its text by `text` (pairs replaced in turn)
      def santhal(sha: 'santhal', notice: {}, text: [])
        ocr = JSON.parse(FIXTURES.join('santhal_gold.ocr.json').read)
        yield ocr['document_annotation'] if block_given?
        text.each_slice(2) do |from, to|
          ocr['pages'].each { |page| page['markdown'] = page['markdown'].gsub(from, to) }
        end
        Derogations::Decision.new(sha: sha, notice: { 'amm' => '2230002', 'name' => 'SANTHAL GOLD' }.merge(notice), ocr: ocr)
      end

      def assert_refused(pattern, &change)
        decision = santhal(&change)

        refute decision.valid?
        assert decision.errors.any? { |error| pattern.match?(error) }, "#{pattern.inspect} not in #{decision.errors.inspect}"
      end
  end
end
