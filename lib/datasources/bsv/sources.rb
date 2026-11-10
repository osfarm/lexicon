# frozen_string_literal: true

require 'yaml'

module Datasources
  class Bsv
    # The sites where each region publishes its bulletins (`data/bsv/sources.yml`), one entry per region. Only the
    # roots are listed: the rubrics of a year get a new identifier every year, the crawler finds them under the roots.
    class Sources
      FILE = Pathname.new('data/bsv/sources.yml')

      Region = Struct.new(:slug, :site, :roots, :pages, :section_is_sector, :since, :archives_since, :exclude,
                          keyword_init: true) do
        # @return [Array<String>] the absolute addresses the crawler starts from
        def start_urls
          (roots + pages).map { |path| URI.join(site, path).to_s }
        end

        # @param [String] url of a page
        # @return [Boolean] true for a page that lists PDF directly, whose sections name the sector
        def page?(url)
          pages.any? { |path| URI.join(site, path).to_s == url }
        end

        # @param [String] file_name of a PDF
        # @return [Boolean] true when the name says it is not a bulletin (a note, a poster)
        def excluded?(file_name)
          name = file_name.downcase
          exclude.any? { |pattern| name.include?(pattern) }
        end
      end

      # How far back the crawler goes: the current and the previous year, unless `since` says otherwise:
      # « archives » for as far as each site keeps (`archives_since`), or a year.
      # @param [Pathname] file
      # @param [String, nil] since
      # @return [Array<Region>]
      def self.load(file = FILE, since: ENV['LEXICON_BSV_SINCE'])
        YAML.safe_load(file.read).map do |slug, entry|
          archives = (entry['archives_since'] || Date.today.year - 1).to_i
          Region.new(
            slug: slug,
            site: entry.fetch('site'),
            roots: [entry['root'], *entry['roots'], *entry['extra_roots']].compact,
            pages: Array(entry['pages']),
            section_is_sector: entry['section_is_sector'] == true,
            since: since_year(since, archives),
            archives_since: archives,
            exclude: Array(entry['exclude']).map(&:downcase)
          )
        end
      end

      # @return [Integer]
      def self.since_year(since, archives)
        case since.to_s.strip
        when '' then Date.today.year - 1
        when 'archives' then archives
        when /\A\d{4}\z/ then since.to_i
        else raise ArgumentError.new("LEXICON_BSV_SINCE: « archives » or a year, not « #{since} »")
        end
      end
    end
  end
end
