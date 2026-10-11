# frozen_string_literal: true

module Datasources
  # Collective catering as the platform « ma cantine » of the ministry of agriculture knows it: the register of
  # canteens, and what each declares every year of its food purchases under the EGalim law, the share bought
  # organic and the share bought under another quality sign.
  #
  # A canteen that declared nothing is in the register and in no campaign: a commune without a declaration is
  # not a commune without a canteen. A central kitchen declares for the restaurants it delivers, in the commune
  # where it cooks.
  class Canteens < Base
    description "Restauration collective : registre national des cantines et télédéclarations annuelles EGalim (part d'achats bio et sous signe de qualité), d'après « ma cantine »"
    credits name: 'Registre national des cantines et résultats de campagnes de télédéclaration des cantines',
            url: 'https://www.data.gouv.fr/datasets/resultats-de-campagnes-de-teledeclaration-des-cantines',
            provider: "Ministère de l'Agriculture, Direction générale de l'alimentation",
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-11'

    schema_revision 1
    depends_on :postal_codes
    # The register changes every week
    source_date 'SELECT max(modified_on) FROM registered_canteens'
    pivot :commune, table: :registered_canteens, column: :insee_code, minimum: 0.95

    REGISTER = 'registre-national-des-cantines'
    DECLARATIONS = 'resultats-de-campagnes-de-teledeclaration-des-cantines'
    CAMPAIGN = /campagne_td_(\d{4})\.csv/.freeze
    # What the EGalim law asks of the purchases of a canteen: half under a quality sign, a fifth organic
    ORGANIC_TARGET = 0.20
    QUALITY_TARGET = 0.50
    # How a declaration was made: the two last are central kitchens answering for their restaurants
    CENTRAL_MODES = %w[CENTRAL_ALL CENTRAL_APPRO].freeze

    def collect
      register = data_gouv_resources(REGISTER, as: 'register.json').find { |found| found['format'] == 'csv' }
      raise "No CSV file in the dataset #{REGISTER}" if register.nil?

      fetch(register.fetch('url'), 'register.csv', again: true)

      campaigns = data_gouv_resources(DECLARATIONS, as: 'declarations.json').select { |found| found['url'].match?(CAMPAIGN) }
      raise "No campaign in the dataset #{DECLARATIONS}" if campaigns.empty?

      campaigns.each { |campaign| fetch(campaign.fetch('url'), "declarations_#{campaign['url'][CAMPAIGN, 1]}.csv", again: true) }
    end

    def load
      raise "No file #{dir.join('register.csv')}: run the collect phase first" unless dir.join('register.csv').size?
      raise "No campaign in #{dir}: run the collect phase first" if campaigns.empty?

      load_csv(dir.join('register.csv'), 'register', encoding: 'UTF8')
      campaigns.each { |year, file| load_csv(file, "declarations_#{year}", encoding: 'UTF8') }
    end

    def self.table_definitions(builder)
      builder.table(:registered_canteens, sql: <<~SQL)
        CREATE TABLE registered_canteens (
          id integer PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          siret character varying,
          siren character varying,
          insee_code character varying,
          postal_code character varying,
          city character varying,
          epci_code character varying,
          project_ids integer[] NOT NULL DEFAULT '{}',
          sectors text[] NOT NULL DEFAULT '{}',
          economic_model character varying,
          management_type character varying,
          production_type character varying,
          central_kitchen_siret character varying,
          line_ministry character varying,
          daily_meals integer,
          yearly_meals integer,
          declared_years integer[] NOT NULL DEFAULT '{}',
          active boolean NOT NULL,
          created_on date,
          modified_on date
        );
        CREATE INDEX registered_canteens_insee ON registered_canteens (insee_code);
        CREATE INDEX registered_canteens_siret ON registered_canteens (siret);
        CREATE INDEX registered_canteens_projects ON registered_canteens USING GIN (project_ids);
      SQL

      # What a canteen declared for a year, with what it was that year: the register may have changed since
      builder.table(:registered_canteen_declarations, sql: <<~SQL)
        CREATE TABLE registered_canteen_declarations (
          id integer PRIMARY KEY NOT NULL,
          canteen_id integer NOT NULL,
          year integer NOT NULL,
          mode character varying,
          central boolean NOT NULL,
          name character varying,
          siret character varying,
          insee_code character varying,
          project_ids integer[] NOT NULL DEFAULT '{}',
          sectors text[] NOT NULL DEFAULT '{}',
          economic_model character varying,
          management_type character varying,
          production_type character varying,
          central_kitchen_siret character varying,
          organic_share numeric(6,4),
          quality_share numeric(6,4),
          meets_targets boolean,
          yearly_meals integer,
          declared_on date
        );
        CREATE INDEX registered_canteen_declarations_insee ON registered_canteen_declarations (insee_code, year);
        CREATE INDEX registered_canteen_declarations_canteen ON registered_canteen_declarations (canteen_id);
        CREATE INDEX registered_canteen_declarations_projects ON registered_canteen_declarations USING GIN (project_ids);
      SQL

      # The declarations of a commune, year by year. No average: the median, and the share weighted by the
      # meals of the canteens whose meals the register knows (`weighted_declarations` of them).
      builder.table(:registered_canteen_communes, sql: <<~SQL)
        CREATE TABLE registered_canteen_communes (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          declarations_count integer NOT NULL,
          central_declarations_count integer NOT NULL,
          meeting_targets_count integer NOT NULL,
          lowest_organic_share numeric(6,4),
          median_organic_share numeric(6,4),
          highest_organic_share numeric(6,4),
          median_quality_share numeric(6,4),
          weighted_declarations integer NOT NULL,
          weighted_organic_share numeric(6,4),
          weighted_quality_share numeric(6,4),
          PRIMARY KEY (insee_code, year)
        );
      SQL
    end

    def normalize

      query <<~SQL
        INSERT INTO registered_canteens
          (id, name, siret, siren, insee_code, postal_code, city, epci_code, project_ids, sectors, economic_model,
           management_type, production_type, central_kitchen_siret, line_ministry, daily_meals, yearly_meals,
           declared_years, active, created_on, modified_on)
          WITH communes AS MATERIALIZED (SELECT DISTINCT code FROM registered_postal_codes)
          SELECT register.id::integer, register.name, NULLIF(register.siret, ''),
                 COALESCE(NULLIF(register.siren_unite_legale, ''), left(NULLIF(register.siret, ''), 9)),
                 communes.code, NULLIF(register.postal_code, ''), NULLIF(register.city, ''), NULLIF(register.epci, ''),
                 #{integers('register.pat_list')}, #{texts('register.sector_list')},
                 NULLIF(register.economic_model, ''), NULLIF(register.management_type, ''), NULLIF(register.production_type, ''),
                 NULLIF(register.central_producer_siret, ''), NULLIF(register.line_ministry, ''),
                 NULLIF(register.daily_meal_count, '')::numeric::integer, NULLIF(register.yearly_meal_count, '')::numeric::integer,
                 ARRAY(SELECT year FROM (VALUES (2021, register.declaration_donnees_2021), (2022, register.declaration_donnees_2022),
                                               (2023, register.declaration_donnees_2023), (2024, register.declaration_donnees_2024),
                                               (2025, register.declaration_donnees_2025)) AS declared(year, done)
                        WHERE lower(done) = 'true' ORDER BY year),
                 lower(register.active_on_ma_cantine) = 'true',
                 register.creation_date::timestamptz::date, register.modification_date::timestamptz::date
            FROM #{name}.register
            LEFT JOIN communes ON communes.code = register.city_insee_code
           ORDER BY register.id::integer
      SQL

      campaigns.each_key do |year|
        query <<~SQL
          INSERT INTO registered_canteen_declarations
            (id, canteen_id, year, mode, central, name, siret, insee_code, project_ids, sectors, economic_model,
             management_type, production_type, central_kitchen_siret, organic_share, quality_share, meets_targets,
             yearly_meals, declared_on)
            WITH communes AS MATERIALIZED (SELECT DISTINCT code FROM registered_postal_codes)
            SELECT declared.id::integer, declared.canteen_id::integer, declared.year::integer, NULLIF(declared.teledeclaration_mode, ''),
                   COALESCE(declared.teledeclaration_mode IN (#{CENTRAL_MODES.map { |mode| "'#{mode}'" }.join(', ')}), false),
                   NULLIF(declared.canteen_name, ''), NULLIF(declared.canteen_siret, ''), communes.code,
                   #{integers('declared.canteen_pat_list')}, #{texts('declared.canteen_sector_list')},
                   NULLIF(declared.canteen_economic_model, ''), NULLIF(declared.canteen_management_type, ''),
                   NULLIF(declared.canteen_production_type, ''), NULLIF(declared.canteen_central_kitchen_siret, ''),
                   shares.organic, shares.quality,
                   shares.organic >= #{ORGANIC_TARGET} AND shares.organic + shares.quality >= #{QUALITY_TARGET},
                   canteen.yearly_meals, declared.creation_date::timestamptz::date
              FROM #{name}.declarations_#{year} AS declared
              CROSS JOIN LATERAL (SELECT NULLIF(declared.teledeclaration_ratio_bio, '')::numeric AS organic,
                                         NULLIF(declared.teledeclaration_ratio_egalim_hors_bio, '')::numeric AS quality) AS shares
              LEFT JOIN communes ON communes.code = declared.canteen_city_insee_code
              LEFT JOIN registered_canteens AS canteen ON canteen.id = declared.canteen_id::integer
        SQL
      end

      query <<~SQL
        INSERT INTO registered_canteen_communes
          (insee_code, year, declarations_count, central_declarations_count, meeting_targets_count, lowest_organic_share,
           median_organic_share, highest_organic_share, median_quality_share, weighted_declarations,
           weighted_organic_share, weighted_quality_share)
          SELECT insee_code, year, count(*), count(*) FILTER (WHERE central), count(*) FILTER (WHERE meets_targets),
                 min(organic_share), percentile_cont(0.5) WITHIN GROUP (ORDER BY organic_share), max(organic_share),
                 percentile_cont(0.5) WITHIN GROUP (ORDER BY quality_share),
                 count(*) FILTER (WHERE yearly_meals > 0 AND organic_share IS NOT NULL),
                 sum(organic_share * yearly_meals) FILTER (WHERE yearly_meals > 0) / NULLIF(sum(yearly_meals) FILTER (WHERE yearly_meals > 0 AND organic_share IS NOT NULL), 0),
                 sum(quality_share * yearly_meals) FILTER (WHERE yearly_meals > 0) / NULLIF(sum(yearly_meals) FILTER (WHERE yearly_meals > 0 AND quality_share IS NOT NULL), 0)
            FROM registered_canteen_declarations
           WHERE insee_code IS NOT NULL
           GROUP BY insee_code, year
      SQL
    end

    private

      # @return [Hash{String => Pathname}] the file of each campaign collected, by the year it is about
      def campaigns
        Pathname.glob(dir.join('declarations_*.csv')).sort.to_h { |file| [file.basename.to_s[/\d{4}/], file] }
      end

      # A list written « 1585,5563 », as an array of integers
      def integers(column)
        "COALESCE(ARRAY(SELECT part::integer FROM unnest(string_to_array(#{column}, ',')) AS part WHERE part ~ '^[0-9]+$'), '{}')"
      end

      def texts(column)
        "COALESCE(ARRAY(SELECT btrim(part) FROM unnest(string_to_array(#{column}, ',')) AS part WHERE btrim(part) <> ''), '{}')"
      end
  end
end
