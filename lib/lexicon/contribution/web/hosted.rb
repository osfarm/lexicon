# frozen_string_literal: true

require 'openssl'

module Lexicon
  module Contribution
    module Web
      # The same interface served online, behind the API of the serving side. The API checks the key of the
      # visitor, then relays the request with the name of their workspace and a secret only the two share:
      # this service is never reached from outside. Each workspace is a directory of its own, so that the
      # holder of a key sees the datasets of that key and no other.
      class Hosted
        SECRET_HEADER = 'x-lexicon-contribute-secret'
        WORKSPACE_HEADER = 'x-lexicon-workspace'
        WORKSPACE = /\A[a-z0-9]{1,64}\z/.freeze

        # @param [Pathname] root directory holding one directory per workspace
        # @param [String] secret what the API sends with every request
        # @param [String] prefix path the API serves the interface under
        # @param [Array<String>] taken names of the datasources that already exist
        # @param [Integer] maximum_upload size of the largest table accepted, in bytes
        def initialize(root:, secret:, prefix:, taken: [], maximum_upload: Server::HOSTED_MAXIMUM_BODY)
          raise ArgumentError.new('The secret shared with the API is empty') if secret.to_s.strip.empty?

          @root = root
          @secret = secret
          @prefix = prefix
          @taken = taken
          @maximum_upload = maximum_upload
          @apps = {}
          @lock = Mutex.new
        end

        # @param [App::Request] request
        # @return [App::Response]
        def call(request)
          return refusal(403, 'Cette interface ne répond qu’à l’API du Lexicon.') unless trusted?(request)

          workspace = request.headers[WORKSPACE_HEADER].to_s
          return refusal(400, 'Espace de contribution mal nommé.') unless workspace.match?(WORKSPACE)

          app_of(workspace).call(request)
        end

        private

          def trusted?(request)
            given = request.headers[SECRET_HEADER].to_s

            given.bytesize == @secret.bytesize && OpenSSL.fixed_length_secure_compare(given, @secret)
          end

          def app_of(workspace)
            @lock.synchronize do
              @apps[workspace] ||= begin
                dir = @root.join(workspace)
                dir.mkpath
                App.new(root: dir, taken: @taken, prefix: @prefix, hosted: true, maximum_upload: @maximum_upload)
              end
            end
          end

          def refusal(status, message)
            App::Response.new(status: status, headers: { 'Content-Type' => 'text/plain; charset=utf-8' }, body: message)
          end
      end
    end
  end
end
