# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Contribution
    class TabularTest < Minitest::Test
      SHEET = <<~YAML
        description: Relevés d'humidité des sols
        author: Camille Martin, GAEC des Prés
        source:
          name: Relevés de sondes
          url: https://example.org/sondes
          provider: GAEC des Prés
          licence: Licence Ouverte 2.0
          licence_url: https://example.org/licence
          date: 2026-09-30
        tables:
          - file: releves.csv
            key: id
            columns:
              id: text
              insee_code: text
              measured_on: date
              value: number
              checked: boolean
              depth: integer
            pivots:
              insee_code: commune
      YAML
      CSV_FILE = <<~CSV
        id,insee_code,measured_on,value,checked,depth
        r1,17387,2026-09-01,12.5,true,30
        r2,28085,2026-09-02,,false,60
      CSV

      def setup
        @root = Pathname.new(Dir.mktmpdir)
      end

      def teardown
        FileUtils.rm_rf(@root)
        Datasources.send(:remove_const, :ReleveSol) if Datasources.const_defined?(:ReleveSol, false)
      end

      def test_complete_contribution_is_accepted
        review = review_of(SHEET, CSV_FILE)

        assert_empty review.findings.map(&:message)
        assert review.accepted?
      end

      def test_what_the_sheet_lacks_is_named
        messages = errors_of("description: Relevés\ntables: []\n", CSV_FILE)

        assert_includes messages, 'La fiche ne renseigne pas « author ».'
        assert_includes messages, 'La fiche ne renseigne pas « source.licence ».'
        assert(messages.any? { |message| message.include?('ne décrit aucun fichier') })
      end

      def test_sheet_left_as_the_skeleton_wrote_it_is_refused
        messages = errors_of(Scaffold.new.sheet('releve_sol').sub('releve_sol.csv', 'releves.csv'), "id,name,insee_code,measured_on,value\nr1,a,17387,2026-09-01,1\n")

        assert_equal Scaffold::PLACEHOLDERS.size, messages.size
        assert_includes messages, 'La fiche garde pour « author » le texte du modèle, « Prénom Nom, organisme » : le remplacer.'
      end

      def test_closed_licence_is_refused_unless_the_dataset_is_reserved
        closed = SHEET.sub('Licence Ouverte 2.0', 'Tous droits réservés')

        assert(errors_of(closed, CSV_FILE).any? { |message| message.include?("n'est pas une licence ouverte") })
        assert_empty errors_of("scope: members\n#{closed}", CSV_FILE)
      end

      def test_share_alike_licence_is_a_warning
        findings = review_of(SHEET.sub('Licence Ouverte 2.0', 'CC-BY-SA 4.0'), CSV_FILE).findings

        assert_equal [:warning], findings.map(&:level)
      end

      def test_values_are_read_against_the_type_of_their_column
        csv = "id,insee_code,measured_on,value,checked,depth\nr1,17387,01/09/2026,\"12,5\",oui,3.5\nr2,28085,2026-09-02,abc,true,60\n"
        messages = errors_of(SHEET, csv)

        assert(messages.any? { |message| message.include?("« measured_on » : 1 valeur n'est pas une date écrite AAAA-MM-JJ (ligne 2 « 01/09/2026 »)") })
        assert(messages.any? { |message| message.include?('« value » : 2 valeurs ne sont pas un nombre') && message.include?('ligne 2 « 12,5 », ligne 3 « abc »') })
        assert(messages.any? { |message| message.include?("« checked » : 1 valeur n'est pas true ou false") })
        assert(messages.any? { |message| message.include?("« depth » : 1 valeur n'est pas un nombre entier") })
      end

      def test_key_must_be_filled_and_unique
        csv = "id,insee_code,measured_on,value,checked,depth\nr1,1,2026-09-01,1,true,1\nr1,2,2026-09-01,1,true,1\n,3,2026-09-01,1,true,1\n"
        messages = errors_of(SHEET, csv)

        assert(messages.any? { |message| message.include?("1 ligne n'a pas de valeur dans « id »") })
        assert(messages.any? { |message| message.include?('1 valeur de « id » revient plusieurs fois (r1)') })
      end

      def test_columns_of_the_file_and_of_the_sheet_must_be_the_same
        messages = errors_of(SHEET, "id,insee_code,measured_on,value,checked,note\nr1,1,2026-09-01,1,true,x\n")

        assert(messages.any? { |message| message.include?('il manque la colonne depth, annoncée par la fiche') })
        assert(messages.any? { |message| message.include?("la colonne note n'est pas décrite") })
      end

      def test_postal_code_and_name_of_a_commune_go_together
        csv = "id,code_postal,ville\nr1,17400,Saint-Jean-d'Angély\n"
        columns = "      id: text\n      code_postal: text\n      ville: text\n"
        sheet = SHEET.sub(/      id: text.*      depth: integer\n/m, columns)
        both = review_of(sheet.sub('insee_code: commune', "code_postal: commune_postal_code\n      ville: commune_name"), csv)
        alone = errors_of(sheet.sub('insee_code: commune', 'code_postal: commune_postal_code'), csv)

        assert both.accepted?
        assert(both.findings.any? { |finding| finding.level == :warning && finding.message.include?('ajoutera une colonne « insee_code »') })
        assert(alone.any? { |message| message.include?('Désigner aussi la colonne qui porte le nom de la commune') })
      end

      def test_commune_found_from_postal_code_and_name_is_a_column_of_the_table
        dir = @root.join('releve_sol')
        dir.mkpath
        table = Sheet::Table.new(file: 'releves.csv', name: 'registered_releve_sol', key: 'id',
                                 columns: { 'id' => 'text', 'code_postal' => 'text', 'ville' => 'text' },
                                 pivots: { 'code_postal' => 'commune_postal_code', 'ville' => 'commune_name' })
        insert = TabularDatasource.insert_sql(table, 'releve_sol')

        assert_equal({ postal_code: 'code_postal', name: 'ville', column: 'insee_code' }, table.place)
        assert_empty table.keys
        assert_includes TabularDatasource.create_sql(table), '"insee_code" character varying'
        assert_includes insert, 'INSERT INTO registered_releve_sol ("id", "code_postal", "ville", "insee_code")'
        assert_includes insert, %(place.postal_code = trim(source."code_postal"))
        assert_includes insert, 'HAVING count(DISTINCT place.code) = 1'
      end

      def test_point_is_a_cell_holding_latitude_then_longitude
        sheet = SHEET.sub('value: number', 'value: point')
        table = Sheet.load(sheet_of(sheet, nil).dir).tables.first

        assert_empty errors_of(sheet, %(id,insee_code,measured_on,value,checked,depth\nr1,17387,2026-09-01,"48.81,2.21",true,30\n))
        assert(errors_of(sheet, %(id,insee_code,measured_on,value,checked,depth\nr1,17387,2026-09-01,"148.81,2.21",true,30\n))
          .any? { |message| message.include?("1 valeur n'est pas un point écrit latitude,longitude") })
        assert_includes TabularDatasource.create_sql(table), '"value" postgis.geometry(Point,4326)'
        assert_includes TabularDatasource.insert_sql(table, 'releve_sol'),
                        "postgis.ST_MakePoint(split_part(NULLIF(trim(\"value\"), ''), ',', 2)::float8"
        assert_equal [43.233885, 0.000099], Sheet.point('43.233885, 9.9e-05')
      end

      def test_datetime_is_a_day_and_a_time
        sheet = SHEET.sub('measured_on: date', 'measured_on: datetime')
        line = ->(value) { "id,insee_code,measured_on,value,checked,depth\nr1,17387,#{value},1,true,30\n" }

        assert_empty errors_of(sheet, line.call('2025-12-04T17:00:53+01:00'))
        assert_empty errors_of(sheet, line.call('2025-12-04 17:00'))
        assert(errors_of(sheet, line.call('2025-12-04')).any? { |message| message.include?("1 valeur n'est pas une date et une heure") })
        assert(errors_of(sheet, line.call('2025-02-30T10:00:00')).any? { |message| message.include?("n'est pas une date et une heure") })
        assert_includes TabularDatasource.create_sql(Sheet.load(sheet_of(sheet, nil).dir).tables.first), '"measured_on" timestamp with time zone'
      end

      def test_personal_columns_need_a_reason
        sheet = SHEET.sub("      id: text\n", "      id: text\n      email: text\n")
        csv = CSV_FILE.lines.map.with_index { |line, index| line.chomp + (index.zero? ? ',email' : ',a@b.org') }.join("\n")

        assert(errors_of(sheet, csv).any? { |message| message.include?('la colonne email ressemble à des données personnelles') })
        assert_empty errors_of("personal_data: adresses de contact de personnes morales\n#{sheet}", csv)
      end

      def test_missing_file_unknown_type_and_unknown_link_are_said
        sheet = SHEET.sub('value: number', 'value: decimal').sub('insee_code: commune', 'insee_code: village')
        messages = errors_of(sheet, nil)

        assert(messages.any? { |message| message.include?("« releves.csv » n'est pas dans le dossier") })
        assert(messages.any? { |message| message.include?('a le type « decimal », inconnu') })
        assert(messages.any? { |message| message.include?('le lien « insee_code: village » ne se comprend pas') })
      end

      def test_datasource_is_made_from_the_sheet
        datasource = TabularDatasource.define(sheet_of(SHEET, CSV_FILE))

        assert_equal 'releve_sol', datasource.datasource_name
        assert_equal "Relevés d'humidité des sols", datasource.description
        assert_equal ['Relevés de sondes (contribution : Camille Martin, GAEC des Prés)', 'GAEC des Prés', 'Licence Ouverte 2.0', '2026-09-30'],
                     datasource.get_credits.first.then { |credit| [credit.name, credit.provider, credit.licence, credit.updated_at] }
        assert_equal [{ key: 'commune', table: 'registered_releve_sol', column: 'insee_code' }], datasource.get_pivots
        assert_equal 'open', datasource.scope
        assert_nil TabularDatasource.define(sheet_of(SHEET, CSV_FILE)), 'a name is taken once'
      end

      def test_tables_take_the_types_of_the_sheet
        datasource = TabularDatasource.define(sheet_of(SHEET, CSV_FILE))
        table = datasource.sheet.tables.first

        assert_equal <<~SQL.strip, datasource.create_sql(table)
          CREATE TABLE registered_releve_sol (
            "id" character varying PRIMARY KEY NOT NULL,
            "insee_code" character varying,
            "measured_on" date,
            "value" numeric,
            "checked" boolean,
            "depth" integer
          );
        SQL
        insert = datasource.insert_sql(table, 'releve_sol')
        assert_includes insert, %(NULLIF(trim("value"), '')::numeric)
        assert_includes insert, %(NULLIF("id", ''))
        assert_includes insert, 'FROM releve_sol.releves'
      end

      def test_incomplete_or_unreadable_sheet_makes_no_datasource
        assert_nil TabularDatasource.define(sheet_of("description: Relevés\n", CSV_FILE))
        @root.join('casse').mkpath
        @root.join('casse', Sheet::FILE).write("description: [unclosed\n")

        assert_empty TabularDatasource.define_all(@root).map(&:datasource_name) - ['releve_sol']
      end

      def test_several_files_give_one_table_each
        tables = sheet_of("tables:\n  - file: Stations 2026.csv\n  - file: releves.csv\n    table: registered_mesures\n", nil).tables

        assert_equal %w[registered_releve_sol_stations_2026 registered_mesures], tables.map(&:name)
      end

      private

        def sheet_of(yaml, csv)
          dir = @root.join('releve_sol')
          dir.mkpath
          dir.join(Sheet::FILE).write(yaml)
          csv.nil? ? FileUtils.rm_f(dir.join('releves.csv')) : dir.join('releves.csv').write(csv)

          Sheet.load(dir)
        end

        def review_of(yaml, csv)
          Review.new(sheet_of(yaml, csv))
        end

        def errors_of(yaml, csv)
          review_of(yaml, csv).findings.select { |finding| finding.level == :error }.map(&:message)
        end
    end
  end
end
