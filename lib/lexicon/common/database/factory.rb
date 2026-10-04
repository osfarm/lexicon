# frozen_string_literal: true

module Lexicon
  module Common
    module Database
      class Factory
        attr_reader :verbose

        def initialize(verbose: false)
          @verbose = verbose
        end

        def new_instance(url:)
          Database.new(PG.connect(url), verbose: @verbose)
        end
      end
    end
  end
end
