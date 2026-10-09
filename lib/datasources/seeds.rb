# frozen_string_literal: true

require 'csv'
require 'zlib'

module Datasources
  # Seeds sold to French farms: the species, and the prices merchants show every week. The species table
  # is written by hand (`data/seeds/species.csv`) and linked to the taxonomy; prices are read at five merchants:
  # Germineo and Cereapro with the readers of `fertilizers`, for one place of delivery, Semence Biologique,
  # Agrilisa and La Récolte with their own. Readings add up week after week.
  class Seeds < Base
    description 'Semences : espèces cultivées avec leur dose de semis indicative, prix relevés chaque semaine chez des marchands et prix mensuel au kilo par espèce'
    credits name: 'Catalogue Germineo',
            url: 'https://www.germineo.com/semences-1',
            provider: 'Germineo',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://www.germineo.com',
            updated_at: '2026-10-07'
    credits name: 'Catalogue Semence Biologique',
            url: 'https://www.semence-biologique.fr',
            provider: 'Semence Biologique (Partner & Co)',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://www.semence-biologique.fr',
            updated_at: '2026-10-07'
    credits name: 'Catalogue La Récolte',
            url: 'https://www.larecolte.fr/2293-couverts-vegetaux',
            provider: 'La Récolte',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://www.larecolte.fr',
            updated_at: '2026-10-07'
    credits name: 'Catalogue Agrilisa',
            url: 'https://www.agrilisa.com',
            provider: 'Agrilisa',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://www.agrilisa.com',
            updated_at: '2026-10-07'
    credits name: 'Catalogue des offres Cereapro',
            url: 'https://appro-cereapro.com/catalogue',
            provider: 'Cereapro',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://appro-cereapro.com',
            updated_at: '2026-10-07'

    schema_revision 2
    # The official catalogue of varieties is read to tell which variety an offer is about
    depends_on :seed_varieties
    # Prices name the merchants that show them: they are served to the members of OSFarm only
    scope :members
    source_date 'SELECT max(observed_on) FROM registered_seed_price_readings'
    pivot :taxon, table: :registered_seed_species, column: :taxon_reference_name

    Germineo = Fertilizers::Germineo
    Cereapro = Fertilizers::Cereapro
    USER_AGENT = Fertilizers::USER_AGENT
    PAUSE = 1
    # La Récolte asks robots for three seconds between two pages
    LONG_PAUSE = 3
    MAXIMUM_PAGES = 20
    # Seeds travel in bags: one place of delivery is enough, the first of the places of `fertilizers`
    PLACE = { 'postal_code' => '17250', 'insee_code' => '17387' }.freeze
    CATEGORIES = %w[semences/cereales-a-paille-meteils-37 semences/autres-cereales-39 semences/mais-38 semences/oleagineux-41
                    semences/proteagineux-40 semences/fourrageres-35 semences/couverts-intercultures-36].freeze
    KILOGRAMS = { 'kilogram' => 1.0, 'quintal' => 100.0, 'ton' => 1000.0 }.freeze
    # Euros per kilogram outside of which a price is a mistake of reading
    PRICE_RANGE = (0.1..200.0).freeze
    MINIMUM_OFFERS = 100
    PREVIOUS_PACKAGES = 'out/packages/seeds'
    READING_COLUMNS = %w[id species_id merchant observed_on delivery_postal_code label variety organic treated mixture packaging
                         price unit price_per_kilogram negotiated source_url].freeze

    def collect
      day = dir.join(Date.today.iso8601)
      day.mkpath
      collect_cereapro(day)
      collect_germineo(day)
      collect_semence_biologique(day)
      collect_agrilisa(day)
      collect_la_recolte(day)
    end

    def load
      label = Label.new(species)
      readings = previous_readings.to_h { |row| [row['id'], row] }
      days = dir.children.select { |child| child.directory? && child.basename.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.sort
      raise "No collection in #{dir}: run the collect phase first" if days.empty?

      days.each do |day|
        rows = offers_of(day).map { |offer| reading_row(offer, label, Date.iso8601(day.basename.to_s)) }.select { |row| usable?(row) }
        raise "#{rows.size} priced seed offers on #{day.basename}, at least #{MINIMUM_OFFERS} expected" if day == days.last && rows.size < MINIMUM_OFFERS

        rows.each { |row| readings[row['id']] = row }
      end

      write_csv('species.csv', species.first.keys, species.map(&:values))
      write_csv('readings.csv', READING_COLUMNS, readings.values.map { |row| row.values_at(*READING_COLUMNS) })
      load_csv(dir.join('species.csv'), 'species')
      load_csv(dir.join('readings.csv'), 'readings')
    end

    def self.table_definitions(builder)
      builder.table(:registered_seed_species, sql: <<~SQL)
        CREATE TABLE registered_seed_species (
          id character varying PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          latin_name character varying NOT NULL,
          family character varying NOT NULL,
          category character varying NOT NULL,
          season character varying NOT NULL,
          sowing_rate_min numeric(8,2),
          sowing_rate_max numeric(8,2),
          taxon_reference_name character varying
        );
      SQL

      species = { species_id: %i[registered_seed_species id] }
      builder.table(:registered_seed_price_readings, sql: <<~SQL).references(**species)
        CREATE TABLE registered_seed_price_readings (
          id character varying PRIMARY KEY NOT NULL,
          species_id character varying,
          merchant character varying NOT NULL,
          observed_on date NOT NULL,
          delivery_postal_code character varying NOT NULL,
          label character varying NOT NULL,
          variety character varying,
          organic boolean NOT NULL,
          treated boolean,
          mixture boolean NOT NULL,
          packaging character varying,
          price numeric(10,2) NOT NULL,
          unit character varying NOT NULL,
          price_per_kilogram numeric(10,4),
          negotiated boolean NOT NULL,
          source_url character varying,
          variety_id character varying
        );
        CREATE INDEX registered_seed_price_readings_species_id ON registered_seed_price_readings (species_id, observed_on);
        CREATE INDEX registered_seed_price_readings_variety_id ON registered_seed_price_readings (variety_id);
      SQL

      builder.table(:registered_seed_monthly_prices, sql: <<~SQL).references(**species)
        CREATE TABLE registered_seed_monthly_prices (
          id character varying PRIMARY KEY NOT NULL,
          species_id character varying NOT NULL,
          organic boolean NOT NULL,
          month date NOT NULL,
          price_per_kilogram numeric(10,4) NOT NULL,
          lowest_price_per_kilogram numeric(10,4) NOT NULL,
          highest_price_per_kilogram numeric(10,4) NOT NULL,
          offers integer NOT NULL,
          merchants text[] NOT NULL,
          last_observed_on date NOT NULL
        );
        CREATE INDEX registered_seed_monthly_prices_species_id ON registered_seed_monthly_prices (species_id, month);
      SQL
    end

    def normalize
      query <<~SQL
        INSERT INTO registered_seed_species
          SELECT id, name, latin_name, family, category, season, NULLIF(sowing_rate_min, '')::numeric,
                 NULLIF(sowing_rate_max, '')::numeric, NULLIF(taxon_reference_name, '')
            FROM #{name}.species ORDER BY id
      SQL
      query <<~SQL
        INSERT INTO registered_seed_price_readings
          SELECT id, NULLIF(species_id, ''), merchant, observed_on::date, delivery_postal_code, label, NULLIF(variety, ''),
                 organic::boolean, NULLIF(treated, '')::boolean, mixture::boolean, NULLIF(packaging, ''), price::numeric, unit,
                 NULLIF(price_per_kilogram, '')::numeric, negotiated::boolean, NULLIF(source_url, ''), NULL
            FROM #{name}.readings ORDER BY observed_on, id
      SQL
      link_varieties
      # One price per offer and per month, its latest, then the species: the median of every seed of the species
      # sold by the kilogram, whatever its variety, so that one odd offer does not move the price. Mixtures and
      # seeds sold by the dose are left out.
      query <<~SQL
        INSERT INTO registered_seed_monthly_prices
          SELECT species_id || '_' || CASE WHEN organic THEN 'organic' ELSE 'conventional' END || '_' || to_char(month, 'YYYY-MM'),
                 species_id, organic, month, round((percentile_cont(0.5) WITHIN GROUP (ORDER BY price_per_kilogram))::numeric, 4),
                 min(price_per_kilogram), max(price_per_kilogram),
                 count(*), array_agg(DISTINCT merchant ORDER BY merchant), max(observed_on)
            FROM (
              SELECT DISTINCT ON (merchant, source_url, label, packaging, date_trunc('month', observed_on))
                     species_id, organic, merchant, date_trunc('month', observed_on)::date AS month, price_per_kilogram, observed_on
                FROM registered_seed_price_readings
               WHERE species_id IS NOT NULL AND NOT mixture AND price_per_kilogram IS NOT NULL
               ORDER BY merchant, source_url, label, packaging, date_trunc('month', observed_on), observed_on DESC
            ) AS offers
           GROUP BY species_id, organic, month
           ORDER BY month, species_id, organic
      SQL
    end

    private

      # The variety of the official catalogue that bears the name read in the offer, within the species of the
      # offer: the catalogue goes down to the subspecies (brassica_napus_napus) where the species table stops
      # above (brassica_napus), or the other way round.
      def link_varieties
        if query("SELECT to_regclass('lexicon.registered_seed_varieties') AS found").first['found'].nil?
          return logger.warn('registered_seed_varieties is not built: varieties are left without their number')
        end

        same_species = <<~SQL
          (variety.id_specie = species.taxon_reference_name
           OR variety.id_specie LIKE replace(species.taxon_reference_name, '_', '\\_') || '\\_%'
           OR species.taxon_reference_name LIKE replace(variety.id_specie, '_', '\\_') || '\\_%')
        SQL
        named = "upper(postgis.unaccent(variety.variety_name))"
        read = "upper(postgis.unaccent(reading.variety))"
        # The same name first; failing that, the only variety whose name ends with it: merchants drop the mark of
        # the breeder that the catalogue keeps ("ABSALON" for "LG ABSALON")
        ["#{named} = #{read}", "#{named} LIKE '% ' || #{read}"].each do |same_name|
          query <<~SQL
            UPDATE registered_seed_price_readings AS reading
               SET variety_id = (
                     SELECT min(variety.id)
                       FROM registered_seed_varieties AS variety
                      WHERE #{same_name} AND #{same_species}
                     HAVING count(*) = 1
                   )
              FROM registered_seed_species AS species
             WHERE species.id = reading.species_id AND reading.variety IS NOT NULL AND reading.variety_id IS NULL
               AND species.taxon_reference_name IS NOT NULL
          SQL
        end
      end

      def species
        @species ||= CSV.read('data/seeds/species.csv', headers: true).map(&:to_h)
      end

      def fetch(file, url, options = '', pause: PAUSE)
        return if file.size?

        execute "curl -sSLf --retry 2 -A '#{USER_AGENT}' #{options} -o '#{file}' '#{url}'"
        sleep pause
      end

      # The page of Cereapro holds its whole catalogue: the one `fertilizers` fetched the same day is taken
      def collect_cereapro(day)
        file = day.join("cereapro_#{PLACE['postal_code']}.html")
        already = Pathname.new("raw/fertilizers/#{day.basename}/#{file.basename}")
        return FileUtils.cp(already, file) if !file.size? && already.size?

        session = CGI.escape(JSON.generate(codeInsee: PLACE['insee_code']))
        fetch(file, "#{Cereapro::SITE}/catalogue", "-H 'Cookie: __client_session=#{session}'")
      end

      def collect_germineo(day)
        pages = ->(category, page) { day.join("germineo_#{category.split('/').last}_#{page}.html") }
        return if CATEGORIES.all? { |category| pages.call(category, 1).size? }

        cookies = "-b '#{day.join('germineo_cookies.txt')}' -c '#{day.join('germineo_cookies.txt')}'"
        entry = day.join('germineo_entry.html')
        FileUtils.rm_f([entry, day.join('germineo_cookies.txt')])
        fetch(entry, "#{Germineo::SITE}/semences-1", cookies)
        token = entry.size? ? entry.read[/csrf-token" content="([^"]+)"/, 1] : nil
        return if token.nil?

        fetch(day.join('germineo_zip.html'), "#{Germineo::SITE}/zip",
              "#{cookies} --data-urlencode '_token=#{token}' --data 'country_id=1&zip=#{PLACE['postal_code']}'")
        CATEGORIES.each do |category|
          (1..MAXIMUM_PAGES).each do |page|
            file = pages.call(category, page)
            fetch(file, "#{Germineo::SITE}/#{category}?page=#{page}", cookies)
            break unless file.size? && Germineo.next_page?(file.read, page)
          end
        end
      end

      # The shop gives its catalogue a hundred products at a time
      def collect_semence_biologique(day)
        (1..MAXIMUM_PAGES).each do |page|
          file = day.join("semence_biologique_#{page}.json")
          fetch(file, "#{SemenceBiologique::API}?per_page=#{SemenceBiologique::PER_PAGE}&page=#{page}")
          break unless file.size? && SemenceBiologique.offers(file.read).size == SemenceBiologique::PER_PAGE
        end
      end

      def collect_agrilisa(day)
        (Agrilisa::CATEGORIES + Agrilisa::ORGANIC_CATEGORIES).each do |category|
          fetch(day.join("agrilisa_#{category}.html"), "#{Agrilisa::SITE}/Catalogue/catid/#{category}/semences")
        end
      end

      # The lists every week; the page of a product once, the first time it is seen, for the weight of its bag
      def collect_la_recolte(day)
        products = dir.join('la_recolte_products')
        products.mkpath
        (1..MAXIMUM_PAGES).each do |page|
          file = day.join("la_recolte_#{page}.html")
          fetch(file, "#{LaRecolte::SITE}/#{LaRecolte::CATEGORY}?page=#{page}", pause: LONG_PAUSE)
          break unless file.size?

          LaRecolte.cards(file.read).each { |card| fetch(products.join("#{card.id}.html"), card.url, pause: LONG_PAUSE) }
          break unless LaRecolte.next_page?(file.read, page)
        end
      end

      def la_recolte_offers(day)
        Pathname.glob(day.join('la_recolte_*.html')).sort.flat_map { |file| LaRecolte.cards(file.read) }.map do |card|
          page = dir.join('la_recolte_products', "#{card.id}.html")
          { merchant: LaRecolte::MERCHANT, source_id: card.id, label: card.name, packaging: 'sac', price: card.price, unit: 'bag',
            kilograms: page.size? ? LaRecolte.kilograms(page.read) : nil, url: card.url, negotiated: false, several: false }
        end
      end

      # @return [Array<Hash>] what each merchant offers that day, in the same shape
      def offers_of(day)
        semence_biologique = Pathname.glob(day.join('semence_biologique_*.json')).sort.flat_map { |file| SemenceBiologique.offers(file.read) }
        agrilisa = Agrilisa::ORGANIC_CATEGORIES.map { |category| [category, true] }.concat(Agrilisa::CATEGORIES.map { |category| [category, false] })
                                               .flat_map do |category, organic|
          file = day.join("agrilisa_#{category}.html")
          file.size? ? Agrilisa.offers(file.read, organic: organic) : []
        end

        germineo = Pathname.glob(day.join('germineo_*_[0-9]*.html')).sort.flat_map { |file| Germineo.cards(file.read) }.uniq(&:id).map do |card|
          { merchant: Germineo::MERCHANT, source_id: card.id, label: card.name, packaging: card.packaging_label, price: card.price,
            unit: card.unit, url: card.url, negotiated: false, several: card.attributes.count { |_, value| value.match?(/\A[\d.,]+\s*%\z/) } > 1 }
        end
        page = day.join("cereapro_#{PLACE['postal_code']}.html")
        cereapro = (page.size? ? Cereapro.records(page.read) : []).select { |record| record['productType'] == 'semences' && record['basePrice'].is_a?(Hash) }
                                                                 .uniq { |record| record['sku'] }.map do |record|
          { merchant: Cereapro::MERCHANT, source_id: record['sku'], label: record['productName'], packaging: record['packagingName'],
            price: record.dig('basePrice', 'currencyAmount').to_f, unit: Fertilizers::Offer.unit(record['unitAbbreviation']) || record['unitAbbreviation'].to_s.downcase,
            url: "#{Cereapro::SITE}/semences/#{record['productSlug']}", negotiated: true, several: false }
        end

        (germineo + cereapro + semence_biologique + agrilisa + la_recolte_offers(day)).uniq { |offer| [offer[:merchant], offer[:source_id]] }
      end

      def reading_row(offer, label, observed_on)
        read = label.read(offer[:label], several: offer[:several])
        # A merchant that prices by the bag says how heavy the bag is
        kilograms = offer.key?(:kilograms) ? offer[:kilograms] : KILOGRAMS[offer[:unit]]

        { 'id' => [offer[:merchant], offer[:source_id], observed_on.iso8601].join('|'), 'species_id' => read.species_id,
          'merchant' => offer[:merchant], 'observed_on' => observed_on.iso8601, 'delivery_postal_code' => PLACE['postal_code'],
          'label' => offer[:label], 'variety' => read.variety, 'organic' => offer[:organic] || read.organic, 'treated' => read.treated,
          'mixture' => read.mixture, 'packaging' => Fertilizers::Offer.packaging(offer[:packaging]), 'price' => offer[:price].round(2),
          'unit' => offer[:unit], 'price_per_kilogram' => kilograms && (offer[:price] / kilograms).round(4),
          'negotiated' => offer[:negotiated], 'source_url' => offer[:url] }
      end

      def usable?(row)
        !row['unit'].to_s.empty? && row['price'].positive? && (row['price_per_kilogram'].nil? || PRICE_RANGE.cover?(row['price_per_kilogram']))
      end

      def previous_readings
        package = Pathname.glob("#{PREVIOUS_PACKAGES}/*/data/registered_seed_price_readings_0.csv.gz").max_by { |file| file.dirname.dirname.basename.to_s.split('.').map(&:to_i) }

        package.nil? ? [] : Zlib::GzipReader.open(package.to_s) { |gz| CSV.parse(gz.read) }.map { |values| READING_COLUMNS.zip(values).to_h }
      end

      def write_csv(file, headers, rows)
        CSV.open(dir.join(file), 'w') do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
  end
end
