# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      module V2
        class Package < Common::Package::Package
          # @param [Pathname] dir
          # @param [Pathname] checksum_file
          # @param [Semantic::Version] version
          def initialize(version:, spec_file:, checksum_file:, dir:, file_sets:)
            super(
              checksum_file: checksum_file,
              dir: dir,
              spec_file: spec_file,
              schema_version: 2,
              version: version,
            )

            @file_sets = file_sets
          end

          def valid?
            super
          end

          def files
            file_sets.flat_map { |fs| file_set_files(fs) }
          end

          # @return [SourceFileSet]
          attr_reader :file_sets

          def data_dir
            dir.join('data')
          end

          private

            # @param [SourceFileSet] file_set
            # @return [Array<PackageFile>]
            def file_set_files(file_set)
              relative_data_dir = data_dir.basename

              structure_file = PackageFile.new_structure(relative_data_dir.join(file_set.structure))
              table_files = file_set.tables
                                    .values.flatten(1)
                                    .map { |table_file| PackageFile.new_data(relative_data_dir.join(table_file)) }

              [structure_file, *table_files]
            end
        end
      end
    end
  end
end
