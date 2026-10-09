# frozen_string_literal: true

require 'test_helper'

module Datasources
  class SeedsMerchantsTest < Minitest::Test
    def test_semence_biologique_price_is_the_one_of_the_only_bag_on_order
      products = [
        product(1, 'Grand épeautre Martongold &#8211; R2', 4375, %w[sac-de-25kg], ['Céréales à paille']),
        product(2, 'Pois PANDORA', 5950, %w[sac-de-25kg sac-de-500kg], ['Pois']),
        product(3, 'Mélange BIOMAX', 9000, %w[sac-de-20kg], ['Nos mélanges']),
        product(4, 'Sur devis', 0, %w[sac-de-25kg], ['Pois'])
      ]

      offers = Seeds::SemenceBiologique.offers(JSON.generate(products))

      assert_equal %w[1 2 3], offers.map { |offer| offer[:source_id] }
      assert_equal ['Grand épeautre Martongold - R2', 43.75, 'bag', 25.0, true, false, false],
                   offers[0].values_at(:label, :price, :unit, :kilograms, :organic, :negotiated, :several)
      assert_nil offers[1][:kilograms], 'two bags on order: the price says nothing of the kilogram'
      assert offers[2][:several]
    end

    def test_semence_biologique_answer_that_is_not_a_list_gives_nothing
      assert_empty Seeds::SemenceBiologique.offers('<html>Maintenance</html>')
    end

    def test_agrilisa_products_show_their_price_per_kilogram
      html = <<~HTML
        <div id="listwrapper" class="productlist">
        <div class="product"> <div class="pltitle"> <h2> <a href="/Catalogue/Fiche/catid/804/eid/191/trefle-alexandrie">TREFLE ALEXANDRIE</a> </h2>
          <div class="plextra"> <span>Conditionnement : </span>SAC DE 25 KG <span> - Prix au kg : </span>4.88€ HT </div> </div>
          <span class="ht">122,00€<small> HT</small></span> </div>
        <div class="product"> <div class="pltitle"> <h2> <a href="/Catalogue/Fiche/catid/804/eid/300/melange">MELANGE PRAIRIE LONGUE DUREE</a> </h2>
          <div class="plextra"> <span>Conditionnement : </span>SAC DE 15 KG <span> - Prix au kg : </span>6,10€ HT </div> </div> </div>
        <div class="product"> <div class="pltitle"> <h2> <a href="/Catalogue/Fiche/catid/804/eid/301/x">SANS PRIX</a> </h2> </div> </div>
        <!-- Product List Footer -->
      HTML

      offers = Seeds::Agrilisa.offers(html, organic: false)

      assert_equal 2, offers.size
      assert_equal ['agrilisa', '191', 'TREFLE ALEXANDRIE', 'SAC DE 25 KG', 4.88, 'kilogram', 1.0, false, false],
                   offers[0].values_at(:merchant, :source_id, :label, :packaging, :price, :unit, :kilograms, :organic, :several)
      assert_equal [6.1, true], offers[1].values_at(:price, :several)
      assert(Seeds::Agrilisa.offers(html, organic: true).all? { |offer| offer[:organic] })
    end

    def test_la_recolte_lists_give_the_price_of_a_bag_and_product_pages_its_weight
      html = <<~HTML
        <article data-id-product="110620" data-id-product-attribute="0" class="product-miniature js-product-miniature" >
          <p class="h3 product-title" itemprop="name"> <a href="https://www.larecolte.fr/les-legumineuses/110620-vesuvio.html" class="thumbnail">Semence de féverole de printemps moyen PMG - VESUVIO</a></p>
          <span itemprop="price" class="price">1&nbsp;036,25 € HT</span>
        </article>
        <article data-id-product="5" class="product-miniature" >
          <p class="h3 product-title" itemprop="name"> <a href="https://www.larecolte.fr/x/5-drone.html">Prestation de semis de couverts par drone</a></p>
          <span itemprop="price" class="price">30,00 € HT</span>
        </article>
        <article data-id-product="6" class="product-miniature" >
          <p class="h3 product-title" itemprop="name"> <a href="https://www.larecolte.fr/x/6-ttc.html">Semence de phacélie</a></p>
          <span itemprop="price" class="price">30,00 € TTC</span>
        </article>
        <a href="?page=2">2</a>
      HTML

      cards = Seeds::LaRecolte.cards(html)

      assert_equal [['110620', 'Semence de féverole de printemps moyen PMG - VESUVIO', 1036.25]], cards.map { |card| [card.id, card.name, card.price] }
      assert Seeds::LaRecolte.next_page?(html, 1)
      assert_in_delta 25.0, Seeds::LaRecolte.kilograms('<script>var kg = 3 kg;</script><dt>Conditionnement</dt><dd>Sac de 25 kg</dd>')
      assert_in_delta 12.5, Seeds::LaRecolte.kilograms('<p>Conditionnement : seau de 12,5 kg</p>')
      assert_nil Seeds::LaRecolte.kilograms('<p>Dose de semis : 80 kg/ha</p>')
    end

    def test_name_all_in_capitals_gives_the_species_but_no_variety
      label = Seeds::Label.new([{ 'id' => 'trefle_alexandrie', 'pattern' => 'trefle (d.)?alexandrie' }, { 'id' => 'trefle_blanc', 'pattern' => 'trefle blanc' }])

      assert_equal ['trefle_alexandrie', nil], label.read('TREFLE ALEXANDRIE').to_a.first(2)
      assert_equal ['trefle_blanc', nil], label.read('TREFLE BLANC NAIN HUIA').to_a.first(2)
    end

    private

      def product(id, name, cents, bags, categories)
        { id: id, name: name, permalink: "https://www.semence-biologique.fr/produit/#{id}/",
          prices: { price: cents.to_s, currency_minor_unit: 2 },
          variations: bags.map { |bag| { attributes: [{ name: 'Choisissez votre conditionnement', value: bag }] } },
          categories: categories.map { |category| { name: category } } }
      end
  end
end
