# frozen_string_literal: true

require 'test_helper'

module Datasources
  class SeedsLabelTest < Minitest::Test
    SPECIES = [
      { 'id' => 'fromental', 'pattern' => 'avoine elevee?|fromental' },
      { 'id' => 'avoine_rude', 'pattern' => 'avoine (rude|diploide)' },
      { 'id' => 'ble_dur', 'pattern' => 'ble dur' },
      { 'id' => 'ble_tendre', 'pattern' => 'ble( tendre)?\b' },
      { 'id' => 'avoine', 'pattern' => 'avoine' },
      { 'id' => 'seigle', 'pattern' => 'seigle' },
      { 'id' => 'trefle_violet', 'pattern' => 'trefle violet' },
      { 'id' => 'trefle', 'pattern' => 'trefle' },
      { 'id' => 'lin', 'pattern' => 'lin\b' }
    ].freeze

    def setup
      @label = Seeds::Label.new(SPECIES)
    end

    def test_species_variety_and_treatment_are_read
      read = @label.read('Seigle fourrager TURBOGREEN non traité')

      assert_equal ['seigle', 'TURBOGREEN', false, false, false], read.to_a
    end

    def test_organic_seed_says_so_and_its_mark_is_not_a_variety
      read = @label.read('Avoine VODKA blanche AB non traité')

      assert_equal ['avoine', 'VODKA', true], [read.species_id, read.variety, read.organic]
    end

    def test_seed_treatment_is_not_a_variety
      read = @label.read('Blé tendre KINGKONG VIBRANCE GOLD')

      assert_equal ['ble_tendre', 'KINGKONG', false, nil], [read.species_id, read.variety, read.organic, read.treated]
    end

    def test_most_precise_species_wins
      assert_equal 'ble_dur', @label.read('Blé dur ANVERGUR').species_id
      assert_equal 'avoine_rude', @label.read('Avoine Rude Diploïde').species_id
      assert_equal 'fromental', @label.read('Avoine élevé - Fromental ARONE non traité').species_id
      assert_equal 'trefle_violet', @label.read('Trèfle violet BONUS 2n AB non traité').species_id
      assert_equal 'trefle', @label.read('Trèfle de Perse LASER non traité').species_id
    end

    def test_word_starting_like_a_species_is_not_that_species
      assert_nil @label.read('Linotte des champs').species_id
      assert_equal 'lin', @label.read('Lin oléagineux ATTILA').species_id
    end

    def test_mixture_has_no_species_nor_variety
      named = @label.read("Mélange PERMA'TOP non traité")
      listed = @label.read('Luzernes PERMA non traité', several: true)

      assert_equal [nil, nil, true], [named.species_id, named.variety, named.mixture]
      assert listed.mixture
      assert @label.read('Méteil fourrager METEIL PROTEINE').mixture
    end

    def test_capitals_inside_a_word_are_not_a_variety
      assert_equal 'TILLSANO', @label.read('Blé tendre TILLSANO AB Vinaigre et STICoP').variety
      assert_equal 'BIG BOSS', @label.read('Blé demi-précoce BIG BOSS MaïsPROTECTOR').variety
    end

    def test_unknown_seed_keeps_its_label_only
      read = @label.read('Bourrache non traité')

      assert_equal [nil, nil, false], [read.species_id, read.variety, read.mixture]
    end
  end
end
