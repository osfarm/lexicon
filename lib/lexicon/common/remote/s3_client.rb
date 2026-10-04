# frozen_string_literal: true

module Lexicon
  module Common
    module Remote
      class S3Client
        # @return [Aws::S3::Client]
        attr_reader :raw

        # @param [Aws::S3::Client] raw
        def initialize(raw:)
          @raw = raw
        end

        # @return [Array<Object>]
        def ls(bucket)
          raw.list_objects_v2(bucket: bucket)
            .to_h
            .fetch(:contents, [])
        end

        # @param [String] name
        # @return [Boolean]
        def bucket_exist?(name)
          if raw.head_bucket(bucket: name)
            true
          else
            false
          end
        rescue StandardError
          false
        end

        # @param [String] name
        def ensure_bucket_absent(name)
          if bucket_exist?(name)
            raw.delete_bucket(bucket: name)
          end
        end
      end
    end
  end
end
