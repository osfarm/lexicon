# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      module V2
        class PackageBuilder < Package
          def initialize(version:, dir:)
            super(
              file_sets: [],
              version: version,
              dir: dir,
              checksum_file: dir.join(CHECKSUM_FILE_NAME),
              spec_file: dir.join(SPEC_FILE_NAME),
            )

            FileUtils.mkdir_p(data_dir)
          end

          # @param [String] id
          # @param [String] name
          # @param [Pathname] structure
          #   Takes ownership of the file (moves it to the correct folder)
          # @param [Hash{String=>Array<Pathname>}] tables
          #   Takes ownership of the files (moves them to the correct folder)
          def add_file_set(id, name:, structure:, tables:)
            # @type [Pathname] structure_file_path
            structure_file_path = data_dir.join(structure_file_name(id))
            FileUtils.mv(structure.to_s, structure_file_path.to_s)

            table_data = tables.map do |table_name, files|
              index = 0

              file_names = files.map do |file|
                file_name = "#{table_name}_#{index}.csv.gz"
                FileUtils.mv(file.to_s, data_dir.join(file_name))
                index += 1

                file_name
              end

              [table_name, file_names]
            end

            file_sets << SourceFileSet.new(
              id: id,
              name: name,
              structure: structure_file_name(id),
              tables: table_data.to_h
            )
          end

          def as_package
            Package.new(
              checksum_file: checksum_file,
              dir: dir,
              file_sets: file_sets,
              spec_file: spec_file,
              version: version,
            )
          end

          private

            def structure_file_name(id)
              "#{id}__structure.sql"
            end
        end
      end
    end
  end
end
