# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      module V1
        class Package < Common::Package::Package
          # @return [Array<SourceFileSet>]
          attr_reader :file_sets

          # @param [Array<SourceFileSet>] file_sets
          # @param [Pathname] dir
          # @param [Pathname] checksum_file
          # @param [Semantic::Version] version
          def initialize(version:, spec_file:, checksum_file:, dir:, file_sets:)
            super(
              checksum_file: checksum_file,
              dir: dir,
              spec_file: spec_file,
              schema_version: 1,
              version: version,
            )

            @file_sets = file_sets
          end

          # @return [Boolean]
          def valid?
            super && data_dir.directory? && all_sets_valid?
          end

          def files
            structures = file_sets.map { |fs| PackageFile.new_structure(relative_structure_path(fs)) }
            data = file_sets.flat_map do |fs|
              data_path = relative_data_path(fs)

              if data_path.nil?
                []
              else
                [PackageFile.new_data(data_path)]
              end
            end

            [*structures, *data]
          end

          # @param [SourceFileSet] file_set
          # @return [Pathname]
          def data_path(file_set)
            dir.join(relative_data_path(file_set))
          end

          # @return [Pathname]
          def data_dir
            dir.join('data')
          end

          # @return [Pathname, nil]
          def relative_data_path(file_set)
            if file_set.data_path.nil?
              nil
            else
              data_dir.basename.join(file_set.data_path)
            end
          end

          # @return [Pathname]
          def relative_structure_path(file_set)
            data_dir.basename.join(file_set.structure_path)
          end

          private

            def all_sets_valid?
              file_sets.all? do |set|
                data_dir.join(set.structure_path).exist? && !set.data_path.nil? && data_dir.join(set.data_path).exist?
              end
            end
        end
      end
    end
  end
end
