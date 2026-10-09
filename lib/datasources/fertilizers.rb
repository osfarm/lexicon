# frozen_string_literal: true

require 'csv'
require 'zlib'

module Datasources
  # Fertilisers and amendments sold to French farms, with the delivered prices two merchants show every
  # week for five places, the monthly price drawn from them and the value of a kilogram of nitrogen,
  # phosphorus, potassium and sulphur. Readings add up week after week: the ones of the previous package
  # and the pages kept in `raw/fertilizers/` are read again at each build.
  class Fertilizers < Base
    description 'Engrais et amendements : composition, prix livrés relevés chaque semaine chez des marchands, prix mensuel et valeur des unités fertilisantes'
    credits name: 'Catalogue des offres Cereapro',
            url: 'https://appro-cereapro.com/catalogue',
            provider: 'Cereapro',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://appro-cereapro.com',
            updated_at: '2026-10-07'
    credits name: 'Catalogue Germineo',
            url: 'https://www.germineo.com/fertilisants-2',
            provider: 'Germineo',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://www.germineo.com',
            updated_at: '2026-10-07'

    schema_revision 1
    # Prices name the merchants that show them: they are served to the members of OSFarm only
    scope :members
    source_date 'SELECT max(observed_on) FROM registered_fertilizer_price_readings'
    pivot :variant, table: :registered_fertilizers, column: :variant_reference_name

    USER_AGENT = 'Lexicon OSFarm (+https://lexicon.osfarm.org)'
    # Seconds between two requests to a merchant
    PAUSE = 1
    MAXIMUM_PAGES = 10
    # Euros per tonne outside of which a price is a mistake of reading
    PRICE_RANGE = (20.0..5000.0).freeze
    # Fewer priced offers than that for a merchant, all places together, and its collection is set aside
    MINIMUM_OFFERS = { Cereapro::MERCHANT => 100, Germineo::MERCHANT => 100 }.freeze
    PREVIOUS_PACKAGES = 'out/packages/fertilizers'
    READING_COLUMNS = %w[id fertilizer_id merchant observed_on delivery_postal_code packaging delivery_from delivery_to price
                         unit negotiated origin source_label source_url].freeze
    FERTILIZER_COLUMNS = %w[id name kind nitrogen phosphorus potassium sulfur magnesium calcium variant_reference_name merchants].freeze

    # One directory per day of collection. A page already there is not asked for again.
    def collect
      day = dir.join(Date.today.iso8601)
      day.mkpath

      places.each do |place|
        collect_cereapro(day, place)
        collect_germineo(day, place)
      end
    end

    # Reads every collection kept, checks the latest, and computes everything before loading anything
    def load
      catalog = Catalog.new(simple: CSV.read('data/fertilizers/simple_fertilizers.csv', headers: true).map(&:to_h),
                            variants: CSV.read('data/variants/variants - fertilizers.csv', headers: true).map(&:to_h))
      fertilizers = previous_rows('registered_fertilizers', FERTILIZER_COLUMNS).to_h { |row| [row['id'], row] }
      readings = previous_rows('registered_fertilizer_price_readings', READING_COLUMNS).to_h { |row| [row['id'], row] }

      days = dir.children.select { |child| child.directory? && child.basename.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.sort
      raise "No collection in #{dir}: run the collect phase first" if days.empty?

      days.each do |day|
        offers = offers_of(day, check: day == days.last)
        offers.each do |place, offer|
          product = catalog.product(offer)
          fertilizers[product.id] = fertilizer_row(product, offer, fertilizers[product.id])
          reading = reading_row(product, offer, place, Date.iso8601(day.basename.to_s))
          readings[reading['id']] = reading
        end
      end

      write_tables(fertilizers.values, readings.values)
    end

    def self.table_definitions(builder)
      builder.table(:registered_fertilizers, sql: <<~SQL)
        CREATE TABLE registered_fertilizers (
          id character varying PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          kind character varying NOT NULL,
          nitrogen numeric(6,2),
          phosphorus numeric(6,2),
          potassium numeric(6,2),
          sulfur numeric(6,2),
          magnesium numeric(6,2),
          calcium numeric(6,2),
          variant_reference_name character varying,
          merchants text[]
        );
        CREATE INDEX registered_fertilizers_kind ON registered_fertilizers (kind);
      SQL

      fertilizer = { fertilizer_id: %i[registered_fertilizers id] }
      builder.table(:registered_fertilizer_price_readings, sql: <<~SQL).references(**fertilizer)
        CREATE TABLE registered_fertilizer_price_readings (
          id character varying PRIMARY KEY NOT NULL,
          fertilizer_id character varying NOT NULL,
          merchant character varying NOT NULL,
          observed_on date NOT NULL,
          delivery_postal_code character varying NOT NULL,
          packaging character varying,
          delivery_from date,
          delivery_to date,
          price numeric(10,2) NOT NULL,
          unit character varying NOT NULL,
          negotiated boolean NOT NULL,
          origin character varying,
          source_label character varying NOT NULL,
          source_url character varying
        );
        CREATE INDEX registered_fertilizer_price_readings_fertilizer_id ON registered_fertilizer_price_readings (fertilizer_id, observed_on);
      SQL

      builder.table(:registered_fertilizer_monthly_prices, sql: <<~SQL).references(**fertilizer)
        CREATE TABLE registered_fertilizer_monthly_prices (
          id character varying PRIMARY KEY NOT NULL,
          fertilizer_id character varying NOT NULL,
          packaging character varying,
          month date NOT NULL,
          price numeric(10,2) NOT NULL,
          unit character varying NOT NULL,
          merchant character varying NOT NULL,
          negotiated boolean NOT NULL,
          observations integer NOT NULL,
          last_observed_on date NOT NULL
        );
        CREATE INDEX registered_fertilizer_monthly_prices_fertilizer_id ON registered_fertilizer_monthly_prices (fertilizer_id, month);
      SQL

      builder.table(:registered_fertilizer_unit_values, sql: <<~SQL).references(**fertilizer)
        CREATE TABLE registered_fertilizer_unit_values (
          id character varying PRIMARY KEY NOT NULL,
          month date NOT NULL,
          nutrient character varying NOT NULL,
          value numeric(10,4) NOT NULL,
          fertilizer_id character varying NOT NULL,
          packaging character varying NOT NULL,
          price numeric(10,2) NOT NULL,
          merchant character varying NOT NULL
        );
        CREATE INDEX registered_fertilizer_unit_values_month ON registered_fertilizer_unit_values (month, nutrient);
      SQL
    end

    def normalize
      number = ->(column) { "NULLIF(#{column}, '')::numeric" }
      date = ->(column) { "NULLIF(#{column}, '')::date" }

      query <<~SQL
        INSERT INTO registered_fertilizers
          SELECT id, name, kind, #{%w[nitrogen phosphorus potassium sulfur magnesium calcium].map(&number).join(', ')},
                 NULLIF(variant_reference_name, ''), string_to_array(merchants, '|')
            FROM #{name}.fertilizers ORDER BY id
      SQL
      query <<~SQL
        INSERT INTO registered_fertilizer_price_readings
          SELECT id, fertilizer_id, merchant, observed_on::date, delivery_postal_code, NULLIF(packaging, ''),
                 #{date.call('delivery_from')}, #{date.call('delivery_to')}, price::numeric, unit, negotiated::boolean,
                 NULLIF(origin, ''), source_label, NULLIF(source_url, '')
            FROM #{name}.readings ORDER BY observed_on, id
      SQL
      query <<~SQL
        INSERT INTO registered_fertilizer_monthly_prices
          SELECT fertilizer_id || '_' || COALESCE(NULLIF(packaging, ''), 'any') || '_' || unit || '_' || left(month, 7), fertilizer_id,
                 NULLIF(packaging, ''), month::date, price::numeric, unit, merchant, negotiated::boolean, observations::integer,
                 last_observed_on::date
            FROM #{name}.months ORDER BY month, fertilizer_id
      SQL
      query <<~SQL
        INSERT INTO registered_fertilizer_unit_values
          SELECT nutrient || '_' || left(month, 7), month::date, nutrient, value::numeric, fertilizer_id, packaging, price::numeric, merchant
            FROM #{name}.unit_values ORDER BY month, nutrient
      SQL
    end

    private

      def places
        CSV.read('data/fertilizers/delivery_places.csv', headers: true).map(&:to_h)
      end

      def fetch(file, url, options = '')
        return if file.size?

        execute "curl -sSLf --retry 2 -A '#{USER_AGENT}' #{options} -o '#{file}' '#{url}'"
        sleep PAUSE
      end

      # One page holds every offer once the session names the commune of delivery
      def collect_cereapro(day, place)
        session = CGI.escape(JSON.generate(codeInsee: place['insee_code']))

        fetch(day.join("cereapro_#{place['postal_code']}.html"), "#{Cereapro::SITE}/catalogue", "-H 'Cookie: __client_session=#{session}'")
      end

      # The postal code is given once through the form of the shop, then the categories are read page after page
      def collect_germineo(day, place)
        pages = ->(category, page) { day.join("germineo_#{place['postal_code']}_#{category.split('/').last}_#{page}.html") }
        return if Germineo::CATEGORIES.keys.all? { |category| pages.call(category, 1).size? }

        cookies = "-b '#{day.join('germineo_cookies.txt')}' -c '#{day.join('germineo_cookies.txt')}'"
        entry = day.join("germineo_#{place['postal_code']}_entry.html")
        FileUtils.rm_f([entry, day.join('germineo_cookies.txt')])
        fetch(entry, "#{Germineo::SITE}/fertilisants-2", cookies)
        token = entry.size? ? entry.read[/csrf-token" content="([^"]+)"/, 1] : nil
        return if token.nil?

        fetch(day.join("germineo_#{place['postal_code']}_zip.html"), "#{Germineo::SITE}/zip",
              "#{cookies} --data-urlencode '_token=#{token}' --data 'country_id=1&zip=#{place['postal_code']}'")
        Germineo::CATEGORIES.each_key do |category|
          (1..MAXIMUM_PAGES).each do |page|
            file = pages.call(category, page)
            fetch(file, "#{Germineo::SITE}/#{category}?page=#{page}", cookies)
            break unless file.size? && Germineo.next_page?(file.read, page)
          end
        end
      end

      # @return [Array<Array(Hash, Offer)>] offers of the day with their place. A merchant whose collection of
      #   the day is doubtful is set aside; the build stops when none is left
      def offers_of(day, check:)
        by_merchant = {
          Cereapro::MERCHANT => places.flat_map do |place|
            file = day.join("cereapro_#{place['postal_code']}.html")
            file.size? ? Cereapro.offers(file.read).map { |offer| [place, offer] } : []
          end,
          Germineo::MERCHANT => places.flat_map do |place|
            Germineo::CATEGORIES.flat_map do |category, kind|
              Pathname.glob(day.join("germineo_#{place['postal_code']}_#{category.split('/').last}_*.html")).sort.flat_map do |file|
                Germineo.offers(file.read, kind: kind).map { |offer| [place, offer] }
              end
            end
          end
        }
        usable = by_merchant.transform_values { |offers| offers.select { |_, offer| usable?(offer) }.uniq { |place, offer| [place['postal_code'], offer.source_id, offer.packaging, offer.delivery_from] } }
        return usable.values.flatten(1) unless check

        doubtful = usable.select { |merchant, offers| offers.size < MINIMUM_OFFERS.fetch(merchant) }
        doubtful.each { |merchant, offers| logger.warn("#{merchant}: #{offers.size} priced offers on #{day.basename}, at least #{MINIMUM_OFFERS.fetch(merchant)} expected: set aside") }
        raise "No merchant gave enough offers on #{day.basename}: #{usable.transform_values(&:size)}" if doubtful.size == usable.size

        usable.reject { |merchant, _| doubtful.key?(merchant) }.values.flatten(1)
      end

      # A price by the tonne or by the litre, within what a fertiliser costs
      def usable?(offer)
        !offer.unit.nil? && !offer.price.nil? && (offer.unit != 'ton' || PRICE_RANGE.cover?(offer.price)) && offer.price.positive? &&
          (offer.price - 999.99).abs > 0.001
      end

      def fertilizer_row(product, offer, known)
        merchants = ((known ? known['merchants'].to_s.split('|') : []) | [offer.merchant]).sort
        composition = product.composition.empty? && known ? Catalog::NUTRIENTS.to_h { |nutrient| [nutrient, known[nutrient.to_s]] } : product.composition

        { 'id' => product.id, 'name' => product.name, 'kind' => product.kind,
          **Catalog::NUTRIENTS.to_h { |nutrient| [nutrient.to_s, composition[nutrient]] },
          'variant_reference_name' => product.variant, 'merchants' => merchants.join('|') }
      end

      def reading_row(product, offer, place, observed_on)
        id = [offer.merchant, offer.source_id, offer.packaging, place['postal_code'], observed_on.iso8601].compact.join('|')

        { 'id' => id, 'fertilizer_id' => product.id, 'merchant' => offer.merchant, 'observed_on' => observed_on.iso8601,
          'delivery_postal_code' => place['postal_code'], 'packaging' => offer.packaging, 'delivery_from' => offer.delivery_from&.iso8601,
          'delivery_to' => offer.delivery_to&.iso8601, 'price' => offer.price.round(2), 'unit' => offer.unit,
          'negotiated' => offer.negotiated, 'origin' => offer.origin, 'source_label' => offer.name, 'source_url' => offer.url }
      end

      # Rows of a table in the latest package: what was published is not lost when the pages of a past week are
      def previous_rows(table, columns)
        package = Pathname.glob("#{PREVIOUS_PACKAGES}/*/data/#{table}_0.csv.gz").max_by { |file| file.dirname.dirname.basename.to_s.split('.').map(&:to_i) }
        return [] if package.nil?

        Zlib::GzipReader.open(package.to_s) { |gz| CSV.parse(gz.read) }.map do |values|
          columns.zip(values).to_h.tap { |row| row['merchants'] = row['merchants'].to_s.delete('{}"').tr(',', '|') if row.key?('merchants') }
        end
      end

      def write_tables(fertilizers, readings)
        pricing = Pricing.new
        months = pricing.monthly(readings.map { |row| pricing_reading(row) })
        unit_values = pricing.unit_values(months)

        write_csv('fertilizers.csv', FERTILIZER_COLUMNS, fertilizers.map { |row| row.values_at(*FERTILIZER_COLUMNS) })
        write_csv('readings.csv', READING_COLUMNS, readings.map { |row| row.values_at(*READING_COLUMNS) })
        write_csv('months.csv', Pricing::Monthly.members.map(&:to_s), months.map(&:to_a))
        write_csv('unit_values.csv', Pricing::UnitValue.members.map(&:to_s), unit_values.map(&:to_a))
        %w[fertilizers readings months unit_values].each { |table| load_csv(dir.join("#{table}.csv"), table) }
      end

      def pricing_reading(row)
        Pricing::Reading.new(
          fertilizer_id: row['fertilizer_id'], merchant: row['merchant'], observed_on: Date.iso8601(row['observed_on'].to_s),
          packaging: row['packaging'].to_s.empty? ? nil : row['packaging'], unit: row['unit'], price: row['price'].to_f,
          delivery_from: row['delivery_from'].to_s.empty? ? nil : Date.iso8601(row['delivery_from'].to_s),
          negotiated: [true, 'true', 't'].include?(row['negotiated'])
        )
      end

      def write_csv(file, headers, rows)
        CSV.open(dir.join(file), 'w') do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
  end
end
