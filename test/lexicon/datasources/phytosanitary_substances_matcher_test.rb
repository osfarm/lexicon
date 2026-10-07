# frozen_string_literal: true

require 'test_helper'

module Datasources
  class PhytosanitarySubstancesMatcherTest < Minitest::Test
    Matcher = PhytosanitarySubstances::Matcher

    HRAC = [
      { name: 'Mecoprop', group: '4' },
      { name: 'Fluazifop-butyl', group: '1' },
      { name: 'Halauxifen', group: '4' },
      { name: 'Bentazon', group: '6' },
      { name: 'Allidochlor=CDAA', group: '15' },
      { name: 'Diquat', group: '22' },
      { name: 'Flamprop-m', group: '0' },
      { name: 'Flamprop-isopropyl', group: '31' }
    ].freeze
    EIQ = [
      { name: 'glyphosate', cas: '1071-83-6', eiq: 32 },
      { name: 'zinc phosphide', cas: '1314-84-7', eiq: 40 },
      { name: 'fosetyl-aluminium', cas: '39148-24-8', eiq: 12 },
      { name: 'mecoprop', cas: '7085-19-0', eiq: 36 }
    ].freeze

    def test_cas_number_wins_over_the_name
      match = Matcher.new(EIQ).match('Glyphosate (sel)', cas: '1071-83-6')

      assert_equal 'cas', match.how
      assert_equal 32, match.entry[:eiq]
    end

    def test_name_is_compared_whatever_the_case_and_the_punctuation
      assert_equal 'name', Matcher.new(EIQ).match('Zinc  Phosphide').how
    end

    def test_synonyms_of_a_line_both_match
      matcher = Matcher.new(HRAC)

      assert_equal '15', matcher.match('CDAA').entry[:group]
      assert_equal '15', matcher.match('allidochlor').entry[:group]
    end

    def test_what_ephy_adds_between_parentheses_is_ignored
      assert_equal 'name', Matcher.new(HRAC).match('Diquat (dibromide)').how
    end

    def test_another_form_does_not_share_a_toxicity
      matcher = Matcher.new(EIQ)

      assert_nil matcher.match('Zinc'), 'zinc is not zinc phosphide'
      assert_nil matcher.match('Fosetyl')
      assert_nil matcher.match('Mecoprop-P')
    end

    def test_alias_says_which_form_a_toxicity_was_measured_on
      match = Matcher.new(EIQ, aliases: { 'Fosetyl' => 'fosetyl-aluminium' }).match('Fosetyl')

      assert_equal 'alias', match.how
      assert_equal 12, match.entry[:eiq]
    end

    def test_isomer_shares_the_mode_of_action
      match = Matcher.new(HRAC, isomers: true, forms: true).match('Mecoprop-P')

      assert_equal 'isomer', match.how
      assert_equal '4', match.entry[:group]
    end

    def test_salt_or_ester_shares_the_mode_of_action_both_ways
      matcher = Matcher.new(HRAC, isomers: true, forms: true)

      assert_equal %w[form 1], matcher.match('Fluazifop-P').then { |match| [match.how, match.entry[:group]] }
      assert_equal %w[form 4], matcher.match('Halauxifen-methyl').then { |match| [match.how, match.entry[:group]] }
    end

    def test_forms_that_disagree_do_not_match
      assert_nil Matcher.new(HRAC, forms: true).match('Flamprop')
    end

    def test_alias_names_the_line_of_the_list
      match = Matcher.new(HRAC, aliases: { 'Bentazone' => 'Bentazon' }).match('Bentazone')

      assert_equal 'alias', match.how
    end

    def test_unknown_substance_does_not_match
      assert_nil Matcher.new(HRAC, isomers: true, forms: true).match('Sulphur')
      assert_nil Matcher.new(HRAC).match('')
    end
  end

  class PhytosanitarySubstancesCompositionTest < Minitest::Test
    Composition = PhytosanitarySubstances::Composition

    def test_substances_of_a_product_are_read_with_their_dose
      parts = Composition.parse('dicamba sel de sodium et de potassium (Dicamba) 15.0 g/L | MCPA sels de sodium (MCPA) 180.0 g/L')

      assert_equal %w[Dicamba MCPA], parts.map(&:name)
      assert_equal ['dicamba sel de sodium et de potassium', 'MCPA sels de sodium'], parts.map(&:french_name)
      assert_equal [%w[15.0 g/L], %w[180.0 g/L]], parts.map { |part| [part.quantity, part.unit] }
    end

    def test_name_holding_parentheses_is_kept_whole
      part = Composition.parse('cydia pomonella granulosis virus (Cydia pomonella Granulovirus (CpGV)) 10000000000000 Corps viraux/L').first

      assert_equal 'Cydia pomonella Granulovirus (CpGV)', part.name
      assert_equal 'cydia pomonella granulosis virus', part.french_name
      assert_equal ['10000000000000', 'Corps viraux/L'], [part.quantity, part.unit]
    end

    def test_substance_without_dose_is_kept
      part = Composition.parse('bouillie bordelaise (Copper compounds)').first

      assert_equal 'Copper compounds', part.name
      assert_nil part.quantity
    end

    def test_repetition_is_read_once
      assert_equal 1, Composition.parse('diméthoate (Dimethoate) 400.0 g/L | diméthoate (Dimethoate) 400.0 g/L').size
    end

    def test_empty_composition_has_no_part
      assert_empty Composition.parse(nil)
      assert_empty Composition.parse('')
    end
  end
end
