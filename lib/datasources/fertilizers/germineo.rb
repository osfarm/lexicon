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
      UNITS = { 'tonne' => 'ton', 'litre' => 'liter', 'kg' => 'kilogram', 'kilo' => 'kilogram', 'quintal' => 'quintal',
                'dose' => 'dose' }.freeze
      Card = Struct.new(:id, :name, :url, :price, :unit, :packaging_label, :attributes, keyword_init: true)
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

      # @param [String] html
      # @return [Array<Card>] the products of a page that show a price, whatever they are
      def self.cards(html)
        html.scan(ARTICLE).map { |article| card(article) }.compact
      end

      def self.card(article)
        link = article.match(/<a class="clickable-trigger[^"]*"\s+href="([^"]+)"\s+title="([^"]*)"/)
        # A reduced price follows the one it replaces
        price = text(article[%r{<span class="tw-font-serif[^"]*">([\s\S]*?)</span>}, 1]).scan(/[\d\s\u00a0\u202f.,]*\d(?=\s*€)/).last
        return nil if link.nil? || price.nil?

        Card.new(id: link[1][/-(\d+)\z/, 1], name: text(link[2]), url: link[1], price: number(price),
                 unit: UNITS[text(article)[/HT\s+par\s+(\w+)/, 1]],
                 packaging_label: text(article[%r{<span class="tw-font-bold">([\s\S]*?)</span>}, 1]), attributes: attributes(article))
      end

      # @return [Hash{String => String}] rows of the table of a card: contents of a fertiliser, traits of a variety
      def self.attributes(article)
        article.scan(%r{<tr>\s*<td>([\s\S]*?)</td>\s*<td>([\s\S]*?)</td>\s*</tr>}).to_h { |label, value| [text(label), text(value)] }
      end

      def self.offer(article, kind)
        card = card(article)
        return nil if card.nil?

        Offer.new(
          merchant: MERCHANT, source_id: card.id, product_ref: card.id, name: card.name, kind: kind,
          category: card.url.split('/')[-2], packaging: Offer.packaging(card.packaging_label), unit: card.unit, price: card.price,
          composition: composition(card.attributes), url: card.url, negotiated: false
        )
      end

      # Rows of the table of contents; the ones starting with a dash detail the row above
      def self.composition(attributes)
        attributes.each_with_object({}) do |(label, value), found|
          nutrient = NUTRIENTS.find { |pattern, _| label.match?(pattern) }&.last
          amount = value[/[\d.,]+(?=[^%]*%)/]
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
