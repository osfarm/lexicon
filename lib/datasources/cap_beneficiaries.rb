require 'csv'

module Datasources
  class CapBeneficiaries < Base
    # Date of the latest file of the source
    LAST_UPDATED = "2026-06-01"
    SCHEMA = 'cap_beneficiaries'.freeze
    # One file per year, `cap_beneficiaries_<year>.csv` in raw/cap_beneficiaries/. The source changed its
    # layout with the 2025 file:
    # - :hierarchical — a row for the beneficiary (identity and totals), then one row per operation with
    #   no identity at all; comma separated
    # - :flat — every row carries the identity of its beneficiary; semicolon separated; no first name
    #   nor company column, but a postal code and an INSEE code
    FORMATS = { 2024 => :hierarchical, 2025 => :flat }.freeze
    YEARS = FORMATS.keys.freeze

    description 'Bénéficiaires des subventions de la Politique Agricole Commune (PAC) — FEAGA & FEADER'
    credits name: 'Bénéficiaires des aides de la PAC',
            url: 'https://www.data.gouv.fr/fr/datasets/beneficiaires-des-aides-de-la-pac/',
            provider: 'Agence de Services et de Paiement (ASP)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: LAST_UPDATED
    schema_revision 2
    pivot :siren, table: :registered_cap_beneficiaries, column: :siren
    pivot :commune, table: :registered_cap_beneficiaries, column: :commune_code

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

    # What the :flat layout adds or names differently
    FLAT_HEADERS = {
      commune:      'Commune',
      postal_code:  'Code postal',
      commune_code: 'Code INSEE commune',
      fund:         'Fonds'
    }.freeze

    OUTPUT_HEADERS = %w[
      row_kind siren beneficiary_name beneficiary_firstname company_name commune postal_code commune_code
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
        logger.debug "Preprocessing #{src.basename} → #{dst.basename} (#{FORMATS.fetch(year)} layout)…"
        FORMATS.fetch(year) == :flat ? preprocess_flat(src, dst) : preprocess_hierarchical(src, dst)
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
          postal_code character varying,
          commune_code character varying,
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

      # The :hierarchical layout: a "beneficiary" row (identity and totals) is followed by N "operation"
      # rows that carry no identity. PostgreSQL's COPY does not preserve row order, so the SIREN cannot be
      # carried forward in SQL after loading: it is done here in a streaming pass.
      #
      # A beneficiary without SIREN is left out with its operations. They must not go to the beneficiary
      # that came before: a row is a beneficiary row when it has no intervention code, whatever its SIREN.
      def preprocess_hierarchical(src, dst)
        current = nil

        CSV.open(dst, 'wb', encoding: 'UTF-8') do |out|
          out << OUTPUT_HEADERS
          CSV.foreach(src, headers: true, encoding: 'UTF-8') do |row|
            if row[SOURCE_HEADERS[:intervention_code]].to_s.strip == ''
              siren = row[SOURCE_HEADERS[:siren]].to_s.strip
              current = siren == '' ? nil : [
                siren,
                row[SOURCE_HEADERS[:beneficiary_name]],
                row[SOURCE_HEADERS[:beneficiary_firstname]],
                row[SOURCE_HEADERS[:company_name]],
                row[SOURCE_HEADERS[:commune]],
                nil, nil
              ]
              out << beneficiary_row(current, row) if current
            elsif current
              out << operation_row(current, row)
            end
          end
        end
      end

      # The :flat layout: every row carries its beneficiary. A row without fund nor intervention code holds
      # the totals; a beneficiary settled in several communes has one such row per commune.
      def preprocess_flat(src, dst)
        CSV.open(dst, 'wb', encoding: 'UTF-8') do |out|
          out << OUTPUT_HEADERS
          CSV.foreach(src, headers: true, encoding: 'UTF-8', col_sep: ';', liberal_parsing: true) do |row|
            siren = row[SOURCE_HEADERS[:siren]].to_s.strip
            next if siren == ''

            identity = [
              siren,
              row[SOURCE_HEADERS[:beneficiary_name]],
              nil, nil,
              row[FLAT_HEADERS[:commune]],
              code_or_nil(row[FLAT_HEADERS[:postal_code]]),
              code_or_nil(row[FLAT_HEADERS[:commune_code]])
            ]
            is_total = row[FLAT_HEADERS[:fund]].to_s.strip == '' && row[SOURCE_HEADERS[:intervention_code]].to_s.strip == ''

            out << (is_total ? beneficiary_row(identity, row) : operation_row(identity, row))
          end
        end
      end

      # The source writes "COMMUNE ANONYMISEE - …" in place of the codes of the smallest beneficiaries
      def code_or_nil(value)
        value.to_s.strip.match?(/\A[0-9][0-9AB][0-9]{3}\z/) ? value.strip : nil
      end

      def beneficiary_row(identity, row)
        [
          'beneficiary', *identity,
          nil, nil, nil, nil, nil,
          nil,
          row[SOURCE_HEADERS[:feaga_total]],
          nil,
          row[SOURCE_HEADERS[:feader_total]],
          nil,
          row[SOURCE_HEADERS[:cofinanced_total]],
          row[SOURCE_HEADERS[:total_feader_cofinanced]],
          row[SOURCE_HEADERS[:total_eu_cofinanced]]
        ]
      end

      def operation_row(identity, row)
        [
          'operation', *identity,
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
          nil, nil, nil
        ]
      end

      # The totals of a beneficiary are not read from the source: they are the sum of its operations. A SIREN
      # may have several rows of totals in a year, one per commune or per name, and the source is not
      # consistent about them: some hold their own share, others repeat the total of the whole beneficiary.
      # The operations, them, are each given once.
      def insert_beneficiaries(year)
        amount = ->(column) { "COALESCE(SUM(NULLIF(#{column}, '')::numeric(14,2)), 0)" }

        query <<~SQL
          INSERT INTO registered_cap_beneficiaries
            (siren, year, beneficiary_name, beneficiary_firstname, company_name, commune, postal_code, commune_code,
             feaga_total, feader_total, cofinanced_total,
             total_feader_cofinanced, total_eu_cofinanced)
          SELECT
            identity.siren,
            #{year},
            identity.beneficiary_name,
            identity.beneficiary_firstname,
            identity.company_name,
            identity.commune,
            identity.postal_code,
            identity.commune_code,
            COALESCE(operations.feaga, 0),
            COALESCE(operations.feader, 0),
            COALESCE(operations.cofinanced, 0),
            COALESCE(operations.feader, 0) + COALESCE(operations.cofinanced, 0),
            COALESCE(operations.feaga, 0) + COALESCE(operations.feader, 0) + COALESCE(operations.cofinanced, 0)
          FROM (
            SELECT siren,
                   MAX(NULLIF(beneficiary_name, '')) AS beneficiary_name,
                   MAX(NULLIF(beneficiary_firstname, '')) AS beneficiary_firstname,
                   MAX(NULLIF(company_name, '')) AS company_name,
                   MAX(NULLIF(commune, '')) AS commune,
                   MAX(NULLIF(postal_code, '')) AS postal_code,
                   MAX(NULLIF(commune_code, '')) AS commune_code
              FROM #{SCHEMA}.cap_beneficiaries_#{year}
             WHERE row_kind = 'beneficiary'
               AND siren IS NOT NULL AND siren <> ''
             GROUP BY siren
          ) AS identity
          LEFT JOIN (
            SELECT siren,
                   #{amount.call('feaga_amount')} AS feaga,
                   #{amount.call('feader_amount')} AS feader,
                   #{amount.call('cofinanced_amount')} AS cofinanced
              FROM #{SCHEMA}.cap_beneficiaries_#{year}
             WHERE row_kind = 'operation'
               AND intervention_code IS NOT NULL AND intervention_code <> ''
             GROUP BY siren
          ) AS operations USING (siren)
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
