# frozen_string_literal: true

module Lexicon
  module Dsl
    module Python
      extend ActiveSupport::Concern

      module ClassMethods
        def python(*actions)
          actions.each do |action|
            define_method action do
              execute("python3 -c 'from lib.datasources.#{name} import *; #{action}()'")
            end
          end
        end
      end
    end
  end
end
