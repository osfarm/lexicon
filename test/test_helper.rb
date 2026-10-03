# frozen_string_literal: true

require 'bundler'
Bundler.require(:default)
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/filters'
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'lexicon'

require 'minitest/autorun'
require 'tmpdir'
