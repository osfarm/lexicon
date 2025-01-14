# frozen_string_literal: true

module Lexicon
  module Package
    class PackageCreator
      include Common::Mixin::LoggerAware

      # @param [Pathname] dir
      # @param [PackageHasher] hasher
      # @param [Common::Package::DirectoryPackageLoader] loader
      def initialize(dir:, hasher:, loader:)
        @dir = dir
        @hasher = hasher
        @loader = loader
      end

      # @param [Semantic::Version] version
      # @param [Boolean] force
      # @yieldparam [Common::Package::PackageBuilder] package
      # @yieldparam [Pathname] dir
      # @return [Common::Package::Package, nil]
      def create_package(version, force: false, &block)
        version_dir = @dir.join(version.to_s)

        if version_dir.exist? && !force
          nil
        else
          if version_dir.exist?
            log('Removing already existing package...')

            FileUtils.rm_rf(version_dir)
          end

          Dir.mktmpdir(nil, @dir) do |package_temp_dir|
            package_temp_dir = Pathname.new(package_temp_dir)

            package = Common::Package::V2::PackageBuilder.new(version: version, dir: package_temp_dir)

            Dir.mktmpdir(nil, @dir) do |dir|
              dir = Pathname.new(dir)

              block.call(package, dir)
            end

            write_manifest(package)

            puts 'Computing package checksum'
            @hasher.compute_package_hash(package)
            puts '[  OK ]'.green + ' Checksum file created'

            FileUtils.mkdir_p(version_dir)

            package_temp_dir.children.each do |child|
              FileUtils.mv(child.to_s, version_dir.join(child.basename).to_s)
            end
          end

          loader.load_package(version.to_s)
        end
      end

      private

        # @return [Common::Package::DirectoryPackageLoader]
        attr_reader :loader

        # @param [Common::Package::PackageBuilder] builder
        def write_manifest(builder)
          builder.spec_file.open('w') do |f|
            f.write(
              JSON.dump({
                          schema_version: 2,
                          version: builder.version,
                          content: builder.file_sets.map do |fs|
                            [
                              fs.id,
                              {
                                name: fs.name,
                                structure: fs.structure,
                                tables: fs.tables
                              }
                            ]
                          end.to_h
                        })
            )
          end
        end
    end
  end
end
