# frozen_string_literal: true

require 'zeitwerk'

lex_loader = Zeitwerk::Loader.for_gem
lex_loader.setup

require 'forwardable'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/concern'
require 'bigdecimal'

module Lexicon
end

lex_loader.eager_load
