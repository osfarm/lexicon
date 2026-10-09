# frozen_string_literal: true

require 'test_helper'

module Lexicon
  module Contribution
    class ImportTest < Minitest::Test
      def test_table_of_a_french_spreadsheet_is_made_a_contribution
        csv = "Code INSEE;Nom de la parcelle;Mesuré le;Humidité (%);Irrigué;Profondeur\n" \
              "17387;Les Prés;01/09/2026;12,5;oui;30\n01001;Le Bois;2/9/2026;8;non;60\n"
        result = Import.new('Relevés Sol 2026.csv', csv).result

        assert_equal 'releves_sol_2026.csv', result.file
        assert_equal({ 'code_insee' => 'text', 'nom_de_la_parcelle' => 'text', 'mesure_le' => 'date', 'humidite' => 'number',
                       'irrigue' => 'boolean', 'profondeur' => 'integer' }, result.columns)
        assert_equal "code_insee,nom_de_la_parcelle,mesure_le,humidite,irrigue,profondeur\n" \
                     "17387,Les Prés,2026-09-01,12.5,true,30\n01001,Le Bois,2026-09-02,8,false,60\n", result.csv
        assert_equal 'code_insee', result.key
        assert_equal({ 'code_insee' => 'commune' }, result.pivots)
        assert(result.notes.any? { |note| note.start_with?('6 colonnes sont renommées') })
        assert(result.notes.any? { |note| note.include?('le point-virgule') })
      end

      def test_codes_stay_text_whatever_they_look_like
        result = Import.new('a.csv', "id,code_postal,departement,numero,quantite\n1,17100,17,007,3\n2,01000,01,012,4\n").result

        assert_equal({ 'id' => 'text', 'code_postal' => 'text', 'departement' => 'text', 'numero' => 'text', 'quantite' => 'integer' },
                     result.columns)
        assert_includes result.csv, "2,01000,01,012,4\n"
        assert_equal({ 'departement' => 'department' }, result.pivots)
      end

      def test_mixed_column_is_text_and_keeps_its_values
        result = Import.new('a.csv', "id,valeur,jour\na,12,2026-09-01\nb,environ 3,hier\n").result

        assert_equal({ 'id' => 'text', 'valeur' => 'text', 'jour' => 'text' }, result.columns)
        assert_includes result.csv, "b,environ 3,hier\n"
      end

      def test_date_that_does_not_exist_is_not_a_date
        assert_equal 'text', Import.new('a.csv', "id,jour\na,31/02/2026\nb,01/03/2026\n").result.columns['jour']
      end

      def test_day_exported_as_an_instant_is_a_date_and_a_real_time_is_a_datetime
        csv = "id,inspecte_le,edite_le\na,2026-06-03T02:00:00+02:00,2026-06-15T04:30:27+02:00\nb,2025-12-03T01:00:00+01:00,2025-12-04T00:00:00\n"
        result = Import.new('a.csv', csv).result

        assert_equal({ 'id' => 'text', 'inspecte_le' => 'date', 'edite_le' => 'datetime' }, result.columns)
        assert_includes result.csv, "a,2026-06-03,2026-06-15T04:30:27+02:00\nb,2025-12-03,2025-12-04T00:00:00\n"
      end

      def test_many_renamed_columns_are_counted_not_listed
        result = Import.new('a.csv', "Id,Nom,Prénom,Ville,Pays\n1,a,b,c,d\n2,e,f,g,h\n").result

        assert_includes result.notes, '5 colonnes sont renommées en minuscules, sans accent ni espace : « Id » devient « id », ' \
                                      '« Nom » devient « nom », « Prénom » devient « prenom »…'
      end

      def test_numbers_with_thousands_are_read
        result = Import.new('a.csv', "id;surface\na;1 234,5\nb;12\n").result

        assert_equal 'number', result.columns['surface']
        assert_includes result.csv, "a,1234.5\n"
      end

      def test_line_number_is_added_when_no_column_identifies_a_line
        result = Import.new('a.csv', "commune,valeur\nSaintes,1\nSaintes,2\n").result

        assert_equal 'id', result.key
        assert_equal "id,commune,valeur\n1,Saintes,1\n2,Saintes,2\n", result.csv
        assert_equal 'integer', result.columns['id']
      end

      def test_titles_are_made_names_that_differ
        result = Import.new('a.csv', "Nom,nom,,2024,Été\na,b,c,1,d\ne,f,g,2,h\n").result

        assert_equal %w[nom nom_2 colonne_3 c_2024 ete], result.columns.keys
      end

      def test_file_in_another_encoding_keeps_its_accents
        result = Import.new('a.csv', "id;commune\n1;Orléans\n2;Sète\n".encode(Encoding::WINDOWS_1252)).result

        assert_includes result.csv, "1,Orléans\n"
        assert(result.notes.any? { |note| note.include?('UTF-8') })
      end

      def test_tabs_and_empty_lines_are_read
        result = Import.new('a.tsv', "id\tvaleur\n\na\t1\n\t\nb\t2\n").result

        assert_equal "id,valeur\na,1\nb,2\n", result.csv
      end

      def test_excel_sheet_is_read_with_its_dates_and_numbers
        book = Spreadsheet::Workbook.new
        sheet = book.create_worksheet(name: 'Relevés')
        sheet.row(0).concat(['Référence', 'Mesuré le', 'Valeur', 'Nombre'])
        sheet.row(1).concat(['r1', Date.new(2026, 9, 1), 12.5, 3])
        sheet.row(2).concat(['r2', Date.new(2026, 9, 2), 8.0, 4])
        content = StringIO.new.tap { |io| book.write(io) }.string
        result = Import.new('releves.xls', content).result

        assert_equal({ 'reference' => 'text', 'mesure_le' => 'date', 'valeur' => 'number', 'nombre' => 'integer' }, result.columns)
        assert_equal "reference,mesure_le,valeur,nombre\nr1,2026-09-01,12.5,3\nr2,2026-09-02,8,4\n", result.csv
        assert_equal 'reference', result.key
        assert(result.notes.any? { |note| note.include?('« Relevés »') })
      end

      def test_postal_code_and_name_tell_a_commune_when_no_column_carries_its_code
        result = Import.new('a.csv', "id,code_postal,ville\n1,17400,Saint-Jean-d'Angély\n2,92310,Sèvres\n").result
        coded = Import.new('a.csv', "id,code_postal,ville,code_insee\n1,17400,Saint-Jean-d'Angély,17347\n2,92310,Sèvres,92072\n").result

        assert_equal({ 'code_postal' => 'commune_postal_code', 'ville' => 'commune_name' }, result.pivots)
        assert_equal({ 'code_insee' => 'commune' }, coded.pivots)
      end

      def test_establishment_number_is_a_link_even_with_a_few_odd_values
        lines = (1..40).map { |index| "#{index},#{format('%014d', 98_457_348_500_000 + index)}" }
        result = Import.new('a.csv', "id,siret\n#{lines.join("\n")}\n41,P00077744001\n").result
        odd = Import.new('a.csv', "id,siret\n1,98457348500013\n2,P00077744001\n3,H00000259001\n").result

        assert_equal({ 'siret' => 'siret' }, result.pivots)
        assert_equal 'text', result.columns['siret']
        assert_empty odd.pivots
      end

      def test_points_are_read_however_they_are_written
        csv = "id;geores;position;surface\n1;48.811873,2.211849;POINT(2.21 48.81);12,5\n2;5.637673,-53.742925;POINT(-53.74 5.63);8,25\n"
        object = %(id;geo\n1;"{""lon"": 2.211849, ""lat"": 48.811873}"\n2;"{""lat"": 5.637673, ""lon"": -53.742925}"\n)
        result = Import.new('a.csv', csv).result

        assert_equal({ 'id' => 'text', 'geores' => 'point', 'position' => 'point', 'surface' => 'number' }, result.columns)
        assert_includes result.csv, %(1,"48.811873,2.211849","48.81,2.21",12.5\n)
        assert_includes Import.new('a.csv', object).result.csv, %(1,"48.811873,2.211849"\n2,"5.637673,-53.742925"\n)
        assert_equal 'text', Import.new('a.csv', "id,note\n1,\"95.5,2.5\"\n2,\"12.5,3.5\"\n").result.columns['note']
      end

      def test_french_dates_with_a_time_are_rewritten
        result = Import.new('a.csv', "id;releve_le\n1;04/12/2025 17:00\n2;5/1/2026 9h05\n3;06/01/2026\n").result
        wrong = Import.new('a.csv', "id;releve_le\n1;04/12/2025 25:00\n2;05/01/2026 09:05\n").result

        assert_equal 'datetime', result.columns['releve_le']
        assert_equal "id,releve_le\n1,2025-12-04T17:00:00\n2,2026-01-05T09:05:00\n3,2026-01-06T00:00:00\n", result.csv
        assert_equal 'text', wrong.columns['releve_le']
      end

      def test_what_is_no_table_is_said
        assert_raises(Import::Unreadable) { Import.new('notes.pdf', 'x').result }
        assert_raises(Import::Unreadable) { Import.new('a.csv', '').result }
        assert_raises(Import::Unreadable) { Import.new('a.csv', "id,valeur\n").result }
        assert_raises(Import::Unreadable) { Import.new('a.xlsx', 'pas un classeur').result }
      end
    end
  end
end
