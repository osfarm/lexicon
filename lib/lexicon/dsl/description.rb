# frozen_string_literal: true

module Lexicon
  module Dsl
    module Description
      extend ActiveSupport::Concern

      module ClassMethods
        def description(desc = nil)
          if desc.nil?
            @desc
          else
            @desc = desc
          end
        end
      end
    end
  end
end
