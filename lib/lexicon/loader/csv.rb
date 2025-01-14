# frozen_string_literal: true

module Lexicon
  module Loader
    class Csv
      def initialize(psql:)
        @psql = psql
      end

      def load(file, table_name:, search_path:, **options)
        encoding = detect_encoding(file)
        col_sep = options.fetch(:col_sep, ',')

        headers = File.open(file) do |f|
          utf8_encoded_content = CharlockHolmes::Converter.convert f.readline, encoding, 'UTF-8'
          h = CSV.parse_line(utf8_encoded_content, col_sep: col_sep) || []

          h.map.with_index { |header, index| header.presence || "padding#{index}" }
        end

        raise StandardError.new("Unable to load #{file}: headers are empty") if headers.empty?

        @psql.execute(<<~SQL, search_path: search_path)
            DROP TABLE IF EXISTS #{table_name};
            CREATE TABLE #{table_name} (
            #{headers.map { |h| "#{StringUtils.symbolize(h)} VARCHAR" }.join(", \n")}
          );
        SQL

        @psql.execute_raw(<<~SQL)
          \\copy "#{search_path.first}"."#{table_name}" FROM '#{file.expand_path}' WITH CSV HEADER DELIMITER '#{col_sep}' ENCODING '#{encoding}'
        SQL
      end

      private

        def detect_encoding(file)
          detector = CharlockHolmes::EncodingDetector.new
          detection = detector.detect(File.read(file))

          detection[:encoding]
        end
    end
  end
end
