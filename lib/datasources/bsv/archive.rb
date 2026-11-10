# frozen_string_literal: true

module Datasources
  class Bsv
    # Every bulletin ever collected, in `raw/bsv/archive/`, never emptied: a site drops its bulletins at the end of a
    # campaign (Pays de la Loire), the package keeps them.
    #
    #   <sha>.pdf            a bulletin, named by the first 24 characters of its SHA-256
    #   <sha>.notice.json    where it was listed: regions, addresses, label, title and section of the page,
    #                        first_seen_on, last_seen_on
    #   <sha>.pages.json     the text of each page (pdftotext), for the search and to check the quotes
    #   <sha>.haiku.json     what Haiku read in it (`Extractor`), and <sha>.opus.json for the few Opus reads too
    #
    # and beside it `raw/bsv/batches/<id>.json`, a batch sent to the API and not gathered yet.
    #
    # A PDF dropped by hand in the directory is read like the others; it has no notice.
    class Archive
      Entry = Struct.new(:sha, :pdf, :notice, :pages, keyword_init: true)

      attr_reader :dir

      # @param [Pathname] dir
      def initialize(dir)
        @dir = Pathname.new(dir)
      end

      # @return [Array<Entry>] by name of file
      def entries
        dir.glob('*.pdf').sort.map do |pdf|
          sha = pdf.basename('.pdf').to_s
          Entry.new(sha: sha, pdf: pdf, notice: read_json("#{sha}.notice.json"), pages: read_json("#{sha}.pages.json"))
        end
      end

      # @return [Hash{String => String}] the fingerprint of each address already downloaded
      def known_urls
        dir.glob('*.notice.json').each_with_object({}) do |file, known|
          sha = file.basename('.notice.json').to_s
          Array(JSON.parse(file.read)['pdf_urls']).each { |url| known[url] = sha }
        end
      end

      # Keeps a downloaded PDF under its fingerprint
      # @param [Pathname] file downloaded, moved into the archive
      # @return [String] its fingerprint
      def store(file)
        FileUtils.mkdir_p(dir)
        sha = Digest::SHA256.file(file).hexdigest[0, 24]
        target = dir.join("#{sha}.pdf")
        target.exist? ? FileUtils.rm_f(file) : FileUtils.mv(file, target)
        sha
      end

      # Records where a bulletin was listed, and the day: a same PDF listed by two regions keeps both. Label, title
      # and section are those of the page it was first listed on, read again each time that page lists it.
      # @param [String] sha
      # @param [Crawler::Link] link
      # @param [String] region slug
      # @param [Date] seen_on
      def see(sha, link, region, seen_on)
        notice = read_json("#{sha}.notice.json") || {}
        first = notice.empty? || Array(notice['page_urls']).first == link.page_url
        notice['regions'] = (Array(notice['regions']) | [region])
        notice['pdf_urls'] = (Array(notice['pdf_urls']) | [link.pdf_url])
        notice['page_urls'] = (Array(notice['page_urls']) | [link.page_url])
        if first
          notice['label'] = link.label
          notice['page_title'] = link.page_title
          notice['section'] = link.section
        end
        notice['first_seen_on'] ||= seen_on.iso8601
        notice['last_seen_on'] = [notice['last_seen_on'].to_s, seen_on.iso8601].max
        write_json("#{sha}.notice.json", notice)
      end

      # @param [String] sha
      # @return [Boolean]
      def pages?(sha)
        dir.join("#{sha}.pages.json").exist?
      end

      # @param [String] sha
      # @param [Array<String>] pages
      def keep_pages(sha, pages)
        write_json("#{sha}.pages.json", pages)
      end

      # @param [String] sha
      # @param [String] key haiku or opus
      # @return [Hash, nil] what the API answered for that bulletin (`Extractor`)
      def answer(sha, key)
        read_json("#{sha}.#{key}.json")
      end

      def keep_answer(sha, key, answer)
        write_json("#{sha}.#{key}.json", answer)
      end

      # @return [Array<Hash>] the batches sent and not gathered yet, in `raw/bsv/batches/`
      def batches
        batches_dir.glob('*.json').sort.map { |file| JSON.parse(file.read) }
      end

      def keep_batch(id, batch)
        FileUtils.mkdir_p(batches_dir)
        batches_dir.join("#{id}.json").write(JSON.pretty_generate(batch))
      end

      def drop_batch(id)
        FileUtils.rm_f(batches_dir.join("#{id}.json"))
      end

      private

        def batches_dir
          dir.parent.join('batches')
        end

        def read_json(file)
          path = dir.join(file)
          path.exist? ? JSON.parse(path.read) : nil
        end

        def write_json(file, data)
          dir.join(file).write(JSON.pretty_generate(data))
        end
    end
  end
end
