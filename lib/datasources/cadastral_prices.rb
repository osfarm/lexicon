module Datasources
  class CadastralPrices < Base
    description 'Prices of cadastre'
    credits name: 'Demandes de valeurs foncières', url: "https://www.data.gouv.fr/fr/datasets/5cc1b94a634f4165e96436c1/", provider: "Etalab", licence: "Open Licence 2.0", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf", updated_at: "2024-04-17"

    YEAR = [2018, 2019, 2020, 2021, 2022, 2023]

    def collect
      files = []
      YEAR.each do |year|
        logger.debug "Download #{year} files..."
        downloader.curl "https://files.data.gouv.fr/geo-dvf/latest/csv/#{year}/full.csv.gz", out: "#{year}.gz"
        files << [year.to_s, "#{year}.gz"]
      end

      files.each do |file|
        logger.debug  "Extracting #{file[1]}..."
        archive = dir.join(file[1])
        execute("7z x #{archive} -so > #{dir}/#{file[0]}.csv")
      end
    end

    def load
      YEAR.each do |year|
        logger.debug  "Load #{year} cadastral_prices..."
        load_csv(dir.join("#{year}.csv"), "cadastral_prices_#{year}")
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_cadastral_prices, sql: <<-SQL
        CREATE TABLE registered_cadastral_prices (
          id SERIAL PRIMARY KEY NOT NULL,
          mutation_id character varying,
          mutation_date DATE,
          mutation_reference character varying,
          mutation_nature character varying,
          cadastral_price numeric(14,2),
          cadastral_parcel_id character varying,
          building_nature character varying,
          building_area integer,
          cadastral_parcel_area integer,
          address character varying,
          postal_code character varying,
          city character varying,
          department character varying,
          centroid postgis.geometry(Point,4326)
        );

        CREATE INDEX registered_cadastral_prices_id ON registered_cadastral_prices(id);
        CREATE INDEX registered_cadastral_prices_cadastral_parcel_id ON registered_cadastral_prices(cadastral_parcel_id);
        CREATE INDEX registered_cadastral_prices_department ON registered_cadastral_prices(department);
        CREATE INDEX registered_cadastral_prices_centroid ON registered_cadastral_prices USING GIST (centroid);
      SQL
    end

    def normalize
      YEAR.each do |year|
        logger.debug  "Normalize cadastral_prices of #{year} year..."
        query <<-SQL
          INSERT INTO registered_cadastral_prices
            (mutation_id, mutation_date, mutation_reference, mutation_nature,
              cadastral_price, building_nature,
              address, postal_code, city, department,
              cadastral_parcel_id, building_area, cadastral_parcel_area, centroid)
            SELECT
              id_mutation, date_mutation::DATE, numero_disposition, nature_mutation,
              valeur_fonciere::NUMERIC(14,2), type_local,
              CONCAT(adresse_numero, adresse_nom_voie), code_postal, nom_commune, code_departement,
              id_parcelle, surface_reelle_bati::int, surface_terrain::int, postgis.ST_SetSRID(postgis.ST_Point(latitude::FLOAT, longitude::FLOAT), 4326)::geometry
            FROM cadastral_prices.cadastral_prices_#{year}
        SQL
      end
    end

  end
end
