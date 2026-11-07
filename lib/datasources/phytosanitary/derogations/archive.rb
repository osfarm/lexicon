# frozen_string_literal: true

module Datasources
  class Phytosanitary
    module Derogations
      # Every decision ever collected, in `raw/phytosanitary/derogations/`, never emptied: the page only lists the
      # decisions in force, and a decision that has ended must stay in the package.
      #
      #   page_<date>.html    the page of a collection
      #   <sha>.pdf           a decision, named by the first 24 characters of its SHA-256
      #   <sha>.notice.json   what the page said of it, with `first_seen_on` and `last_seen_on`
      #   <sha>.ocr.json      the answer of Mistral OCR (`document_annotation`, `pages[].markdown`)
      #
      # A PDF dropped by hand in the directory (a decision no longer on the page) is read like the others.
      class Archive
        Entry = Struct.new(:sha, :pdf, :notice, :ocr, keyword_init: true)

        attr_reader :dir

        # @param [Pathname] dir
        def initialize(dir)
          @dir = Pathname.new(dir)
        end

        # @return [Array<Entry>] the decisions of the archive, by name of file
        def entries
          dir.glob('*.pdf').sort.map do |pdf|
            sha = pdf.basename('.pdf').to_s
            Entry.new(sha: sha, pdf: pdf, notice: read_json("#{sha}.notice.json"), ocr: read_json("#{sha}.ocr.json"))
          end
        end

        # @return [Set<String>] the addresses of the PDF already downloaded
        def known_urls
          entries.map { |entry| entry.notice&.dig('pdf_url') }.compact.to_set
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

        # Records what the page said of a decision, and the day it was seen
        # @param [String] sha
        # @param [Page::Notice] notice
        # @param [Date] seen_on
        def see(sha, notice, seen_on)
          previous = read_json("#{sha}.notice.json") || {}
          write_json("#{sha}.notice.json",
                     previous.merge(notice.to_h.compact.transform_keys(&:to_s))
                             .merge('first_seen_on' => previous['first_seen_on'] || seen_on.iso8601,
                                    'last_seen_on' => seen_on.iso8601))
        end

        # @param [String] sha
        # @param [Hash] ocr
        def keep_ocr(sha, ocr)
          write_json("#{sha}.ocr.json", ocr)
        end

        private

          def read_json(file)
            path = dir.join(file)
            path.exist? ? JSON.parse(path.read) : nil
          end

          def write_json(file, data)
            path = dir.join(file)
            path.write(JSON.pretty_generate(data))
          end
      end
    end
  end
end
