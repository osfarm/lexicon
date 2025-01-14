# frozen_string_literal: true

module Lexicon
  module Datasource
    class ResourceCollector
      include Common::Mixin::LoggerAware

      # @param [Pathname] data_dir
      def initialize(data_dir:)
        @data_dir = data_dir
      end

      # @param [Datasource::Resource] resource
      # @param [Pathname] to
      # @return [Boolean]
      def collect(resource, to:)
        dest = to.join(resource.name)

        if resource.is_a?(LocalResource)
          transactionnal(dest) do |tmp|
            collect_local(resource, dest: tmp)
          end
        elsif resource.is_a?(RemoteResource)
          transactionnal(dest) do |tmp|
            collect_remote(resource, dest: tmp)
          end
        else
          false
        end
      end

      private

        # @param [Pathname] dest
        def transactionnal(dest, &block)
          Dir.mktmpdir(nil, dest.dirname) do |dir|
            tmpdest = Pathname.new(dir).join(dest.basename)

            res = block.call(tmpdest)

            if res
              tmpdest.rename(dest)
            end

            res
          end
        end

        # @param [Datasource::LocalResource] resource
        # @param [Pathname] dest
        # @return [Boolean]
        def collect_local(resource, dest:)
          source = @data_dir.join(resource.source)

          log "Copying #{source} to #{dest}"

          FileUtils.cp(source, dest)

          true
        rescue StandardError => e
          log(e.message)
          false
        end

        # @param [Datasource::RemoteResource] resource
        # @param [Pathname] dest
        # @return [Boolean]
        def collect_remote(resource, dest:)
          log "Fetching #{resource.url} to #{dest}"

          curl(url: resource.url, out: dest)
        end

        # @param [String] url
        # @param [Pathname] out
        def curl(url:, out:)
          !!system("curl -C - -L -o '#{out}' '#{url}'")
        end
    end
  end
end
