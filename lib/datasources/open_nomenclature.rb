require 'onoma'

module Datasources
  class OpenNomenclature < Base
    description 'Open Nomenclature'
    credits name: 'Open Nomenclature', url: "https://open-nomenclature.org/", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2020-02-12"

    LOCALES = %i[arb cmn deu eng fra ita jpn por spa].freeze

    def load
      I18n.available_locales = LOCALES
      ::Onoma.load_locales
      I18n.reload!
      Onoma.load!

      table_name = 'nomenclatures'
      query "DROP TABLE IF EXISTS #{table_name}"
      query "CREATE TABLE #{table_name} (nomenclature VARCHAR NOT NULL, name VARCHAR NOT NULL, label JSONB, properties JSONB)"

      database.copy_data "COPY #{table_name} (nomenclature, name, label, properties) FROM STDIN" do |c|
        Onoma.each do |nomenclature|
          nomenclature.find_each do |item|
            label = LOCALES.each_with_object({}) { |l, h| h[l] = sanitize(item.l(locale: l)) }
            properties = (item.attributes || {})
            c.call "#{nomenclature.name}\t#{item.name}\t#{label.to_json}\t#{properties.to_json}\n"
          end
        end
      end
    end

    def self.table_definitions(builder)
      builder.table :master_nomenclatures, sql: <<~SQL
        CREATE TABLE master_nomenclatures (
          nomenclature character varying NOT NULL,
          name         character varying NOT NULL,
          label        jsonb,
          properties   jsonb,
          PRIMARY KEY (nomenclature, name)
        );

        CREATE INDEX master_nomenclatures_nomenclature ON master_nomenclatures(nomenclature);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO master_nomenclatures (nomenclature, name, label, properties)
          SELECT nomenclature, name, label, properties
          FROM open_nomenclature.nomenclatures
      SQL
    end

    private

    # COPY uses TAB-separated framing: strip any TAB/newline from label values so a
    # stray character can't shift columns or split rows.
    def sanitize(value)
      value.to_s.gsub(/[\t\n\r]/, ' ')
    end
  end
end
