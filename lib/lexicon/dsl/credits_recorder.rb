# frozen_string_literal: true

module Lexicon
  module Dsl
    module CreditsRecorder
      extend ActiveSupport::Concern

      module ClassMethods
        def credits(name: nil, url:, provider:, licence:, licence_url:, updated_at:)
          @credits ||= []
          @credits << Credits.new(
            datasource: datasource_name,
            name: name,
            url: url,
            provider: provider,
            licence: licence,
            licence_url: licence_url,
            updated_at: updated_at
          )
        end

        def get_credits
          @credits || []
        end
      end
    end
  end
end
