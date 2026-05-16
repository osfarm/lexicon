module Datasources
  class MsaPopulations < Base
    description "MSA populations: retraités, chefs d'exploitation et nouveaux installés par commune"
    credits name: 'Statistiques MSA',
            url: 'https://statistiques.msa.fr/',
            provider: 'Caisse Centrale de la Mutualité Sociale Agricole (CCMSA)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: '2026-05-16'

    FILES = {
      'COTAS_EMPLOI.csv' => 'cotas_emploi',
      'COTNS_CHEF.csv'   => 'cotns_chef',
      'RET_STOCK.csv'    => 'ret_stock'
    }.freeze

    def collect
      FILES.each_key do |filename|
        FileUtils.cp("data/msa_populations/#{filename}", dir)
      end
    end

    def load
      FILES.each do |filename, table|
        load_csv(dir.join(filename), table, col_sep: ';')
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_msa_populations, sql: <<-SQL
        CREATE TABLE registered_msa_populations (
          id SERIAL PRIMARY KEY NOT NULL,
          insee_code character varying NOT NULL,
          city_name character varying,
          year integer NOT NULL,
          new_contracts integer,
          farm_chiefs integer,
          retired_non_salaried integer,
          retired_salaried integer,
          UNIQUE (insee_code, year)
        );
        CREATE INDEX registered_msa_populations_insee_code ON registered_msa_populations(insee_code);
        CREATE INDEX registered_msa_populations_year ON registered_msa_populations(year);
      SQL
    end

    def normalize
      query <<-SQL
        WITH unioned AS (
          SELECT commune_2020 AS insee, libelle AS city, annee::int AS year,
                 NULLIF(NULLIF(nb_contrats, 'N/A - secret statistique'), '')::int AS new_contracts,
                 NULL::int AS farm_chiefs,
                 NULL::int AS retired_non_salaried,
                 NULL::int AS retired_salaried
            FROM msa_populations.cotas_emploi
          UNION ALL
          SELECT commune_2020, libelle, annee::int,
                 NULL::int,
                 NULLIF(NULLIF(nb_chefs_d_exploit_ou_d_entr_agricole, 'N/A - secret statistique'), '')::int,
                 NULL::int,
                 NULL::int
            FROM msa_populations.cotns_chef
          UNION ALL
          SELECT commune_2020, libelle, annee::int,
                 NULL::int,
                 NULL::int,
                 NULLIF(NULLIF(retraites_non_salaries_agricoles, 'N/A - secret statistique'), '')::int,
                 NULLIF(NULLIF(retraites_salaries_agricoles, 'N/A - secret statistique'), '')::int
            FROM msa_populations.ret_stock
        ),
        merged AS (
          SELECT insee, MAX(city) AS city, year,
                 MAX(new_contracts) AS new_contracts,
                 MAX(farm_chiefs) AS farm_chiefs,
                 MAX(retired_non_salaried) AS retired_non_salaried,
                 MAX(retired_salaried) AS retired_salaried
            FROM unioned
           WHERE insee IS NOT NULL AND year IS NOT NULL
           GROUP BY insee, year
        )
        INSERT INTO registered_msa_populations
          (insee_code, city_name, year, new_contracts, farm_chiefs, retired_non_salaried, retired_salaried)
          SELECT insee, city, year, new_contracts, farm_chiefs, retired_non_salaried, retired_salaried
            FROM merged
           WHERE new_contracts IS NOT NULL
              OR farm_chiefs IS NOT NULL
              OR retired_non_salaried IS NOT NULL
              OR retired_salaried IS NOT NULL
      SQL
    end
  end
end
