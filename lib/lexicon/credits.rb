# frozen_string_literal: true

module Lexicon
  class Credits
    attr_reader :datasource, :name, :url, :provider, :licence, :licence_url, :updated_at

    def initialize(datasource:, name:, url:, provider:, licence:, licence_url:, updated_at:)
      @datasource = datasource
      @licence = licence
      @licence_url = licence_url
      @name = name
      @provider = provider
      @updated_at = updated_at
      @url = url
    end

    def self.table_definitions(builder)
      builder.table :datasource_credits, sql: <<-SQL
          CREATE TABLE IF NOT EXISTS datasource_credits (
            "datasource" VARCHAR,
            "name" VARCHAR,
            "url" VARCHAR,
            "provider" VARCHAR,
            "licence" VARCHAR,
            "licence_url" VARCHAR,
            "updated_at" TIMESTAMP WITH TIME ZONE
          );
      SQL
    end
  end
end
