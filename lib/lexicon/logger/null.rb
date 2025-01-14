# frozen_string_literal: true

module Lexicon
  module Logger
    class Null
      def log(*_args, **_options) end

      def debug(*_args, **_options) end
    end
  end
end
