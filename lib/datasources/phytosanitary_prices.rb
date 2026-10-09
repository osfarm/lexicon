# frozen_string_literal: true

require 'csv'
require 'zlib'

module Datasources
  # Prices of plant protection products, read every week in the offers of Cereapro, a purchasing group, for
  # the places of delivery of `fertilizers`. An offer is tied to a marketing authorisation of E-Phy through
  # the names of the products it stands for. Readings add up week after week.
  class PhytosanitaryPrices < Base
    description "Prix des produits phytosanitaires : offres relevées chaque semaine chez un groupement d'achats, rattachées à un numéro d'AMM, et prix mensuel"
    credits name: 'Catalogue des offres Cereapro',
            url: 'https://appro-cereapro.com/catalogue',
            provider: 'Cereapro',
            licence: 'Réutilisation avec attribution',
            licence_url: 'https://appro-cereapro.com',
            updated_at: '2026-10-07'
    credits name: 'Catalogue E-Phy : noms des produits autorisés',
            url: 'https://www.data.gouv.fr/fr/datasets/donnees-ouvertes-du-catalogue-e-phy-des-produits-phytopharmaceutiques-matieres-fertilisantes-et-supports-de-culture-adjuvants-produits-mixtes-et-melanges/',
            provider: 'ANSES',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-09-29'

    schema_revision 1
    # Prices name the merchant that shows them: they are served to the members of OSFarm only
    scope :members
    source_date 'SELECT max(observed_on) FROM registered_phytosanitary_price_readings'
    pivot :amm, table: :registered_phytosanitary_price_readings, column: :product_id

    Cereapro = Fertilizers::Cereapro
    USER_AGENT = Fertilizers::USER_AGENT
    EPHY_URL = PhytosanitarySubstances::EPHY_URL
    PAUSE = 1
    UNITS = { 'l' => 'liter', 'kg' => 'kilogram' }.freeze
    # Euros per litre or per kilogram outside of which a price is a mistake of reading
    PRICE_RANGE = (0.5..2000.0).freeze
    MINIMUM_OFFERS = 10
    PREVIOUS_PACKAGES = 'out/packages/phytosanitary_prices'
    READING_COLUMNS = %w[id product_id merchant observed_on delivery_postal_code label reference_name stands_for active_substances
                         category packaging price unit negotiated source_url].freeze

    def collect
      day = dir.join(Date.today.iso8601)
      day.mkpath
      fetch(day.join('ephy.zip'), EPHY_URL)
      places.each { |place| collect_cereapro(day, place) }
    end

    def load
      readings = previous_readings.to_h { |row| [row['id'], row] }
      days = dir.children.select { |child| child.directory? && child.basename.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.sort
      raise "No collection in #{dir}: run the collect phase first" if days.empty?

      days.each do |day|
        rows = rows_of(day)
        raise "#{rows.size} priced offers on #{day.basename}, at least #{MINIMUM_OFFERS} expected" if day == days.last && rows.size < MINIMUM_OFFERS

        rows.each { |row| readings[row['id']] = row }
      end

      CSV.open(dir.join('readings.csv'), 'w') do |csv|
        csv << READING_COLUMNS
        readings.each_value { |row| csv << row.values_at(*READING_COLUMNS) }
      end
      load_csv(dir.join('readings.csv'), 'readings')
    end

    def self.table_definitions(builder)
      builder.table(:registered_phytosanitary_price_readings, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_price_readings (
          id character varying PRIMARY KEY NOT NULL,
          product_id integer,
          merchant character varying NOT NULL,
          observed_on date NOT NULL,
          delivery_postal_code character varying NOT NULL,
          label character varying NOT NULL,
          reference_name character varying,
          stands_for text[],
          active_substances text[],
          category character varying,
          packaging character varying,
          price numeric(10,2) NOT NULL,
          unit character varying NOT NULL,
          negotiated boolean NOT NULL,
          source_url character varying
        );
        CREATE INDEX registered_phytosanitary_price_readings_product_id ON registered_phytosanitary_price_readings (product_id, observed_on);
      SQL

      builder.table(:registered_phytosanitary_monthly_prices, sql: <<~SQL)
        CREATE TABLE registered_phytosanitary_monthly_prices (
          id character varying PRIMARY KEY NOT NULL,
          product_id integer NOT NULL,
          month date NOT NULL,
          price numeric(10,2) NOT NULL,
          unit character varying NOT NULL,
          merchant character varying NOT NULL,
          negotiated boolean NOT NULL,
          observations integer NOT NULL,
          last_observed_on date NOT NULL
        );
        CREATE INDEX registered_phytosanitary_monthly_prices_product_id ON registered_phytosanitary_monthly_prices (product_id, month);
      SQL
    end

    def normalize
      array = ->(column) { "CASE WHEN #{column} = '' THEN NULL ELSE string_to_array(#{column}, '|') END" }

      query <<~SQL
        INSERT INTO registered_phytosanitary_price_readings
          SELECT id, NULLIF(product_id, '')::integer, merchant, observed_on::date, delivery_postal_code, label,
                 NULLIF(reference_name, ''), #{array.call('stands_for')}, #{array.call('active_substances')}, NULLIF(category, ''),
                 NULLIF(packaging, ''), price::numeric, unit, negotiated::boolean, NULLIF(source_url, '')
            FROM #{name}.readings ORDER BY observed_on, id
      SQL
      # The price of an authorisation for a month: the average of what was read for it, all places and packagings together
      query <<~SQL
        INSERT INTO registered_phytosanitary_monthly_prices
          SELECT product_id || '_' || unit || '_' || to_char(date_trunc('month', observed_on), 'YYYY-MM'), product_id,
                 date_trunc('month', observed_on)::date, round(avg(price), 2), unit, min(merchant), bool_and(negotiated), count(*),
                 max(observed_on)
            FROM registered_phytosanitary_price_readings
           WHERE product_id IS NOT NULL
           GROUP BY product_id, unit, date_trunc('month', observed_on)
           ORDER BY 3, 2
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

      # The page of Cereapro holds its whole catalogue: the one `fertilizers` fetched the same day is taken
      def collect_cereapro(day, place)
        file = day.join("cereapro_#{place['postal_code']}.html")
        already = Pathname.new("raw/fertilizers/#{day.basename}/#{file.basename}")
        return FileUtils.cp(already, file) if !file.size? && already.size?

        session = CGI.escape(JSON.generate(codeInsee: place['insee_code']))
        fetch(file, "#{Cereapro::SITE}/catalogue", "-H 'Cookie: __client_session=#{session}'")
      end

      def rows_of(day)
        products = products_of(day)
        observed_on = day.basename.to_s

        places.flat_map do |place|
          file = day.join("cereapro_#{place['postal_code']}.html")
          records = (file.size? ? Cereapro.records(file.read) : []).select { |record| record['productType'] == 'phytos' && record['basePrice'].is_a?(Hash) }

          records.uniq { |record| record['sku'] }.map { |record| row(record, place, observed_on, products) }.select { |row| usable?(row) }
        end
      end

      # The names of E-Phy as they were on the day of the collection, or failing that the latest ones kept
      def products_of(day)
        archive = [day.join('ephy.zip'), *Pathname.glob(dir.join('*/ephy.zip')).sort.reverse].find(&:size?)
        raise "No ephy.zip in #{dir}: run the collect phase first" if archive.nil?

        unzip(archive, dir.join('ephy'))
        Products.new(CSV.read(dir.join('ephy', 'produits_utf8.csv'), col_sep: ';', headers: true, quote_char: "\x00", encoding: 'bom|utf-8').map(&:to_h))
      end

      def row(record, place, observed_on, products)
        stands_for = Array(record['alternativeNames']).map { |name| name['name'] }
        number, reference_name = products.find([record['productName'], *stands_for])
        substances = Array(record['activeIngredients']).map { |substance| [substance['variant'], substance['amount'], substance['unit']].compact.join(' ') }

        { 'id' => [Cereapro::MERCHANT, record['sku'], place['postal_code'], observed_on].join('|'), 'product_id' => number,
          'merchant' => Cereapro::MERCHANT, 'observed_on' => observed_on, 'delivery_postal_code' => place['postal_code'],
          'label' => record['productName'], 'reference_name' => reference_name, 'stands_for' => stands_for.join('|'),
          'active_substances' => substances.join('|'), 'category' => record['categoryName'],
          'packaging' => Fertilizers::Offer.packaging(record['packagingName']), 'price' => record.dig('basePrice', 'currencyAmount').to_f.round(2),
          'unit' => UNITS[record['unitAbbreviation'].to_s.downcase], 'negotiated' => true,
          'source_url' => "#{Cereapro::SITE}/phytos/#{record['productSlug']}" }
      end

      # Prices by the litre or the kilogram only: a price by the flask or the dose compares with nothing
      def usable?(row)
        !row['unit'].nil? && PRICE_RANGE.cover?(row['price'])
      end

      def previous_readings
        package = Pathname.glob("#{PREVIOUS_PACKAGES}/*/data/registered_phytosanitary_price_readings_0.csv.gz")
                          .max_by { |file| file.dirname.dirname.basename.to_s.split('.').map(&:to_i) }
        return [] if package.nil?

        Zlib::GzipReader.open(package.to_s) { |gz| CSV.parse(gz.read) }.map do |values|
          READING_COLUMNS.zip(values).to_h.tap { |row| %w[stands_for active_substances].each { |column| row[column] = row[column].to_s.delete('{}"').tr(',', '|') } }
        end
      end
  end
end
