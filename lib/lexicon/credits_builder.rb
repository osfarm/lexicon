# frozen_string_literal: true

module Lexicon
  class CreditsBuilder
    def build(datasource_class, database:)
      return unless datasource_class.respond_to? :get_credits

      datasource_class.get_credits.each do |credit|
        database.query <<-SQL
          DELETE FROM datasource_credits WHERE "datasource" = '#{datasource_class.name}';

          INSERT INTO datasource_credits ("datasource", "name", "url", "provider", "licence", "licence_url", "updated_at")
          VALUES ('#{credit.datasource}','#{credit.name}','#{credit.url}','#{credit.provider}','#{credit.licence}','#{credit.licence_url}','#{credit.updated_at}'::TIMESTAMPTZ);
        SQL
      end
    end
  end
end
