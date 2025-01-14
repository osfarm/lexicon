module Datasources
  class QualityAndOriginSigns < Base
    description 'AOC - AOP - IGP'
    credits name: 'Liste des AOC - AOP - IGP', url: "https://www.data.gouv.fr/fr/datasets/aires-et-produits-aoc-aop-et-igp/", provider: "INAO", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: "2024-07-08"

    def collect
      # get 2019-11-05-comagri-aires-produits.csv
      # resource is available here: https://www.data.gouv.fr/fr/datasets/aires-et-produits-aoc-aop-et-igp/
      FileUtils.rm dir.join('qos.csv'), force: true
      downloader.curl 'https://www.data.gouv.fr/fr/datasets/r/a6bf5c97-296d-4886-ab9c-0ade02fbbaff', out: 'qos.csv'
    end

    def load
      load_csv(dir.join('qos.csv'), 'qos', col_sep: ';', encoding: 'ISO-8859-15')
    end

    def self.table_definitions(builder)
      builder.table :registered_quality_and_origin_signs, sql: <<-SQL
        CREATE TABLE registered_quality_and_origin_signs (
          id integer PRIMARY KEY NOT NULL,
          ida integer NOT NULL,
          geographic_area character varying,
          fr_sign character varying,
          eu_sign character varying,
          product_human_name JSONB,
          product_human_name_fra character varying,
          reference_number character varying
        );
      SQL
    end

    #French category "VSIG"
    VSIG = {1 => "VSIG", 2 => "VSIG rouge", 3 => "VSIG blanc", 4 => "VSIG rosé"}

    def normalize
      query "UPDATE quality_and_origin_signs.qos SET produit = REPLACE(produit, '\\', '');"

      query <<-SQL
        INSERT INTO registered_quality_and_origin_signs (id, ida, geographic_area, fr_sign, eu_sign, product_human_name, product_human_name_fra, reference_number)
          SELECT id_produit::INTEGER, ida::INTEGER, aire_geographique, signe_fr, signe_ue, CONCAT('{"fra":"', produit, '"}')::JSONB, produit, reference
          FROM quality_and_origin_signs.qos
      SQL

      #Add VSIG
      VSIG.each do |(id, product)|
        query 'INSERT INTO registered_quality_and_origin_signs
        (id, ida, geographic_area, fr_sign, eu_sign, product_human_name, product_human_name_fra)
        VALUES ($1, $2, $3, $4, $5, $6, $7)',
        id, 1, '-------', 'Vin de France -', 'VSIG', {"fra": product}.to_json, product
      end
    end

  end
end
