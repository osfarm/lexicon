# frozen_string_literal: true

require 'net/http'

module Datasources
  class Bsv
    # A polite client for the sites of the DRAAF: it says who it is, reads `robots.txt` once per site and keeps to
    # it, and waits between two requests to a site (one second at least, more if `Crawl-delay` asks for it).
    class Http
      class Failed < StandardError; end

      USER_AGENT = 'Lexicon OSFarm (+https://lexicon.osfarm.org)'
      MAX_REDIRECTS = 5

      # @param [Float] delay seconds between two requests to the same site
      # @param [Integer] timeout seconds
      def initialize(delay: 1.0, timeout: 60)
        @delay = delay
        @timeout = timeout
        @last = {}
        @robots = {}
      end

      # @param [String] url
      # @return [Array(String, String)] the body, in UTF-8, and the address it came from after redirections
      def get(url)
        response, final = request(url)
        [response.body.to_s.dup.force_encoding('UTF-8').scrub, final]
      end

      # Downloads a file, unless `robots.txt` forbids it
      # @param [String] url
      # @param [Pathname] path where it is written
      # @return [Pathname]
      def download(url, path)
        raise Failed.new("#{url} is forbidden by robots.txt") unless allowed?(url)

        response, = request(url)
        body = response.body.to_s
        # A connection cut short leaves a truncated file, a missing file is sometimes a page of the site: neither is kept
        expected = response['content-length']&.to_i
        raise Failed.new("#{url} was cut short (#{body.bytesize} of #{expected} bytes)") if expected && body.bytesize != expected
        raise Failed.new("#{url} is no PDF") unless body.start_with?('%PDF')

        FileUtils.mkdir_p(path.dirname)
        path.binwrite(body)
        path
      end

      # @param [String] url
      # @return [Boolean] false when `robots.txt` of its site forbids it
      def allowed?(url)
        uri = URI(url)
        robots(uri).allowed?(uri.request_uri)
      end

      private

        def request(url, redirects = MAX_REDIRECTS)
          uri = URI(url)
          wait(uri.host)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout,
                                                         read_timeout: @timeout) do |http|
            request = Net::HTTP::Get.new(uri)
            request['User-Agent'] = USER_AGENT
            http.request(request)
          end
          if response.is_a?(Net::HTTPRedirection) && redirects.positive?
            return request(URI.join(url, response['location']).to_s, redirects - 1)
          end
          raise Failed.new("#{url} answered #{response.code}") unless response.is_a?(Net::HTTPSuccess)

          [response, url]
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
          raise Failed.new("#{url}: #{e.class}: #{e.message}")
        end

        def wait(host)
          delay = [@delay, @robots[host]&.crawl_delay.to_f].max
          elapsed = Time.now - (@last[host] || Time.at(0))
          sleep(delay - elapsed) if elapsed < delay
          @last[host] = Time.now
        end

        def robots(uri)
          @robots[uri.host] ||= begin
            response, = request("#{uri.scheme}://#{uri.host}/robots.txt")
            Robots.parse(response.body.to_s)
          rescue Failed
            Robots.parse('')
          end
        end
    end
  end
end
