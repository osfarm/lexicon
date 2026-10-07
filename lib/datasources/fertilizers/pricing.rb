# frozen_string_literal: true

module Datasources
  class Fertilizers
    # Turns the readings into one price per product, packaging and month, then into the value of a
    # kilogram of nitrogen, phosphorus, potassium and sulphur.
    class Pricing
      Reading = Struct.new(:fertilizer_id, :merchant, :observed_on, :packaging, :unit, :price, :delivery_from,
                           :negotiated, keyword_init: true)
      Monthly = Struct.new(:fertilizer_id, :packaging, :unit, :month, :price, :merchant, :negotiated, :observations,
                           :last_observed_on, keyword_init: true)
      UnitValue = Struct.new(:month, :nutrient, :value, :fertilizer_id, :packaging, :price, :merchant, keyword_init: true)

      # An offer to be delivered later than that is a price for another season
      HORIZON = 90
      # Public prices first; a price negotiated by a purchasing group only when no public one exists
      PRIORITY = %w[germineo cereapro].freeze
      # Simple fertiliser each nutrient is valued from, and the kilograms of it in a tonne
      REFERENCES = { 'N' => ['ammonitrate_33_5', 335.0], 'P2O5' => ['tsp_45', 450.0], 'K2O' => ['potassium_chloride_60', 600.0] }.freeze
      # Ammonium sulphate carries 210 kg of nitrogen and 600 kg of SO3: its sulphur is what its nitrogen does not pay
      SULFUR = { fertilizer: 'ammonium_sulphate', nitrogen: 210.0, sulfur: 600.0 }.freeze
      PACKAGINGS = %w[bulk big_bag_600].freeze

      # @param [Array<Reading>] readings
      # @return [Array<Monthly>]
      def monthly(readings)
        current = readings.select { |reading| reading.delivery_from.nil? || reading.delivery_from <= reading.observed_on + HORIZON }

        current.group_by { |reading| [reading.fertilizer_id, reading.packaging, reading.unit, first_day(reading.observed_on)] }
               .map { |(fertilizer_id, packaging, unit, month), group| month_of(fertilizer_id, packaging, unit, month, group) }
               .sort_by { |row| [row.fertilizer_id, row.packaging.to_s, row.month] }
      end

      # @param [Array<Monthly>] months
      # @return [Array<UnitValue>]
      def unit_values(months)
        months.map(&:month).uniq.sort.flat_map do |month|
          values = REFERENCES.map { |nutrient, (fertilizer, kilograms)| unit_value(months, month, nutrient, fertilizer) { |price| price / kilograms } }.compact
          nitrogen = values.find { |value| value.nutrient == 'N' }
          sulfur = nitrogen && unit_value(months, month, 'SO3', SULFUR[:fertilizer]) do |price|
            (price - (SULFUR[:nitrogen] * nitrogen.value)) / SULFUR[:sulfur]
          end

          # A struct spreads into its fields when splatted
          [*values, sulfur].compact
        end
      end

      private

        def first_day(date)
          Date.new(date.year, date.month, 1)
        end

        def month_of(fertilizer_id, packaging, unit, month, readings)
          merchant, kept = readings.group_by(&:merchant).min_by { |name, _| PRIORITY.index(name) || PRIORITY.size }

          Monthly.new(fertilizer_id: fertilizer_id, packaging: packaging, unit: unit, month: month,
                      price: (kept.sum(&:price) / kept.size).round(2), merchant: merchant, negotiated: kept.all?(&:negotiated),
                      observations: kept.size, last_observed_on: kept.map(&:observed_on).max)
        end

        # A value below zero means the reference prices of the month do not hold together: nothing is published
        def unit_value(months, month, nutrient, fertilizer)
          row = PACKAGINGS.lazy.map { |packaging| months.find { |candidate| candidate.month == month && candidate.fertilizer_id == fertilizer && candidate.packaging == packaging && candidate.unit == 'ton' } }
                          .find { |candidate| !candidate.nil? }
          return nil if row.nil?

          value = yield(row.price)
          return nil unless value.positive?

          UnitValue.new(month: month, nutrient: nutrient, value: value.round(4), fertilizer_id: fertilizer, packaging: row.packaging,
                        price: row.price, merchant: row.merchant)
        end
    end
  end
end
