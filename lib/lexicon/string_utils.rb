# frozen_string_literal: true

module Lexicon
  module StringUtils
    class << self
      # Utility method
      def symbolize(text)
        I18n.available_locales = %i[arb cmn deu en fra ita jpn por spa]
        I18n.transliterate(text)
            .underscore
            .downcase
            .gsub(/[^a-z0-9]+/, '_')
            .gsub(/(^\_|\_$)/, '')
            .gsub(/^([0-9])/, '_\1')
      end
    end
  end
end
