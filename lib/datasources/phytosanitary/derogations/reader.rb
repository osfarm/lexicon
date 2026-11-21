# frozen_string_literal: true

require 'open3'

module Datasources
  class Phytosanitary
    module Derogations
      # Reads a decision in two steps: `ocr.py` gives the text of each page (text layer of the PDF, Tesseract for a
      # scan), then Claude Haiku fills the fields of `SCHEMA` from that text (structured output). What is kept has
      # the shape the former readings of Mistral OCR had: `document_annotation` and `pages[].markdown`.
      class Reader
        class Failed < StandardError; end
        # The API still refuses after the retries of the SDK: the next decisions would be refused too
        class RateLimited < Failed; end

        SCRIPT = Pathname.new(__dir__).join('ocr.py')
        MAX_TOKENS = 16_000

        # @param [#messages] client an Anthropic::Client
        # @param [String] model
        def initialize(client:, model: MODEL)
          @client = client
          @model = model
        end

        # @param [Pathname] pdf
        # @return [Hash] 'document_annotation' (Hash) and 'pages' (each with 'index' and 'markdown')
        def read(pdf)
          text = self.class.text(pdf)
          message = self.class.hash(@client.messages.create(**params(text['pages'])))
          self.class.answer(message, text)
        rescue Anthropic::Errors::RateLimitError => e
          raise RateLimited.new("Claude still answers 429: #{e.message[0, 200]}")
        rescue Anthropic::Errors::APIError => e
          raise Failed.new("Claude answered #{e.class.name.demodulize}: #{e.message[0, 300]}")
        end

        # @return [Hash] the body of the request
        def params(pages)
          {
            model: @model,
            max_tokens: MAX_TOKENS,
            system_: SYSTEM,
            output_config: { effort: 'medium', format: { type: 'json_schema', schema: SCHEMA } },
            messages: [{ role: 'user', content: self.class.message(pages) }]
          }
        end

        # @param [Pathname] pdf
        # @return [Hash] 'engine' and 'pages', as printed by `ocr.py`
        def self.text(pdf)
          out, err, status = Open3.capture3('python3', SCRIPT.to_s, pdf.to_s)
          raise Failed.new("ocr.py failed: #{err.lines.last(3).join.strip[0, 300]}") unless status.success?

          data = JSON.parse(out)
          raise Failed.new('no text in the PDF, even read by Tesseract') if data['pages'].all? { |page| page['markdown'].to_s.strip.empty? }

          data
        rescue JSON::ParserError => e
          raise Failed.new("ocr.py printed something that is not JSON: #{e.message[0, 200]}")
        end

        # @return [String] the pages, each in its tag
        def self.message(pages)
          pages.map { |page| "<page numero=\"#{page['index'].to_i + 1}\">\n#{page['markdown']}\n</page>" }.join("\n")
        end

        # Keeps what is read again later: the fields, and the text of the pages
        # @param [Hash] message the answer of Claude, with symbol keys
        # @param [Hash] text what `ocr.py` printed
        # @return [Hash]
        def self.answer(message, text)
          stop = message[:stop_reason].to_s
          raise Failed.new("Claude stopped on #{stop}") unless stop == 'end_turn'

          body = Array(message[:content]).select { |block| block[:type].to_s == 'text' }.map { |block| block[:text] }.join
          annotation = JSON.parse(body)
          raise Failed.new('Claude answered with no fields') unless annotation.is_a?(Hash)

          {
            'model' => message[:model].to_s,
            'ocr' => text['engine'],
            'read_at' => Time.now.utc.iso8601,
            'usage' => message[:usage]&.slice(:input_tokens, :output_tokens)&.transform_keys(&:to_s),
            'document_annotation' => annotation,
            'pages' => text['pages'].map { |page| { 'index' => page['index'], 'markdown' => page['markdown'] } }
          }
        rescue JSON::ParserError => e
          raise Failed.new("Claude answered something that is not JSON: #{e.message[0, 200]}")
        end

        # The SDK answers with models, the tests with hashes: both read as hashes with symbol keys
        def self.hash(object)
          case object
          when Hash then object.to_h { |key, item| [key.to_sym, hash(item)] }
          when Array then object.map { |item| hash(item) }
          when nil, String, Symbol, Numeric, true, false then object
          else object.respond_to?(:to_h) ? hash(object.to_h) : object
          end
        end
      end
    end
  end
end
