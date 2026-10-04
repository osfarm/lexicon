# frozen_string_literal: true

using Corindon::Result::Ext

module Lexicon
  module Common
    module Remote
      class PackageDownloader < RemoteBase
        # @param [S3Client] s3
        # @param [Pathname] out_dir
        # @param [DirectoryPackageLoader] package_loader
        def initialize(s3:, out_dir:, package_loader:)
          super(s3: s3)

          @out_dir = out_dir
          @package_loader = package_loader
        end

        # @param [Semantic::Version] version
        # @return [Corindon::Result::Result]
        def download(version)
          rescue_failure do
            bucket = version.to_s

            if s3.bucket_exist?(bucket)
              Dir.mktmpdir(nil, out_dir) do |tmp_dir|
                tmp_dir = Pathname.new(tmp_dir)

                download_spec_files(bucket, tmp_dir).unwrap!

                package = package_loader.load_package(tmp_dir.basename.to_s)
                if !package.nil?
                  puts "[  OK ] Found package with key #{version}, version is #{package.version}".green

                  download_data_files(package, bucket).unwrap!

                  dest_dir = out_dir.join(version.to_s)
                  FileUtils.mkdir_p(dest_dir)

                  tmp_dir.children.each do |child|
                    FileUtils.mv(child.to_s, dest_dir.join(child.basename).to_s)
                  end

                  Success(package)
                else
                  puts "[ NOK ] The remote contains a bucket '#{version}' but it does not contains a valid package.".red

                  Failure(StandardError.new("The folder #{bucket} on the server does not contain a valid package"))
                end
              end
            else
              Failure(StandardError.new("The server does not have a directory named #{bucket}"))
            end
          end
        end

        private

          def download_data_files(package, bucket)
            rescue_failure do
              threads = package.files.map do |file|
                Thread.new do
                  destination = package.dir.join(file.path)
                  FileUtils.mkdir_p(destination.dirname)

                  s3.raw.get_object(bucket: bucket, key: file.to_s, response_target: destination)

                  puts "[  OK ] Downloaded #{file}".green
                end
              end

              threads.each(&:join)

              Success(nil)
            end
          end

          def download_spec_files(bucket, tmp_dir)
            rescue_failure do
              s3.raw.get_object(
                bucket: bucket,
                key: Package::Package::SPEC_FILE_NAME,
                response_target: tmp_dir.join(Package::Package::SPEC_FILE_NAME).to_s
              )
              s3.raw.get_object(
                bucket: bucket,
                key: Package::Package::CHECKSUM_FILE_NAME,
                response_target: tmp_dir.join(Package::Package::CHECKSUM_FILE_NAME).to_s
              )

              Success(nil)
            end
          end

          # @return [DirectoryPackageLoader]
          attr_reader :package_loader
          # @return [Pathname]
          attr_reader :out_dir
      end
    end
  end
end
