# frozen_string_literal: true

require 'open3'

module Datasources
  class Bsv
    # The text of each page of a bulletin, by `pdftotext` (poppler-utils), which separates pages with a form feed.
    module Pages
      class Failed < StandardError; end

      # @param [Pathname] pdf
      # @return [Array<String>] one text per page; blank texts for a scanned bulletin
      def self.read(pdf)
        out, err, status = Open3.capture3('pdftotext', '-enc', 'UTF-8', pdf.to_s, '-')
        raise Failed.new("pdftotext #{pdf.basename}: #{err.strip[0, 200]}") unless status.success?

        split(out)
      end

      # @param [String] text the output of pdftotext
      # @return [Array<String>]
      def self.split(text)
        pages = text.scrub.delete("\u0000").split("\f", -1).map(&:strip)
        pages.pop while pages.any? && pages.last.empty? && pages.size > 1
        pages
      end

      # The year of a bulletin before it is read: the latest year its first page writes, in full (« 5 novembre
      # 2026 ») or in a date (« 05/11/26 »)
      # @param [Array<String>] pages
      # @return [Integer, nil]
      def self.year(pages)
        first = pages.first.to_s[0, 3000]
        years = first.scan(/(?<!\d)(20[12]\d)(?!\d)/).flatten.map(&:to_i) +
                first.scan(%r{\b\d{1,2}[/.]\d{1,2}[/.](\d{2})\b}).flatten.map { |year| 2000 + year.to_i }
        years.select { |year| year.between?(2010, Date.today.year) }.max
      end

      # @param [Array<String>] pages
      # @return [Boolean] true when no page has text: the PDF is made of images
      def self.scanned?(pages)
        pages.all? { |page| page.gsub(/\s+/, '').length < 20 }
      end
    end
  end
end
