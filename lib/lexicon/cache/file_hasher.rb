# frozen_string_literal: true

module Lexicon
  module Cache
    class FileHasher
      # @param [Pathname] file
      # @return [String]
      def hash(file)
        sha2 = Digest::SHA2.new
        file.open('rb') do |io|
          buf = String.new
          sha2.update(buf) while io.read(4096, buf)
        end

        sha2.hexdigest
      end
    end
  end
end
