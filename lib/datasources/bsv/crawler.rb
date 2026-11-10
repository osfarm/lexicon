# frozen_string_literal: true

require 'cgi'
require 'nokogiri'

module Datasources
  class Bsv
    # Walks the BSV tree of a DRAAF site (SPIP): from the roots of `sources.yml`, it reads the rubrics, follows their
    # sub-rubrics, their articles and their pages (`debut_…=`), and a `meta refresh` where a rubric with one article
    # points to it. An article is a leaf: its PDF are kept, its links are not followed. Only the main content of a page
    # is read, without its navigation (breadcrumb, side menu) nor « Sur le même sujet », so that the walk stays in
    # the tree.
    class Crawler
      # A PDF as the site lists it
      Link = Struct.new(:pdf_url, :label, :page_url, :page_title, :section, keyword_init: true)

      # Enough for a site walked back to 2015 (Grand Est, Hauts-de-France: about 3 000 pages)
      MAX_PAGES = 6000
      PAGE = %r{\A/?[a-z0-9-]+-([ra])\d+\.html\z}.freeze
      PAGINATION = /debut_[a-z_]+=\d+/.freeze
      YEAR = /(?<!\d)((?:19|20)\d\d)(?!\d)/.freeze
      ANCHOR = %r{<a\b[^>]*?href=["']([^"']+)["'][^>]*>(.*?)</a>}im.freeze
      # A heading above a list of PDF: a title, or a paragraph that opens in bold (« > Grandes cultures : »)
      HEADING = %r{<h[23]\b[^>]*>(.*?)</h[23]>|<p\b[^>]*>\s*<strong>(.*?)</strong>}im.freeze
      REFRESH = /<meta[^>]+http-equiv=["']refresh["'][^>]+content=["']\d+\s*;\s*url=([^"']+)["']/i.freeze

      # @param [Sources::Region] region
      # @param [#get] http
      # @param [#call, nil] say what is printed of the walk
      def initialize(region, http:, say: nil)
        @region = region
        @http = http
        @say = say || ->(_) {}
      end

      # @return [Array<Link>] each PDF once, in the order it was found
      def links
        found = {}
        queue = @region.start_urls.dup
        seen = Set.new
        while (url = queue.shift)
          next if seen.include?(url) || seen.size >= MAX_PAGES

          seen << url
          next unless @http.allowed?(url)

          begin
            html, final = @http.get(url)
          rescue Http::Failed => e
            @say.call("  #{e.message}")
            next
          end
          if (target = html[REFRESH, 1])
            queue.unshift(absolute(CGI.unescapeHTML(target), final))
            next
          end
          content = self.class.content(html)
          self.class.pdf_links(content, final, @region).each { |link| found[link.pdf_url] ||= link }
          queue.concat(followed(content, final)) if rubric?(final)
        end
        @say.call("  #{@region.slug}: #{seen.size} pages read since #{@region.since}, #{found.size} PDF listed")
        @say.call("  #{@region.slug}: stopped at #{MAX_PAGES} pages, the walk is not complete".red) if seen.size >= MAX_PAGES
        found.values
      end

      # The main content of a page, without what leads elsewhere in the site
      # @param [String] html
      # @return [String]
      def self.content(html)
        text = html[/<main\b.*?<\/main>/im] || html
        text = text.sub(/Sur le même sujet.*\z/im, '')
        # The breadcrumb leads up, the side menu sideways: both go. The pages of a list (`fr-pagination`) stay.
        text.gsub(%r{<nav\b(?![^>]*pagination)[^>]*>.*?</nav>}im, '')
      end

      # @param [String] content
      # @param [String] page_url
      # @param [Sources::Region] region
      # @return [Array<Link>] the PDF of the site the content links to, with the heading above each
      def self.pdf_links(content, page_url, region)
        title = text(content[%r{<h1\b[^>]*>(.*?)</h1>}im, 1].to_s)
        host = URI(page_url).host
        content.to_enum(:scan, ANCHOR).filter_map do
          match = Regexp.last_match
          url = URI.join(page_url, CGI.unescapeHTML(match[1])).to_s rescue next
          uri = URI(url)
          next unless uri.host == host && uri.path.match?(%r{/IMG/pdf/[^/]+\.pdf\z}i)

          section = content[0...match.begin(0)].scan(HEADING).map(&:compact).last&.first
          Link.new(pdf_url: url, label: text(match[2]), page_url: page_url, page_title: title,
                   section: region.page?(page_url) && section ? heading(section) : nil)
        end
      end

      # @return [String] text of an HTML fragment, on one line, its entities decoded (« f&eacute;vrier »)
      def self.text(html)
        Nokogiri::HTML.fragment(html.gsub(/<[^>]+>/, ' \\0 ')).text.gsub(/[[:space:]]+/, ' ').strip
      end

      # @return [String] the name of a section, without what frames it (« > Grandes cultures : »)
      def self.heading(html)
        text(html).sub(/\A[>»\s]+/, '').sub(/[\s:]+\z/, '')
      end

      private

        def rubric?(url)
          path = URI(url).path
          @region.start_urls.include?(url) || path[PAGE, 1] == 'r' || url.match?(PAGINATION)
        end

        # The rubrics, articles and pages a rubric leads to, without those of years before `since`
        def followed(content, page_url)
          host = URI(page_url).host
          content.to_enum(:scan, ANCHOR).filter_map do
            match = Regexp.last_match
            href = CGI.unescapeHTML(match[1])
            url = absolute(href, page_url) or next
            uri = URI(url)
            next unless uri.host == host
            next unless uri.path.match?(PAGE) || (uri.path == URI(page_url).path && href.match?(PAGINATION))
            # The number of a rubric or an article is no year: « mais-a1987.html » is a page of 2026
            next if too_old?("#{uri.path.sub(/-[ra]\d+\.html\z/, '')} #{self.class.text(match[2])}")

            url.sub(/#.*\z/, '')
          end
        end

        def too_old?(words)
          years = words.scan(YEAR).flatten.map(&:to_i)
          years.any? && years.max < @region.since
        end

        def absolute(href, base)
          URI.join(base, href).to_s
        rescue URI::Error
          nil
        end
    end
  end
end
