# frozen_string_literal: true

require 'cgi'

module Datasources
  class Seeds
    # Reads La Récolte, an online shop. Its lists give the price of a bag; how heavy the bag is stands in
    # the page of each product, which is read once and kept.
    module LaRecolte
      MERCHANT = 'la_recolte'
      SITE = 'https://www.larecolte.fr'
      # Cover crops and forage seeds: the category holds every seed the shop sells
      CATEGORY = '2293-couverts-vegetaux'
      MINIATURE = %r{<article[^>]*class="[^"]*product-miniature[\s\S]*?</article>}.freeze
      SEED = /\A(semences?|m[ée]lange)\b/i.freeze
      BAG = /Conditionnement\s*(?:Sac|Big.?bag|Seau|Carton|Bo[iî]te)?\D{0,15}(\d+(?:[.,]\d+)?)\s*kg/i.freeze

      Card = Struct.new(:id, :name, :url, :price, keyword_init: true)

      # @param [String] html a page of the category
      # @return [Array<Card>] the products that show a price before tax
      def self.cards(html)
        html.scan(MINIATURE).map do |miniature|
          link = miniature.match(%r{<p class="h3 product-title"[^>]*>\s*<a href="([^"]+)"[^>]*>([\s\S]*?)</a>})
          price = text(miniature[%r{<span itemprop="price"[^>]*>([\s\S]*?)</span>}, 1])
          # The category also holds lawn seed, services and training days
          next if link.nil? || !price.match?(/HT/i) || !text(link[2]).match?(SEED)

          Card.new(id: miniature[/data-id-product="(\d+)"/, 1], name: text(link[2]), url: link[1],
                   price: price[/[\d\s.,]*\d/].to_s.gsub(/\s/, '').tr(',', '.').to_f)
        end.compact
      end

      # @return [Boolean]
      def self.next_page?(html, page)
        html.match?(MINIATURE) && html.include?("page=#{page + 1}")
      end

      # @param [String] html the page of a product
      # @return [Float, nil] kilograms in the bag the price is for
      def self.kilograms(html)
        text(html.gsub(%r{<(script|style)[\s\S]*?</\1>}, ' '))[BAG, 1]&.tr(',', '.')&.to_f
      end

      def self.text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ' ').gsub(/&nbsp;|&#160;|&#8239;/, ' ')).gsub(/[\s  ]+/, ' ').strip
      end
    end
  end
end
