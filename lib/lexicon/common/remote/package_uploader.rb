# frozen_string_literal: true

using Corindon::Result::Ext

module Lexicon
  module Common
    module Remote
      class PackageUploader < RemoteBase
        include Mixin::LoggerAware

        # @param [Package] package
        # @return [Corindon::Result::Result]
        def upload(package)
          rescue_failure do
            bucket_name = package.version.to_s

            if s3.bucket_exist?(bucket_name)
              Failure(StandardError.new("The server already has a folder named #{bucket_name}"))
            else
              upload_package(package, bucket_name)
            end
          end
        end

        private

          # @return [Corindon::Result::Result]
          def upload_package(package, bucket_name)
            s3.raw.create_bucket(bucket: bucket_name)

            relative_paths = [*base_files, *package.files.map(&:path)]

            upload_files(*relative_paths, from: package.dir, bucket: bucket_name) do |path|
              puts "[  OK ] #{path.basename}".green
            end

            Success(package)
          rescue StandardError => e
            s3.ensure_bucket_absent(bucket_name)

            Failure(e)
          end

          # @param [Array<Pathname>] files
          # @param [Pathname] from
          # @yieldparam [Pathname] path
          def upload_files(*files, bucket:, from:)
            files.each do |path|
              from.join(path).open do |f|
                s3.raw.put_object(bucket: bucket, key: path.to_s, body: f)
              end

              yield path if block_given?
            end
          end

          # @return [Array<Pathname>]
          def base_files
            [
              Pathname.new(Package::Package::CHECKSUM_FILE_NAME),
              Pathname.new(Package::Package::SPEC_FILE_NAME),
            ]
          end
      end
    end
  end
end
