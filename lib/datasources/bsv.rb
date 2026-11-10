# frozen_string_literal: true

require 'csv'
require 'json'

module Datasources
  # Bulletins de santé du végétal (BSV): each week, for a region and a sector, what stage the crops are at, which
  # pests are seen and where, and the risk for the week ahead. The 13 metropolitan regions publish them as PDF on the
  # sites of their DRAAF (`data/bsv/sources.yml`).
  #
  # `collect` walks those sites (`Crawler`), keeps every PDF ever seen in `raw/bsv/archive/` (`Archive`) with the
  # text of its pages (`Pages`), and has the Claude API read the new ones (`Extractor`: Haiku for all, Opus for a
  # few, to measure Haiku with `Control`). `load` checks each answer against the text (`Extraction`) and writes the
  # raw tables (`Rows`) with no network; `normalize` makes the catalogue, the searchable text and the risks
  # (`doc/datasources/bsv.md`).
  class Bsv < Base
    description 'Bulletins de santé du végétal des DRAAF : catalogue et texte des bulletins, risques par culture et bioagresseur'
    credits name: 'Bulletins de santé du végétal',
            url: 'https://agriculture.gouv.fr/le-bulletin-de-sante-du-vegetal',
            provider: "Réseaux régionaux d'épidémiosurveillance (DRAAF, chambres d'agriculture, FREDON)",
            licence: 'Reproduction autorisée avec mention de la source',
            licence_url: 'https://agriculture.gouv.fr/le-bulletin-de-sante-du-vegetal',
            updated_at: '2026-11-09'
    licence_exception 'Each bulletin allows its reproduction, in part with its reference: every row carries the bulletin it comes from'
    # Places are tied to their commune during normalize
    depends_on :postal_codes
    # The source is as recent as the last bulletin collected
    source_date 'SELECT COALESCE(max(published_on), max(first_seen_on)) FROM registered_bsv_bulletins'

    ARCHIVE = 'archive'
    # Bulletins Opus reads too, each collect
    CONTROLS = 5

    def collect
      archive = Archive.new(dir.join(ARCHIVE))
      crawl(archive) unless ENV['LEXICON_BSV_CRAWL'] == 'no'
      read_pages(archive)
      extract(archive)
    end

    def load
      zones = Zones.new
      rows = Rows.new(Archive.new(dir.join(ARCHIVE)), zones).build
      pages = Archive.new(dir.join(ARCHIVE)).entries.flat_map do |entry|
        Array(entry.pages).each_with_index.map { |text, index| [entry.sha, index + 1, text] }
      end
      write_csv('bulletins.csv', Rows::BULLETINS, rows.bulletins)
      write_csv('pages.csv', %w[bulletin_id page text], pages)
      write_csv('risks.csv', Rows::RISKS, rows.risks)
      write_csv('places.csv', Rows::PLACES, rows.places)
      %w[bulletins pages risks places].each { |table| load_csv(dir.join("#{table}.csv"), table) }
      report(rows, pages.size)
      report_coverage(Coverage.new(zones).build(rows.bulletins.map { |row| Rows::BULLETINS.zip(row).to_h }))
    end

    def self.table_definitions(builder)
      builder.table(:registered_bsv_bulletins, sql: <<~SQL)
        CREATE TABLE registered_bsv_bulletins (
          id character varying PRIMARY KEY NOT NULL,
          region character varying NOT NULL,
          regions character varying[] NOT NULL,
          department_codes character varying[] NOT NULL,
          zone character varying,
          sector character varying,
          subsector character varying,
          number character varying,
          published_on date,
          first_seen_on date NOT NULL,
          last_seen_on date NOT NULL,
          nature character varying,
          label character varying,
          page_title character varying,
          section character varying,
          article_url character varying,
          pdf_url character varying,
          pages_count integer NOT NULL,
          scanned boolean,
          status character varying NOT NULL,
          superseded_by character varying,
          model character varying,
          instructions_version character varying,
          citation character varying
        );

        CREATE INDEX registered_bsv_bulletins_region ON registered_bsv_bulletins(region);
        CREATE INDEX registered_bsv_bulletins_published_on ON registered_bsv_bulletins(published_on);
        CREATE INDEX registered_bsv_bulletins_department_codes ON registered_bsv_bulletins USING GIN (department_codes);
      SQL

      builder.table(:registered_bsv_pages, sql: <<~SQL).references(bulletin_id: %i[registered_bsv_bulletins id])
        CREATE TABLE registered_bsv_pages (
          bulletin_id character varying NOT NULL,
          page integer NOT NULL,
          text text NOT NULL,
          search tsvector NOT NULL DEFAULT ''::tsvector,
          PRIMARY KEY (bulletin_id, page)
        );

        CREATE INDEX registered_bsv_pages_search ON registered_bsv_pages USING GIN (search);
      SQL

      builder.table(:registered_bsv_risks, sql: <<~SQL).references(bulletin_id: %i[registered_bsv_bulletins id])
        CREATE TABLE registered_bsv_risks (
          id character varying PRIMARY KEY NOT NULL,
          bulletin_id character varying NOT NULL,
          crop character varying NOT NULL,
          production_names character varying[],
          pest character varying,
          pest_type character varying,
          stage character varying,
          bbch_min integer,
          bbch_max integer,
          level character varying NOT NULL,
          level_text character varying,
          conditional boolean NOT NULL DEFAULT false,
          condition character varying,
          risk_period character varying,
          threshold character varying,
          observations text,
          page integer,
          source_quote text NOT NULL
        );

        CREATE INDEX registered_bsv_risks_bulletin_id ON registered_bsv_risks(bulletin_id);
        CREATE INDEX registered_bsv_risks_pest ON registered_bsv_risks(pest);
        CREATE INDEX registered_bsv_risks_production_names ON registered_bsv_risks USING GIN (production_names);
      SQL

      # Kept, not served by the API for now (decision of 2026-11-08)
      builder.table(:registered_bsv_risk_places, sql: <<~SQL).references(risk_id: %i[registered_bsv_risks id])
        CREATE TABLE registered_bsv_risk_places (
          risk_id character varying NOT NULL,
          name character varying NOT NULL,
          department_code character varying,
          insee_code character varying
        );

        CREATE INDEX registered_bsv_risk_places_risk_id ON registered_bsv_risk_places(risk_id);
      SQL
    end

    def normalize
      query <<~SQL
        INSERT INTO registered_bsv_bulletins
          (id, region, regions, department_codes, zone, sector, subsector, number, published_on, first_seen_on,
           last_seen_on, nature, label, page_title, section, article_url, pdf_url, pages_count, scanned, status,
           superseded_by, model, instructions_version, citation)
        SELECT id, region, string_to_array(regions, '|'), string_to_array(department_codes, '|'), NULLIF(zone, ''),
               NULLIF(sector, ''), NULLIF(subsector, ''), NULLIF(number, ''), NULLIF(published_on, '')::date,
               first_seen_on::date, last_seen_on::date, NULLIF(nature, ''), NULLIF(label, ''), NULLIF(page_title, ''),
               NULLIF(section, ''), NULLIF(article_url, ''), NULLIF(pdf_url, ''), pages_count::integer,
               NULLIF(scanned, '')::boolean, status, NULLIF(superseded_by, ''), NULLIF(model, ''),
               NULLIF(instructions_version, ''), NULLIF(citation, '')
          FROM #{name}.bulletins
      SQL

      # What the pages are searched by. Accents are removed, as in `rd_agri`: « ble » finds « blé ».
      query <<~SQL
        INSERT INTO registered_bsv_pages (bulletin_id, page, text, search)
        SELECT bulletin_id, page::integer, text,
               to_tsvector('french', translate(lower(text), '#{RdAgri::ACCENTED}', '#{RdAgri::UNACCENTED}'))
          FROM #{name}.pages
      SQL

      query <<~SQL
        INSERT INTO registered_bsv_risks
          (id, bulletin_id, crop, production_names, pest, pest_type, stage, bbch_min, bbch_max, level, level_text,
           conditional, condition, risk_period, threshold, observations, page, source_quote)
        SELECT id, bulletin_id, crop, string_to_array(NULLIF(production_names, ''), '|'), NULLIF(pest, ''),
               NULLIF(pest_type, ''), NULLIF(stage, ''), NULLIF(bbch_min, '')::integer, NULLIF(bbch_max, '')::integer,
               level, NULLIF(level_text, ''), conditional::boolean, NULLIF(condition, ''), NULLIF(risk_period, ''),
               NULLIF(threshold, ''), NULLIF(observations, ''), NULLIF(page, '')::integer, source_quote
          FROM #{name}.risks
      SQL

      # A place is the one commune of that name in its department, or failing a department, in those the bulletin
      # covers; no code when there is none or several.
      plain = ->(expression) { Lexicon::Contribution::TabularDatasource.plain_sql(expression) }
      query <<~SQL
        INSERT INTO registered_bsv_risk_places (risk_id, name, department_code, insee_code)
        SELECT place.risk_id, place.name, NULLIF(place.department_code, ''),
               (SELECT min(commune.code)
                  FROM registered_postal_codes AS commune
                 WHERE #{plain.call('commune.city_name')} = #{plain.call('place.name')}
                   AND CASE WHEN NULLIF(place.department_code, '') IS NOT NULL
                            THEN left(commune.code, 2) = place.department_code
                            ELSE left(commune.code, 2) = ANY(bulletin.department_codes) END
                HAVING count(DISTINCT commune.code) = 1)
          FROM #{name}.places AS place
          JOIN registered_bsv_risks AS risk ON risk.id = place.risk_id
          JOIN registered_bsv_bulletins AS bulletin ON bulletin.id = risk.bulletin_id
      SQL
    end

    private

      def crawl(archive)
        http = Http.new
        known = archive.known_urls
        today = Date.today
        regions.each do |region|
          links = Crawler.new(region, http: http, say: ->(text) { puts text }).links
          added = 0
          links.each do |link|
            sha = known[link.pdf_url]
            if sha.nil?
              sha = archive.store(http.download(link.pdf_url, dir.join('incoming.pdf')))
              known[link.pdf_url] = sha
              added += 1
            end
            archive.see(sha, link, region.slug, today)
          rescue Http::Failed => e
            puts "  #{e.message}".yellow
          end
          puts "BSV #{region.slug}: #{links.size} PDF listed, #{added} new"
        rescue Http::Failed, URI::Error => e
          puts "BSV #{region.slug}: not read (#{e.message}), the archive is kept".red
        end
      end

      # The regions to collect: all of `sources.yml`, or those of LEXICON_BSV_REGIONS (slugs separated by commas)
      def regions
        all = Sources.load
        wanted = list('LEXICON_BSV_REGIONS')
        return all if wanted.empty?

        unknown = wanted - all.map(&:slug)
        raise "LEXICON_BSV_REGIONS: unknown regions #{unknown.join(', ')}" if unknown.any?

        all.select { |region| wanted.include?(region.slug) }
      end

      # Reads the text of the bulletins that have none yet (new ones, and PDF dropped by hand)
      def read_pages(archive)
        archive.entries.reject(&:pages).each do |entry|
          archive.keep_pages(entry.sha, Pages.read(entry.pdf))
        rescue Pages::Failed => e
          puts "  #{e.message}".yellow
        end
      end

      # Has the API read the bulletins it has not read yet. LEXICON_BSV_ONLY (fingerprints separated by commas)
      # and LEXICON_BSV_FROM (a year, last year by default, `all` for every one: bulletins whose first page is of
      # that year or later) narrow them; past
      # LEXICON_BSV_MAX_NEW (300) bulletins, nothing is sent: raise it knowingly.
      def extract(archive)
        if ENV['ANTHROPIC_API_KEY'].to_s.empty?
          puts 'BSV: no ANTHROPIC_API_KEY, the new bulletins are not read'.yellow
          return
        end

        require 'anthropic'
        say = ->(text) { puts text }
        extractor = Extractor.new(archive, client: Anthropic::Client.new, say: say)
        gathered = extractor.gather
        only = list('LEXICON_BSV_ONLY')
        from = ENV.fetch('LEXICON_BSV_FROM', (Date.today.year - 1).to_s)
        from = from == 'all' ? nil : Integer(from)
        entries = archive.entries.select do |entry|
          entry.pages && (only.empty? || only.include?(entry.sha)) && (from.nil? || Pages.year(entry.pages).to_i >= from)
        end
        haiku = extractor.wanted(entries, 'haiku')
        maximum = Integer(ENV.fetch('LEXICON_BSV_MAX_NEW', '300'))
        if only.empty? && haiku.size > maximum
          puts format('BSV: %<n>d bulletins to read, over LEXICON_BSV_MAX_NEW=%<max>d (about %<cost>.0f $ with Haiku): ' \
                      'nothing sent', n: haiku.size, max: maximum, cost: haiku.size * 0.004).red
        elsif haiku.any?
          # Opus measures bulletins read for the first time: a bulletin asked again (error, answer cut) is no sample
          fresh = haiku.reject { |entry| archive.answer(entry.sha, 'haiku') }
          opus = extractor.wanted(sample(fresh), 'opus')
          extractor.submit(haiku.map { |entry| [entry, 'haiku'] } + opus.map { |entry| [entry, 'opus'] })
          gathered += extractor.gather(wait: Integer(ENV.fetch('LEXICON_BSV_WAIT', '90')) * 60)
        end
        gathered += correct(extractor, entries)
        puts "BSV: #{gathered.size} answers gathered" if gathered.any?
        Control.run(archive, gathered.select { |_, key| key == 'opus' }.map(&:first), dir.join('controls.csv'), say: say)
      end

      # Has the extractions made under former instructions corrected (`Correction`), once each; past
      # LEXICON_BSV_MAX_FIX (300) bulletins, nothing is sent: raise it knowingly
      def correct(extractor, entries)
        fixes = extractor.wanted_fixes(entries)
        maximum = Integer(ENV.fetch('LEXICON_BSV_MAX_FIX', '300'))
        if fixes.size > maximum
          puts format('BSV: %<n>d extractions to correct, over LEXICON_BSV_MAX_FIX=%<max>d (about %<cost>.0f $ with Haiku): ' \
                      'nothing sent', n: fixes.size, max: maximum, cost: fixes.size * 0.0013).red
          return []
        end
        return [] if fixes.empty?

        extractor.submit(fixes.map { |entry| [entry, Correction::KEY] })
        extractor.gather(wait: Integer(ENV.fetch('LEXICON_BSV_WAIT', '90')) * 60)
      end

      # A few bulletins of different sections, the same each time for the same bulletins
      def sample(entries)
        entries.group_by { |entry| entry.notice&.values_at('region', 'section', 'page_title')&.compact&.join('|').to_s }
               .values.map { |same| same.min_by(&:sha) }.min_by(CONTROLS, &:sha)
      end

      def report(rows, pages)
        puts "BSV: #{rows.bulletins.size} bulletins (#{rows.statuses.sort.map { |status, n| "#{n} #{status}" }.join(', ')}), " \
             "#{pages} pages, #{rows.risks.size} risks, #{rows.places.size} places"
        puts "  lines refused: #{rows.refusals.sort_by { |_, n| -n }.map { |reason, n| "#{n} #{reason}" }.join(', ')}".yellow if rows.refusals.any?
        list = ->(counts) { counts.sort_by { |name, n| [-n, name] }.first(30).map { |name, n| "#{name} (#{n})" }.join(', ') }
        puts "  crops missing from data/bsv/cultures.csv: #{list.call(rows.unknown_crops)}".yellow if rows.unknown_crops.any?
        puts "  zones missing from data/bsv/zones.csv: #{list.call(rows.unknown_zones)}".yellow if rows.unknown_zones.any?
        puts "  levels set from their text: #{rows.levels_changed}" if rows.levels_changed.positive?
        puts "  corrected: #{rows.levels_corrected} levels, #{rows.lines_dropped} lines dropped" if (rows.levels_corrected + rows.lines_dropped).positive?
      end

      def report_coverage(coverage)
        states = coverage.by_state
        puts "BSV coverage of data/bsv/editions.csv: #{%w[ok late missing].map { |state| "#{Array(states[state]).size} #{state}" }.join(', ')}"
        %w[missing late].each do |state|
          Array(states[state]).each { |edition| puts "  #{state}: #{edition.name} (last #{edition.last || 'never'})".yellow }
        end
        coverage.unmatched.sort_by { |key, n| [-n, key] }.first(15).each do |key, n|
          puts "  no edition for #{key.reject(&:empty?).join(' / ')} (#{n})".yellow
        end
      end

      def list(variable)
        ENV[variable].to_s.split(',').map(&:strip).reject(&:empty?)
      end
  end
end
