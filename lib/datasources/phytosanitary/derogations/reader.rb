# frozen_string_literal: true

require 'net/http'

module Datasources
  class Phytosanitary
    module Derogations
      # Reads a decision with Mistral OCR: the text of each page, and the fields of `SCHEMA` filled from it
      # (`document_annotation`). The PDF is sent in base64, so it needs no public address.
      class Reader
        class Failed < StandardError; end
        # Mistral still refuses after the waits: the next decisions would be refused too
        class RateLimited < Failed; end

        ENDPOINT = URI('https://api.mistral.ai/v1/ocr')

        # @param [String] api_key
        # @param [String] model
        # @param [Integer] timeout seconds
        def initialize(api_key:, model: OCR_MODEL, timeout: 180)
          @api_key = api_key
          @model = model
          @timeout = timeout
        end

        # @param [String] pdf bytes
        # @return [Hash] 'document_annotation' (Hash) and 'pages' (each with 'index' and 'markdown')
        def read(pdf)
          payload = JSON.generate(body(pdf))
          response = nil
          RETRY_WAITS.each do |wait|
            response = post(payload)
            # A limit of 0 is a setting of the account, not a burst: waiting changes nothing
            break unless response.code == '429' && wait && response['x-ratelimit-limit-req-minute'] != '0'

            sleep(wait)
          end
          raise RateLimited.new("Mistral OCR still answers 429 (#{response['x-ratelimit-limit-req-minute'] || '?'} requests a minute allowed): #{response.body.to_s[0, 200]}") if response.code == '429'
          raise Failed.new("Mistral OCR answered #{response.code}: #{response.body.to_s[0, 300]}") unless response.is_a?(Net::HTTPSuccess)

          self.class.answer(JSON.parse(response.body))
        rescue JSON::ParserError => e
          raise Failed.new("Mistral OCR answered something that is not JSON: #{e.message[0, 200]}")
        end

        # Seconds waited before asking again when Mistral answers 429 (too many requests); nil: give up
        RETRY_WAITS = [5, 20, 60, nil].freeze

        def post(payload)
          Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, read_timeout: @timeout) do |http|
            request = Net::HTTP::Post.new(ENDPOINT)
            request['Authorization'] = "Bearer #{@api_key}"
            request['Content-Type'] = 'application/json'
            request.body = payload
            http.request(request)
          end
        end

        # @return [Hash] the body of the request
        def body(pdf)
          {
            model: @model,
            document: { type: 'document_url', document_url: "data:application/pdf;base64,#{Base64.strict_encode64(pdf)}" },
            document_annotation_format: {
              type: 'json_schema',
              json_schema: { name: 'derogation', description: INSTRUCTIONS, schema: SCHEMA, strict: true }
            },
            include_image_base64: false
          }
        end

        # Keeps what is read again later: the fields, and the text of the pages
        # @param [Hash] data the answer of Mistral
        # @return [Hash]
        def self.answer(data)
          pages = data['pages']
          raise Failed.new('Mistral OCR answered with no pages') unless pages.is_a?(Array) && pages.any?

          annotation = annotation(data['document_annotation'])
          raise Failed.new('Mistral OCR answered with no document_annotation') if annotation.nil?

          {
            'model' => data['model'],
            'read_at' => Time.now.utc.iso8601,
            'document_annotation' => annotation,
            'pages' => pages.map { |page| { 'index' => page['index'], 'markdown' => page['markdown'] } }
          }
        end

        # @return [Hash, nil] `document_annotation`, which Mistral gives as a JSON string
        def self.annotation(value)
          return value if value.is_a?(Hash)
          return nil unless value.is_a?(String)

          text = value.strip.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '')
          parsed = JSON.parse(text)
          parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
