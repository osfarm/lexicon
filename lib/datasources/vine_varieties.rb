module Datasources
  class VineVarieties < Base
    description 'Vine varieties'
    credits name: 'Liste des cépages et porte-greffes', url: "https://www.franceagrimer.fr/filieres-Vin-et-cidre/Vin/Accompagner/Dispositifs-par-filiere/Normalisation-Qualite/Bois-et-plants-de-vigne/Catalogue-officiel-des-varietes-de-vigne", provider: "FranceAgriMer", licence: "NC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-nc-sa/4.0/", updated_at: "2020-10-19"

    def collect
      #Collect each csv file in vine_varieties directory
      FileUtils.cp Dir.glob('data/vine_varieties/*.csv'), dir
    end

    def load
      load_csv(dir.join('vine_varieties - vine_varieties.csv'), 'vine_varieties')
      load_csv(dir.join('vine_varieties - custom_codes.csv'), 'custom_codes')
    end

    def self.table_definitions(builder)
      builder.table :registered_vine_varieties, sql: <<-SQL
        CREATE TABLE registered_vine_varieties (
          id character varying PRIMARY KEY NOT NULL,
          short_name character varying NOT NULL,
          long_name character varying,
          category character varying NOT NULL,
          fr_validated boolean,
          utilities text[],
          color character varying,
          custom_code character varying
        );

        CREATE INDEX registered_vine_varieties_id ON registered_vine_varieties(id);
      SQL
    end

    def normalize
      query <<-SQL
      INSERT INTO registered_vine_varieties (id, short_name, long_name, category, fr_validated, utilities, color, custom_code)
          SELECT id, name, long_name, category, TRUE,
          CASE WHEN utilities IS NOT NULL THEN CONCAT('{', utilities, '}')::TEXT[] ELSE NULL END, color, custom_code
          FROM vine_varieties.vine_varieties LEFT JOIN vine_varieties.custom_codes
          ON vine_varieties.name = custom_codes.short_name
      SQL

      #Add missing varieties from french custom
      missing_varieties = {"3309" => "Couderc",
                           "9960" => "Riparia",
                           "9985" => "Binova",
                           "9986" => "Borner"}

      missing_varieties.each do |(custom_code, name)|
        query 'INSERT INTO registered_vine_varieties (id, short_name, long_name, category, fr_validated, utilities, custom_code)
        VALUES ($1, $2, $2, $3, $4, $5, $6)',
        'CUS_EKY_VARIETY_' + custom_code, name, 'rootstock', 'FALSE', '{wine}', custom_code
      end
    end
  end
end
