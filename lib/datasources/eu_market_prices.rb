module Datasources
  class EuMarketPrices < Base
    description 'Europe market prices'
    credits name: 'Index des prix agricoles UE', url: "https://agridata.ec.europa.eu/extensions/DataPortal/agricultural_markets.html#", provider: "European Union", licence: "", licence_url: "", updated_at: "2024-02-22"
    # EUROPA API
    # DOC on https://agridata.ec.europa.eu/extensions/DataPortal/API_Documentation.html
    EUROPA_BASE_URL = "https://ec.europa.eu/agrifood/api/cereal/prices"

    # EUROPA_PARAMETERS = "?memberStateCodes=FR"

    EUROPA_PRODUCT_CODE = { 'AVO' => :avena_sativa,
                            'BLTFOUR' => :triticum_aestivum,
                            'BLTPAN' => :triticum_aestivum,
                            'DUR' => :triticum_durum,
                            'MAI' => :zea_mays,
                            'ORGBRASS' => :hordeum_vulgare,
                            'ORGFOUR' => :hordeum_vulgare,
                            'SEGPAN' => :secale_cereale,
                            'SEGFOUR' => :secale_cereale,
                            'TRI' => :x_triticosecale
                          }.freeze

    TRANSCODE_EUROPA_UNIT = { 'TONNES' => :ton }.freeze

    def self.table_definitions(builder)
      builder.table :registered_eu_market_prices, sql: <<-SQL
        CREATE TABLE registered_eu_market_prices (
          id character varying PRIMARY KEY NOT NULL,
          nature character varying,
          category character varying,
          specie character varying,
          production_reference_name character varying,
          sector_code character varying,
          product_code character varying,
          product_label character varying,
          product_description character varying,
          unit_value integer,
          unit_name character varying,
          country character varying,
          price numeric(8,2),
          start_date date,
          end_date date
        );

        CREATE INDEX registered_eu_market_prices_id ON registered_eu_market_prices(id);
        CREATE INDEX registered_eu_market_prices_category ON registered_eu_market_prices(category);
        CREATE INDEX registered_eu_market_prices_sector_code ON registered_eu_market_prices(sector_code);
        CREATE INDEX registered_eu_market_prices_product_code ON registered_eu_market_prices(product_code);
      SQL
    end

    def normalize
      EUROPA_PRODUCT_CODE.each do |code, specie|
        logger.debug  "EUROPA SQL insert for #{specie}..."
        url = EUROPA_BASE_URL + "?productCodes=#{code}"
        logger.debug "#{url}"
        begin
          call = RestClient.get url
        rescue RestClient::ExceptionWithResponse => e
          logger.debug e.response
        end
        if call && call.code == 200
          response = JSON.parse(call.body).map(&:deep_symbolize_keys)
          response.each do |item|
            next if item[:price].nil?
            query <<-SQL
              INSERT INTO registered_eu_market_prices (id, nature, specie,
                category, sector_code, product_code, product_label,
                product_description, unit_value, unit_name, country, price, start_date, end_date)
                VALUES (
                  '#{code + '_' + item[:memberStateCode] + '_' + Date.parse(item[:beginDate]).to_s}',
                  'eu_price',
                  '#{specie.to_s}',
                  'Vegetal Products',
                  'CER',
                  '#{code}',
                  '#{item[:productName] + ' ' + item[:marketName].delete("'")}',
                  '#{item[:stageName]}',
                  1,
                  '#{TRANSCODE_EUROPA_UNIT[item[:unit]]}',
                  '#{item[:memberStateCode]}',
                  '#{item[:price].delete("^0-9^,^.").to_f}',
                  TO_DATE('#{item[:beginDate]}', 'DD/MM/YYYY'),
                  TO_DATE('#{item[:endDate]}', 'DD/MM/YYYY'))
              ON CONFLICT DO NOTHING
            SQL
          end
        else
          logger.debug  "Error when calling API for #{specie}..."
        end
      end
    end

  end
end
