# frozen_string_literal: true

module Lexicon
  # Formerly the lexicon-common gem (Ekylibre, AGPL-3.0). Brought into this repository under its MIT
  # licence with the permission of Ekylibre, on 2026-10-04.
  module Common
    LEXICON_SCHEMA_RELATIVE_PATH = 'resources/lexicon.schema.json'
    LEXICON_SCHEMA_ABSOLUTE_PATH = Pathname.new(__dir__).join('..', '..', LEXICON_SCHEMA_RELATIVE_PATH).freeze
  end
end
