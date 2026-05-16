require 'csv'

module Datasources
  class CapBeneficiaries < Base
    LAST_UPDATED = "2024-12-31"
    SCHEMA = 'cap_beneficiaries'.freeze
    YEARS = [2024].freeze

    description 'Bénéficiaires des subventions de la Politique Agricole Commune (PAC) — FEAGA & FEADER'
    credits name: 'Bénéficiaires des aides de la PAC',
            url: 'https://www.data.gouv.fr/fr/datasets/beneficiaires-des-aides-de-la-pac/',
            provider: 'Agence de Services et de Paiement (ASP)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: LAST_UPDATED

    SOURCE_HEADERS = {
      beneficiary_name:        'Nom du bénéficiaire / entité légale / association',
      beneficiary_firstname:   'Prénom du bénéficiaire',
      company_name:            'Nom de la société',
      siren:                   'Numéro de SIREN',
      commune:                 'Nom de la commune',
      intervention_code:       'Code nomenclature intervention UE',
      intervention_label:      "Type d'intervention UE",
      intervention_objective:  "Objectifs spécifiques de l'intervention",
      intervention_start_date: "Date de début de l'intervention",
      intervention_end_date:   "Date de fin de l'intervention",
      feaga_amount:            "Montant FEAGA pour l'opération et pour le bénéficiaire",
      feaga_total:             'Montant FEAGA total pour le bénéficiaire',
      feader_amount:           "Montant FEADER pour l'opération et pour le bénéficiaire",
      feader_total:            'Montant FEADER total pour le bénéficiaire',
      cofinanced_amount:       "Montant cofinancé pour l'opération et pour le bénéficiaire",
      cofinanced_total:        'Montant cofinancé total pour le bénéficiaire',
      total_feader_cofinanced: 'Montant total FEADER et cofinancé pour le bénéficiaire',
      # The official header is truncated to "...pour le bénéfic" in the source file.
      total_eu_cofinanced:     "Montant total financé par l'UE et cofinancé pour le bénéfic",
    }.freeze

    OUTPUT_HEADERS = %w[
      row_kind siren beneficiary_name beneficiary_firstname company_name commune
      intervention_code intervention_label intervention_objective
      intervention_start_date intervention_end_date
      feaga_amount feaga_total feader_amount feader_total
      cofinanced_amount cofinanced_total total_feader_cofinanced total_eu_cofinanced
    ].freeze

    def collect
      YEARS.each do |year|
        src = dir.join("cap_beneficiaries_#{year}.csv")
        raise "Missing CAP beneficiaries file: #{src}" unless File.exist?(src)

        dst = dir.join("cap_beneficiaries_#{year}_filled.csv")
        logger.debug "Preprocessing #{src.basename} → #{dst.basename} (forward-fill SIREN)…"
        preprocess(src, dst)
      end
    end

    def load
      YEARS.each do |year|
        logger.debug "Loading CAP beneficiaries #{year} into #{SCHEMA}.cap_beneficiaries_#{year}…"
        load_csv(dir.join("cap_beneficiaries_#{year}_filled.csv"),
                 "cap_beneficiaries_#{year}",
                 col_sep: ',')
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_cap_beneficiaries, sql: <<-SQL
        CREATE TABLE registered_cap_beneficiaries (
          id SERIAL PRIMARY KEY NOT NULL,
          siren character varying NOT NULL,
          year integer NOT NULL,
          beneficiary_name character varying,
          beneficiary_firstname character varying,
          company_name character varying,
          commune character varying,
          feaga_total numeric(14,2),
          feader_total numeric(14,2),
          cofinanced_total numeric(14,2),
          total_feader_cofinanced numeric(14,2),
          total_eu_cofinanced numeric(14,2),
          UNIQUE (siren, year)
        );

        CREATE INDEX registered_cap_beneficiaries_siren ON registered_cap_beneficiaries(siren);
        CREATE INDEX registered_cap_beneficiaries_year ON registered_cap_beneficiaries(year);
        CREATE INDEX registered_cap_beneficiaries_commune ON registered_cap_beneficiaries(commune);
      SQL

      builder.table :registered_cap_subsidies, sql: <<-SQL
        CREATE TABLE registered_cap_subsidies (
          id SERIAL PRIMARY KEY NOT NULL,
          siren character varying NOT NULL,
          year integer NOT NULL,
          intervention_code character varying NOT NULL,
          intervention_label character varying,
          intervention_objective text,
          intervention_start_date date,
          intervention_end_date date,
          feaga_amount numeric(14,2),
          feader_amount numeric(14,2),
          cofinanced_amount numeric(14,2)
        );

        CREATE INDEX registered_cap_subsidies_siren ON registered_cap_subsidies(siren);
        CREATE INDEX registered_cap_subsidies_year ON registered_cap_subsidies(year);
        CREATE INDEX registered_cap_subsidies_intervention_code ON registered_cap_subsidies(intervention_code);
        CREATE INDEX registered_cap_subsidies_siren_year ON registered_cap_subsidies(siren, year);
      SQL
    end

    def normalize
      YEARS.each do |year|
        logger.debug "Normalizing CAP beneficiaries #{year}…"
        insert_beneficiaries(year)
        logger.debug "Normalizing CAP subsidies #{year}…"
        insert_subsidies(year)
      end
    end

    private

      # The source CSV is hierarchical: a "beneficiary" row (with SIREN and totals)
      # is followed by N "operation" rows that have an empty SIREN. PostgreSQL's
      # COPY does not preserve row order, so we cannot forward-fill the SIREN with
      # a SQL window function after loading. We do it here in a streaming pass.
      def preprocess(src, dst)
        current_siren     = nil
        current_name      = nil
        current_firstname = nil
        current_company   = nil
        current_commune   = nil

        CSV.open(dst, 'wb', encoding: 'UTF-8') do |out|
          out << OUTPUT_HEADERS
          CSV.foreach(src, headers: true, encoding: 'UTF-8') do |row|
            siren_cell = row[SOURCE_HEADERS[:siren]].to_s.strip

            if siren_cell != ''
              current_siren     = siren_cell
              current_name      = row[SOURCE_HEADERS[:beneficiary_name]]
              current_firstname = row[SOURCE_HEADERS[:beneficiary_firstname]]
              current_company   = row[SOURCE_HEADERS[:company_name]]
              current_commune   = row[SOURCE_HEADERS[:commune]]

              out << [
                'beneficiary', current_siren, current_name, current_firstname,
                current_company, current_commune,
                nil, nil, nil, nil, nil,
                nil,
                row[SOURCE_HEADERS[:feaga_total]],
                nil,
                row[SOURCE_HEADERS[:feader_total]],
                nil,
                row[SOURCE_HEADERS[:cofinanced_total]],
                row[SOURCE_HEADERS[:total_feader_cofinanced]],
                row[SOURCE_HEADERS[:total_eu_cofinanced]],
              ]
            elsif current_siren
              out << [
                'operation', current_siren, current_name, current_firstname,
                current_company, current_commune,
                row[SOURCE_HEADERS[:intervention_code]],
                row[SOURCE_HEADERS[:intervention_label]],
                row[SOURCE_HEADERS[:intervention_objective]],
                row[SOURCE_HEADERS[:intervention_start_date]],
                row[SOURCE_HEADERS[:intervention_end_date]],
                row[SOURCE_HEADERS[:feaga_amount]],
                nil,
                row[SOURCE_HEADERS[:feader_amount]],
                nil,
                row[SOURCE_HEADERS[:cofinanced_amount]],
                nil, nil, nil,
              ]
            end
          end
        end
      end

      def insert_beneficiaries(year)
        query <<~SQL
          INSERT INTO registered_cap_beneficiaries
            (siren, year, beneficiary_name, beneficiary_firstname, company_name, commune,
             feaga_total, feader_total, cofinanced_total,
             total_feader_cofinanced, total_eu_cofinanced)
          SELECT
            siren,
            #{year},
            MAX(NULLIF(beneficiary_name, '')),
            MAX(NULLIF(beneficiary_firstname, '')),
            MAX(NULLIF(company_name, '')),
            MAX(NULLIF(commune, '')),
            MAX(NULLIF(feaga_total, '')::numeric(14,2)),
            MAX(NULLIF(feader_total, '')::numeric(14,2)),
            MAX(NULLIF(cofinanced_total, '')::numeric(14,2)),
            MAX(NULLIF(total_feader_cofinanced, '')::numeric(14,2)),
            MAX(NULLIF(total_eu_cofinanced, '')::numeric(14,2))
          FROM #{SCHEMA}.cap_beneficiaries_#{year}
          WHERE row_kind = 'beneficiary'
            AND siren IS NOT NULL AND siren <> ''
          GROUP BY siren
          ON CONFLICT (siren, year) DO NOTHING
        SQL
      end

      def insert_subsidies(year)
        query <<~SQL
          INSERT INTO registered_cap_subsidies
            (siren, year, intervention_code, intervention_label, intervention_objective,
             intervention_start_date, intervention_end_date,
             feaga_amount, feader_amount, cofinanced_amount)
          SELECT
            siren,
            #{year},
            intervention_code,
            NULLIF(intervention_label, ''),
            NULLIF(intervention_objective, ''),
            NULLIF(intervention_start_date, '')::date,
            NULLIF(intervention_end_date, '')::date,
            NULLIF(feaga_amount, '')::numeric(14,2),
            NULLIF(feader_amount, '')::numeric(14,2),
            NULLIF(cofinanced_amount, '')::numeric(14,2)
          FROM #{SCHEMA}.cap_beneficiaries_#{year}
          WHERE row_kind = 'operation'
            AND siren IS NOT NULL AND siren <> ''
            AND intervention_code IS NOT NULL AND intervention_code <> ''
        SQL
      end
  end
end
