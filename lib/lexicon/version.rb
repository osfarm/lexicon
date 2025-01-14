# frozen_string_literal: true

module Lexicon
  VERSION = File.read(Pathname(File.dirname(__FILE__)).join('../../VERSION')).strip.freeze
end
