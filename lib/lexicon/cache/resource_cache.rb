# frozen_string_literal: true

module Lexicon
  module Cache
    class ResourceCache
      def initialize(file_hasher:, root:)
        @file_hasher = file_hasher
        @root = root
        @cache = @root.join('.cache')
      end

      def fetch(resource, &block)
        if fresh?(resource)
          true
        elsif block.nil?
          false
        else
          file = block.call
          file.exist? && add(resource, file)
        end
      end

      # @param [Datasource::Resource] resource
      # @param [Pathname] file
      # @return [Boolean]
      def add(resource, file)
        entry = CacheEntry.new(
          hash: @file_hasher.hash(file),
          key: resource.key,
          name: resource.name,
          stat: {
            mtime: file.mtime,
            size: file.size
          }
        )

        write_cache_entry(entry, cache_file_path(resource.name))
      end

      # @param [Resource] resource
      # @return [Boolean]
      def fresh?(resource)
        cache_file = cache_file_path(resource.name)

        resource_path(resource.name).file? && cache_file.file? && cache_entry_valid?(cache_file, resource)
      end

      private

        # @param [Pathname] path
        # @param [Resource] resource
        def cache_entry_valid?(path, resource)
          entry = read_cache_entry(path)

          !entry.nil? && cache_entry_fresh?(entry, resource)
        end

        # @param [CacheEntry] entry
        # @param [Resource] resource
        # @return [Boolean]
        def cache_entry_fresh?(entry, resource)
          path = resource_path(resource.name)

          entry.key == resource.key && (stat_valid?(entry.stat, path) || hash_valid?(entry.hash, path))
        end

        # @param [Hash] expected
        # @param [Pathname] file
        # @return [Boolean]
        def stat_valid?(expected, file)
          expected.fetch(:mtime) == file.mtime && expected.fetch(:size) == file.size
        rescue KeyError
          false
        end

        # @param [String] expected
        # @param [Pathname] resource_path
        # @return [Boolean]
        def hash_valid?(expected, resource_path)
          expected == @file_hasher.hash(resource_path)
        end

        # @param [Strine] name
        # @return [Pathname]
        def resource_path(name)
          @root.join(name)
        end

        # @param [String] name
        # @return [Pathname]
        def cache_file_path(name)
          @cache.join("#{name}.json")
        end

        CACHE_KEYS = %i[hash key name stat].freeze

        # @param [Pathname] path
        # @return [CacheEntry, nil]
        def read_cache_entry(path)
          data = read_cache_file(path)

          if CACHE_KEYS.all? { |k| data.key?(k) }
            CacheEntry.new(**data.slice(*CACHE_KEYS))
          else
            path.unlink

            nil
          end
        end

        # @param [Pathname] path
        # @return [Hash<Symbol => String>]
        def read_cache_file(path)
          d = JSON.parse(path.read)

          if d.is_a?(Hash)
            d.transform_keys(&:to_sym)
          else
            {}
          end
        rescue JSON::ParserError
          {}
        end

        # @param [CacheEntry] entry
        # @return [Boolean]
        def write_cache_entry(entry, path)
          ensure_cache_dir

          path.open('w') { |f| f.write(entry.to_h.to_json) }

          true
        rescue StandardError => e
          log("Unable to write cache file to #{path}; #{e.message}")

          false
        end

        def ensure_cache_dir
          @cache.mkdir unless @cache.exist?
        end
    end
  end
end
