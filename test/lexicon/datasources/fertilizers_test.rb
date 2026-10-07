# frozen_string_literal: true

require 'test_helper'

module Datasources
  class FertilizersCatalogTest < Minitest::Test
    Offer = Fertilizers::Offer

    SIMPLE = [
      { 'id' => 'ammonitrate_33_5', 'name' => 'Ammonitrate 33.5', 'pattern' => 'ammonitrate\s*33[.,]5', 'nitrogen' => '33.5', 'variant_reference_name' => 'ammonitrate_33' },
      { 'id' => 'ammonitrate_27', 'name' => 'Ammonitrate 27', 'pattern' => '(ammonitrate|\bcan)\s*27', 'nitrogen' => '27', 'variant_reference_name' => '' },
      { 'id' => 'urea_46_inhibited', 'name' => 'Urée 46 inhibée', 'pattern' => 'uree\s*46.*(inhib|nbpt)', 'nitrogen' => '46', 'variant_reference_name' => '' },
      { 'id' => 'urea_46', 'name' => 'Urée 46', 'pattern' => 'uree\s*46', 'nitrogen' => '46', 'variant_reference_name' => 'urea_46' },
      { 'id' => 'ssp_18', 'name' => 'Superphosphate 18', 'pattern' => 'superphosphate\s*18\b', 'phosphorus' => '18', 'sulfur' => '29', 'variant_reference_name' => 'ssp_18' }
    ].freeze
    VARIANTS = [{ 'reference_name' => '15_15_15_15', 'nitrogen_concentration' => '15', 'phosphorus_concentration' => '15',
                  'potassium_concentration' => '15', 'sulfur_dioxide_concentration' => '15' }].freeze

    def setup
      @catalog = Fertilizers::Catalog.new(simple: SIMPLE, variants: VARIANTS)
    end

    def test_same_simple_fertiliser_under_two_names_is_one_product
      first = product('AMMONITRATE 33,5 - Engrais Granulé YARA', merchant: 'germineo')
      second = product('Ammonitrate 33.5', merchant: 'cereapro')

      assert_equal %w[ammonitrate_33_5 ammonitrate_33_5], [first.id, second.id]
      assert_equal 'ammonitrate_33', first.variant
      assert_equal({ nitrogen: 33.5 }, first.composition)
    end

    def test_accents_and_order_of_the_rules
      assert_equal 'urea_46', product('Urée 46 - Engrais').id
      assert_equal 'urea_46_inhibited', product('UREE 46 Inhibée NBPT Granulé').id
    end

    def test_sulphur_grade_is_not_the_fertiliser_it_is_named_after
      soufre = product('Ammonitrate 27 soufré - 10 soufre', composition: { nitrogen: 27.0, sulfur: 10.0 })

      assert_equal 'npk-27-0-0-s10', soufre.id
      assert_equal 'ssp_18', product('SUPERPHOSPHATE 18 - 30 soufre - Engrais').id, 'its sulphur belongs to it'
    end

    def test_compound_fertiliser_is_known_by_its_formula
      found = product('BLAUKORN classic', composition: { nitrogen: 15.0, phosphorus: 15.0, potassium: 15.0, sulfur: 15.0 })

      assert_equal 'npk-15-15-15-s15', found.id
      assert_equal '15-15-15 + 15 SO3', found.name
      assert_equal '15_15_15_15', found.variant
    end

    def test_formula_is_read_in_the_name_when_the_merchant_gives_no_composition
      assert_equal 'npk-0-18-18-s16', product('00.18.18+16so3').id
      assert_equal 'npk-33.5-0-0-s30', product('33.5.00.00+30 So3').id
      assert_equal 'npk-22-14-0-s20', product('22.14.00+20so3').id
      assert_equal 'npk-15-15-15-s16', product('15-15-15 + 16 So3').id
    end

    def test_anything_else_stays_a_product_of_its_merchant
      organic = product('Fientes de poules', kind: 'organic', product_ref: 'fientes-de-poules', composition: { nitrogen: 4.0, phosphorus: 3.0 })
      unknown = product('Magnesia-Kaïnit®', product_ref: 'magnesia-kainit')

      assert_equal 'cereapro-fientes-de-poules', organic.id
      assert_equal 'cereapro-magnesia-kainit', unknown.id
    end

    private

      def product(name, merchant: 'cereapro', kind: 'mineral', composition: {}, product_ref: 'ref')
        @catalog.product(Offer.new(merchant: merchant, name: name, kind: kind, composition: composition, product_ref: product_ref))
      end
  end

  class FertilizersPricingTest < Minitest::Test
    Reading = Fertilizers::Pricing::Reading

    def setup
      @pricing = Fertilizers::Pricing.new
    end

    def test_public_price_is_kept_before_the_one_of_a_purchasing_group
      months = @pricing.monthly([
                                  reading('cereapro', 590.0, negotiated: true), reading('cereapro', 600.0, negotiated: true),
                                  reading('germineo', 560.0), reading('germineo', 570.0, on: Date.new(2026, 10, 12))
                                ])

      assert_equal 1, months.size
      assert_equal ['germineo', 565.0, false, 2, Date.new(2026, 10, 12)],
                   months.first.to_h.values_at(:merchant, :price, :negotiated, :observations, :last_observed_on)
      assert_equal Date.new(2026, 10, 1), months.first.month
    end

    def test_negotiated_price_is_kept_when_alone_and_says_so
      month = @pricing.monthly([reading('cereapro', 590.0, negotiated: true)]).first

      assert_equal ['cereapro', true], [month.merchant, month.negotiated]
    end

    def test_packagings_and_months_are_priced_apart
      months = @pricing.monthly([
                                  reading('germineo', 560.0), reading('germineo', 590.0, packaging: 'big_bag_600'),
                                  reading('germineo', 580.0, on: Date.new(2026, 11, 2))
                                ])

      assert_equal [['bulk', 10], ['bulk', 11], ['big_bag_600', 10]].sort, months.map { |month| [month.packaging, month.month.month] }.sort
    end

    def test_offer_for_another_season_is_not_the_price_of_the_month
      months = @pricing.monthly([reading('cereapro', 400.0, delivery_from: Date.new(2027, 3, 1)),
                                 reading('cereapro', 590.0, delivery_from: Date.new(2026, 12, 1))])

      assert_equal [590.0], months.map(&:price)
    end

    def test_unit_values_come_from_the_simple_fertilisers
      months = @pricing.monthly([
                                  reading('germineo', 560.5), reading('germineo', 718.84, fertilizer: 'tsp_45'),
                                  reading('germineo', 420.84, fertilizer: 'potassium_chloride_60'),
                                  reading('germineo', 410.84, fertilizer: 'ammonium_sulphate')
                                ])

      values = @pricing.unit_values(months).to_h { |value| [value.nutrient, value.value] }

      assert_in_delta 1.6731, values['N'], 0.0001
      assert_in_delta 1.5974, values['P2O5'], 0.0001
      assert_in_delta 0.7014, values['K2O'], 0.0001
      assert_in_delta (410.84 - (210 * 1.6731)) / 600, values['SO3'], 0.0001
    end

    def test_sulphur_is_not_valued_without_nitrogen_nor_below_zero
      without_nitrogen = @pricing.monthly([reading('germineo', 410.0, fertilizer: 'ammonium_sulphate')])
      cheap = @pricing.monthly([reading('germineo', 560.0), reading('germineo', 300.0, fertilizer: 'ammonium_sulphate')])

      assert_empty @pricing.unit_values(without_nitrogen)
      assert_equal ['N'], @pricing.unit_values(cheap).map(&:nutrient)
    end

    def test_big_bag_stands_in_when_bulk_is_missing
      months = @pricing.monthly([reading('cereapro', 596.0, packaging: 'big_bag_600', negotiated: true)])

      assert_equal ['big_bag_600'], @pricing.unit_values(months).map(&:packaging)
    end

    private

      def reading(merchant, price, fertilizer: 'ammonitrate_33_5', packaging: 'bulk', on: Date.new(2026, 10, 5), negotiated: false, delivery_from: nil)
        Reading.new(fertilizer_id: fertilizer, merchant: merchant, observed_on: on, packaging: packaging, unit: 'ton', price: price,
                    delivery_from: delivery_from, negotiated: negotiated)
      end
  end

  class FertilizersMerchantsTest < Minitest::Test
    def test_cereapro_offers_are_read_from_the_data_of_the_page
      offer = { localisation: 'localisee', sku: 'T:camion-P:19-C:1', productName: 'Ammonitrate 33.5', productType: 'engrais',
                productSlug: 'ammonitrate-33-5', categoryName: 'Azoté', compositionEngrais: '$8d', packagingName: 'Vrac',
                unitAbbreviation: 'T', period: { start: '$D2026-12-01T00:00:00.000Z', end: '$D2026-12-31T00:00:00.000Z' },
                basePrice: { amount: 572_000, currencyAmount: 572.0 }, origin: 'Europe', tags: [{ name: 'Granulé {industriel}' }] }
      feed = { localisation: 'localisee', sku: 'feed', productName: 'Tourteau', productType: 'alimentation-animale', basePrice: { currencyAmount: 300.0 } }
      unpriced = offer.merge(sku: 'unpriced', basePrice: '$undefined')
      html = page(%(8d:{"azote":33.5,"phosphore":0,"soufre":0}\n) + "x:[#{JSON.generate(offer)},#{JSON.generate(offer)},#{JSON.generate(feed)},#{JSON.generate(unpriced)}]")

      offers = Fertilizers::Cereapro.offers(html)

      assert_equal 1, offers.size
      found = offers.first
      assert_equal ['cereapro', 'T:camion-P:19-C:1', 'ammonitrate-33-5', 'mineral', 'bulk', 'ton', 572.0, true],
                   found.to_h.values_at(:merchant, :source_id, :product_ref, :kind, :packaging, :unit, :price, :negotiated)
      assert_equal [Date.new(2026, 12, 1), Date.new(2026, 12, 31)], [found.delivery_from, found.delivery_to]
      assert_equal({ nitrogen: 33.5 }, found.composition)
    end

    def test_cereapro_page_without_data_has_no_offer
      assert_empty Fertilizers::Cereapro.offers('<html><body>Maintenance</body></html>')
    end

    def test_germineo_products_are_read_from_their_cards
      html = <<~HTML
        <article class="product-item tw-w-full" >
          <h2><a class="clickable-trigger | tw-block" href="https://www.germineo.com/p/azote-pur/ammonitrate-27-engrais-86" title="AMMONITRATE 27 - Engrais">AMMONITRATE 27</a></h2>
          <table class="table-list"><tbody>
            <tr> <td>Azote total</td> <td>27 %</td> </tr>
            <tr> <td>- Dont azote nitrique</td> <td>13,5 %</td> </tr>
            <tr> <td>Magnésie</td> <td>3 à 4 %</td> </tr>
          </tbody></table>
          <span class="tw-font-serif tw-font-bold"> 1&nbsp;488,50 € </span>
          <span class="tw-text-xs"> HT par tonne<br>transport inclus </span>
          <p><span class="tw-font-bold">Big-bag de 600 Kg</span><br></p>
        </article>
        <article class="product-item tw-w-full" >
          <h2><a class="clickable-trigger" href="https://www.germineo.com/p/azote-pur/sans-prix-99" title="Sans prix">Sans prix</a></h2>
        </article>
      HTML

      offers = Fertilizers::Germineo.offers(html, kind: 'mineral')

      assert_equal 1, offers.size
      found = offers.first
      assert_equal ['germineo', '86', 'AMMONITRATE 27 - Engrais', 'mineral', 'big_bag_600', 'ton', 1488.5, false],
                   found.to_h.values_at(:merchant, :source_id, :name, :kind, :packaging, :unit, :price, :negotiated)
      assert_equal({ nitrogen: 27.0, magnesium: 3.0 }, found.composition)
    end

    def test_germineo_category_goes_on_only_after_a_page_holding_products
      card = '<article class="product-item x"></article>'

      assert Fertilizers::Germineo.next_page?("#{card}<a href=\"?page=2\">", 1)
      refute Fertilizers::Germineo.next_page?('<a href="?page=4">', 3)
      refute Fertilizers::Germineo.next_page?(card, 1)
    end

    private

      # The page gives its data as escaped pieces of text
      def page(payload)
        "<script>self.__next_f.push([1,#{JSON.generate(payload)}])</script>"
      end
  end
end
