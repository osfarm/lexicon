# frozen_string_literal: true

require 'test_helper'

module Datasources
  class FuelPricesReadingsTest < Minitest::Test
    FIRST_FRIDAY = Date.new(2020, 1, 3)
    WEEKS = 352

    def test_sheet_of_the_dgec_is_read
      readings = FuelPrices::Readings.new(sheet, today: last_friday + 3)

      readings.validate!

      assert_equal WEEKS, readings.weekly.size
      assert_equal FIRST_FRIDAY, readings.weekly.first.observed_on
      assert_in_delta 0.6, readings.weekly.first.excluding_taxes
      assert_in_delta 0.96, readings.weekly.first.including_taxes
    end

    def test_months_are_averaged_from_their_readings
      january = FuelPrices::Readings.new(sheet, today: last_friday).monthly.first

      assert_equal Date.new(2020, 1, 1), january.month
      assert_equal 5, january.observations
      assert_equal Date.new(2020, 1, 31), january.last_observed_on
      assert_in_delta 0.62, january.excluding_taxes
      assert_in_delta 0.98, january.including_taxes
    end

    def test_price_excluding_vat_keeps_the_other_taxes
      assert_in_delta 1.6889, FuelPrices::Readings.excluding_vat(2.0267), 0.0001
    end

    def test_changed_headers_are_refused
      rows = sheet
      rows[1][1] = 'Fioul domestique'

      assert_refused(rows, /cell 2,2 should start with 'Gazole non routier'/)
    end

    def test_truncated_sheet_is_refused
      assert_refused(sheet(weeks: 40), /40 readings, at least 350 expected/)
    end

    def test_reading_on_another_day_is_refused
      rows = sheet
      rows[10][0] += 1

      assert_refused(rows, /1 readings are not on a Friday/)
    end

    def test_stale_sheet_is_refused
      assert_refused(sheet, /more than 21 days ago/, today: last_friday + 22)
    end

    def test_unlikely_price_is_refused
      rows = sheet
      rows[20][1] = 612.0

      assert_refused(rows, /1 unlikely prices/)
    end

    def test_swapped_columns_are_refused
      rows = sheet.map { |row| row[0].is_a?(Date) ? [row[0], row[2], row[1]] : row }

      assert_refused(rows, /unlikely prices/)
    end

    def test_averages_apart_from_the_ones_of_the_dgec_are_refused
      rows = sheet
      rows[rows.index { |row| row[0] == 'MOYENNES MENSUELLES' } + 3][1] += 0.05

      assert_refused(rows, /1 monthly averages differ from the ones of the DGEC, first 2020-03-01/)
    end

    def test_sheet_without_monthly_averages_is_refused
      rows = sheet.take_while { |row| row[0] != 'MOYENNES MENSUELLES' }

      assert_refused(rows, /no monthly average/)
    end

    private

      def last_friday(weeks = WEEKS)
        FIRST_FRIDAY + (7 * (weeks - 1))
      end

      # The sheet as Roo hands it over: two header rows, the readings, then the averages of the DGEC
      def sheet(weeks: WEEKS)
        readings = Array.new(weeks) { |week| [FIRST_FRIDAY + (7 * week), 0.6 + (0.01 * (week % 5)), 0.96 + (0.01 * (week % 5))] }
        months = readings.group_by { |date, _, _| Date.new(date.year, date.month, 1) }.map do |month, rows|
          [month, rows.sum { |row| row[1] } / rows.size, rows.sum { |row| row[2] } / rows.size]
        end

        [
          [nil, 'PRIX DE VENTE H.T.T. (en euro par litre)', 'PRIX DE VENTE T.T.C. (en euro par litre)'],
          ['Date', 'Gazole non routier (livraisons inférieures à 5 000 litres)', 'Gazole non routier (livraisons inférieures à 5 000 litres)'],
          *readings,
          [nil, nil, nil],
          ['MOYENNES MENSUELLES', nil, nil],
          *months,
          [nil, nil, nil],
          ['MOYENNES ANNUELLES', nil, nil],
          ['2020', 0.62, 0.98]
        ]
      end

      def assert_refused(rows, message, today: last_friday)
        error = assert_raises(FuelPrices::Readings::Invalid) { FuelPrices::Readings.new(rows, today: today).validate! }

        assert_match message, error.message
      end
  end
end
