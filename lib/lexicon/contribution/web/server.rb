# frozen_string_literal: true

require 'socket'

module Lexicon
  module Contribution
    module Web
      # Serves the local interface over HTTP with nothing but the standard library: one request per
      # connection, which is enough for one person on one machine.
      class Server
        # A table dropped from the browser is not larger than this
        MAXIMUM_BODY = 200 * 1024 * 1024
        REASONS = { 200 => 'OK', 303 => 'See Other', 400 => 'Bad Request', 403 => 'Forbidden', 404 => 'Not Found',
                    413 => 'Payload Too Large', 422 => 'Unprocessable Entity', 500 => 'Internal Server Error' }.freeze

        # Online, where the server is shared
        HOSTED_MAXIMUM_BODY = 50 * 1024 * 1024

        # @param [#call] app
        # @param [String] host
        # @param [Integer] port
        # @param [Integer] maximum_body
        def initialize(app, host:, port:, maximum_body: MAXIMUM_BODY)
          @app = app
          @host = host
          @port = port
          @maximum_body = maximum_body
        end

        # Serves until interrupted.
        def run
          server = TCPServer.new(@host, @port)
          loop do
            Thread.new(server.accept) { |client| serve(client) }
          end
        rescue Interrupt
          nil
        ensure
          server&.close
        end

        private

          def serve(client)
            request = read(client)
            response = request.is_a?(App::Request) ? @app.call(request) : failure(request)
            write(client, response)
          rescue StandardError => e
            write(client, failure(500, "#{e.class}: #{e.message}"))
          ensure
            client.close
          end

          # @return [App::Request, Integer] the request, or the status that refuses it
          def read(client)
            verb, path, = client.gets.to_s.split
            return 400 if path.nil?

            headers = {}
            while (line = client.gets) && !line.strip.empty?
              name, value = line.split(':', 2)
              headers[name.strip.downcase] = value.to_s.strip
            end
            length = headers['content-length'].to_i
            return 413 if length > @maximum_body

            App::Request.new(verb: verb, path: path, headers: headers, body: length.positive? ? client.read(length) : '')
          end

          def failure(status, message = nil)
            App::Response.new(status: status, headers: { 'Content-Type' => 'text/plain; charset=utf-8' }, body: message || REASONS[status])
          end

          def write(client, response)
            body = response.body.to_s.b
            headers = response.headers.merge('Content-Length' => body.bytesize, 'Connection' => 'close', 'Cache-Control' => 'no-store')

            client.write("HTTP/1.1 #{response.status} #{REASONS.fetch(response.status, 'OK')}\r\n")
            headers.each { |name, value| client.write("#{name}: #{value}\r\n") }
            client.write("\r\n")
            client.write(body)
          rescue Errno::EPIPE, Errno::ECONNRESET
            nil
          end
      end
    end
  end
end
