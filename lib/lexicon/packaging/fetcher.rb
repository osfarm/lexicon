# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'uri'

module Lexicon
  module Packaging
    # Downloads a repository of packages served over HTTP, such as a private bundle, into a local
    # directory that `server sync` can then load.
    class Fetcher
      class FetchError < StandardError; end

      ATTEMPTS = 5

      # @param [String] base_url address of the repository, without trailing slash
      # @param [String, nil] api_key
      # @param [#call] download ->(url, destination) raising FetchError; the HTTP download by default
      def initialize(base_url:, api_key: nil, download: nil)
        @base_url = base_url.chomp('/')
        @api_key = api_key
        @download = download || method(:http_download)
      end

      # @param [Pathname] to
      # @yieldparam [String] name
      # @yieldparam [String] version
      # @return [Array<String>] names of the datasources fetched
      def fetch(to)
        to.mkpath
        index_file = to.join(".#{Repository::INDEX_FILE}.tmp")
        @download.call("#{@base_url}/#{Repository::INDEX_FILE}", index_file)
        index = JSON.parse(index_file.read, symbolize_names: true)

        names = index.fetch(:datasources, {}).map do |name, entry|
          fetch_package(to, name.to_s, entry.fetch(:current))
          yield name.to_s, entry.fetch(:current) if block_given?

          name.to_s
        end
        # The index goes last: an interrupted download leaves no package designated half-fetched
        File.rename(index_file, to.join(Repository::INDEX_FILE))

        names
      ensure
        FileUtils.rm_f(index_file) if index_file
      end

      private

        def fetch_package(to, name, version)
          dir = to.join(name, version)
          return if dir.join(Manifest::FILE_NAME).file?

          work = to.join(name, ".fetching-#{version}")
          FileUtils.rm_rf(work)
          work.join(Builder::DATA_DIR).mkpath
          remote = "#{@base_url}/#{name}/#{version}"

          [Manifest::FILE_NAME, Builder::STRUCTURE_FILE, Builder::INDEXES_FILE].each do |file|
            @download.call("#{remote}/#{file}", work.join(file))
          end
          Manifest.load(work.join(Manifest::FILE_NAME)).tables.flat_map { |table| table[:files] }.each do |file|
            @download.call("#{remote}/#{file[:path]}", work.join(file[:path]))
            next if Digest::SHA256.file(work.join(file[:path])).hexdigest == file[:sha256]

            raise FetchError.new("#{name}@#{version}: #{file[:path]} does not match its checksum")
          end

          File.rename(work, dir)
        ensure
          FileUtils.rm_rf(work) if work&.exist?
        end

        def http_download(url, destination, attempt = 1)
          uri = URI(url)
          request = Net::HTTP::Get.new(uri)
          request['X-API-Key'] = @api_key unless @api_key.nil?

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request) do |response|
              case response
              when Net::HTTPSuccess
                destination.open('wb') { |file| response.read_body { |chunk| file.write(chunk) } }
              when Net::HTTPTooManyRequests
                raise FetchError.new("#{url}: allowance exhausted") if attempt >= ATTEMPTS

                # The server says how long to wait before asking again
                sleep(response['Retry-After'].to_i.clamp(1, 120))
                return http_download(url, destination, attempt + 1)
              else
                raise FetchError.new("#{url}: HTTP #{response.code} #{response.body.to_s[0, 200]}")
              end
            end
          end
        end
    end
  end
end
