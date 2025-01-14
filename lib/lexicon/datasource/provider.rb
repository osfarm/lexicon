# frozen_string_literal: true

module Lexicon
  module Datasource
    class Provider
      def initialize(datasource_classes)
        @classes = datasource_classes.map { |c| [c.datasource_name, c] }.to_h.freeze
      end

      def names
        all.keys
      end

      def values
        all.values
      end

      def all
        @classes
      end

      def has?(key)
        @classes.key?(key.to_sym)
      end

      def get(name)
        all.fetch(name, nil)
      end
    end
  end
end
