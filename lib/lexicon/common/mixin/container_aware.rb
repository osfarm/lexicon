# frozen_string_literal: true

module Lexicon
  module Common
    module Mixin
      module ContainerAware
        attr_accessor :container

        # @param [Object] service
        def get(service)
          container.get(service)
        end
      end
    end
  end
end
