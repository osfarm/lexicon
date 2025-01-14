# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:gitlab) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://gitlab.com/#{repo_name}.git"
end

ruby '>= 2.7'

gem 'lexicon-common', gitlab: 'ekylibre/lexicon/lexicon-common', branch: 'dev'

# CLI and app core system
gem 'colored'
gem 'concurrent-ruby'
gem 'dotenv'
gem 'dry-container'
gem 'progress_bar'
gem 'thor'
gem 'zeitwerk'

# Utilities
gem 'activesupport'
gem 'aws-sdk-s3'
gem 'charlock_holmes'
gem 'i18n'
gem 'json'
gem 'json_schemer'
gem 'nokogiri'
gem 'pg'
gem 'rest-client'
gem 'roo'
gem 'roo-xls'
gem 'rubyzip'
gem 'semantic'

# Debug
gem 'pry'
gem 'pry-byebug'

# Data
# gem 'onoma', '~> 0.9.1'
gem 'onoma', gitlab: 'ekylibre/onoma', branch: 'lexicon'

# Doc and code quality
gem 'rubocop', '~> 1.11.0', require: false
gem 'yard', '~> 0.9.26', require: false
