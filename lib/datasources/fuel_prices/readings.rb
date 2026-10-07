# frozen_string_literal: true

module Datasources
  class FuelPrices
    # Reads the rows of the sheet "Carburants non routiers" of the DGEC workbook: one reading per Friday,
    # then the monthly and yearly averages of the DGEC. Refuses a sheet that does not look like the one
    # this datasource was written for, so that a doubtful collection never replaces the data in service.
    class Readings
      class Invalid < StandardError; end

      PRODUCT = 'non_road_diesel'
      # Standard VAT rate of mainland France, the only area the DGEC surveys (Corsica excluded)
      VAT_RATE = 0.20
      MONTHS_TITLE = 'MOYENNES MENSUELLES'
      HEADERS = [
        [0, 1, 'PRIX DE VENTE H.T.T. (en euro par litre)'],
        [0, 2, 'PRIX DE VENTE T.T.C. (en euro par litre)'],
        [1, 0, 'Date'],
        [1, 1, 'Gazole non routier'],
        [1, 2, 'Gazole non routier']
      ].freeze
      FRIDAY = 5
      MINIMUM_READINGS = 350
      MAXIMUM_AGE = 21
      PRICE_RANGE = (0.20..3.00).freeze
      AVERAGE_TOLERANCE = 0.005

      Reading = Struct.new(:observed_on, :excluding_taxes, :including_taxes, keyword_init: true)
      Month = Struct.new(:month, :excluding_taxes, :including_taxes, :observations, :last_observed_on, keyword_init: true)

      # @param [Array<Array>] rows cells of the sheet, dates as Date and prices as Float
      # @param [Date] today
      def initialize(rows, today: Date.today)
        @rows = rows
        @today = today
      end

      # @return [Array<Reading>] the readings of the DGEC, oldest first
      def weekly
        @weekly ||= dated(@rows.take(months_title_index || @rows.size)).map do |date, excluding_taxes, including_taxes|
          Reading.new(observed_on: date, excluding_taxes: excluding_taxes, including_taxes: including_taxes)
        end
      end

      # @return [Array<Month>] average of the readings of each month; the last one may be partial
      def monthly
        @monthly ||= weekly.group_by { |reading| first_day(reading.observed_on) }.map do |month, readings|
          Month.new(
            month: month,
            excluding_taxes: average(readings.map(&:excluding_taxes)),
            including_taxes: average(readings.map(&:including_taxes)),
            observations: readings.size,
            last_observed_on: readings.map(&:observed_on).max
          )
        end
      end

      # @param [Float] including_taxes
      # @return [Float] the price a farm pays: VAT is recovered, the other taxes are not
      def self.excluding_vat(including_taxes)
        including_taxes / (1 + VAT_RATE)
      end

      # @raise [Invalid] naming everything that is wrong with the sheet
      def validate!
        problems = [*header_problems, *reading_problems, *average_problems]

        raise Invalid.new(problems.join('; ')) if problems.any?
      end

      private

        def months_title_index
          @rows.index { |row| row[0].to_s.strip == MONTHS_TITLE }
        end

        # @return [Hash{Date => Array<Float>}] the monthly averages the DGEC publishes in the same sheet
        def source_months
          return {} if months_title_index.nil?

          dated(@rows.drop(months_title_index + 1)).to_h { |date, *prices| [date, prices] }
        end

        # @return [Array<Array>] rows starting with a date and carrying both prices
        def dated(rows)
          rows.select { |row| row[0].is_a?(Date) && row[1].is_a?(Numeric) && row[2].is_a?(Numeric) }
              .map { |row| [row[0], row[1].to_f, row[2].to_f] }
        end

        def first_day(date)
          Date.new(date.year, date.month, 1)
        end

        def average(values)
          values.sum / values.size
        end

        def header_problems
          HEADERS.reject { |row, column, expected| @rows.dig(row, column).to_s.strip.start_with?(expected) }
                 .map { |row, column, expected| "cell #{row + 1},#{column + 1} should start with '#{expected}'" }
        end

        def reading_problems
          return ["no reading before the title '#{MONTHS_TITLE}'"] if weekly.empty?

          last = weekly.map(&:observed_on).max
          other_days = weekly.reject { |reading| reading.observed_on.wday == FRIDAY }
          unlikely = weekly.reject do |reading|
            PRICE_RANGE.cover?(reading.excluding_taxes) && reading.including_taxes > reading.excluding_taxes
          end

          [
            ("#{weekly.size} readings, at least #{MINIMUM_READINGS} expected" if weekly.size < MINIMUM_READINGS),
            ("readings are not sorted or repeat a date" unless weekly.each_cons(2).all? { |a, b| a.observed_on < b.observed_on }),
            ("#{other_days.size} readings are not on a Friday, first #{other_days.first.observed_on}" if other_days.any?),
            ("last reading is from #{last}, more than #{MAXIMUM_AGE} days ago" if (@today - last) > MAXIMUM_AGE),
            ("#{unlikely.size} unlikely prices, first on #{unlikely.first.observed_on}" if unlikely.any?)
          ].compact
        end

        # Months that are over must match what the DGEC computes itself
        def average_problems
          return [] if weekly.empty?

          published = source_months
          return ["no monthly average after the title '#{MONTHS_TITLE}'"] if published.empty?

          current = first_day(weekly.map(&:observed_on).max)
          apart = monthly.select do |month|
            expected = published[month.month]

            month.month < current && (expected.nil? ||
              (month.excluding_taxes - expected[0]).abs > AVERAGE_TOLERANCE ||
              (month.including_taxes - expected[1]).abs > AVERAGE_TOLERANCE)
          end

          apart.empty? ? [] : ["#{apart.size} monthly averages differ from the ones of the DGEC, first #{apart.first.month}"]
        end
    end
  end
end
