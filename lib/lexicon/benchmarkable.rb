# frozen_string_literal: true

module Lexicon
  module Benchmarkable
    extend ActiveSupport::Concern

    module ClassMethods
      def benchmarked(method)
        benchmarked_name = "benchmarked_#{method}".to_sym

        alias_method benchmarked_name, method
        define_method method do |*args, **options|
          start = Time.now
          result = send(benchmarked_name, *args, **options)
          Lexicon.log "#{DONE_WORDS[meth].green} #{datasource_name.to_s.yellow} in #{(Time.now - start).round(2)}s"
          result
        end
      end
    end
  end
end
