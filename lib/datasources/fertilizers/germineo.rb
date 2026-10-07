# frozen_string_literal: true

require 'cgi'

module Datasources
  class Fertilizers
    # Reads a category page of Germineo, an online shop. Once a country and a postal code are given, each
    # product shows its delivered price, for the packaging the shop puts forward.
    module Germineo
      MERCHANT = 'germineo'
      SITE = 'https://www.germineo.com'
      # Categories read, with the kind of what they hold
      CATEGORIES = {
        'fertilisants/engrais-simples-8' => 'mineral',
        'fertilisants/engrais-binaires-9' => 'mineral',
        'fertilisants/engrais-ternaires-10' => 'mineral',
        'fertilisants/engrais-organiques-12' => 'organic',
        'fertilisants/amendements-14' => 'amendment',
        'fertilisants/engrais-foliaires-474' => 'foliar'
      }.freeze
      NUTRIENTS = [
        [/\Aazote/i, :nitrogen], [/\Aphosphore/i, :phosphorus], [/\Apotasse/i, :potassium], [/\Asoufre/i, :sulfur],
        [/\Amagn[ée]si/i, :magnesium], [/\Acalcium/i, :calcium]
      ].freeze
      UNITS = { 'tonne' => 'ton', 'litre' => 'liter', 'kg' => 'kilogram', 'kilo' => 'kilogram' }.freeze
      ARTICLE = %r{<article class="product-item[\s\S]*?</article>}.freeze

      # @param [String] html
      # @param [String] kind
      # @return [Array<Offer>] the products of the page that show a price
      def self.offers(html, kind:)
        html.scan(ARTICLE).map { |article| offer(article, kind) }.compact
      end

      # @param [String] html
      # @return [Boolean] whether the category goes on after this page. A page past the last one still links
      #   to the next: only a page holding products is followed
      def self.next_page?(html, page)
        html.match?(ARTICLE) && html.include?("page=#{page + 1}")
      end

      def self.offer(article, kind)
        link = article.match(/<a class="clickable-trigger[^"]*"\s+href="([^"]+)"\s+title="([^"]*)"/)
        price = text(article[%r{<span class="tw-font-serif[^"]*">([\s\S]*?)</span>}, 1])[/[\d\s\u00a0\u202f.,]+(?=\s*€)/]
        return nil if link.nil? || price.nil?

        Offer.new(
          merchant: MERCHANT, source_id: link[1][/-(\d+)\z/, 1], product_ref: link[1][/-(\d+)\z/, 1], name: text(link[2]), kind: kind,
          category: link[1].split('/')[-2], packaging: Offer.packaging(text(article[%r{<span class="tw-font-bold">([\s\S]*?)</span>}, 1])),
          unit: UNITS[text(article)[/HT\s+par\s+(\w+)/, 1]], price: number(price), composition: composition(article),
          url: link[1], negotiated: false
        )
      end

      # Rows of the table of contents; the ones starting with a dash detail the row above
      def self.composition(article)
        article.scan(%r{<tr>\s*<td>([\s\S]*?)</td>\s*<td>([\s\S]*?)</td>\s*</tr>}).each_with_object({}) do |(label, value), found|
          nutrient = NUTRIENTS.find { |pattern, _| text(label).match?(pattern) }&.last
          amount = text(value)[/[\d.,]+(?=[^%]*%)/]
          found[nutrient] ||= number(amount) unless nutrient.nil? || amount.nil?
        end
      end

      def self.text(html)
        # Thousands are set apart by a space that does not break, written in several ways
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ' ').gsub(/&nbsp;|&#160;|&#8239;/, ' ')).gsub(/[\s\u00a0\u202f]+/, ' ').strip
      end

      def self.number(value)
        value.to_s.gsub(/[\s\u00a0\u202f]/, '').tr(',', '.').to_f
      end
    end
  end
end
