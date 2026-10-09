# frozen_string_literal: true

require 'cgi'

module Datasources
  class Seeds
    # Reads a category page of Agrilisa, an online shop: each product shows its bag and its price per kilogram.
    module Agrilisa
      MERCHANT = 'agrilisa'
      SITE = 'https://www.agrilisa.com'
      # Categories of seeds, by their number; the ones of organic seeds apart
      CATEGORIES = [804, 47_816, 1767, 1771, 1773, 1775, 1779, 1781, 1783, 1785, 1787, 1789, 1791, 5004, 65_057].freeze
      ORGANIC_CATEGORIES = [819, 1914, 1918, 1922, 1926, 1928, 1930, 1934, 47_826].freeze
      PRODUCT = %r{<div class="product">[\s\S]*?(?=<div class="product">|<!-- Product List Footer|\z)}.freeze
      MIXTURES = /m[ée]lange|prairie|couvert/i.freeze

      # @param [String] html
      # @param [Boolean] organic whether the category is one of organic seeds
      # @return [Array<Hash>] offers in the shape `Seeds` expects
      def self.offers(html, organic:)
        html.scan(PRODUCT).map { |product| offer(product, organic) }.compact
      end

      def self.offer(product, organic)
        link = product.match(%r{<h2>\s*<a href="([^"]+)">([\s\S]*?)</a>})
        per_kilogram = text(product)[/Prix au kg\s*:\s*([\d.,]+)\s*€\s*HT/i, 1]
        return nil if link.nil? || per_kilogram.nil?

        name = text(link[2])
        { merchant: MERCHANT, source_id: link[1][%r{/eid/(\d+)}, 1], label: name,
          packaging: text(product)[/Conditionnement\s*:\s*(.*?)\s*-\s*Prix/i, 1], price: per_kilogram.tr(',', '.').to_f, unit: 'kilogram',
          kilograms: 1.0, url: "#{SITE}#{link[1]}", negotiated: false, organic: organic || name.match?(/\b(UAB|BIO)\b/i),
          several: name.match?(MIXTURES) }
      end

      def self.text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
      end
    end
  end
end
