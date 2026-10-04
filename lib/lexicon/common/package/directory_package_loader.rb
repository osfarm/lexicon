# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      class DirectoryPackageLoader
        include Mixin::LoggerAware

        # @return [Pathname]
        attr_reader :root_dir

        # @param [Pathname] root_dir
        # @param [JSONSchemer::Schema::Base] schema_validator
        def initialize(root_dir, schema_validator:)
          @root_dir = root_dir
          @schema_validator = schema_validator
        end

        # @param [String] name
        # @return [Package::Package, nil]
        def load_package(name)
          package_dir = root_dir.join(name.to_s)

          if package_dir.directory?
            load_from_dir(package_dir)
          else
            nil
          end
        end

        protected

          def load_from_dir(dir)
            # @type [Pathname]
            spec_file = dir.join(Package::SPEC_FILE_NAME)
            # @type [Pathname]
            checksum_file = dir.join(Package::CHECKSUM_FILE_NAME)

            if spec_file.exist? && checksum_file.exist?
              json = JSON.parse(spec_file.read)

              if @schema_validator.valid?(json)
                package_version = json.fetch('schema_version', 1)
                case package_version
                when 1
                  load_v1(dir: dir, spec_file: spec_file, checksum_file: checksum_file, json: json)
                when 2
                  load_v2(dir: dir, spec_file: spec_file, checksum_file: checksum_file, json: json)
                else
                  log("Package version #{package_version} is not supported")

                  nil
                end
              else
                log("Package at path #{dir} has invalid manifest")

                nil
              end
            else
              nil
            end
          end

          # @param [Pathname] checksum_file
          # @param [Pathname] dir
          # @param [Hash] json
          # @param [Pathname] spec_file
          # @return [V1::Package]
          def load_v1(dir:, spec_file:, checksum_file:, json:)
            version = Semantic::Version.new(json.fetch('version'))
            file_sets = json.fetch('content').map do |id, values|
              V1::SourceFileSet.new(
                id: id,
                name: values.fetch('name'),
                structure: values.fetch('structure'),
                data: values.fetch('data', nil),
                tables: values.fetch('tables', [])
              )
            end

            V1::Package.new(file_sets: file_sets, version: version, dir: dir, checksum_file: checksum_file, spec_file: spec_file)
          end

          # @param [Pathname] checksum_file
          # @param [Pathname] dir
          # @param [Hash] json
          # @param [Pathname] spec_file
          # @return [V2::Package]
          def load_v2(dir:, spec_file:, checksum_file:, json:)
            version = Semantic::Version.new(json.fetch('version'))
            file_sets = json.fetch('content').map do |id, values|
              V2::SourceFileSet.new(
                id: id,
                name: values.fetch('name'),
                structure: values.fetch('structure'),
                tables: values.fetch('tables', {})
              )
            end

            V2::Package.new(
              file_sets: file_sets,
              version: version,
              dir: dir,
              checksum_file: checksum_file,
              spec_file: spec_file
            )
          end
      end
    end
  end
end
