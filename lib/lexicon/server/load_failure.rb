# frozen_string_literal: true

module Lexicon
  module Server
    # A package could not be put in service. The version previously in service is left untouched.
    class LoadFailure < StandardError
      # @return [Array<String>]
      attr_reader :reasons

      # @param [Array<String>, String] reasons
      def initialize(reasons)
        @reasons = Array(reasons)

        super(@reasons.join(' ; '))
      end
    end
  end
end
