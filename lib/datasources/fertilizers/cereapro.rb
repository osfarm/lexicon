# frozen_string_literal: true

require 'json'

module Datasources
  class Fertilizers
    # Reads the catalogue page of Cereapro, a purchasing group. Once a place of delivery is known, the
    # page carries its offers as data, with their delivered price: the ones a visitor sees.
    module Cereapro
      MERCHANT = 'cereapro'
      SITE = 'https://appro-cereapro.com'
      KINDS = { 'engrais' => 'mineral', 'engrais-organiques' => 'organic', 'amendement' => 'amendment',
                'engrais-foliaires' => 'foliar' }.freeze
      NUTRIENTS = { nitrogen: 'azote', phosphorus: 'phosphore', potassium: 'potasse', sulfur: 'soufre',
                    magnesium: 'magnesium' }.freeze
      PAYLOAD = /self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)/.freeze
      OFFER_START = '{"localisation":'

      # @param [String] html
      # @return [Array<Offer>] the offers of fertilisers and amendments that carry a price
      def self.offers(html)
        records(html).select { |record| KINDS.key?(record['productType']) && record['basePrice'].is_a?(Hash) }
                     .uniq { |record| record['sku'] }
                     .map { |record| offer(record) }
      end

      # The page streams its data as pieces of text: offers are the objects starting with their place.
      # Positions are counted in bytes: every character that matters here is one byte, and a text of a
      # million characters is not walked again for each of them.
      def self.records(html)
        text = html.scan(PAYLOAD).map { |(piece)| JSON.parse(%("#{piece}")) }.join.b
        references = references(text)
        found = []
        from = 0
        while (start = text.index(OFFER_START, from))
          finish = closing(text, start)
          break if finish.nil?

          found << resolve(JSON.parse(text[start..finish].force_encoding(Encoding::UTF_8)), references)
          from = finish
        end

        # The same offer comes several times, complete or not: the complete one first
        found.sort_by { |record| record['basePrice'].is_a?(Hash) && record['compositionEngrais'].is_a?(Hash) ? 0 : 1 }
      rescue JSON::ParserError
        []
      end

      # A value may be written apart, on a line of its own, and named by "$" and the mark of that line
      def self.references(text)
        text.scan(/^([0-9a-f]+):(\{.*\})$/).each_with_object({}) do |(mark, json), found|
          found["$#{mark}"] = JSON.parse(json.dup.force_encoding(Encoding::UTF_8))
        rescue JSON::ParserError
          next
        end
      end

      def self.resolve(record, references)
        record.transform_values do |value|
          found = value.is_a?(String) ? references[value] : value
          found.is_a?(Hash) ? found.transform_values { |inner| inner.is_a?(String) && references[inner] ? references[inner] : inner } : (found || value)
        end
      end

      # @return [Integer, nil] index of the brace closing the object opened at `start`
      def self.closing(text, start)
        depth = 0
        in_string = false
        escaped = false
        (start...text.bytesize).each do |index|
          char = text[index]
          if in_string
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == '"'
              in_string = false
            end
          elsif char == '"'
            in_string = true
          elsif char == '{'
            depth += 1
          elsif char == '}'
            depth -= 1
            return index if depth.zero?
          end
        end

        nil
      end

      def self.offer(record)
        Offer.new(
          merchant: MERCHANT, source_id: record['sku'], product_ref: record['productSlug'], name: record['productName'], kind: KINDS[record['productType']],
          category: record['categoryName'], packaging: Offer.packaging(record['packagingName']),
          unit: Offer.unit(record['unitAbbreviation']), price: record.dig('basePrice', 'currencyAmount').to_f,
          delivery_from: date(record.dig('period', 'start')), delivery_to: date(record.dig('period', 'end')),
          origin: record['origin'].to_s.strip.downcase, composition: composition(record['compositionEngrais']),
          url: "#{SITE}/#{record['productType']}/#{record['productSlug']}", negotiated: true
        )
      end

      def self.composition(values)
        return {} unless values.is_a?(Hash)

        NUTRIENTS.transform_values { |key| values[key].to_f }.reject { |_, value| value.zero? }
      end

      # "$D2026-10-01T00:00:00.000Z"
      def self.date(value)
        text = value.to_s[/\d{4}-\d{2}-\d{2}/]

        text && Date.iso8601(text)
      end
    end
  end
end
