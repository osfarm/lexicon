# frozen_string_literal: true

require 'base64'
require 'json'

module Datasources
  class Bsv
    # Has the Claude API read the bulletins, through the Message Batches API (half price, answers within the day).
    #
    # Each bulletin goes to Haiku; a few of them, of different sections, also go to Opus, whose answers only
    # measure those of Haiku (`Control`). The PDF itself is sent: gauges, cursors and coloured tables are read.
    #
    # A batch sent is written in `raw/bsv/batches/<id>.json` before anything else, so that a collect stopped, or one
    # that stopped waiting, finds it again the next time. Each answer is kept beside its PDF, in
    # `<sha>.<haiku|opus>.json`, with the model, the version of the instructions and what the API said:
    #
    #   succeeded   the answer (`answer`), or its raw text when it is no JSON; `stop_reason` says when it was cut,
    #               and a cut answer is asked again with room for twice as many tokens
    #   errored, expired, canceled   sent again by the next collect, twice at most (`attempts`)
    #   too_large   not sent: over the limits of a document
    #
    # The key `fix` is the correction of an extraction made under former instructions (`Correction`): Haiku again,
    # on the text of the pages, kept in `<sha>.fix.json` with the batch of the extraction it corrects (`of`).
    class Extractor
      MODELS = { 'haiku' => 'claude-haiku-5-5', 'opus' => 'claude-opus-5-5', Correction::KEY => 'claude-haiku-5-5' }.freeze
      RETRIED = %w[errored expired canceled].freeze
      ATTEMPTS = 3
      MAX_TOKENS = 32_000
      # For a bulletin whose answer was cut: Haiku 5.5 writes up to 128K tokens
      MAX_TOKENS_AGAIN = 64_000
      # A correction answers a few lines at most
      MAX_TOKENS_FIX = 8_000
      # The API takes 256 MB a batch; half of it leaves room for the base64 and the instructions
      MAX_BATCH_BYTES = 100 * 1024 * 1024
      # A document: 32 MB, 100 pages
      MAX_PDF_BYTES = 30 * 1024 * 1024
      MAX_PAGES = 100
      POLL = 60

      attr_reader :archive

      # @param [Archive] archive
      # @param [#messages] client an Anthropic::Client
      # @param [#call] say
      # @param [#call] sleep waits a number of seconds
      def initialize(archive, client:, say: nil, sleep: nil)
        @archive = archive
        @client = client
        @say = say || ->(_) {}
        @sleep = sleep || ->(seconds) { Kernel.sleep(seconds) }
      end

      # @param [Array<Archive::Entry>] entries
      # @param [String] key haiku or opus
      # @return [Array<Archive::Entry>] those that have no answer of that model yet, or one to ask again, and are in
      #   no batch waiting
      def wanted(entries, key)
        waiting = archive.batches.flat_map { |batch| batch['requests'].values }.to_set
        entries.select do |entry|
          next false if waiting.include?([entry.sha, key])

          answer = archive.answer(entry.sha, key)
          answer.nil? || ((RETRIED.include?(answer['result']) || cut?(answer)) && answer['attempts'].to_i < ATTEMPTS)
        end
      end

      # @param [Array<Archive::Entry>] entries
      # @return [Array<Archive::Entry>] those whose extraction follows former instructions and has no correction of
      #   today, of that extraction, yet (or one to ask again), and are in no batch waiting; one with no line has
      #   nothing to correct
      def wanted_fixes(entries)
        version = Schema.version
        fix_version = Correction.version
        waiting = archive.batches.flat_map { |batch| batch['requests'].values }.to_set
        entries.select do |entry|
          extraction = archive.answer(entry.sha, 'haiku')
          next false unless extraction && extraction['result'] == 'succeeded' && extraction['stop_reason'] == 'end_turn' &&
                            extraction['answer'].is_a?(Hash) && extraction['version'] != version &&
                            Array(extraction['answer']['lignes']).any?
          next false if waiting.include?([entry.sha, Correction::KEY])

          fix = archive.answer(entry.sha, Correction::KEY)
          next true if fix.nil? || fix['version'] != fix_version || fix['of'] != extraction['batch_id']

          (RETRIED.include?(fix['result']) || cut?(fix)) && fix['attempts'].to_i < ATTEMPTS
        end
      end

      # @return [Boolean] the answer stopped on the limit of tokens
      def cut?(answer)
        answer['result'] == 'succeeded' && answer['stop_reason'] == 'max_tokens'
      end

      # Sends the bulletins, in as many batches as their size asks
      # @param [Array<Array(Archive::Entry, String)>] requests a bulletin and the key of a model
      # @return [Array<String>] the ids of the batches
      def submit(requests)
        version = Schema.version
        system = [{ type: 'text', text: Schema.instructions, cache_control: { type: 'ephemeral' } }]
        fix_system = [{ type: 'text', text: Correction.instructions, cache_control: { type: 'ephemeral' } }]
        sendable = requests.reject { |entry, key| key != Correction::KEY && too_large(entry, key, version) }
        slices(sendable).map do |slice|
          ids = {}
          params = slice.map do |entry, key|
            custom_id = "#{entry.sha}-#{key}"
            ids[custom_id] = [entry.sha, key]
            { custom_id: custom_id, params: key == Correction::KEY ? fix_params(entry, fix_system) : params(entry, key, system) }
          end
          batch = hash(@client.messages.batches.create(requests: params))
          archive.keep_batch(batch[:id], { 'id' => batch[:id], 'version' => version, 'fix_version' => Correction.version,
                                           'sent_at' => Time.now.utc.iso8601, 'requests' => ids })
          @say.call("  batch #{batch[:id]}: #{params.size} bulletins")
          batch[:id]
        end
      end

      # Gathers the answers of the batches that ended, waiting for the others up to `wait` seconds
      # @param [Integer] wait
      # @return [Array<Array(String, String)>] sha and key of each answer kept
      def gather(wait: 0)
        kept = []
        waited = 0
        loop do
          archive.batches.each do |batch|
            state = hash(@client.messages.batches.retrieve(batch['id']))
            next unless state[:processing_status].to_s == 'ended'

            kept.concat(results(batch))
            archive.drop_batch(batch['id'])
          end
          break if archive.batches.empty? || waited >= wait

          @sleep.call(POLL)
          waited += POLL
        end
        archive.batches.each { |batch| @say.call("  batch #{batch['id']} not ended, gathered by the next collect".yellow) }
        kept
      end

      private

        def params(entry, key, system)
          data = Base64.strict_encode64(entry.pdf.binread)
          {
            model: MODELS.fetch(key),
            max_tokens: cut?(archive.answer(entry.sha, key) || {}) ? MAX_TOKENS_AGAIN : MAX_TOKENS,
            system_: system,
            output_config: { effort: 'medium', format: { type: 'json_schema', schema: Schema::SCHEMA } },
            messages: [{ role: 'user', content: [
              { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: data } },
              { type: 'text', text: 'Extrais ce bulletin selon la consigne.' }
            ] }]
          }
        end

        # The text of the pages and the lines already extracted, the corrections only in the answer
        def fix_params(entry, system)
          {
            model: MODELS.fetch(Correction::KEY),
            max_tokens: cut?(archive.answer(entry.sha, Correction::KEY) || {}) ? MAX_TOKENS_FIX * 4 : MAX_TOKENS_FIX,
            system_: system,
            output_config: { effort: 'low', format: { type: 'json_schema', schema: Correction::SCHEMA } },
            messages: [{ role: 'user', content: Correction.message(entry.pages, archive.answer(entry.sha, 'haiku')['answer']) }]
          }
        end

        def too_large(entry, key, version)
          pages = entry.pages&.size.to_i
          return false if entry.pdf.size <= MAX_PDF_BYTES && pages <= MAX_PAGES

          archive.keep_answer(entry.sha, key, { 'model' => MODELS.fetch(key), 'version' => version, 'result' => 'too_large',
                                                'error' => "#{entry.pdf.size} bytes, #{pages} pages" })
          @say.call("  #{entry.sha}: too large for the API (#{entry.pdf.size} bytes, #{pages} pages)".yellow)
          true
        end

        # Requests in batches under MAX_BATCH_BYTES (base64 makes a PDF a third larger)
        def slices(requests)
          slices = [[]]
          size = 0
          requests.each do |request|
            entry, key = request
            bytes = key == Correction::KEY ? JSON.generate(entry.pages).bytesize : entry.pdf.size * 4 / 3
            if slices.last.any? && size + bytes > MAX_BATCH_BYTES
              slices << []
              size = 0
            end
            slices.last << request
            size += bytes
          end
          slices.reject(&:empty?)
        end

        def results(batch)
          @client.messages.batches.results_streaming(batch['id']).filter_map do |response|
            response = hash(response)
            sha, key = batch['requests'][response[:custom_id]]
            next unless sha

            archive.keep_answer(sha, key, answer(response[:result], sha, key, batch))
            [sha, key]
          end
        end

        def answer(result, sha, key, batch)
          previous = archive.answer(sha, key) || {}
          kept = { 'model' => MODELS.fetch(key), 'version' => key == Correction::KEY ? batch['fix_version'] : batch['version'],
                   'batch_id' => batch['id'],
                   'result' => result[:type].to_s, 'answered_on' => Date.today.iso8601,
                   'attempts' => previous['attempts'].to_i + 1 }
          kept['of'] = archive.answer(sha, 'haiku')&.dig('batch_id') if key == Correction::KEY
          return kept.merge('error' => JSON.generate(result[:error] || {})[0, 500]) unless kept['result'] == 'succeeded'

          message = result[:message]
          text = Array(message[:content]).select { |block| block[:type].to_s == 'text' }.map { |block| block[:text] }.join
          kept['stop_reason'] = message[:stop_reason].to_s
          kept['usage'] = message[:usage]&.slice(:input_tokens, :output_tokens, :cache_read_input_tokens,
                                                 :cache_creation_input_tokens)
          kept['answer'] = JSON.parse(text)
          kept
        rescue JSON::ParserError
          kept.merge('text' => text)
        end

        # The SDK answers with models, the tests with hashes: both read as hashes with symbol keys
        def hash(object)
          object.respond_to?(:to_h) ? deep_symbolize(object.to_h) : object
        end

        # The `to_h` of a model of the SDK leaves the models inside it as they are: they are converted too
        def deep_symbolize(value)
          case value
          when Hash then value.to_h { |key, item| [key.to_sym, deep_symbolize(item)] }
          when Array then value.map { |item| deep_symbolize(item) }
          when nil, String, Symbol, Numeric, true, false then value
          else value.respond_to?(:to_h) ? deep_symbolize(value.to_h) : value
          end
        end
    end
  end
end
