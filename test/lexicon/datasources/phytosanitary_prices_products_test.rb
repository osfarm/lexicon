# frozen_string_literal: true

require 'test_helper'

module Datasources
  class PhytosanitaryPricesProductsTest < Minitest::Test
    ROWS = [
      { 'numero AMM' => '2000003', 'nom produit' => 'SULTAN', 'seconds noms commerciaux' => 'RAPSAN 500 SC | BUTISAN S', 'Etat d’autorisation' => 'AUTORISE' },
      { 'numero AMM' => '2140173', 'nom produit' => 'LIBRAX', 'seconds noms commerciaux' => '', 'Etat d’autorisation' => 'AUTORISE' },
      { 'numero AMM' => '9000001', 'nom produit' => 'OLDIE', 'seconds noms commerciaux' => '', 'Etat d’autorisation' => 'RETIRE' },
      { 'numero AMM' => '2060088 - 2100111', 'nom produit' => 'MELANGE', 'seconds noms commerciaux' => '', 'Etat d’autorisation' => 'AUTORISE' }
    ].freeze

    def setup
      @products = PhytosanitaryPrices::Products.new(ROWS)
    end

    def test_offer_is_tied_to_the_first_known_product_it_stands_for
      assert_equal [2_140_173, 'LIBRAX'], @products.find(%w[Katwe LIBRAX SULTAN])
    end

    def test_own_name_wins_when_ephy_knows_it
      assert_equal [2_000_003, 'Sultan'], @products.find(%w[Sultan LIBRAX])
    end

    def test_second_names_and_marks_of_similarity_are_understood
      assert_equal 2_000_003, @products.find(['Butisan S']).first
      assert_equal 2_000_003, @products.find(['Rapsan 500 SC (ou spécialité similaire)']).first
    end

    def test_withdrawn_products_and_mixes_are_not_matched
      assert_nil @products.find(%w[OLDIE MELANGE])
      assert_nil @products.find([])
    end
  end
end
