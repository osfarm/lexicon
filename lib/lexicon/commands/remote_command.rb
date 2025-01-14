# frozen_string_literal: true

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
            puts "[  OK ] Version #{semver} uploaded.".green
          else
            puts "[ NOK ] Error while uploading: #{result.error}".red
            log_error(result.error)
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
