# frozen_string_literal: true

require 'test_helper'

module Datasources
  class BsvArchiveTest < Minitest::Test
    def documents
      @documents ||= BsvArchive::Documents.new
    end

    def read(path, content)
      BsvArchive::Documents::COLUMNS.zip(documents.row(path, content)).to_h
    end

    def test_an_avertissement_takes_its_sectors_and_regions_from_its_name_and_its_date_from_its_title
      xml = <<~XML
        <TEI><teiHeader><fileDesc><titleStmt><title>Avertissements agricoles Le 16 Octobre 1984 Suppl&#233;ment</title></titleStmt></fileDesc></teiHeader>
        <text><body><head>ARBORICULTURE</head><div1><head>S&#233;sie sur pommier :</head><p>Contre ce ravageur...</p></div1></body></text></TEI>
      XML
      row = read('projets/musk/pestobserver/reportsOCR/AA_AF_VG_Pays_de_la_Loire_Poitou_Charentes_1984_030.xml', xml)

      assert_equal 'AA_AF_VG_Pays_de_la_Loire_Poitou_Charentes_1984_030', row['id']
      assert_equal 'avertissement', row['kind']
      assert_equal 'arboriculture|viticulture', row['sectors']
      assert_equal 'pays de la loire|poitou charentes', row['old_regions']
      assert_equal 'pays-de-la-loire|nouvelle-aquitaine', row['regions']
      assert_equal '16|17|44|49|53|72|79|85|86', row['department_codes']
      assert_equal ['1984-10-16', 1984], row.values_at('published_on', 'year')
      assert_equal "ARBORICULTURE\nSésie sur pommier :\nContre ce ravageur...", row['text']
    end

    def test_a_department_or_a_vineyard_of_a_name_is_a_place_too
      row = read('AA_VG_Rhone-Alpes_Bas-Vivarais_1990_001.xml', '<title>Bulletin</title><text>x</text>')
      assert_equal 'rhone alpes|bas vivarais', row['old_regions']
      assert_nil row['published_on']
      assert_equal 1990, row['year']

      assert_equal '16', read('BP_GC_Charente_1982_001.xml', '<text>x</text>')['department_codes']
    end

    def test_a_bsv_takes_its_region_from_the_site_in_its_name
      row = read('draaf.alsace-champagne-ardenne-lorraine.agriculture.gouv.fr_IMG_pdf_BSV_Viti_no11_08062011_cle8982ed.txt',
                 'BULLETIN DE SANTE DU VEGETAL Vigne')

      assert_equal 'grand-est', row['regions'], 'one region of today, not Alsace, Champagne-Ardenne and Lorraine'
      assert_equal %w[viticulture 2011-06-08], row.values_at('sectors', 'published_on')
    end

    def test_a_bsv_takes_its_region_and_date_from_its_header_or_the_sites_it_names
      spaced = "B U L L E T I N   D E   S A N T É   D U\nV É G É T A L   P A Y S   D E   L A   L O I R E\n0 9   M A R S   2 0 1 0\nN° 14"
      row = read('14_bsv_gc_cle01154c.txt', "BULLETIN DE SANTE DU VEGETAL\nPAYS DE LA LOIRE\n#{spaced}")
      assert_equal ['pays-de-la-loire', 'grandes cultures', '2010-03-09'], row.values_at('regions', 'sectors', 'published_on')

      row = read('BSV_ZNA_14-06_cle862712.txt', "Bulletin N° 6 du 12 mai 2014\nInscription sur cra-idf.chambagri.fr")
      assert_equal ['ile-de-france', 'horticulture', '2014-05-12'], row.values_at('regions', 'sectors', 'published_on')

      row = read('BSV_N_7-Melon-2013.05.07.txt', 'BULLETIN DE SANTE DU VEGETAL SUD-OUEST')
      assert_equal ['', 'maraîchage', '2013-05-07'], row.values_at('regions', 'sectors', 'published_on')
      assert_equal 'note', read('Note_nationale_BSV2014_ambroisies_cle889edb-5.txt', 'x')['kind']
    end
  end
end
