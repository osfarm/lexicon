# frozen_string_literal: true

require 'csv'

module Datasources
  class Bsv
    # The departments a bulletin covers, from its region and its zone (`data/bsv/zones.csv`)
    class Zones
      FILE = Pathname.new('data/bsv/zones.csv')

      # @param [Pathname] file
      def initialize(file = FILE)
        @departments = CSV.read(file, headers: true).each_with_object({}) do |row, all|
          all[[row['region'], row['zone'].to_s]] = row['department_codes'].split('|')
        end
      end

      # @param [String] region slug
      # @param [String, nil] zone as `zones.csv` names it, nil for the whole region
      # @return [Array<String>, nil] nil when the region or the zone is unknown
      def departments(region, zone = nil)
        @departments[[region, zone.to_s]]
      end

      # A zone as a bulletin writes it (« Nord Aquitaine », « Edition Nord Nouvelle-Aquitaine », « Secteurs Basse
      # Durance (13 et 84) & Alpin (04 et 05) »): its words are compared without the words that only introduce it
      # (`key`). A zone the region does not know is looked for in the others, when they all give the same
      # departments (« Grand Sud-Ouest » written by a bulletin seen on the site of Grand Est)
      # @param [String] region slug
      # @param [String] name
      # @return [Array<String>, nil]
      def find(region, name)
        wanted = self.class.key(name)
        return if wanted.empty?

        found = @departments.select { |(_, zone), _| !zone.empty? && self.class.key(zone) == wanted }
        mine = found.find { |(slug, _), _| slug == region }
        return mine.last if mine

        found.values.uniq.size == 1 ? found.values.first : nil
      end

      # @return [String] the words of a zone name, without department numbers, « et », nor the words that introduce
      #   it (territoire, édition, secteur, vignoble de)
      def self.key(name)
        words = Extraction.plain(name).split.reject { |word| word.match?(/\A\d+\z/) || %w[et a].include?(word) }
        words.shift while %w[territoire edition secteur secteurs vignoble de d du].include?(words.first)
        words.join(' ')
      end

      # @param [String] name of a region as a bulletin writes it (« Provence-Alpes-Côte d'Azur »)
      # @return [String] its slug (provence-alpes-cote-d-azur)
      def self.slug(name)
        Extraction.plain(name).tr(' ', '-')
      end

      # @return [Array<String>] the regions `zones.csv` knows
      def regions
        @departments.keys.map(&:first).uniq
      end
    end
  end
end
