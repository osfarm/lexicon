# frozen_string_literal: true

module Datasources
  class Phytosanitary
    module Derogations
      # The page of the ministry, as a list of notices. Each decision is a download card of the French state design
      # system: `<a href="/telecharger/{id}">n°{AMM} - {NAME} <span>pdf - X Ko</span></a>`, with no `.pdf` in the
      # address, after a list « Culture(s) concernée(s) : … », « Numéro d'AMM : … », « Échéance : … ».
      class Page
        Notice = Struct.new(:amm, :name, :crops, :pest, :substance, :issued_on, :expires_on, :pdf_url, keyword_init: true) do
          def to_h
            super.transform_values { |value| value.is_a?(Date) ? value.iso8601 : value }
          end

          def self.from_h(hash)
            values = hash.transform_keys(&:to_sym).slice(*members)
            %i[issued_on expires_on].each { |key| values[key] = values[key] && Date.parse(values[key].to_s) }
            new(**values)
          end
        end

        class Changed < StandardError; end

        ANCHOR = %r{<a\b[^>]*?href=["'](/telecharger/\d+)["'][^>]*>(.*?)</a>}im.freeze
        # A decision, not a menu nor the guidelines of article 53
        LABEL = /\An°\s*(\d{7})\s*[-–]\s*(.+?)\s*(?:pdf\s*-.*)?\z/i.freeze
        ITEM = %r{<li>(.*?)</li>}im.freeze
        FIELDS = {
          crops: /\ACulture\(s\) concernée\(s\)\z/i,
          pest: /\AOrganisme nuisible/i,
          substance: /\ASubstance/i,
          issued_on: /\ADate de délivrance\z/i,
          expires_on: /\AÉchéance\z/i
        }.freeze

        # @param [String] html
        # @param [String] base_url
        # @return [Array<Notice>]
        def self.parse(html, base_url = PAGE_URL)
          notices = []
          previous_end = 0
          html.to_enum(:scan, ANCHOR).each do
            match = Regexp.last_match
            decision = LABEL.match(text(match[2]))
            if decision
              fields = fields(html[previous_end...match.begin(0)])
              notices << Notice.new(amm: decision[1], name: decision[2].strip, pdf_url: URI.join(base_url, match[1]).to_s,
                                    **fields)
            end
            previous_end = match.end(0)
          end
          notices
        end

        # @return [Hash] the fields of the list before a card, the last list only
        def self.fields(html)
          list = html.scan(%r{<ul>(.*?)</ul>}im).flatten.last.to_s
          list.scan(ITEM).flatten.each_with_object({}) do |item, fields|
            key, value = text(item).split(/\s*:\s*/, 2)
            field = FIELDS.find { |_, pattern| pattern.match?(key.to_s) }&.first
            next if field.nil? || value.blank?

            fields[field] = %i[issued_on expires_on].include?(field) ? date(value) : value
          end
        end

        # @return [Date, nil] a date written dd/mm/yyyy
        def self.date(value)
          day, month, year = value[%r{\d{1,2}/\d{1,2}/\d{4}}]&.split('/')&.map(&:to_i)
          day && Date.new(year, month, day)
        rescue Date::Error
          nil
        end

        # @return [String] HTML as plain text: tags removed, entities decoded, spaces reduced
        def self.text(html)
          CGI.unescapeHTML(html.gsub(/<[^>]+>/, ' ')).gsub(/[[:space:]]+/, ' ').strip
        end
      end
    end
  end
end
