# frozen_string_literal: true

require 'json'

module Lexicon
  module Commands
    class RemoteCommand < ContainerAwareCommand
      desc 'upload VERSION', 'Uploads the version to the configured S3 storage'
      def upload(version)
        # @type [Common::Package::PackageUploader] uploader
        uploader = get('production.package.uploader')
        # @type [Common::Package::DirectoryPackageLoader]
        loader = get('production.package.loader')

        semver = Semantic::Version.new(version) rescue nil

        if semver.nil?
          puts "[ NOK ] #{version} is not a valid version.".red
        elsif (package = loader.load_package(semver.to_s)).nil?
          puts "[ NOK ] No package found for version #{semver}.".red
        else
          result = uploader.upload(package)

          if result.success?
            make_bucket_public(semver.to_s)
            puts "[  OK ] Version #{semver} uploaded.".green
          else
            puts "[ NOK ] Error while uploading: #{result.error}".red
          end
        end
      end

      desc 'delete VERSION', 'Deletes a version from the S3 storage'
      def delete(version)
        # @type [Aws::S3::Client] s3
        s3 = get('minio.client')

        semver = Semantic::Version.new(version) rescue nil

        if semver.nil?
          puts "[ NOK ] #{version} is not a valid version.".red
        else
          bucket = semver.to_s

          if bucket_exist?(s3, bucket)
            s3.list_objects_v2(bucket: bucket)
              .to_h
              .fetch(:contents, [])
              .each { |content| s3.delete_object(bucket: bucket, key: content.fetch(:key)) }
            s3.delete_bucket(bucket: bucket)

            puts "[  OK ] The version #{semver} has been deleted from the server".green
          else
            puts "[ NOK ] The version #{semver} does not exist on the server".red
          end
        end
      end

      desc 'download VERSION', 'Download the given version from the server'
      def download(version)
        # @type [Common::Package::PackageDownloader] uploader
        downloader = get('production.package.downloader')
        # @type [Common::Package::DirectoryPackageLoader]
        loader = get('production.package.loader')

        semver = Semantic::Version.new(version) rescue nil

        if semver.nil?
          puts "[ NOK ] #{version} is not a valid version.".red
        elsif !loader.load_package(semver.to_s).nil?
          puts "[ NOK ] You already have the version #{semver} locally.".red
        else
          result = downloader.download(semver)

          if result.success?
            puts "[  OK ] The version #{semver} has been downloaded."
          else
            puts '[ NOK ] Error while downloading.'.red
            puts result.error.inspect.yellow
          end
        end
      end

      private

        # Applies a MinIO "download" policy on the bucket so its objects can be
        # downloaded anonymously (without credentials), e.g. for the open source
        # distribution. Equivalent of `mc anonymous set download <alias>/<bucket>`.
        #
        # Files then become reachable at:
        #   #{MINIO_HOST}/<version>/<key>   (force_path_style is enabled)
        #
        # @param [String] bucket
        def make_bucket_public(bucket)
          # @type [Aws::S3::Client] s3
          s3 = get('minio.client')

          policy = {
            'Version' => '2012-10-17',
            'Statement' => [
              {
                'Effect' => 'Allow',
                'Principal' => { 'AWS' => ['*'] },
                'Action' => ['s3:GetBucketLocation', 's3:ListBucket'],
                'Resource' => ["arn:aws:s3:::#{bucket}"],
              },
              {
                'Effect' => 'Allow',
                'Principal' => { 'AWS' => ['*'] },
                'Action' => ['s3:GetObject'],
                'Resource' => ["arn:aws:s3:::#{bucket}/*"],
              },
            ],
          }

          s3.put_bucket_policy(bucket: bucket, policy: JSON.dump(policy))
          puts "[  OK ] Anonymous download enabled for version #{bucket}".green
        rescue StandardError => e
          puts "[ WARN ] Could not enable anonymous download on #{bucket}: #{e.message}".yellow
        end

        # @param [Aws::S3::Client] s3
        # @param [String] name
        # @return [Boolean]
        def bucket_exist?(s3, name)
          if s3.head_bucket(bucket: name)
            true
          else
            false
          end
        rescue StandardError
          false
        end
    end
  end
end
