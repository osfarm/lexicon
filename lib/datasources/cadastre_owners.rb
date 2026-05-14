module Datasources
  class CadastreOwners < Base
    description 'Cadastre owners (legal entities / personnes morales) — DGFiP MAJIC 2025'
    credits name: 'Fichier des locaux et parcelles des personnes morales',
            url: "https://www.data.gouv.fr/fr/datasets/fichiers-des-locaux-et-des-parcelles-des-personnes-morales/",
            provider: "DGFiP",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: "2025-08-19"

    SCHEMA = 'cadastre_owners'.freeze
    LOCAUX_DIR = 'locaux_2025'.freeze
    PARCELLES_DIR = 'parcelles_2025'.freeze

    def collect
      missing = []
      missing << "#{LOCAUX_DIR}/"    if Dir.glob(dir.join(LOCAUX_DIR, '*.csv')).empty?
      missing << "#{PARCELLES_DIR}/" if Dir.glob(dir.join(PARCELLES_DIR, '*.csv')).empty?
      raise "Missing CSV files in #{dir}: #{missing.join(', ')}" unless missing.empty?

      logger.debug "Found #{Dir.glob(dir.join(LOCAUX_DIR, '*.csv')).size} locaux files"
      logger.debug "Found #{Dir.glob(dir.join(PARCELLES_DIR, '*.csv')).size} parcelles files"
    end

    def load
      query <<~SQL
        DROP TABLE IF EXISTS raw_locaux;
        CREATE TABLE raw_locaux (
          department         varchar,
          direction_code     varchar,
          commune_code       varchar,
          commune_name       varchar,
          section_prefix     varchar,
          section            varchar,
          plan_number        varchar,
          building           varchar,
          entrance           varchar,
          level              varchar,
          door               varchar,
          street_number      varchar,
          street_rep         varchar,
          majic_road_code    varchar,
          rivoli_road_code   varchar,
          road_nature        varchar,
          road_name          varchar,
          droit_code_label   varchar,
          majic_number       varchar,
          siren              varchar,
          group_label        varchar,
          legal_form_code    varchar,
          legal_form_short   varchar,
          denomination       varchar
        );

        DROP TABLE IF EXISTS raw_parcelles;
        CREATE TABLE raw_parcelles (
          department         varchar,
          direction_code     varchar,
          commune_code       varchar,
          commune_name       varchar,
          section_prefix     varchar,
          section            varchar,
          plan_number        varchar,
          street_number      varchar,
          street_rep         varchar,
          majic_road_code    varchar,
          rivoli_road_code   varchar,
          road_nature        varchar,
          road_name          varchar,
          parcel_surface     varchar,
          suf                varchar,
          culture_nature_label varchar,
          suf_surface        varchar,
          droit_code_label   varchar,
          majic_number       varchar,
          siren              varchar,
          group_label        varchar,
          legal_form_code    varchar,
          legal_form_short   varchar,
          denomination       varchar
        );
      SQL

      copy_files(Dir.glob(dir.join(LOCAUX_DIR, '*.csv')).sort, "#{SCHEMA}.raw_locaux")
      copy_files(Dir.glob(dir.join(PARCELLES_DIR, '*.csv')).sort, "#{SCHEMA}.raw_parcelles")
    end

    def self.table_definitions(builder)
      builder.table :registered_cadastral_owners, sql: <<-SQL
        CREATE TABLE registered_cadastral_owners (
          majic_number       character varying NOT NULL,
          department_code    character varying NOT NULL,
          siren              character varying,
          denomination       character varying,
          legal_form_code    character varying,
          legal_form_short   character varying,
          person_group_code  character varying,
          person_group_label character varying,
          PRIMARY KEY (majic_number, department_code)
        );
        CREATE INDEX registered_cadastral_owners_majic ON registered_cadastral_owners(majic_number);
        CREATE INDEX registered_cadastral_owners_department ON registered_cadastral_owners(department_code);
        CREATE INDEX registered_cadastral_owners_siren ON registered_cadastral_owners(siren);
        CREATE INDEX registered_cadastral_owners_denomination ON registered_cadastral_owners(denomination);
        CREATE INDEX registered_cadastral_owners_person_group ON registered_cadastral_owners(person_group_code);
      SQL

      builder.table :registered_cadastral_premises, sql: <<-SQL
        CREATE TABLE registered_cadastral_premises (
          id                    serial PRIMARY KEY NOT NULL,
          cadastral_parcel_id   character varying NOT NULL,
          town_insee_code       character varying NOT NULL,
          department_code       character varying NOT NULL,
          section_prefix        character varying,
          section               character varying,
          work_number           character varying,
          building              character varying,
          entrance              character varying,
          level                 character varying,
          door                  character varying,
          address               character varying,
          street_rivoli_code    character varying,
          droit_code            character varying,
          majic_number          character varying NOT NULL,
          siren                 character varying
        );
        CREATE INDEX registered_cadastral_premises_parcel_id ON registered_cadastral_premises(cadastral_parcel_id);
        CREATE INDEX registered_cadastral_premises_majic ON registered_cadastral_premises(majic_number);
        CREATE INDEX registered_cadastral_premises_majic_dept ON registered_cadastral_premises(majic_number, department_code);
        CREATE INDEX registered_cadastral_premises_siren ON registered_cadastral_premises(siren);
        CREATE INDEX registered_cadastral_premises_insee ON registered_cadastral_premises(town_insee_code);
        CREATE INDEX registered_cadastral_premises_department ON registered_cadastral_premises(department_code);
      SQL

      builder.table :registered_cadastral_parcel_owners, sql: <<-SQL
        CREATE TABLE registered_cadastral_parcel_owners (
          id                       serial PRIMARY KEY NOT NULL,
          cadastral_parcel_id      character varying NOT NULL,
          town_insee_code          character varying NOT NULL,
          department_code          character varying NOT NULL,
          section_prefix           character varying,
          section                  character varying,
          work_number              character varying,
          parcel_surface_area      integer,
          suf                      character varying,
          culture_nature_code      character varying,
          suf_surface_area         integer,
          address                  character varying,
          street_rivoli_code       character varying,
          droit_code               character varying,
          majic_number             character varying NOT NULL,
          siren                    character varying
        );
        CREATE INDEX registered_cadastral_parcel_owners_parcel_id   ON registered_cadastral_parcel_owners(cadastral_parcel_id);
        CREATE INDEX registered_cadastral_parcel_owners_majic       ON registered_cadastral_parcel_owners(majic_number);
        CREATE INDEX registered_cadastral_parcel_owners_majic_dept  ON registered_cadastral_parcel_owners(majic_number, department_code);
        CREATE INDEX registered_cadastral_parcel_owners_siren       ON registered_cadastral_parcel_owners(siren);
        CREATE INDEX registered_cadastral_parcel_owners_insee       ON registered_cadastral_parcel_owners(town_insee_code);
        CREATE INDEX registered_cadastral_parcel_owners_department  ON registered_cadastral_parcel_owners(department_code);
        CREATE INDEX registered_cadastral_parcel_owners_culture     ON registered_cadastral_parcel_owners(culture_nature_code);
      SQL
    end

    def normalize
      logger.debug "Normalize cadastral owners (deduplicated personnes morales, scoped by department)..."
      query <<~SQL
        INSERT INTO registered_cadastral_owners (
          majic_number, department_code, siren, denomination,
          legal_form_code, legal_form_short, person_group_code, person_group_label
        )
        SELECT DISTINCT ON (majic_number, department_code)
          majic_number,
          department_code,
          CASE WHEN siren ~ '^[0-9]{9}$' THEN siren END,
          NULLIF(TRIM(denomination), ''),
          NULLIF(TRIM(legal_form_code), ''),
          NULLIF(TRIM(legal_form_short), ''),
          TRIM(SPLIT_PART(group_label, ' - ', 1)),
          TRIM(SPLIT_PART(group_label, ' - ', 2))
        FROM (
          SELECT majic_number, TRIM(department) AS department_code,
                 siren, denomination, legal_form_code, legal_form_short, group_label
            FROM #{SCHEMA}.raw_locaux
            WHERE majic_number IS NOT NULL AND majic_number <> ''
              AND department IS NOT NULL AND TRIM(department) <> ''
          UNION ALL
          SELECT majic_number, TRIM(department) AS department_code,
                 siren, denomination, legal_form_code, legal_form_short, group_label
            FROM #{SCHEMA}.raw_parcelles
            WHERE majic_number IS NOT NULL AND majic_number <> ''
              AND department IS NOT NULL AND TRIM(department) <> ''
        ) merged
        ORDER BY majic_number, department_code, siren NULLS LAST
        ON CONFLICT (majic_number, department_code) DO NOTHING
      SQL

      logger.debug "Normalize cadastral premises (locaux MAJIC)..."
      query <<~SQL
        INSERT INTO registered_cadastral_premises (
          cadastral_parcel_id, town_insee_code, department_code,
          section_prefix, section, work_number,
          building, entrance, level, door,
          address, street_rivoli_code, droit_code,
          majic_number, siren
        )
        SELECT
          CONCAT(
            department || commune_code,
            LPAD(COALESCE(NULLIF(TRIM(section_prefix), ''), '000'), 3, '0'),
            LPAD(TRIM(section), 2, '0'),
            LPAD(TRIM(plan_number), 4, '0')
          ),
          department || commune_code,
          TRIM(department),
          NULLIF(TRIM(section_prefix), ''),
          NULLIF(TRIM(section), ''),
          NULLIF(TRIM(plan_number), ''),
          NULLIF(TRIM(building), ''),
          NULLIF(TRIM(entrance), ''),
          NULLIF(TRIM(level), ''),
          NULLIF(TRIM(door), ''),
          NULLIF(TRIM(CONCAT_WS(' ',
            NULLIF(TRIM(street_number), ''),
            NULLIF(TRIM(street_rep), ''),
            NULLIF(TRIM(road_nature), ''),
            NULLIF(TRIM(road_name), '')
          )), ''),
          NULLIF(TRIM(rivoli_road_code), ''),
          TRIM(SPLIT_PART(droit_code_label, ' - ', 1)),
          majic_number,
          CASE WHEN siren ~ '^[0-9]{9}$' THEN siren END
        FROM #{SCHEMA}.raw_locaux
        WHERE majic_number IS NOT NULL AND majic_number <> ''
          AND department IS NOT NULL AND TRIM(department) <> ''
          AND commune_code IS NOT NULL
      SQL

      logger.debug "Normalize cadastral parcel owners (parcelles non-bâti)..."
      query <<~SQL
        INSERT INTO registered_cadastral_parcel_owners (
          cadastral_parcel_id, town_insee_code, department_code,
          section_prefix, section, work_number,
          parcel_surface_area, suf, culture_nature_code, suf_surface_area,
          address, street_rivoli_code, droit_code,
          majic_number, siren
        )
        SELECT
          CONCAT(
            department || commune_code,
            LPAD(COALESCE(NULLIF(TRIM(section_prefix), ''), '000'), 3, '0'),
            LPAD(TRIM(section), 2, '0'),
            LPAD(TRIM(plan_number), 4, '0')
          ),
          department || commune_code,
          TRIM(department),
          NULLIF(TRIM(section_prefix), ''),
          NULLIF(TRIM(section), ''),
          NULLIF(TRIM(plan_number), ''),
          NULLIF(TRIM(parcel_surface), '')::integer,
          NULLIF(TRIM(suf), ''),
          TRIM(SPLIT_PART(culture_nature_label, ' - ', 1)),
          NULLIF(TRIM(suf_surface), '')::integer,
          NULLIF(TRIM(CONCAT_WS(' ',
            NULLIF(TRIM(street_number), ''),
            NULLIF(TRIM(street_rep), ''),
            NULLIF(TRIM(road_nature), ''),
            NULLIF(TRIM(road_name), '')
          )), ''),
          NULLIF(TRIM(rivoli_road_code), ''),
          TRIM(SPLIT_PART(droit_code_label, ' - ', 1)),
          majic_number,
          CASE WHEN siren ~ '^[0-9]{9}$' THEN siren END
        FROM #{SCHEMA}.raw_parcelles
        WHERE majic_number IS NOT NULL AND majic_number <> ''
          AND department IS NOT NULL AND TRIM(department) <> ''
          AND commune_code IS NOT NULL
      SQL

      logger.debug "Update registered_cadastral_parcels.pm_owners_count..."
      query <<~SQL
        UPDATE lexicon.registered_cadastral_parcels p
           SET pm_owners_count = sub.cnt
          FROM (
            SELECT cadastral_parcel_id, COUNT(DISTINCT majic_number) AS cnt
              FROM lexicon.registered_cadastral_parcel_owners
             GROUP BY cadastral_parcel_id
          ) sub
         WHERE p.id = sub.cadastral_parcel_id
      SQL

      logger.debug "Update registered_cadastral_parcels.has_agricultural_pm_owner..."
      query <<~SQL
        UPDATE lexicon.registered_cadastral_parcels p
           SET has_agricultural_pm_owner = true
         WHERE EXISTS (
           SELECT 1
             FROM lexicon.registered_cadastral_parcel_owners po
             JOIN lexicon.registered_enterprises e ON e.siren = po.siren
            WHERE po.cadastral_parcel_id = p.id
         )
      SQL
    end

    private

      def copy_files(files, qualified_table)
        if files.empty?
          logger.debug "No files to load into #{qualified_table}"
          return
        end

        logger.debug "Loading #{files.size} file(s) into #{qualified_table}..."

        files.each do |file|
          escaped = file.gsub("'", "''")
          sql = "\\copy #{qualified_table} FROM '#{escaped}' WITH CSV HEADER DELIMITER ';' ENCODING 'UTF8'"
          execute(psql_command(sql))
        end
      end

      def psql_command(sql)
        host = ENV.fetch('POSTGRES_HOST', 'localhost')
        port = ENV.fetch('POSTGRES_PORT', '5432')
        user = ENV.fetch('POSTGRES_USER', 'lexicon')
        password = ENV.fetch('POSTGRES_PASSWORD', '')
        name = ENV['POSTGRES_NAME'] || ENV.fetch('POSTGRES_DB', 'lexicon')

        env_prefix = password.empty? ? '' : "PGPASSWORD='#{password.gsub("'", "'\\''")}' "
        "#{env_prefix}psql -h '#{host}' -p '#{port}' -U '#{user}' -d '#{name}' -v ON_ERROR_STOP=1 -c \"#{sql}\""
      end
  end
end
