# frozen_string_literal: true

require 'csv'

module Datasources
  # Active substances of the plant protection products of E-Phy, with what two reference lists say of
  # them: the Environmental Impact Quotient of Cornell University, and the mode of action of herbicides
  # of the HRAC. The tables of `phytosanitary` are left as they are: this datasource stands beside them
  # and links to its products by their marketing authorisation number.
  class PhytosanitarySubstances < Base
    description "Matières actives des produits phytosanitaires d'E-Phy, avec leur indicateur de risque EIQ et le mode d'action HRAC des herbicides"
    credits name: 'Catalogue E-Phy : substances actives et composition des produits',
            url: 'https://www.data.gouv.fr/fr/datasets/donnees-ouvertes-du-catalogue-e-phy-des-produits-phytopharmaceutiques-matieres-fertilisantes-et-supports-de-culture-adjuvants-produits-mixtes-et-melanges/',
            provider: 'ANSES',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-09-29'
    credits name: 'EIQ Pesticide Values',
            url: 'https://cals.cornell.edu/integrated-pest-management/risk-assessment/eiq/eiq-pesticide-values',
            provider: 'Cornell University, New York State Integrated Pest Management',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://cals.cornell.edu/integrated-pest-management/risk-assessment/eiq',
            updated_at: '2026-02-01'
    credits name: 'HRAC Global Herbicide MoA Classification Master List',
            url: 'https://hracglobal.com/tools',
            provider: 'Herbicide Resistance Action Committee (HRAC)',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://hracglobal.com/tools',
            updated_at: '2026-02-04'

    schema_revision 1
    licence_exception "listes publiées librement par leurs auteurs pour être utilisées ; conditions de réutilisation vérifiées par OSFarm le 2026-10-07"
    pivot :amm, table: :registered_phytosanitary_product_substances, column: :product_id

    EPHY_URL = 'https://www.data.gouv.fr/api/1/datasets/r/cb51408e-2b97-43a4-94e2-c0de5c3bf5b2'
    EIQ_PAGE = 'https://cornell.box.com/v/eiq-pesticide-list'
    HRAC_SITE = 'https://hracglobal.com'
    # Sites of Cornell and of the HRAC answer browsers only
    USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0'

    EIQ_HEADERS = ['Active', 'CAS Number', 'Pesticide type', 'FINAL EIQ', 'Farm_worker', 'Consumer', 'Ecological'].freeze
    HRAC_HEADERS = ['MODE OF ACTION', 'CHEMICAL CLASSIFICATION', 'ACTIVE', 'HRAC GLOBAL', 'LEGACY HRAC GLOBAL'].freeze
    APPROVAL_STATES = { 'INSCRITE' => 'approved', 'NON_INSCRITE' => 'not_approved', 'AUTRE_CAS' => 'other' }.freeze
    # Fewer lines than that and a file is not the one this datasource was written for
    MINIMUM = { substances: 1000, products: 10_000, eiq: 500, hrac: 300, with_eiq: 350, with_hrac: 200 }.freeze

    # The three files are kept under the date of the day: a past collection can be replayed.
    # A file already there is not downloaded again: one that cannot be reached can be dropped by hand.
    def collect
      today = Date.today.iso8601

      fetch(dir.join("ephy_#{today}.zip")) { |file| download(EPHY_URL, file) }
      fetch(dir.join("eiq_#{today}.xlsx")) { |file| download_eiq(file) }
      fetch(dir.join("hrac_#{today}.xlsx")) { |file| download_hrac(file) }
    end

    # Reads and matches everything before loading anything: doubtful files stop here, the published tables untouched.
    def load
      unzip(latest('ephy_*.zip'), dir.join('ephy'))
      substances = ephy_rows('substance_active_utf8.csv')
      products = ephy_rows('produits_utf8.csv')
      eiq = eiq_entries
      hrac = hrac_entries
      refuse_short(substances: substances, products: products, eiq: eiq, hrac: hrac)

      rows = substance_rows(substances, products, eiq, hrac)
      refuse_short(with_eiq: rows.reject { |row| row[5].nil? }, with_hrac: rows.reject { |row| row[11].nil? })

      write_csv('substances.csv', %w[id name cas_number approval_state french_names eiq eiq_farm_worker eiq_consumer
                                     eiq_ecological eiq_incomplete eiq_source_name hrac_group hrac_legacy_group
                                     hrac_mode_of_action hrac_chemical_class hrac_source_name eiq_match hrac_match], rows)
      write_csv('compositions.csv', %w[product_id name french_name quantity unit], composition_rows(products))
      load_csv(dir.join('substances.csv'), 'substances')
      load_csv(dir.join('compositions.csv'), 'compositions')
    end

    def self.table_definitions(builder)
      builder.table(:registered_phytosanitary_substances, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_substances (
          id character varying PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          cas_number character varying,
          approval_state character varying,
          french_names text[],
          eiq numeric(8,2),
          eiq_farm_worker numeric(8,2),
          eiq_consumer numeric(8,2),
          eiq_ecological numeric(8,2),
          eiq_incomplete boolean,
          eiq_source_name character varying,
          eiq_match character varying,
          hrac_group character varying,
          hrac_legacy_group character varying,
          hrac_mode_of_action character varying,
          hrac_chemical_class character varying,
          hrac_source_name character varying,
          hrac_match character varying
        );
        CREATE INDEX registered_phytosanitary_substances_cas_number ON registered_phytosanitary_substances (cas_number);
        CREATE INDEX registered_phytosanitary_substances_hrac_group ON registered_phytosanitary_substances (hrac_group);
      SQL

      builder.table(:registered_phytosanitary_product_substances, sql: <<~SQL).references(substance_id: %i[registered_phytosanitary_substances id])
        CREATE TABLE registered_phytosanitary_product_substances (
          id character varying PRIMARY KEY NOT NULL,
          product_id integer NOT NULL,
          substance_id character varying NOT NULL,
          french_name character varying,
          quantity numeric,
          unit character varying
        );
        CREATE INDEX registered_phytosanitary_product_substances_product_id ON registered_phytosanitary_product_substances (product_id);
        CREATE INDEX registered_phytosanitary_product_substances_substance_id ON registered_phytosanitary_product_substances (substance_id);
      SQL
    end

    def normalize
      query <<~SQL
        INSERT INTO registered_phytosanitary_substances
          SELECT id, name, NULLIF(cas_number, ''), NULLIF(approval_state, ''),
                 CASE WHEN french_names = '' THEN NULL ELSE string_to_array(french_names, '|') END,
                 NULLIF(eiq, '')::numeric, NULLIF(eiq_farm_worker, '')::numeric, NULLIF(eiq_consumer, '')::numeric,
                 NULLIF(eiq_ecological, '')::numeric, NULLIF(eiq_incomplete, '')::boolean, NULLIF(eiq_source_name, ''),
                 NULLIF(eiq_match, ''), NULLIF(hrac_group, ''), NULLIF(hrac_legacy_group, ''),
                 NULLIF(hrac_mode_of_action, ''), NULLIF(hrac_chemical_class, ''), NULLIF(hrac_source_name, ''),
                 NULLIF(hrac_match, '')
            FROM #{name}.substances
           ORDER BY id
      SQL
      # A substance E-Phy names twice in a product, at two doses, keeps its two lines
      query <<~SQL
        INSERT INTO registered_phytosanitary_product_substances (id, product_id, substance_id, french_name, quantity, unit)
          SELECT product_id || '_' || substance_id || '_' || row_number() OVER (PARTITION BY product_id, substance_id ORDER BY quantity, unit),
                 product_id::integer, substance_id, NULLIF(french_name, ''), NULLIF(quantity, '')::numeric, NULLIF(unit, '')
            FROM (SELECT compositions.*, substances.id AS substance_id
                    FROM #{name}.compositions
                    JOIN #{name}.substances ON substances.name = compositions.name) AS parts
           ORDER BY product_id::integer, substance_id
      SQL
    end

    private

      def fetch(file)
        return if file.size?

        yield file
        raise "Nothing downloaded for #{file.basename}: drop the file by hand in #{dir} under that name" unless file.size?
      end

      def download(url, file, cookies: nil)
        jar = cookies.nil? ? '' : "-b '#{cookies}' -c '#{cookies}'"

        execute "curl -sSLf --retry 2 -A '#{USER_AGENT}' #{jar} -o '#{file}' '#{url}'"
      end

      # The workbook is shared through Box: its page names the file, which is then asked for by that name
      def download_eiq(file)
        page = dir.join('eiq_page.html')
        cookies = dir.join('eiq_cookies.txt')
        download(EIQ_PAGE, page, cookies: cookies)
        content = page.size? ? page.read : ''
        shared_name = content[/"sharedName":"([^"]+)"/, 1]
        file_id = content[/"typedID":"(f_\d+)"/, 1]
        return if shared_name.nil? || file_id.nil?

        download("https://cornell.app.box.com/index.php?rm=box_download_shared_file&shared_name=#{shared_name}&file_id=#{file_id}",
                 file, cookies: cookies)
      end

      # The classification is published again every year, under an address that carries the year
      def download_hrac(file)
        page = dir.join('hrac_page.html')
        download("#{HRAC_SITE}/tools", page)
        classification = (page.size? ? page.read : '').scan(%r{tools/(\d{4})-hrac-global-herbicide-moa-classification}).flatten.max
        return if classification.nil?

        download("#{HRAC_SITE}/tools/#{classification}-hrac-global-herbicide-moa-classification", page)
        link = page.read[/getdoc\.php\?file=[^"&]*Master-List-without-Molecular-Structures\.xlsx/]
        download("#{HRAC_SITE}/#{link}", file) unless link.nil?
      end

      def latest(pattern)
        Pathname.glob(dir.join(pattern)).max || raise("No file #{pattern} in #{dir}: run the collect phase first")
      end

      # The files of E-Phy hold quotes that open nothing: they are read without any quoting
      def ephy_rows(file)
        CSV.read(dir.join('ephy', file), col_sep: ';', headers: true, quote_char: "\x00", encoding: 'bom|utf-8').map(&:to_h)
      end

      def sheet_rows(file, headers)
        sheet = ::Roo::Spreadsheet.open(file.to_s).sheet(0)
        rows = (1..sheet.last_row).map { |index| sheet.row(index) }
        start = rows.index { |row| row.first(headers.size).map { |cell| cell.to_s.strip } == headers }
        raise "No row #{headers.join(', ')} in #{file}" if start.nil?

        rows.drop(start + 1).reject { |row| row[0].to_s.strip.empty? && row[2].to_s.strip.empty? }
      end

      def eiq_entries
        sheet_rows(latest('eiq_*.xlsx'), EIQ_HEADERS).select { |row| row[3].is_a?(Numeric) }.map do |row|
          { name: row[0].to_s.strip, cas: row[1].to_s.strip, eiq: row[3], farm_worker: row[4], consumer: row[5],
            ecological: row[6], incomplete: !row[7].to_s.strip.empty? }
        end
      end

      def hrac_entries
        sheet_rows(latest('hrac_*.xlsx'), HRAC_HEADERS).map do |row|
          { mode_of_action: row[0].to_s.strip, chemical_class: row[1].to_s.strip, name: row[2].to_s.strip,
            group: text(row[3]), legacy_group: text(row[4]) }
        end
      end

      # Group numbers come as numbers, and some cells as fragments of HTML
      def text(cell)
        value = cell.is_a?(Float) && cell == cell.to_i ? cell.to_i : cell

        value.to_s.gsub(/<[^>]+>/, '').strip
      end

      def refuse_short(counted)
        short = counted.select { |what, rows| rows.size < MINIMUM.fetch(what) }
        return if short.empty?

        raise short.map { |what, rows| "#{what}: #{rows.size} lines, at least #{MINIMUM.fetch(what)} expected" }.join('; ')
      end

      # The substances E-Phy lists, then the ones it only names in the composition of a product
      def substance_rows(substances, products, eiq, hrac)
        eiq_matcher = Matcher.new(eiq, aliases: aliases('eiq'))
        hrac_matcher = Matcher.new(hrac, aliases: aliases('hrac'), isomers: true, forms: true)
        listed = substances.map { |row| [row.values[0].to_s.strip, row.values[1].to_s.strip, APPROVAL_STATES[row.values[2]], row.values[3].to_s] }
        named = products.flat_map { |row| Composition.parse(row['Substances actives']).map(&:name) }.uniq

        (listed + (named - listed.map(&:first)).map { |name| [name, '', nil, ''] })
          .reject { |name, *| name.empty? }.uniq { |name, *| Matcher.normalize(name) }
          .map { |name, cas, state, variants| substance_row(name, cas, state, variants, eiq_matcher, hrac_matcher) }
      end

      def substance_row(name, cas, state, variants, eiq_matcher, hrac_matcher)
        eiq = eiq_matcher.match(name, cas: cas)
        hrac = hrac_matcher.match(name)

        [
          Matcher.normalize(name).tr(' ', '_'), name, cas, state, variants.split('|').map(&:strip).reject(&:empty?).join('|'),
          *(eiq ? eiq.entry.values_at(:eiq, :farm_worker, :consumer, :ecological, :incomplete, :name) : [nil] * 6),
          *(hrac ? hrac.entry.values_at(:group, :legacy_group, :mode_of_action, :chemical_class, :name) : [nil] * 5),
          eiq&.how, hrac&.how
        ]
      end

      def composition_rows(products)
        # A mix of two products carries their two numbers: it is not a product of its own
        products.select { |row| row['numero AMM'].to_s.match?(/\A\d+\z/) }.flat_map do |row|
          Composition.parse(row['Substances actives']).map { |part| [row['numero AMM'], part.name, part.french_name, part.quantity, part.unit] }
        end
      end

      def aliases(list)
        CSV.read('data/phytosanitary_substances/aliases.csv', headers: true)
           .select { |row| row['list'] == list }.to_h { |row| [row['ephy_name'], row['list_name']] }
      end

      def write_csv(file, headers, rows)
        CSV.open(dir.join(file), 'w') do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
  end
end
