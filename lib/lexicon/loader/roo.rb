# frozen_string_literal: true

module Lexicon
  module Loader
    class Roo
      def initialize(csv_loader:)
        @csv_loader = csv_loader
      end

      def load_xls(file, **options)
        load_roo(file, extension: :xls, **options)
      end

      def load_xlsx(file, **options)
        load_roo(file, extension: :xlsx, **options)
      end

      def load_roo(file, extension: nil, search_path:)
        doc = ::Roo::Spreadsheet.open(file, extension: extension)

        doc.each_with_pagename do |name, sheet|
          table_name = StringUtils.symbolize(name)
          Tempfile.create do |f|
            f.write(sheet.to_csv)
            path = Pathname.new(f.path)
            f.close

            @csv_loader.load(path, table_name: table_name, search_path: search_path)
          end
        end
      end
    end
  end
end
