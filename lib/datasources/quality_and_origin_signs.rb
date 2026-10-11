# frozen_string_literal: true

require 'csv'

module Datasources
  # Quality and origin signs tied to a place (AOC/AOP, IGP, IG), as the INAO publishes them: the products of
  # each geographical area, the communes each area covers, and the zones delimited inside the communes for the
  # wines under AOC. What the INAO publishes is for information: the specification of a product alone says
  # where it may be made.
  class QualityAndOriginSigns < Base
    description 'Signes de qualité et d\'origine (AOC/AOP, IGP, IG) : produits, aires géographiques commune par commune et zones délimitées des AOC viticoles, d\'après l\'INAO'
    credits name: 'Aires et produits AOC/AOP et IGP, aires géographiques par commune, délimitation parcellaire des AOC viticoles',
            url: 'https://www.data.gouv.fr/organizations/institut-national-de-l-origine-et-de-la-qualite-inao/',
            provider: 'INAO',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-05'

    schema_revision 2
    depends_on :postal_codes
    pivot :commune, table: :registered_quality_and_origin_sign_communes, column: :insee_code

    # Datasets of the INAO on data.gouv.fr, and the file each is kept as
    PRODUCTS = 'aires-et-produits-aoc-aop-et-igp'
    COMMUNES = { 'communes_ao.csv' => 'aires-geographiques-des-aoc-aop', 'communes_ig.csv' => 'aire-geographique-des-igp-et-des-ig' }.freeze
    REFERENCE = 'referentiel-des-produits-sous-signe-officiel-didentification-de-la-qualite-et-de-lorigine-siqo'
    ZONES = 'delimitation-parcellaire-des-aoc-viticoles-de-linao'
    # Communes that merged or changed code since 1943, by the INSEE: the lists of the INAO name communes that
    # are gone. A newer file dropped as raw/quality_and_origin_signs/movements.csv is read instead.
    MOVEMENTS_URL = 'https://www.insee.fr/fr/statistiques/fichier/8377162/v_mvt_commune_2025.csv'

    # French category "VSIG"
    VSIG = { 1 => 'VSIG', 2 => 'VSIG rouge', 3 => 'VSIG blanc', 4 => 'VSIG rosé' }.freeze

    # The classes of the European register, gathered the way a commune is told about: wine first
    FAMILIES = {
      'wine' => ['Vins'],
      'spirits' => ['Eaux-de-vie de vin et de marc', 'Autres boissons alcoolisées'],
      'cheese' => ['Fromages'],
      'meat' => ['Viandes (et abats) frais', 'Produits à base de viande (cuits, salés, fumés, etc.)'],
      'fruits_and_vegetables' => ["Fruits, légumes et céréales en l'état ou transformés"],
      'seafood' => ['Poissons, mollusques, crustacés frais et produits dérivés']
    }.freeze
    OTHER_FAMILY = 'other'
    # An area none of whose products is in the register of the INAO is told by the names of its products
    WINE_WORDS = '(blanc|rouge|rosé|mousseux|primeur)'

    def collect
      fetch(latest(PRODUCTS, /\.csv\z/i, as: 'products.json'), 'qos.csv', again: true)
      COMMUNES.each { |file, slug| fetch(latest(slug, /\.csv\z/i, as: "#{file}.json"), file, again: true) }
      fetch(latest(REFERENCE, /\.csv\z/i, as: 'reference.json'), 'reference.csv', again: true)
      fetch(MOVEMENTS_URL, 'movements.csv')

      # The delimited zones weigh 270 MB and change every week: downloaded when the INAO dated them anew
      zones = data_gouv_resources(ZONES, as: 'zones.json').select { |found| found['title'].match?(/delim-parcellaire-aoc-shp\.zip\z/) }
                                                         .max_by { |found| found['title'] }
      raise "No delimitation of the AOC in #{ZONES}" if zones.nil?

      stamp = dir.join('zones.stamp')
      return if stamp.exist? && stamp.read == zones['title'] && !Dir.glob(dir.join('zones/*.shp').to_s).empty?

      unzip(fetch(zones.fetch('url'), 'zones.zip', again: true), dir.join('zones'))
      stamp.write(zones['title'])
    end

    def load
      load_csv(dir.join('qos.csv'), 'qos', col_sep: ';')
      load_csv(dir.join('reference.csv'), 'reference')

      listed = listed_communes
      raise "The lists of the INAO name #{listed.size} communes and areas only" if listed.size < 300_000

      load_csv(write_csv('listed.csv', %w[area_id insee_code sign], listed), 'listed')
      load_csv(write_csv('successors.csv', %w[former_code insee_code], successors), 'successors')

      shape = Pathname.glob(dir.join('zones/*.shp')).max
      raise "No shapefile in #{dir.join('zones')}: run the collect phase first" if shape.nil?

      load_shp(shape, table_name: 'zones', srid: 2154, charset: 'UTF-8')
    end

    def self.table_definitions(builder)
      builder.table :registered_quality_and_origin_signs, sql: <<-SQL
        CREATE TABLE registered_quality_and_origin_signs (
          id integer PRIMARY KEY NOT NULL,
          ida integer NOT NULL,
          geographic_area character varying,
          fr_sign character varying,
          eu_sign character varying,
          product_human_name JSONB,
          product_human_name_fra character varying,
          reference_number character varying
        );
        CREATE INDEX registered_quality_and_origin_signs_area ON registered_quality_and_origin_signs (ida);
      SQL

      # One line per geographical area: `ida` of the table of products
      builder.table(:registered_quality_and_origin_sign_areas, sql: <<~SQL)
        CREATE TABLE registered_quality_and_origin_sign_areas (
          id integer PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          sign character varying NOT NULL,
          fr_sign character varying,
          eu_sign character varying,
          family character varying NOT NULL,
          products_count integer NOT NULL,
          communes_count integer NOT NULL
        );
      SQL

      builder.table(:registered_quality_and_origin_sign_communes, sql: <<~SQL)
        CREATE TABLE registered_quality_and_origin_sign_communes (
          area_id integer NOT NULL,
          insee_code character varying NOT NULL,
          sign character varying NOT NULL,
          partial boolean NOT NULL,
          former_communes text[] NOT NULL DEFAULT '{}',
          PRIMARY KEY (area_id, insee_code)
        );
        CREATE INDEX registered_quality_and_origin_sign_communes_insee ON registered_quality_and_origin_sign_communes (insee_code);
      SQL

      # What is delimited, inside a commune, for a wine under AOC: one line per denomination and commune
      builder.table(:registered_quality_and_origin_sign_zones, sql: <<~SQL)
        CREATE TABLE registered_quality_and_origin_sign_zones (
          id integer PRIMARY KEY NOT NULL,
          appellation_id integer NOT NULL,
          appellation character varying NOT NULL,
          denomination_id integer,
          denomination character varying,
          complementary boolean NOT NULL,
          categories character varying,
          insee_code character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL
        );
        CREATE INDEX registered_quality_and_origin_sign_zones_insee ON registered_quality_and_origin_sign_zones (insee_code);
        CREATE INDEX registered_quality_and_origin_sign_zones_shape ON registered_quality_and_origin_sign_zones USING GIST (shape);
      SQL
    end

    def normalize
      query "UPDATE #{name}.qos SET produit = REPLACE(produit, '\\', '');"

      query <<-SQL
        INSERT INTO registered_quality_and_origin_signs (id, ida, geographic_area, fr_sign, eu_sign, product_human_name, product_human_name_fra, reference_number)
          SELECT id_produit::INTEGER, ida::INTEGER, aire_geographique, signe_fr, signe_ue, CONCAT('{"fra":"', produit, '"}')::JSONB, produit, reference
          FROM #{name}.qos
      SQL

      # Add VSIG
      VSIG.each do |(id, product)|
        query 'INSERT INTO registered_quality_and_origin_signs
        (id, ida, geographic_area, fr_sign, eu_sign, product_human_name, product_human_name_fra)
        VALUES ($1, $2, $3, $4, $5, $6, $7)',
              id, 1, '-------', 'Vin de France -', 'VSIG', { "fra": product }.to_json, product
      end

      normalize_communes
      normalize_areas
      normalize_zones
    end

    private

      # The address of the latest file of a dataset whose title matches
      def latest(slug, title, as:)
        found = data_gouv_resources(slug, as: as).select { |resource| resource['title'].to_s.match?(title) }
                                               .max_by { |resource| resource['last_modified'].to_s }
        raise "No file matching #{title.inspect} in the dataset #{slug}" if found.nil?

        found.fetch('url')
      end

      # Area, commune and sign of every line of the two lists, in Windows-1252 with semicolons
      def listed_communes
        COMMUNES.keys.flat_map do |file|
          rows = CSV.read(dir.join(file), col_sep: ';', headers: true, encoding: 'windows-1252:utf-8')
          missing = %w[CI IDA] - rows.headers
          raise "#{file} lacks the columns #{missing.join(', ')}" unless missing.empty?

          rows.map do |row|
            sign = row['Signe UE'].to_s.strip
            [row['IDA'], row['CI'], sign.empty? ? 'AOC' : sign[/\A[A-Z]+/]]
          end
        end.uniq { |area, code, _| [area, code] }
      end

      # Every commune a commune became, through the mergers and changes of code the INSEE recorded: a commune
      # that merged twice leads to both, `normalize` keeps the one that exists today.
      def successors
        became = Hash.new { |hash, code| hash[code] = [] }
        CSV.foreach(dir.join('movements.csv'), headers: true) do |row|
          next unless row['TYPECOM_AV'] == 'COM' && row['TYPECOM_AP'] == 'COM' && row['COM_AV'] != row['COM_AP']

          became[row['COM_AV']] |= [row['COM_AP']]
        end

        became.keys.flat_map do |former|
          reached = []
          pending = became[former].dup
          until pending.empty?
            code = pending.shift
            next if reached.include?(code) || code == former

            reached << code
            pending.concat(became.fetch(code, []))
          end
          reached.map { |code| [former, code] }
        end
      end

      # A commune of today carries the areas the lists give it, and those of the communes it absorbed: `partial`
      # says the area is known through former communes only, named in `former_communes`.
      def normalize_communes
        query <<~SQL
          INSERT INTO registered_quality_and_origin_sign_communes (area_id, insee_code, sign, partial, former_communes)
            WITH communes AS (SELECT DISTINCT code FROM registered_postal_codes),
                 placed AS (
                   SELECT listed.area_id::integer AS area_id, listed.insee_code, listed.sign, NULL::text AS former_code
                     FROM #{name}.listed
                     JOIN communes ON communes.code = listed.insee_code
                   UNION ALL
                   SELECT listed.area_id::integer, successors.insee_code, listed.sign, listed.insee_code
                     FROM #{name}.listed
                     JOIN #{name}.successors ON successors.former_code = listed.insee_code
                     JOIN communes ON communes.code = successors.insee_code
                    WHERE listed.insee_code NOT IN (SELECT code FROM communes)
                 )
            SELECT area_id, insee_code, min(sign), bool_and(former_code IS NOT NULL),
                   COALESCE(array_agg(DISTINCT former_code ORDER BY former_code) FILTER (WHERE former_code IS NOT NULL), '{}')
              FROM placed
             GROUP BY area_id, insee_code
             ORDER BY insee_code, area_id
        SQL
      end

      # The family of an area is the one most of its products belong to, wine winning a tie; an indication
      # of the kind IG is a spirit
      def normalize_areas
        families = FAMILIES.flat_map { |family, classes| classes.map { |label| "WHEN #{database_quote(label)} THEN '#{family}'" } }.join(' ')

        query <<~SQL
          INSERT INTO registered_quality_and_origin_sign_areas (id, name, sign, fr_sign, eu_sign, family, products_count, communes_count)
            SELECT products.ida, min(products.geographic_area),
                   COALESCE(min(covered.sign), NULLIF(min(btrim(products.eu_sign)), ''), NULLIF(min(btrim(products.fr_sign)), ''), '?'),
                   NULLIF(min(btrim(products.fr_sign)), ''), NULLIF(min(btrim(products.eu_sign)), ''),
                   COALESCE((SELECT family
                               FROM (SELECT CASE reference.classe_ue #{families} ELSE '#{OTHER_FAMILY}' END AS family
                                       FROM registered_quality_and_origin_signs AS product
                                       JOIN #{name}.reference ON reference.idproduit::integer = product.id
                                      WHERE product.ida = products.ida) AS classed
                              GROUP BY family
                              ORDER BY count(*) DESC, family = 'wine' DESC, family
                              LIMIT 1),
                            CASE WHEN min(covered.sign) = 'IG' THEN 'spirits'
                                 WHEN bool_or(products.product_human_name_fra ~* '\\m#{WINE_WORDS}\\M') THEN 'wine'
                                 ELSE '#{OTHER_FAMILY}' END),
                   count(*), COALESCE(min(covered.communes), 0)
              FROM registered_quality_and_origin_signs AS products
              LEFT JOIN (SELECT area_id, min(sign) AS sign, count(*) AS communes
                           FROM registered_quality_and_origin_sign_communes GROUP BY area_id) AS covered
                     ON covered.area_id = products.ida
             WHERE products.geographic_area <> '-------'
             GROUP BY products.ida
        SQL
      end

      def normalize_zones
        query <<~SQL
          INSERT INTO registered_quality_and_origin_sign_zones
            (id, appellation_id, appellation, denomination_id, denomination, complementary, categories, insee_code, shape)
            SELECT gid, id_app::integer, app, id_denom::integer, denom, type_denom <> 'appellation', categorie, insee,
                   postgis.ST_Multi(postgis.ST_CollectionExtract(postgis.ST_MakeValid(postgis.ST_Transform(geom, 4326)), 3))
              FROM #{name}.zones
             WHERE id_app IS NOT NULL AND NOT postgis.ST_IsEmpty(geom)
        SQL
      end

      def database_quote(text)
        "'#{text.gsub("'", "''")}'"
      end
  end
end
