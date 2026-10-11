# frozen_string_literal: true

require 'json'

module Datasources
  # Where farming is taught: the schools, apprentice training centres and adult training centres of
  # agricultural education, with what each prepares for (diploma, speciality, route), and the farms and
  # workshops schools teach on. Read from the open data portal of agricultural education (RefEA).
  #
  # A school is placed in its commune, not at its address: the source gives no finer position.
  class AgriculturalSchools < Base
    description "Enseignement agricole : établissements, exploitations pédagogiques et formations préparées (diplôme, spécialité, voie scolaire, apprentissage ou continue), d'après RefEA"
    credits name: 'RefEA : liste des établissements proposant des formations agricoles et offre de formation globale',
            url: 'https://enseignement-agricole.opendatasoft.com/explore/',
            provider: "Ministère de l'Agriculture, Direction générale de l'enseignement et de la recherche",
            licence: 'Licence Ouverte',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf',
            updated_at: '2026-10-09'

    schema_revision 1
    depends_on :postal_codes
    source_date 'SELECT max(data_date) FROM registered_agricultural_schools'
    personal_data 'the telephone and the mailbox of a school, which the ministry publishes for families to reach it; no person is named'
    pivot :commune, table: :registered_agricultural_schools, column: :insee_code, minimum: 0.9

    PORTAL = 'https://enseignement-agricole.opendatasoft.com/api/explore/v2.1/catalog'
    # The list is published under a name that carries its school year
    UNITS = /\Arefea-liste-des-etablissements-proposant-des-formations-agricoles/.freeze
    OFFER = 'offre-formation-globale'

    # What is kept of the list: places where one is taught, and what they teach on
    KINDS = { "Etablissement d'enseignement" => 'school', 'Support Pédagogique' => 'teaching_support' }.freeze
    # The public a training is open to, as the source numbers it
    ROUTES = { '1' => 'higher_education', '2' => 'school', '3' => 'continuing', '4' => 'apprenticeship' }.freeze

    def collect
      catalog = dir.join('catalog.json')
      execute "curl -sSLf --retry 2 -o '#{catalog}' '#{PORTAL}/datasets?limit=100'"
      units = JSON.parse(catalog.read).fetch('results').map { |dataset| dataset['dataset_id'] }.grep(UNITS).max
      raise "No list of establishments on #{PORTAL}" if units.nil?

      # The outline of the commune comes with each line and weighs twenty times the rest: left out
      fetch("#{PORTAL}/datasets/#{units}/exports/csv?select=exclude(geom)&delimiter=%2C", 'units.csv', again: true)
      fetch("#{PORTAL}/datasets/#{OFFER}/exports/csv?delimiter=%2C", 'offer.csv', again: true)
    end

    def load
      %w[units offer].each do |table|
        file = dir.join("#{table}.csv")
        raise "No file #{file}: run the collect phase first" unless file.size?

        execute "sed '1s/^\\xEF\\xBB\\xBF//' '#{file}' > '#{file}.plain'"
        load_csv(Pathname.new("#{file}.plain"), table, encoding: 'UTF8')
      ensure
        FileUtils.rm_f("#{file}.plain")
      end
    end

    def self.table_definitions(builder)
      builder.table(:registered_agricultural_schools, sql: <<~SQL)
        CREATE TABLE registered_agricultural_schools (
          id character varying PRIMARY KEY NOT NULL,
          kind character varying NOT NULL,
          name character varying NOT NULL,
          public_name character varying,
          nature character varying,
          sector character varying,
          affiliation character varying,
          ministry character varying,
          siret character varying,
          national_education_code character varying,
          address character varying,
          postal_code character varying,
          city character varying,
          insee_code character varying,
          department_code character varying,
          region_code character varying,
          phone character varying,
          email character varying,
          website character varying,
          pupils boolean NOT NULL,
          students boolean NOT NULL,
          adults boolean NOT NULL,
          apprentices boolean NOT NULL,
          boarding boolean NOT NULL,
          half_board boolean NOT NULL,
          parent_id character varying,
          parent_name character varying,
          trainings_count integer NOT NULL DEFAULT 0,
          school_year character varying,
          data_date date
        );
        CREATE INDEX registered_agricultural_schools_insee ON registered_agricultural_schools (insee_code);
        CREATE INDEX registered_agricultural_schools_department ON registered_agricultural_schools (department_code);
      SQL

      builder.table(:registered_agricultural_trainings, sql: <<~SQL)
        CREATE TABLE registered_agricultural_trainings (
          school_id character varying NOT NULL,
          code character varying NOT NULL,
          route character varying NOT NULL,
          name character varying NOT NULL,
          diploma character varying NOT NULL,
          speciality character varying,
          national_education_code character varying,
          started_on date,
          PRIMARY KEY (school_id, code, route)
        );
        CREATE INDEX registered_agricultural_trainings_diploma ON registered_agricultural_trainings (diploma);
        CREATE INDEX registered_agricultural_trainings_speciality ON registered_agricultural_trainings (speciality);
      SQL
    end

    def normalize
      kinds = KINDS.map { |label, kind| "WHEN #{quoted(label)} THEN '#{kind}'" }.join(' ')
      routes = ROUTES.map { |number, route| "WHEN '#{number}' THEN '#{route}'" }.join(' ')
      yes = ->(column) { "COALESCE(lower(#{column}) = 'oui', false)" }

      query <<~SQL
        INSERT INTO registered_agricultural_schools
          (id, kind, name, public_name, nature, sector, affiliation, ministry, siret, national_education_code, address,
           postal_code, city, insee_code, department_code, region_code, phone, email, website, pupils, students, adults,
           apprentices, boarding, half_board, parent_id, parent_name, school_year, data_date)
          WITH communes AS MATERIALIZED (SELECT DISTINCT code FROM registered_postal_codes)
          SELECT units.uai_codedger, CASE units.uai_type #{kinds} END, units.uai_libelle_administratif,
                 NULLIF(units.uai_libelle_communication, ''), NULLIF(units.uai_nature, ''), lower(NULLIF(units.uai_secteur, '')),
                 NULLIF(NULLIF(NULLIF(units.uaiprive_orgaffiliation, ''), 'Sans objet'), 'Sans affiliation'),
                 NULLIF(NULLIF(units.uai_ministere_principal, ''), 'Sans objet'),
                 NULLIF(units.uai_code_siret, ''), NULLIF(units.uai_code_educnationale, ''),
                 NULLIF(concat_ws(', ', NULLIF(units.adressegeographique_ligne2, ''), NULLIF(units.adressegeographique_ligne4, '')), ''),
                 substring(units.adressegeographique_ligne6 FROM '^[0-9]{5}'), NULLIF(units.uai_commune, ''),
                 communes.code, NULLIF(units.uai_code_departement, ''), NULLIF(units.uai_code_region, ''),
                 NULLIF(units.uai_telephone, ''), NULLIF(units.uai_mail, ''), NULLIF(units.uai_siteweb, ''),
                 #{yes.call('units.uai_eleve')}, #{yes.call('units.uai_etudiant')}, #{yes.call('units.uai_adulte')},
                 #{yes.call('units.uai_apprenti')}, #{yes.call('units.internat')}, #{yes.call('units.demi_pension')},
                 NULLIF(units.uainiveau1_codedger, units.uai_codedger), NULLIF(units.uainiveau1_libelle_administratif, units.uai_libelle_administratif),
                 NULLIF(units.annee_scolaire, ''), NULLIF(units.date_jeu_donnees, '')::date
            FROM #{name}.units
            LEFT JOIN communes ON communes.code = units.uai_code_commune
           WHERE units.uai_type IN (#{KINDS.keys.map { |label| quoted(label) }.join(', ')})
           ORDER BY units.uai_codedger
      SQL

      # A training is written once per public it is open to; twice now and then
      query <<~SQL
        INSERT INTO registered_agricultural_trainings (school_id, code, route, name, diploma, speciality, national_education_code, started_on)
          SELECT DISTINCT ON (offer.uai_dger_rfa, offer.code_formation_maaf, offer.statapp_cdn)
                 offer.uai_dger_rfa, offer.code_formation_maaf, CASE offer.statapp_cdn #{routes} ELSE 'other' END,
                 offer.formacertif_libusage, offer.fil_libusage, NULLIF(offer.supform_libusage, ''),
                 NULLIF(offer.code_formation_en, ''), NULLIF(offer.debut_formation, '')::date
            FROM #{name}.offer
            JOIN registered_agricultural_schools AS school ON school.id = offer.uai_dger_rfa
           ORDER BY offer.uai_dger_rfa, offer.code_formation_maaf, offer.statapp_cdn
      SQL

      query <<~SQL
        UPDATE registered_agricultural_schools AS school
           SET trainings_count = (SELECT count(*) FROM registered_agricultural_trainings WHERE school_id = school.id)
      SQL
    end

    private

      def quoted(text)
        "'#{text.gsub("'", "''")}'"
      end
  end
end
