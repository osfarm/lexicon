# frozen_string_literal: true

module Datasources
  # Organic farming year by year since 2008, from the yearly inspections of the certification bodies, as the
  # Agence Bio publishes it: operators, farms, areas and livestock, by commune and by intercommunality (EPCI).
  #
  # Two things to know before reading a figure. Areas and livestock of fewer than three farms are kept secret
  # in a commune: the number of farms is given, the figure is not (`masked`); the intercommunality, where
  # almost nothing is secret, gives the order of magnitude. And every parcel of a farm is counted in the
  # commune of its seat, wherever it lies.
  class OrganicFarming < Base
    description "Agriculture biologique depuis 2008 : opérateurs, exploitations, surfaces et cheptels engagés, par commune et par intercommunalité, d'après l'Agence Bio"
    credits name: "Historique détaillé des surfaces, cheptels et nombre d'opérateurs par commune et par EPCI",
            url: 'https://www.data.gouv.fr/datasets/historique-detaille-des-surfaces-cheptels-et-nombre-doperateurs-par-commune',
            provider: 'Agence Bio',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-09-16'

    schema_revision 1
    # The source is as recent as the last year it covers
    source_date 'SELECT make_date(max(year), 12, 31) FROM registered_organic_areas'
    pivot :commune, table: :registered_organic_areas, column: :insee_code, minimum: 0.95

    # The datasets of the Agence Bio, and what their files are loaded as: a file is told by the end of its name
    DATASETS = {
      'historique-detaille-des-surfaces-cheptels-et-nombre-doperateurs-par-commune' =>
        { 'operateurs' => 'operators', 'sau' => 'areas', 'cheptels' => 'livestock' },
      'historique-detaille-des-surfaces-cheptels-et-nombre-doperateurs-par-epci' =>
        { 'sau' => 'epci_areas', 'cheptels' => 'epci_livestock' }
    }.freeze
    # Written in place of a figure under statistical secrecy, and of a value the source does not have
    SECRET = 'NC'
    MISSING = 'NA'
    # Where the source puts what it cannot place
    NOWHERE = '00000'

    AREAS = %w[surfab surfc1 surfc2 surfc3 surfc123 surfbio].freeze
    HEADS = %w[tetesab tetesconversionsimult tetesconversionnonsimult tetesbio].freeze

    # Downloads the files of a publication the source dated anew since the last collect
    def collect
      DATASETS.each do |slug, files|
        resources = data_gouv_resources(slug, as: "#{slug[/par-(\w+)\z/, 1]}.json")
        files.each do |suffix, table|
          resource = resources.find { |found| found['url'].end_with?("-#{suffix}.csv") }
          raise "No file ending with -#{suffix}.csv in the dataset #{slug}" if resource.nil?

          stamp = dir.join("#{table}.stamp")
          next if stamp.exist? && stamp.read == resource['last_modified'] && dir.join("#{table}.csv").size?

          fetch(resource.fetch('url'), "#{table}.csv", again: true)
          stamp.write(resource['last_modified'])
        end
      end
    end

    # The files are loaded as they are, every column as text, without the mark their first line starts with
    def load
      DATASETS.values.flat_map(&:values).each do |table|
        file = dir.join("#{table}.csv")
        raise "No file #{file}: run the collect phase first" unless file.size?

        execute "sed '1s/^\\xEF\\xBB\\xBF//' '#{file}' > '#{file}.plain'"
        load_csv(Pathname.new("#{file}.plain"), table, encoding: 'UTF8')
      ensure
        FileUtils.rm_f("#{file}.plain")
      end
    end

    def self.table_definitions(builder)
      builder.table(:registered_organic_operators, sql: <<~SQL)
        CREATE TABLE registered_organic_operators (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          kind character varying NOT NULL,
          main_production character varying NOT NULL,
          activities character varying NOT NULL,
          operators_count integer NOT NULL,
          PRIMARY KEY (insee_code, year, kind, main_production, activities)
        );
      SQL

      builder.table(:registered_organic_areas, sql: <<~SQL)
        CREATE TABLE registered_organic_areas (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          epci_code character varying,
          farms_count integer NOT NULL,
          masked boolean NOT NULL,
          certified_area numeric(12,4),
          first_year_conversion_area numeric(12,4),
          second_year_conversion_area numeric(12,4),
          third_year_conversion_area numeric(12,4),
          conversion_area numeric(12,4),
          organic_area numeric(12,4),
          PRIMARY KEY (insee_code, year)
        );
        CREATE INDEX registered_organic_areas_year ON registered_organic_areas (year);
      SQL

      builder.table(:registered_organic_livestock, sql: <<~SQL)
        CREATE TABLE registered_organic_livestock (
          insee_code character varying NOT NULL,
          year integer NOT NULL,
          group_code character varying NOT NULL,
          group_name character varying NOT NULL,
          production character varying NOT NULL,
          farms_count integer NOT NULL,
          masked boolean NOT NULL,
          certified_heads integer,
          conversion_heads integer,
          organic_heads integer,
          PRIMARY KEY (insee_code, year, production)
        );
      SQL

      builder.table(:registered_organic_epci_areas, sql: <<~SQL)
        CREATE TABLE registered_organic_epci_areas (
          epci_code character varying NOT NULL,
          year integer NOT NULL,
          epci_name character varying NOT NULL,
          farms_count integer NOT NULL,
          masked boolean NOT NULL,
          certified_area numeric(12,4),
          first_year_conversion_area numeric(12,4),
          second_year_conversion_area numeric(12,4),
          third_year_conversion_area numeric(12,4),
          conversion_area numeric(12,4),
          organic_area numeric(12,4),
          PRIMARY KEY (epci_code, year)
        );
      SQL

      builder.table(:registered_organic_epci_livestock, sql: <<~SQL)
        CREATE TABLE registered_organic_epci_livestock (
          epci_code character varying NOT NULL,
          year integer NOT NULL,
          group_code character varying NOT NULL,
          group_name character varying NOT NULL,
          production character varying NOT NULL,
          farms_count integer NOT NULL,
          masked boolean NOT NULL,
          certified_heads integer,
          conversion_heads integer,
          organic_heads integer,
          PRIMARY KEY (epci_code, year, production)
        );
      SQL

      # The intercommunality of each commune the source names, as its latest year gives it
      builder.table(:registered_organic_communes, sql: <<~SQL)
        CREATE TABLE registered_organic_communes (
          insee_code character varying PRIMARY KEY NOT NULL,
          epci_code character varying,
          epci_name character varying,
          first_year integer NOT NULL,
          last_year integer NOT NULL
        );
      SQL
    end

    # A place the source writes twice in a year, under two names, is one line: its farms are added, and its
    # figures too unless one of them is secret.
    def normalize
      query <<~SQL
        INSERT INTO registered_organic_operators (insee_code, year, kind, main_production, activities, operators_count)
          SELECT codeinseecommune, annee::integer, codesimple_ptdi, productionprincipale, activites, sum(nboperateur::integer)
            FROM #{name}.operators
           WHERE #{placed('codeinseecommune')}
           GROUP BY 1, 2, 3, 4, 5
      SQL

      query <<~SQL
        INSERT INTO registered_organic_areas
          (insee_code, year, epci_code, farms_count, masked, certified_area, first_year_conversion_area,
           second_year_conversion_area, third_year_conversion_area, conversion_area, organic_area)
          SELECT codeinseecommune, annee::integer, min(#{known('codeepci')}), sum(nb_exp::integer), #{masked('surfbio')},
                 #{AREAS.map { |column| total(column, 'numeric') }.join(', ')}
            FROM #{name}.areas
           WHERE #{placed('codeinseecommune')}
           GROUP BY 1, 2
      SQL
      query <<~SQL
        INSERT INTO registered_organic_epci_areas
          (epci_code, year, epci_name, farms_count, masked, certified_area, first_year_conversion_area,
           second_year_conversion_area, third_year_conversion_area, conversion_area, organic_area)
          SELECT codeepci, annee::integer, min(epci), sum(nb_exp::integer), #{masked('surfbio')},
                 #{AREAS.map { |column| total(column, 'numeric') }.join(', ')}
            FROM #{name}.epci_areas
           WHERE #{placed('codeepci')}
           GROUP BY 1, 2
      SQL

      # The source masks the livestock of fewer than three farms in a commune and gives it whole for an
      # intercommunality: it is served as published
      { 'livestock' => %w[registered_organic_livestock insee_code codeinseecommune],
        'epci_livestock' => %w[registered_organic_epci_livestock epci_code codeepci] }.each do |raw, (table, column, source)|
        query <<~SQL
          INSERT INTO #{table}
            (#{column}, year, group_code, group_name, production, farms_count, masked, certified_heads, conversion_heads, organic_heads)
            SELECT #{source}, annee::integer, min(code_groupe), min(groupe_production), production, sum(nb_exp::integer), #{masked('tetesbio')},
                   #{total('tetesab', 'numeric')}::integer,
                   (#{total('tetesconversionsimult', 'numeric')} + #{total('tetesconversionnonsimult', 'numeric')})::integer,
                   #{total('tetesbio', 'numeric')}::integer
              FROM #{name}.#{raw}
             WHERE #{placed(source)}
             GROUP BY 1, 2, production
        SQL
      end

      query <<~SQL
        INSERT INTO registered_organic_communes (insee_code, epci_code, epci_name, first_year, last_year)
          SELECT codeinseecommune,
                 (array_agg(#{known('codeepci')} ORDER BY annee::integer DESC))[1],
                 (array_agg(#{known('epci')} ORDER BY annee::integer DESC))[1],
                 min(annee::integer), max(annee::integer)
            FROM (SELECT codeinseecommune, codeepci, epci, annee FROM #{name}.operators
                  UNION ALL SELECT codeinseecommune, codeepci, epci, annee FROM #{name}.areas
                  UNION ALL SELECT codeinseecommune, codeepci, epci, annee FROM #{name}.livestock) AS named
           WHERE #{placed('codeinseecommune')}
           GROUP BY 1
      SQL
    end

    private

      def known(column)
        "NULLIF(#{column}, '#{MISSING}')"
      end

      def placed(column)
        "#{column} IS NOT NULL AND #{column} NOT IN ('#{MISSING}', '#{NOWHERE}', '')"
      end

      def masked(column)
        "bool_or(#{column} = '#{SECRET}')"
      end

      # The sum of a figure over the lines of a place, unknown as soon as one of them is secret
      def total(column, type)
        "CASE WHEN bool_or(#{column} IN ('#{SECRET}', '#{MISSING}')) THEN NULL ELSE sum(NULLIF(NULLIF(#{column}, '#{SECRET}'), '#{MISSING}')::#{type}) END"
      end
  end
end
