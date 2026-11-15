# frozen_string_literal: true

require 'test_helper'
require 'tempfile'

module Datasources
  class BsvTest < Minitest::Test
    FIXTURES = Pathname.new(__dir__).join('../../fixtures/bsv')
    SITE = 'https://draaf.example.gouv.fr/'

    # A site made of the fixture pages, read without the network
    class FakeHttp
      attr_reader :asked

      def initialize(pages, forbidden: [])
        @pages = pages
        @forbidden = forbidden
        @asked = []
      end

      def get(url)
        @asked << url
        file = @pages[url] or raise Bsv::Http::Failed.new("#{url} answered 404")
        [FIXTURES.join(file).read, url]
      end

      def allowed?(url)
        @forbidden.none? { |path| url.include?(path) }
      end
    end

    def region(**overrides)
      Bsv::Sources::Region.new(slug: 'grand-est', site: SITE, roots: ['bsv-r1.html'], pages: [], section_is_sector: false,
                               since: 2025, exclude: [], **overrides)
    end

    def site_pages
      {
        "#{SITE}bsv-r1.html" => 'root.html',
        "#{SITE}bsv-2026-r20.html" => 'rubric_2026.html',
        "#{SITE}bsv-2026-r20.html?debut_listearticles=8" => 'rubric_2026_page2.html',
        "#{SITE}bsv-2025-r21.html" => 'rubric_2025.html',
        "#{SITE}grandes-cultures-r23.html" => 'rubric_gc.html',
        "#{SITE}grandes-cultures-a100.html" => 'article_gc.html',
        "#{SITE}vigne-a101.html" => 'article_vigne.html',
        "#{SITE}arboriculture-a102.html" => 'article_arbo.html',
        "#{SITE}mais-a1987.html" => 'article_mais.html'
      }
    end

    # Crawler

    def test_the_walk_follows_rubrics_redirections_and_pages_and_keeps_the_pdf_of_the_site
      http = FakeHttp.new(site_pages)
      links = Bsv::Crawler.new(region, http: http).links

      assert_equal %W[
        #{SITE}IMG/pdf/bsv_bilan_2025.pdf
        #{SITE}IMG/pdf/bsv_vigne_12.pdf
        #{SITE}IMG/pdf/bsv_gc_no31_du_05-11-26.pdf
        #{SITE}IMG/pdf/bsv_gc_no30_du_29-10-26.pdf
        #{SITE}IMG/pdf/bsv_arbo_8.pdf
        #{SITE}IMG/pdf/bsv_mais_03_du_03-11-26.pdf
      ].sort, links.map(&:pdf_url).sort
      gc = links.find { |link| link.pdf_url.end_with?('no31_du_05-11-26.pdf') }
      assert_equal 'BSV Grandes Cultures n°31 du 5 novembre 2026 (pdf - 972 kio)', gc.label
      assert_equal 'Grandes cultures', gc.page_title
      assert_equal "#{SITE}grandes-cultures-a100.html", gc.page_url
    end

    def test_the_walk_stays_in_the_tree_and_skips_the_years_before_since
      http = FakeHttp.new(site_pages)
      Bsv::Crawler.new(region, http: http).links

      refute(http.asked.any? { |url| url.match?(/sante-des-vegetaux|foret|voisin|autre-sujet|mentions|autre-article|example\.org/) })
      refute(http.asked.any? { |url| url.include?('2019') })
    end

    def test_the_walk_reads_no_page_robots_txt_forbids
      http = FakeHttp.new(site_pages, forbidden: ['bsv-2026-r20'])
      links = Bsv::Crawler.new(region, http: http).links

      assert_equal ["#{SITE}IMG/pdf/bsv_bilan_2025.pdf"], links.map(&:pdf_url)
    end

    def test_on_a_page_that_lists_pdf_the_section_is_kept
      region = region(roots: [], pages: ['bulletins-a162.html'], section_is_sector: true)
      http = FakeHttp.new({ "#{SITE}bulletins-a162.html" => 'page_sections.html' })
      links = Bsv::Crawler.new(region, http: http).links

      assert_equal({ 'bsv_grandescultures_20260609.pdf' => 'Grandes cultures', 'bsv_20260519_v2.pdf' => 'Viticulture',
                     'bsv_maraichage_no15.pdf' => 'Cultures légumières', 'note_nationale.pdf' => 'Notes' },
                   links.to_h { |link| [link.pdf_url.split('/').last, link.section] })
      assert_equal 'BSV du 4 février', links.find { |link| link.pdf_url.end_with?('no15.pdf') }.label
    end

    # Robots

    def test_robots_txt_of_the_draaf_allows_the_pdf
      robots = Bsv::Robots.parse(<<~TXT)
        User-agent: *
        Disallow: /ecrire/
        Disallow: /spip.php?action=*
        Crawl-delay: 1
      TXT

      assert robots.allowed?('/IMG/pdf/bsv_gc.pdf')
      refute robots.allowed?('/ecrire/?exec=accueil')
      refute robots.allowed?('/spip.php?action=logout')
      assert robots.allowed?('/spip.php?page=sitemap.xml')
      assert_equal 1.0, robots.crawl_delay
    end

    def test_robots_txt_longest_rule_wins_and_other_robots_are_ignored
      robots = Bsv::Robots.parse(<<~TXT)
        User-agent: Googlebot
        Disallow: /

        User-agent: *
        Disallow: /fileadmin/
        Allow: /fileadmin/user_upload/251_chambre/
        Disallow: /*.pdf$
      TXT

      assert robots.allowed?('/fileadmin/user_upload/251_chambre/bsv.html')
      refute robots.allowed?('/fileadmin/user_upload/other/bsv.html')
      refute robots.allowed?('/IMG/bsv.pdf')
      assert robots.allowed?('/IMG/bsv.pdf?x=1')
      assert_nil robots.crawl_delay
    end

    # Archive

    def test_a_pdf_listed_twice_keeps_its_first_label_and_both_regions
      Dir.mktmpdir do |tmp|
        archive = Bsv::Archive.new(tmp)
        file = Pathname.new(tmp).join('incoming.pdf')
        file.write('%PDF-1.4 bulletin')
        sha = archive.store(file)
        first = Bsv::Crawler::Link.new(pdf_url: 'https://a/IMG/pdf/x.pdf', label: 'BSV n°1', page_url: 'https://a/p-a1.html')
        other = Bsv::Crawler::Link.new(pdf_url: 'https://b/IMG/pdf/x.pdf', label: 'Autre', page_url: 'https://b/p-a2.html')
        archive.see(sha, first, 'bretagne', Date.new(2026, 5, 1))
        archive.see(sha, other, 'pays-de-la-loire', Date.new(2026, 5, 8))

        notice = archive.entries.first.notice
        assert_equal %w[bretagne pays-de-la-loire], notice['regions']
        assert_equal 'BSV n°1', notice['label']
        assert_equal '2026-05-01', notice['first_seen_on']
        assert_equal '2026-05-08', notice['last_seen_on']
        assert_equal({ 'https://a/IMG/pdf/x.pdf' => sha, 'https://b/IMG/pdf/x.pdf' => sha }, archive.known_urls)
        refute file.exist?
      end
    end

    def test_a_pdf_stored_again_is_kept_once
      Dir.mktmpdir do |tmp|
        archive = Bsv::Archive.new(tmp)
        2.times do
          file = Pathname.new(tmp).join('incoming.pdf')
          file.write('%PDF-1.4 same')
          archive.store(file)
        end

        assert_equal 1, Pathname.new(tmp).glob('*.pdf').size
      end
    end

    # Pages

    def test_pages_are_split_on_form_feeds
      pages = Bsv::Pages.split("Page un\n\fPage deux\u0000\n\f\n")

      assert_equal ['Page un', 'Page deux'], pages
      refute Bsv::Pages.scanned?(pages + ['Une troisième page assez longue'])
      assert Bsv::Pages.scanned?(['', ' ', "\n"])
    end

    def test_the_year_of_a_bulletin_is_read_on_its_first_page
      assert_equal 2026, Bsv::Pages.year(['BSV n°31 du 5 novembre 2026 – campagne 2025', 'Bilan 2019'])
      assert_equal 2025, Bsv::Pages.year(['Bulletin du 12/03/25'])
      assert_nil Bsv::Pages.year(['Bulletin n°3', 'du 5 mai 2026'])
    end

    # Data files

    def test_every_region_of_the_sources_has_its_departments
      zones = Bsv::Zones.new
      regions = Bsv::Sources.load

      assert_equal 13, regions.size
      regions.each do |region|
        assert region.site.end_with?('/'), region.slug
        refute_empty region.start_urls, region.slug
        refute_empty zones.departments(region.slug).to_a, region.slug
      end
    end

    def test_every_edition_names_a_known_zone
      zones = Bsv::Zones.new
      CSV.foreach(Pathname.new('data/bsv/editions.csv'), headers: true) do |edition|
        names = edition['zone'].to_s.split('|', -1)
        (names.empty? ? [''] : names).each do |zone|
          known = zone.empty? ? zones.departments(edition['region']) : zones.find(edition['region'], zone)
          refute_nil known, "#{edition['region']} #{zone}"
        end
      end
    end

    def test_a_very_high_level_said_very_low_by_its_text_is_low
      assert_equal 'faible', Bsv::Levels.checked('tres_fort', 'peu ou pas de symptômes sur plante, risque très faible')
      assert_equal 'faible', Bsv::Levels.checked('tres_fort', 'Le risque est très faible voire nul.')
      # The text names a high level too, or the model gave another level: the model is kept
      assert_equal 'tres_fort', Bsv::Levels.checked('tres_fort', 'Risque théorique fort à très fort. Très faibles contaminations possibles.')
      assert_equal 'tres_fort', Bsv::Levels.checked('tres_fort', 'Le risque maximal est dépassé dans toute la région.')
      assert_equal 'fort', Bsv::Levels.checked('fort', 'Risque peu important')
      assert_equal 'tres_fort', Bsv::Levels.checked('tres_fort', nil)
    end

    def test_a_range_takes_its_higher_level
      assert_equal 'moyen', Bsv::Levels.checked('faible', 'Risque faible à moyen selon les situations actuellement.')
      assert_equal 'fort', Bsv::Levels.checked('moyen', 'Le risque est moyen à fort selon les parcelles.')
      assert_equal 'fort', Bsv::Levels.checked('moyen', 'moyens à forts dans le Roussillon, moyens à faibles en Languedoc')
      assert_equal 'tres_fort', Bsv::Levels.checked('fort', 'Niveau de risque fort à très fort sur le vignoble.')
      # Already as high, or no level given: kept
      assert_equal 'tres_fort', Bsv::Levels.checked('tres_fort', 'risque moyen à fort')
      assert_equal 'non_precise', Bsv::Levels.checked('non_precise', 'risque faible à moyen')
      assert_equal 'faible', Bsv::Levels.checked('faible', "curseur sur l'échelle faible à fort, placé côté faible")
      assert_equal 'faible', Bsv::Levels.checked('faible', 'curseur sur FAIBLE ; la pression reste moyenne à forte')
    end

    def test_a_date_before_the_bsv_or_well_after_the_bulletin_was_seen_is_not_kept
      assert_equal Date.new(2026, 11, 5), Bsv::Rows.plausible(Date.new(2026, 11, 5), '2026-11-06')
      assert_equal Date.new(2026, 12, 1), Bsv::Rows.plausible(Date.new(2026, 12, 1), '2026-11-06'), 'dated a few weeks ahead'
      assert_nil Bsv::Rows.plausible(Date.new(7777, 7, 7), '2026-11-06')
      assert_nil Bsv::Rows.plausible(Date.new(1900, 1, 1), '2026-11-06')
      assert_nil Bsv::Rows.plausible(Date.new(2026, 12, 31), '2026-11-06'), 'a bilan dated the end of the year'
      assert_nil Bsv::Rows.plausible(nil, '2026-11-06')
    end

    def test_editions_take_the_bulletins_under_their_other_names
      editions = Tempfile.new(['editions', '.csv'])
      editions.write(<<~CSV)
        region,sector,zone,subsector,months,pdf_2026,source
        grand-est,viticulture,Champagne-Ardenne|Champagne,,3-9,17,draaf
        occitanie,arboriculture,Languedoc-Roussillon|Arc méditerranéen|,olivier|oléiculture,3-10,14,draaf
        auvergne-rhone-alpes,arboriculture,Rhône-Alpes,,2-9,30,draaf
        normandie,horticulture,,,2-11,15,draaf
        corse,viticulture,,,4-8,4,draaf
      CSV
      editions.close
      bulletin = ->(region, sector, zone, subsector, on) { { 'region' => region, 'regions' => region, 'sector' => sector, 'zone' => zone, 'subsector' => subsector, 'published_on' => on, 'nature' => 'bulletin' } }
      coverage = Bsv::Coverage.new(Bsv::Zones.new, Pathname.new(editions.path), today: Date.new(2026, 11, 9)).build([
        bulletin.call('grand-est', 'viticulture', 'Champagne', nil, '2026-09-01'),
        bulletin.call('occitanie', 'arboriculture', 'ARC – Méditerranéen', 'Oléiculture', '2026-10-20'),
        bulletin.call('auvergne-rhone-alpes', 'arboriculture', 'Territoire rhônalpin', nil, '2026-09-10'),
        bulletin.call('normandie', 'horticulture', nil, nil, '2026-10-22'),
        bulletin.call('normandie', 'arboriculture', nil, 'fruits à pépins', '2026-06-01')
      ])
      states = coverage.editions.to_h { |edition| [edition.region, coverage.state(edition)] }

      assert_equal({ 'grand-est' => 'ok', 'occitanie' => 'ok', 'auvergne-rhone-alpes' => 'ok', 'normandie' => 'late', 'corse' => 'missing' }, states)
      assert_equal({ ['normandie', 'arboriculture', '', 'fruits à pépins'] => 1 }, coverage.unmatched)
    ensure
      editions&.unlink
    end

    def test_the_crawler_goes_back_one_year_unless_asked_for_the_archives
      year = Date.today.year
      current = Bsv::Sources.load.find { |region| region.slug == 'grand-est' }
      archives = Bsv::Sources.load(since: 'archives').find { |region| region.slug == 'grand-est' }

      assert_equal year - 1, current.since
      assert_equal 2015, archives.since
      assert_equal 2020, Bsv::Sources.load(since: '2020').first.since
      assert_raises(ArgumentError) { Bsv::Sources.load(since: 'toujours') }
    end

    def test_departments_of_a_zone
      zones = Bsv::Zones.new

      assert_equal %w[24 33 40 47 64], zones.departments('nouvelle-aquitaine', 'Aquitaine')
      assert_nil zones.departments('nouvelle-aquitaine', 'Atlantide')
      assert_equal %w[24 33 40 47 64], zones.find('nouvelle-aquitaine', 'aquitaine')
      assert_equal 'provence-alpes-cote-d-azur', Bsv::Zones.slug("Provence-Alpes-Côte d'Azur")
      assert_equal %w[16 17 79 86 87], zones.find('nouvelle-aquitaine', 'Edition Nord Nouvelle-Aquitaine')
      assert_equal %w[04 05 13 84], zones.find('provence-alpes-cote-d-azur', 'Secteurs Basse Durance (13 et 84) & Alpin (04 et 05)')
      assert_equal %w[31 82], zones.find('occitanie', 'Fronton – Tarn & Garonne')
      assert_equal zones.departments('occitanie', 'Grand Sud-Ouest'), zones.find('grand-est', 'Grand Sud-Ouest'),
                   'a zone of another region, when all give the same departments'
      assert_nil zones.find('grand-est', 'Arc méditerranéen').to_a.difference(%w[04 05 06 11 13 30 34 66 83 84]).first
    end

    def test_productions_of_a_crop_name
      crops = Bsv::Crops.new

      assert_equal 'tomato', crops.productions('Tomate sous abri hors sol')
      assert_equal 'melon', crops.productions('Melon plein champ')
      assert_equal 'perrenial_ornamental_plant_and_mapp|nursery', crops.productions('Rosiers')
      assert_equal 'pepper|chili', crops.productions('Poivron / piment')
      assert_equal 'winter_common_wheat', crops.productions('Blé tendre d’hiver')
      assert_nil crops.productions('Poivron / mandragore')
      assert_nil crops.productions('')
    end

    def test_every_crop_names_productions
      CSV.foreach(Bsv::Rows::CROPS, headers: true) do |row|
        refute_empty row['crop'].to_s
        assert_match(/\A[a-z_]+(\|[a-z_]+)*\z/, row['production_names'], row['crop'])
      end
    end

    def test_the_schema_has_no_more_unions_than_the_api_compiles
      unions = ->(object) { object[:properties].values.count { |property| property.key?(:anyOf) } }

      assert_operator unions.call(Bsv::Schema::SCHEMA) + unions.call(Bsv::Schema::LINE), :<=, 16
    end

    # Extraction

    PAGES = ['BSV Grandes cultures n°31 du 5 novembre 2026',
             "Colza\nGrosse altise : risque fort dans les parcelles en cours de levée.\nPuceron : pas de risque."].freeze

    def line(**overrides)
      { 'culture' => 'colza', 'bioagresseur' => 'grosse altise', 'type' => 'ravageur', 'bbch_min' => nil,
        'bbch_max' => nil, 'zadoks_min' => nil, 'zadoks_max' => nil, 'niveau' => 'fort', 'conditionnel' => true,
        'condition' => 'parcelles en cours de levée', 'lieux' => [], 'page' => 2,
        'extrait' => 'Grosse altise : risque fort dans les parcelles en cours de levée.' }.merge(overrides.transform_keys(&:to_s))
    end

    def answer(lines, nature: 'bulletin')
      { 'region' => 'Grand Est', 'regions_citees' => [], 'zone' => nil, 'filiere' => 'grandes cultures',
        'sous_filiere' => nil, 'numero' => '31', 'date' => '2026-11-05', 'nature' => nature, 'lignes' => lines }
    end

    def test_a_line_is_kept_only_when_its_quote_is_in_the_text_and_its_codes_hold
      extraction = Bsv::Extraction.new(answer([
        line,
        line(extrait: 'GROSSE ALTISE — risque fort dans les parcelles en cours de levee'),
        line(extrait: 'Risque fort partout.'),
        line(extrait: 'Colza : risque fort dans les parcelles'),
        line(extrait: 'Puceron : risque fort sur toutes les parcelles.'),
        line(bioagresseur: 'Colza'),
        line(bbch_min: 30, bbch_max: 12),
        line(zadoks_min: 120),
        line(niveau: 'catastrophique')
      ]), PAGES)

      assert_equal [0, 1, 3], extraction.lines.map(&:first), 'words in their order, the layout of the page aside'
      assert_equal ['quote not in the text', 'quote not in the text', 'crop is the pest', 'BBCH out of 0-99', 'Zadoks out of 0-99', 'level catastrophique'],
                   extraction.refusals.map(&:reason)
      assert_equal Date.new(2026, 11, 5), extraction.published_on
    end

    def test_a_scanned_bulletin_keeps_its_lines_and_a_bilan_none
      assert_equal 1, Bsv::Extraction.new(answer([line(extrait: 'lu sur une image')]), ['', ' ']).lines.size
      assert_empty Bsv::Extraction.new(answer([line], nature: 'bilan'), PAGES).lines
    end

    # Extractor

    # The batches of the API, answered from memory
    class FakeBatches
      attr_reader :created

      def initialize(states: {}, results: {})
        @states = states
        @results = results
        @created = []
      end

      def create(requests:)
        @created << requests
        { id: "msgbatch_#{@created.size}" }
      end

      def retrieve(id)
        { id: id, processing_status: @states.fetch(id, 'ended') }
      end

      def results_streaming(id)
        @results.fetch(id, [])
      end
    end

    FakeClient = Struct.new(:batches) do
      def messages
        self
      end
    end

    def archive_with(tmp, *names)
      archive = Bsv::Archive.new(Pathname.new(tmp).join('archive'))
      names.each do |name|
        file = Pathname.new(tmp).join('incoming.pdf')
        file.write("%PDF-1.4 #{name}")
        sha = archive.store(file)
        archive.keep_pages(sha, PAGES)
      end
      archive
    end

    def succeeded(custom_id, data, stop_reason: 'end_turn')
      { custom_id: custom_id, result: { type: 'succeeded', message: {
        stop_reason: stop_reason, content: [{ type: 'text', text: JSON.generate(data) }],
        usage: Struct.new(:input_tokens, :output_tokens).new(3000, 900)
      } } }
    end

    def test_a_batch_is_kept_until_it_ends_and_its_answers_beside_each_pdf
      Dir.mktmpdir do |tmp|
        archive = archive_with(tmp, 'a', 'b')
        entries = archive.entries
        batches = FakeBatches.new(states: { 'msgbatch_1' => 'in_progress' })
        extractor = Bsv::Extractor.new(archive, client: FakeClient.new(batches), sleep: ->(_) {})

        extractor.submit(entries.map { |entry| [entry, 'haiku'] } + [[entries.first, 'opus']])
        request = batches.created.first.first
        assert_equal 3, batches.created.first.size
        assert_equal 'claude-haiku-5-5', request[:params][:model]
        assert_equal 'application/pdf', request[:params][:messages].first[:content].first[:source][:media_type]
        assert_equal 'json_schema', request[:params][:output_config][:format][:type]
        assert_equal 'ephemeral', request[:params][:system_].first[:cache_control][:type]

        assert_empty extractor.gather(wait: 120)
        assert_equal 1, archive.batches.size
        assert_empty extractor.wanted(entries, 'haiku'), 'a bulletin waiting in a batch is not sent again'

        first, second = entries.map(&:sha)
        batches = FakeBatches.new(results: { 'msgbatch_1' => [
          succeeded("#{first}-haiku", answer([line])),
          { custom_id: "#{second}-haiku", result: { type: 'errored', error: { type: 'overloaded_error' } } },
          succeeded("#{first}-opus", answer([line]), stop_reason: 'max_tokens')
        ] })
        extractor = Bsv::Extractor.new(archive, client: FakeClient.new(batches), sleep: ->(_) {})
        assert_equal 3, extractor.gather.size
        assert_empty archive.batches

        assert_equal 'colza', archive.answer(first, 'haiku')['answer']['lignes'].first['culture']
        assert_equal Bsv::Schema.version, archive.answer(first, 'haiku')['version']
        assert_equal 'max_tokens', archive.answer(first, 'opus')['stop_reason']
        assert_equal 900, archive.answer(first, 'haiku')['usage']['output_tokens'], 'a model inside the answer is read too'
        assert_equal [second], extractor.wanted(archive.entries, 'haiku').map(&:sha), 'an error is sent again'
      end
    end

    def test_an_error_is_sent_again_twice_at_most
      Dir.mktmpdir do |tmp|
        archive = archive_with(tmp, 'a')
        sha = archive.entries.first.sha
        archive.keep_answer(sha, 'haiku', { 'result' => 'expired', 'attempts' => 3 })

        assert_empty Bsv::Extractor.new(archive, client: nil).wanted(archive.entries, 'haiku')
      end
    end

    def test_a_cut_answer_is_asked_again_with_more_tokens
      Dir.mktmpdir do |tmp|
        archive = archive_with(tmp, 'a')
        entry = archive.entries.first
        archive.keep_answer(entry.sha, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'max_tokens', 'attempts' => 1 })
        batches = FakeBatches.new
        extractor = Bsv::Extractor.new(archive, client: FakeClient.new(batches))

        assert_equal [entry.sha], extractor.wanted(archive.entries, 'haiku').map(&:sha)
        extractor.submit([[entry, 'haiku']])
        assert_equal Bsv::Extractor::MAX_TOKENS_AGAIN, batches.created.first.first[:params][:max_tokens]

        archive.keep_answer(entry.sha, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'end_turn', 'attempts' => 2 })
        archive.drop_batch('msgbatch_1')
        assert_empty extractor.wanted(archive.entries, 'haiku')
      end
    end

    # Correction

    def test_a_correction_raises_changes_or_drops_a_line_but_never_makes_it_non_precise
      extraction = answer([line(niveau: 'non_precise'), line(niveau: 'faible'), line(niveau: 'fort'), line, line])
      corrected, changed, dropped = Bsv::Correction.apply(extraction, [
        { 'ligne' => 1, 'action' => 'niveau', 'niveau' => 'fort', 'conditionnel' => false, 'condition' => nil, 'niveau_texte' => 'risque élevé' },
        { 'ligne' => 2, 'action' => 'niveau', 'niveau' => 'moyen', 'conditionnel' => true, 'condition' => 'variétés sensibles', 'niveau_texte' => 'moyen' },
        { 'ligne' => 3, 'action' => 'niveau', 'niveau' => 'non_precise', 'conditionnel' => false, 'condition' => nil, 'niveau_texte' => nil },
        { 'ligne' => 4, 'action' => 'supprimer', 'niveau' => nil, 'conditionnel' => false, 'condition' => nil, 'niveau_texte' => nil },
        { 'ligne' => 9, 'action' => 'supprimer', 'niveau' => nil, 'conditionnel' => false, 'condition' => nil, 'niveau_texte' => nil }
      ])

      assert_equal %w[fort moyen fort fort fort], corrected['lignes'].map { |one| one['niveau'] }
      assert_equal [false, false, false, true, false], corrected['lignes'].map { |one| one['supprimee'] == true }
      assert_equal [2, 1], [changed, dropped]
      assert_equal 'non_precise', extraction['lignes'].first['niveau'], 'the extraction is left as it is'
    end

    def test_an_extraction_of_former_instructions_is_corrected_once_from_the_text_of_its_pages
      Dir.mktmpdir do |tmp|
        archive = archive_with(tmp, 'old', 'new')
        old, new = archive.entries.map(&:sha)
        archive.keep_answer(old, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'end_turn', 'version' => 'former',
                                            'batch_id' => 'msgbatch_0', 'answer' => answer([line(niveau: 'non_precise')]) })
        archive.keep_answer(new, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'end_turn', 'version' => Bsv::Schema.version,
                                            'batch_id' => 'msgbatch_0', 'answer' => answer([line]).merge('numero' => '32') })
        batches = FakeBatches.new
        extractor = Bsv::Extractor.new(archive, client: FakeClient.new(batches))

        assert_equal [old], extractor.wanted_fixes(archive.entries).map(&:sha)
        extractor.submit([[archive.entries.first, Bsv::Correction::KEY]])
        params = batches.created.first.first[:params]
        assert_equal 'claude-haiku-5-5', params[:model]
        assert_includes params[:messages].first[:content], "1. p2 | colza | grosse altise | ravageur | non_precise"
        assert_includes params[:messages].first[:content], 'Grosse altise : risque fort'
        assert_includes params[:system_].first[:text], 'Une fourchette prend toujours le niveau le plus haut'
        assert_empty extractor.wanted_fixes(archive.entries), 'a bulletin waiting in a batch is not sent again'

        batches = FakeBatches.new(results: { 'msgbatch_1' => [succeeded("#{old}-fix", { 'corrections' => [
          { 'ligne' => 1, 'action' => 'niveau', 'niveau' => 'fort', 'conditionnel' => true, 'condition' => 'levée', 'niveau_texte' => 'risque fort' }
        ] })] })
        Bsv::Extractor.new(archive, client: FakeClient.new(batches)).gather
        fix = archive.answer(old, 'fix')
        assert_equal ['msgbatch_0', Bsv::Correction.version], fix.values_at('of', 'version')
        assert_empty extractor.wanted_fixes(archive.entries)

        rows = Bsv::Rows.new(archive, Bsv::Zones.new).build
        assert_equal 'fort', rows.risks.find { |risk| risk[1] == old }[Bsv::Rows::RISKS.index('level')]
        assert_equal 1, rows.levels_corrected

        archive.keep_answer(old, 'haiku', archive.answer(old, 'haiku').merge('batch_id' => 'msgbatch_9'))
        assert_equal [old], extractor.wanted_fixes(archive.entries).map(&:sha), 'a new extraction is corrected again'
        rows = Bsv::Rows.new(archive, Bsv::Zones.new).build
        assert_equal 0, rows.levels_corrected, 'a correction of another extraction is not applied'
      end
    end

    # Control

    def test_haiku_is_measured_against_opus
      haiku = answer([line, line(bioagresseur: 'puceron', niveau: 'faible'), line(bioagresseur: 'limace', niveau: 'non_precise')])
      opus = answer([line(culture: 'Colza', bioagresseur: 'Grosse Altise'), line(bioagresseur: 'puceron', niveau: 'nul'),
                     line(bioagresseur: 'limace', niveau: 'faible'), line(bioagresseur: 'charançon')])

      assert_equal({ 'opus_lines' => 4, 'found' => 3, 'compared' => 2, 'same_level' => 1 }, Bsv::Control.compare(haiku, opus))

      haiku = answer([line(culture: 'Buddleia davidii', bioagresseur: 'Mouches des semis (Delia platura)')])
      opus = answer([line(culture: 'buddleia', bioagresseur: 'mouche des semis')])
      assert_equal 1, Bsv::Control.compare(haiku, opus)['found']
    end

    # Rows

    def test_the_rows_of_a_bulletin_read_and_of_its_corrected_version
      Dir.mktmpdir do |tmp|
        archive = archive_with(tmp, 'v1', 'v2', 'bilan')
        v1, v2, bilan = archive.entries.map(&:sha)
        link = Bsv::Crawler::Link.new(pdf_url: 'https://a/IMG/pdf/x.pdf', label: 'BSV', page_url: 'https://a/p-a1.html')
        archive.see(v1, link, 'grand-est', Date.new(2026, 11, 5))
        archive.see(v2, link, 'grand-est', Date.new(2026, 11, 6))
        archive.see(bilan, link, 'grand-est', Date.new(2026, 11, 6))
        lines = [line(lieux: ['Asques 33', 'Reims']), line(extrait: 'inventé'),
                 line(bioagresseur: 'stade phénologique', type: nil, niveau: 'non_precise', extrait: 'Colza : risque fort dans les parcelles')]
        [v1, v2].each { |sha| archive.keep_answer(sha, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'end_turn', 'model' => 'claude-haiku-5-5', 'answer' => answer(lines) }) }
        archive.keep_answer(bilan, 'haiku', { 'result' => 'succeeded', 'stop_reason' => 'end_turn', 'answer' => answer([line], nature: 'bilan').merge('numero' => nil) })

        rows = Bsv::Rows.new(archive, Bsv::Zones.new).build
        bulletins = rows.bulletins.to_h { |row| [row.first, Bsv::Rows::BULLETINS.zip(row).to_h] }

        assert_equal 'superseded', bulletins[v1]['status']
        assert_equal v2, bulletins[v1]['superseded_by']
        assert_equal 'extracted', bulletins[v2]['status']
        assert_equal 'catalogue_only', bulletins[bilan]['status']
        assert_equal 'Bulletin de santé du végétal Grand Est grandes cultures n° 31 du 05/11/2026', bulletins[v2]['citation']
        assert_equal %w[08 10 51 52 54 55 57 67 68 88], bulletins[v2]['department_codes'].split('|')
        assert_equal ["#{v2}:1", "#{v2}:3"], rows.risks.map(&:first)
        assert_equal 'winter_rape|spring_rape', rows.risks.first[3]
        assert_equal [nil, 'stade'], rows.risks.last.values_at(4, 5)
        assert_equal [["#{v2}:1", 'Asques', '33'], ["#{v2}:1", 'Reims', nil]], rows.places
        assert_equal({ 'quote not in the text' => 1 }, rows.refusals)
      end
    end
  end
end
