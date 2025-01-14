# frozen_string_literal: true

module Lexicon
  class CsvFixer
    attr_reader :dir

    def initialize(dir)
      @dir = dir
    end

    def fix(file, out:, headers: nil, delimiter: ',')
      file = dir.join(file)
      out = dir.join(out)

      detector = CharlockHolmes::EncodingDetector.new
      detection1 = detector.detect(File.read(file))
      encoding = detection1[:encoding]

      File.open(file, 'r') do |f|
        File.open(out, 'w') do |o|
          # Skip headers if they are provided
          if headers.present?
            f.readline
            headers = headers.map { |h| "\"#{h}\"" }
            o.write("#{headers.join(delimiter)}\r\n")
          end

          o.write(CharlockHolmes::Converter.convert(f.read, encoding, 'UTF-8').gsub(/^\r\n$/, ''))
        end
      end
    end
  end
end
