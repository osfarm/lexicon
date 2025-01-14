# frozen_string_literal: true

module Lexicon
  module Datasource
    class Register
      attr_reader :list

      def initialize(container)
        @container = container
        @list = Concurrent::Array.new
      end

      def <<(klass)
        name = klass.datasource_name

        @container.namespace :datasource do
          namespace :_auto do
            register(name) { klass }
          end
        end

        @list << "datasource._auto.#{name}"
      end
    end
  end
end
