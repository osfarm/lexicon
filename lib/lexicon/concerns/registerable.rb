# frozen_string_literal: true

module Lexicon
  module Concerns
    module Registerable
      extend ActiveSupport::Concern

      module ClassMethods
        def dependencies(*deps)
          if deps.empty?
            @dependencies || []
          else
            @dependencie = deps
          end
        end
      end
    end
  end
end
