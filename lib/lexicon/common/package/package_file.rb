# frozen_string_literal: true

module Lexicon
  module Common
    module Package
      class PackageFile
        class << self
          def new_structure(path)
            new(path, type: STRUCTURE)
          end

          def new_data(path)
            new(path, type: DATA)
          end
        end

        # @return [Pathname]
        attr_reader :path

        # @return [String]
        def to_s
          path.to_s
        end

        # @return [Boolean]
        def data?
          type == DATA
        end

        # @return [Boolean]
        def structure?
          type == STRUCTURE
        end

        private

          attr_reader :type

          DATA = 'data'
          STRUCTURE = 'structure'

          def initialize(path, type:)
            @path = path
            @type = type
          end

      end
    end
  end
end
