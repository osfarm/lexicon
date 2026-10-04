# frozen_string_literal: true

module Lexicon
  module Packaging
    # Pivot keys are the identifiers datasets share: a commune, a company, a parcel. Each key has one
    # reference table; a datasource declares the columns that carry a key.
    module Pivots
      Key = Struct.new(:name, :table, :column, :where, keyword_init: true)

      KEYS = [
        Key.new(name: 'commune', table: 'registered_postal_codes', column: 'code'),
        Key.new(name: 'department', table: 'registered_administrative_areas', column: 'code', where: "kind = 'department'"),
        Key.new(name: 'siren', table: 'registered_enterprises', column: 'siren'),
        Key.new(name: 'cadastral_parcel', table: 'registered_cadastral_parcels', column: 'id'),
        Key.new(name: 'cap_crop_code', table: 'master_crop_production_cap_codes', column: 'cap_code'),
        Key.new(name: 'taxon', table: 'master_taxonomy', column: 'reference_name'),
        Key.new(name: 'production', table: 'master_productions', column: 'reference_name'),
        Key.new(name: 'weather_station', table: 'registered_weather_stations', column: 'reference_name')
      ].map { |key| [key.name, key] }.to_h.freeze

      # @param [String] name
      # @return [Key]
      def self.fetch(name)
        KEYS.fetch(name.to_s) { raise ArgumentError.new("Unknown pivot key #{name}. Known keys: #{KEYS.keys.join(', ')}") }
      end
    end
  end
end
