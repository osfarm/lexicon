# frozen_string_literal: true

require 'json'
require 'time'

module Lexicon
  module Server
    # Publishes in the repository what is in service, for those who cannot reach the database.
    class StatusFile
      FILE_NAME = 'status.json'

      # @param [Packaging::Repository] repository
      # @param [Meta] meta
      def initialize(repository:, meta:)
        @repository = repository
        @meta = meta
      end

      # @return [Hash]
      def content
        {
          updated_at: Time.now.utc.iso8601,
          packages: @meta.all_installed.map do |package|
            [package.name, { version: package.version, loaded_at: package.loaded_at.utc.iso8601, stale: package.stale }]
          end.to_h,
          last_failures: @meta.recent_loads(50).select { |load| load['state'] == 'failed' }.first(10).map do |load|
            { name: load['name'], version: load['version'], at: load['started_at'], reasons: JSON.parse(load['detail'] || '{}')['reasons'] }
          end
        }
      end

      # Written aside then renamed: a reader never sees a partial file
      def write
        temporary = @repository.root.join(".#{FILE_NAME}.tmp")
        temporary.write("#{JSON.pretty_generate(content)}\n")
        File.rename(temporary, @repository.root.join(FILE_NAME))
      end
    end
  end
end
