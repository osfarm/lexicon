require 'onoma'

module Datasources
  class OpenNomenclature < Base
    description 'Open Nomenclature'
    credits name: 'Open Nomenclature', url: "https://open-nomenclature.org/", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    def load
      I18n.available_locales = %i[arb cmn deu eng fra ita jpn por spa]
      ::Onoma.load_locales
      I18n.reload!
      Onoma.load!
      Onoma.each do |nomenclature|
        table_name = nomenclature.name
        query "DROP TABLE IF EXISTS #{table_name}"
        query "CREATE TABLE #{table_name} (name VARCHAR NOT NULL, label JSONB)"
        database.copy_data "COPY #{table_name} (name, label) FROM STDIN" do |c|
          nomenclature.find_each do |item|
            tr = I18n.available_locales.each_with_object({}) { |l, h| h[l] = item.l(locale: l) }
            c.call "#{item.name}\t#{tr.to_json}\n"
          end
        end
      end
    end
  end
end
