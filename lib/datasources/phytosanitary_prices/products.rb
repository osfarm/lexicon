# frozen_string_literal: true

module Datasources
  class PhytosanitaryPrices
    # Finds the marketing authorisation of the product an offer is about. A purchasing group sells under its
    # own names and says which known products each one stands for: the offer is tied to the first of them
    # that E-Phy knows as authorised.
    class Products
      # @param [Array<Hash>] rows lines of produits_utf8.csv of E-Phy
      def initialize(rows)
        @by_name = {}
        rows.select { |row| row['Etat d’autorisation'] == 'AUTORISE' && row['numero AMM'].to_s.match?(/\A\d+\z/) }.each do |row|
          [row['nom produit'], *row['seconds noms commerciaux'].to_s.split('|')].each do |name|
            key = self.class.normalize(name)
            @by_name[key] ||= row['numero AMM'].to_i unless key.empty?
          end
        end
      end

      # @param [Array<String>] names the name of the offer, then the products it stands for
      # @return [Array(Integer, String), nil] the authorisation number and the name that gave it
      def find(names)
        names.each do |name|
          number = @by_name[self.class.normalize(name)]
          return [number, name] unless number.nil?
        end

        nil
      end

      # "Turban (ou spécialité similaire)" is "TURBAN"
      def self.normalize(name)
        name.to_s.gsub(/\([^)]*\)/, ' ').unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]+/, ' ').strip
      end
    end
  end
end
