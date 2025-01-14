# frozen_string_literal: true

module Lexicon
  module Commands
    class ContainerAwareCommand < Thor
      include Common::Mixin::ContainerAware

      def initialize(_args = [], local_options = {}, config = {})
        super

        self.container = config[:container]
      end
    end
  end
end
