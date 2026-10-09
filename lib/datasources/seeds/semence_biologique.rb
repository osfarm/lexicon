# frozen_string_literal: true

require 'cgi'
require 'json'

module Datasources
  class Seeds
    # Reads the catalogue of Semence Biologique (Partner & Co), a shop of organic seeds, as its own site
    # reads it: a list of products with their price before tax and the bag they are sold in.
    module SemenceBiologique
      MERCHANT = 'semence_biologique'
      API = 'https://www.semence-biologique.fr/wp-json/wc/store/v1/products'
      PER_PAGE = 100
      PACKAGING = /conditionnement/i.freeze
      MIXTURES = /m[ée]lange/i.freeze

      # @param [String] json one page of the list of products
      # @return [Array<Hash>] offers in the shape `Seeds` expects. Everything this shop sells is organic.
      def self.offers(json)
        JSON.parse(json).map { |product| offer(product) }.compact
      rescue JSON::ParserError
        []
      end

      def self.offer(product)
        price = product.dig('prices', 'price').to_f / (10**product.dig('prices', 'currency_minor_unit').to_i)
        return nil unless price.positive?

        bags = bags(product)
        { merchant: MERCHANT, source_id: product['id'].to_s, label: CGI.unescapeHTML(product['name'].to_s).tr('–', '-'),
          packaging: bags.size == 1 ? bags.first : nil, price: price, unit: 'bag', kilograms: bags.size == 1 ? kilograms(bags.first) : nil,
          url: product['permalink'], negotiated: false, organic: true,
          several: product['categories'].to_a.any? { |category| category['name'].to_s.match?(MIXTURES) } }
      end

      # The price shown is the one of the bags that can be ordered: it says nothing of the kilogram when there are several
      def self.bags(product)
        ordered = product['variations'].to_a.flat_map { |variation| variation['attributes'].to_a }
                                       .select { |attribute| attribute['name'].to_s.match?(PACKAGING) }.map { |attribute| attribute['value'].to_s }

        ordered.uniq
      end

      # "sac-de-25kg", "big-bag-500-kg"
      def self.kilograms(bag)
        bag[/(\d+(?:[.,]\d+)?)\s*-?\s*kg/i, 1]&.tr(',', '.')&.to_f
      end
    end
  end
end
