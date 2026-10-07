# frozen_string_literal: true

module Datasources
  class Fertilizers
    # What a merchant offers on a day for a place: a product, a packaging, a delivered price. `source_id` names
    # the offer for the merchant, `product_ref` the product whatever its packaging and its period of delivery.
    class Offer < Struct.new(:merchant, :source_id, :product_ref, :name, :kind, :category, :packaging, :unit, :price, :delivery_from,
                             :delivery_to, :origin, :composition, :url, :negotiated, keyword_init: true)
      PACKAGINGS = [
        [/\bvrac\b/, 'bulk'],
        [/(bb|big.?bag)\D*600/, 'big_bag_600'],
        [/(bb|big.?bag)\D*500/, 'big_bag_500'],
        [/(bb|big.?bag)\D*300/, 'big_bag_300'],
        [/citerne/, 'tank'],
        [/ibc|cubi/, 'ibc_1000'],
        [/bidon/, 'can'],
        [/\bsac/, 'bag']
      ].freeze
      UNITS = { 't' => 'ton', 'tonne' => 'ton', 'l' => 'liter', 'litre' => 'liter', 'kg' => 'kilogram' }.freeze

      # @param [String, nil] label what the merchant calls the packaging
      # @return [String, nil]
      def self.packaging(label)
        text = label.to_s.downcase

        text.empty? ? nil : (PACKAGINGS.find { |pattern, _| text.match?(pattern) }&.last || 'other')
      end

      # @param [String, nil] label
      # @return [String, nil]
      def self.unit(label)
        UNITS[label.to_s.downcase.strip]
      end
    end
  end
end
