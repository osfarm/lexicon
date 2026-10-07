# frozen_string_literal: true

module Datasources
  class PhytosanitarySubstances
    # Reads the composition E-Phy gives for a product, such as
    # "dicamba sel de sodium (Dicamba) 15.0 g/L | MCPA sels de sodium et de potassium (MCPA) 180.0 g/L".
    module Composition
      Part = Struct.new(:french_name, :name, :quantity, :unit, keyword_init: true)

      DOSE = /\A\s*([\d.,]+)\s*(.*?)\s*\z/.freeze

      # @param [String, nil] text
      # @return [Array<Part>] one per substance, without the repetitions E-Phy makes
      def self.parse(text)
        text.to_s.split('|').map { |part| parse_part(part.strip) }.compact.uniq
      end

      # The name of the substance is the last parenthesis, which may hold parentheses itself
      def self.parse_part(part)
        closing = part.rindex(')')
        return nil if closing.nil?

        opening = opening_of(part, closing)
        return nil if opening.nil?

        dose = part[(closing + 1)..].match(DOSE)
        Part.new(
          french_name: part[0...opening].strip,
          name: part[(opening + 1)...closing].strip,
          quantity: dose && dose[1].tr(',', '.'),
          unit: dose && dose[2]
        )
      end

      def self.opening_of(part, closing)
        depth = 0
        closing.downto(0) do |index|
          depth += 1 if part[index] == ')'
          depth -= 1 if part[index] == '('
          return index if depth.zero?
        end

        nil
      end
    end
  end
end
