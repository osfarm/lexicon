# frozen_string_literal: true

module Lexicon
  module Cache
    class CacheEntry
      attr_reader :hash, :key, :name, :stat

      # @param [String] hash
      # @param [String] key
      # @param [String] name
      # @param [Hash{#to_sym => String}] stat
      def initialize(hash:, key:, name:, stat:)
        @hash = hash
        @key = key
        @name = name
        @stat = stat.transform_keys(&:to_sym)
      end

      def to_h
        { hash: hash, key: key, name: name, stat: stat }
      end
    end
  end
end
