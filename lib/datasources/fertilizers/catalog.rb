# frozen_string_literal: true

module Datasources
  class Fertilizers
    # Tells which product an offer is about, so that the same fertiliser sold by two merchants under two
    # names is one product. A simple fertiliser is known by its name; any other mineral one by its formula.
    class Catalog
      Product = Struct.new(:id, :name, :kind, :composition, :variant, keyword_init: true)

      NUTRIENTS = %i[nitrogen phosphorus potassium sulfur magnesium calcium].freeze
      MAIN = %i[nitrogen phosphorus potassium].freeze
      FIGURE = '(\d+(?:[.,]\d)?)'

      # @param [Array<Hash>] simple rows of data/fertilizers/simple_fertilizers.csv
      # @param [Array<Hash>] variants rows of the fertilisers of the `variants` datasource
      def initialize(simple:, variants: [])
        @simple = simple.map do |row|
          [Regexp.new(row['pattern'], Regexp::IGNORECASE),
           Product.new(id: row['id'], name: row['name'], kind: 'mineral', variant: row['variant_reference_name'].to_s.strip.then { |value| value.empty? ? nil : value },
                       composition: NUTRIENTS.to_h { |nutrient| [nutrient, row[nutrient.to_s].to_f] }.reject { |_, value| value.zero? })]
        end
        @variants = variants.to_h { |row| [formula_id(variant_composition(row)), row['reference_name']] }
      end

      # @param [Offer] offer
      # @return [Product]
      def product(offer)
        named(offer) || by_formula(offer) || of_the_merchant(offer)
      end

      # @param [Hash{Symbol => Float}] composition
      # @return [String, nil] "npk-15-15-15-s16", nil without nitrogen, phosphorus or potassium
      def formula_id(composition)
        return nil if MAIN.all? { |nutrient| composition[nutrient].to_f.zero? }

        extras = { 's' => composition[:sulfur], 'mg' => composition[:magnesium] }.reject { |_, value| value.to_f.zero? }

        ['npk', *MAIN.map { |nutrient| figure(composition[nutrient]) }, *extras.map { |mark, value| "#{mark}#{figure(value)}" }].join('-')
      end

      private

        # Names are compared without accents: "Urée", "UREE", "Uree"
        def named(offer)
          name = offer.name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
          product = @simple.find { |pattern, _| name.match?(pattern) }&.last
          # "Ammonitrate soufré 27" is another product than the ammonitrate it is named after
          return nil if product && product.composition[:sulfur].nil? && name.match?(/soufr|so3/i)

          product
        end

        def by_formula(offer)
          return nil unless offer.kind == 'mineral'

          composition = offer.composition.empty? ? composition_in(offer.name) : offer.composition
          id = formula_id(composition)
          id && Product.new(id: id, name: formula_name(composition), kind: offer.kind, composition: composition, variant: @variants[id])
        end

        # "00.18.18+16so3", "15-15-15 + 16 So3", "33.5.00.00+30 So3": a name that is a formula
        def composition_in(name)
          formula = name.to_s.match(/\A\s*#{FIGURE}[.\- ]#{FIGURE}[.\- ]#{FIGURE}(?:[.\- ]0+)?(?:\s*\+\s*#{FIGURE}\s*so3)?\s*\z/i)
          return {} if formula.nil?

          { nitrogen: formula[1], phosphorus: formula[2], potassium: formula[3], sulfur: formula[4] }
            .transform_values { |value| value.to_s.tr(',', '.').to_f }.reject { |_, value| value.zero? }
        end

        def of_the_merchant(offer)
          Product.new(id: "#{offer.merchant}-#{offer.product_ref.to_s.downcase.gsub(/[^a-z0-9]+/, '-')}", name: offer.name,
                      kind: offer.kind, composition: offer.composition, variant: nil)
        end

        def formula_name(composition)
          extras = { 'SO3' => composition[:sulfur], 'MgO' => composition[:magnesium] }.reject { |_, value| value.to_f.zero? }

          [MAIN.map { |nutrient| figure(composition[nutrient]) }.join('-'), *extras.map { |mark, value| "#{figure(value)} #{mark}" }].join(' + ')
        end

        def figure(value)
          rounded = value.to_f.round(1)

          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        def variant_composition(row)
          { nitrogen: row['nitrogen_concentration'], phosphorus: row['phosphorus_concentration'],
            potassium: row['potassium_concentration'], sulfur: row['sulfur_dioxide_concentration'],
            magnesium: row['magnesium_concentration'] }.transform_values(&:to_f)
        end
    end
  end
end
