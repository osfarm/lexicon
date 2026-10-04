# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      module V1
        class PackageBuilder < Package
          def initialize(version:, dir:)
            super(
              file_sets: [],
              version: version,
              dir: dir,
              checksum_file: dir.join(CHECKSUM_FILE_NAME),
              spec_file: dir.join(SPEC_FILE_NAME)
            )

            FileUtils.mkdir_p(data_dir)
          end

          # @param [String] id
          # @param [String] name
          # @param [Pathname] structure
          #   Takes ownership of the file (moves it to the correct folder)
          # @param [Array<String>] tables
          # @param [Pathname] data
          #   Takes ownership of the file (moves it to the correct folder)
          # @param [String] data_ext
          def add_file_set(id, name:, structure:, tables:, data: nil, data_ext: '.sql')
            # @type [Pathname] structure_file_path
            structure_file_path = data_dir.join(structure_file_name(id))
            FileUtils.mv(structure.to_s, structure_file_path.to_s)

            # @type [Pathname] data_file_path
            data_name = if data.nil?
                          nil
                        else
                          dname = data_file_name(id, data_ext)
                          path = data_dir.join(dname)
                          FileUtils.mv(data, path)

                          dname
                        end

            file_sets << SourceFileSet.new(
              id: id,
              name: name,
              structure: structure_file_name(id),
              data: data.nil? ? nil : data_name,
              tables: tables
            )
          end

          def as_package
            Package.new(version: version, dir: dir, file_sets: file_sets, checksum_file: checksum_file, spec_file: spec_file)
          end

          private

            def data_file_name(id, ext)
              "#{id}#{ext}"
            end

            def structure_file_name(id)
              "#{id}__structure.sql"
            end
        end
      end
    end
  end
end
