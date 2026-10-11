# frozen_string_literal: true

require 'csv'
require 'json'

module Datasources
  # Territorial food projects (projets alimentaires territoriaux, PAT): what a territory undertakes to bring
  # food production and consumption closer, recognised by the ministry of agriculture. The observatory
  # France PAT publishes one sheet per project, with the communes it covers and figures about its farming.
  class Pat < Base
    description "Projets alimentaires territoriaux (PAT) : porteur, niveau de labellisation, axes, communes couvertes et chiffres agricoles du territoire, d'après l'observatoire France PAT"
    credits name: 'PAT - projets alimentaires territoriaux - description',
            url: 'https://www.data.gouv.fr/datasets/pat-projets-alimentaires-territoriaux-description',
            provider: 'France PAT',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-02'

    schema_revision 2
    # The source is as recent as the last sheet its observatory validated
    source_date 'SELECT max(validated_on) FROM registered_territorial_food_projects'
    pivot :commune, table: :registered_territorial_food_project_communes, column: :insee_code

    DATASET_URL = 'https://www.data.gouv.fr/api/1/datasets/pat-projets-alimentaires-territoriaux-description/'
    # The files of the dataset: one per publication, each in UTF-8 and in Windows-1252
    FILE = /\Apats-(\d{8})\.csv\z/.freeze

    # The themes a project works on, as the sheet words them, shortened to a key
    THEMES = {
      'Économie alimentaire dont structuration des filières' => 'food_economy',
      'Tourisme, mise en valeur du patrimoine alimentaire et gastronomie' => 'culture_and_gastronomy',
      'Éducation alimentaire' => 'food_education',
      'Nutrition et santé' => 'nutrition_and_health',
      'Justice sociale dont lutte contre la précarité alimentaire' => 'social_justice',
      'Environnement dont lutte contre le gaspillage alimentaire' => 'environment',
      'Accompagnement de la restauration collective' => 'collective_catering',
      'Urbanisme et Aménagement du territoire' => 'town_planning',
      'Gouvernance alimentaire du territoire (Hors instance de décision du PAT)' => 'governance',
      'Autres' => 'other'
    }.freeze

    # Holders whose member communes can be told: the intercommunalities
    INTERCOMMUNAL = ['Intercommunalité', 'Communauté de communes'].freeze
    # What a name of intercommunality starts with or carries, and says nothing of which one it is
    EPCI_WORDS = /\b(communaute d agglomeration|communaute de communes|communaute urbaine|metropole|agglomeration|agglo|intercommunale?|cc|ca|cu|cdc|cda)\b/.freeze
    SMALL_WORDS = /\b(de|du|des|la|le|les|l|d|et|en)\b/.freeze

    # A column of the source for each column kept, and how its value is read
    COLUMNS = {
      'id' => %w[id integer],
      'nom_administratif' => %w[name text],
      'nom_usuel' => %w[usual_name text],
      'lien_vers_la_fiche_pat' => %w[sheet_url text],
      'lien_vers_le_site_du_pat' => %w[website text],
      'regions' => %w[regions text],
      'departement' => %w[departments text],
      'porteur_point_dentree_du_pat' => %w[holder text],
      'porteur_point_dentree_du_pat_type' => %w[holder_kind text],
      'niveaux_de_labelisation' => %w[label text],
      'annee_dobtention_de_la_derniere_labellisation' => %w[labelled_in integer],
      'date_de_validation_de_la_fiche' => %w[validated_on date],
      'nombre_dhabitants_permanents_du_territoire' => %w[inhabitants integer],
      'surface_des_communes_du_territoire_en_km2' => %w[area_km2 decimal],
      'nombre_dexploitations_agricoles' => %w[farms_count integer],
      'nombre_dexploitations_agricoles_certifiee_bio' => %w[organic_farms_count integer],
      'sau_en_hectares' => %w[farmland_ha decimal],
      'sau_en_hectares_en_bio' => %w[organic_farmland_ha decimal],
      'pourcentage_de_la_sau' => %w[farmland_share decimal],
      'pourcentage_de_la_sau_en_bio' => %w[organic_farmland_share decimal],
      'pourcentage_de_la_surface_des_prairies_permanentes' => %w[permanent_grassland_share decimal],
      'pourcentage_de_la_surface_des_cultures_de_legumineuses' => %w[legumes_share decimal],
      'metres_de_haie_par_hectare_de_sau' => %w[hedge_metres_per_ha decimal],
      'm3_deau_utilise_pour_lirragation' => %w[irrigation_m3 decimal],
      'milligrammes_de_nitrates_par_litre_deau' => %w[nitrates_mg_per_l decimal],
      'microgrammes_de_produits_phytopharmaceutiques_par_litre_deau' => %w[pesticides_ug_per_l decimal]
    }.freeze

    # Downloads the latest file of the dataset. The earlier ones are kept: a past collect can be replayed.
    def collect
      description = dir.join('dataset.json')
      execute "curl -sSLf --retry 2 -o '#{description}' '#{DATASET_URL}'"
      latest = JSON.parse(description.read).fetch('resources')
                   .select { |resource| resource['title'].to_s.match?(FILE) }
                   .max_by { |resource| resource['title'] }
      raise "No file named pats-<date>.csv in #{DATASET_URL}" if latest.nil?

      file = dir.join(latest['title'])
      return if file.size?

      execute "curl -sSLf --retry 2 -o '#{file}' '#{latest.fetch('url')}'"
      raise "Nothing downloaded from #{latest['url']}" unless file.size?
    end

    # Reads the sheets, checks them, and writes what is kept as two tables: the projects and their communes.
    def load
      file = Pathname.glob(dir.join('pats-*.csv')).select { |found| found.basename.to_s.match?(FILE) }.max
      raise "No file pats-<date>.csv in #{dir}: run the collect phase first" if file.nil?

      sheets = CSV.read(file, col_sep: ';', headers: true, encoding: 'bom|utf-8')
      missing = (COLUMNS.keys + %w[communes_code_insee axes_thematiques]) - sheets.headers
      raise "#{file.basename} lacks the columns #{missing.join(', ')}" unless missing.empty?
      raise "#{file.basename} holds #{sheets.size} projects only" if sheets.size < 100

      members = members_of_intercommunalities
      write_csv('projects.csv', COLUMNS.values.map(&:first) + %w[themes co_holders], sheets.map { |sheet| project_of(sheet) })
      write_csv('communes.csv', %w[project_id insee_code through], sheets.flat_map { |sheet| communes_of(sheet, members) })
      load_csv(dir.join('projects.csv'), 'projects')
      load_csv(dir.join('communes.csv'), 'communes')
    end

    def self.table_definitions(builder)
      builder.table(:registered_territorial_food_projects, sql: <<~SQL)
        CREATE TABLE registered_territorial_food_projects (
          id integer PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          usual_name character varying,
          sheet_url character varying,
          website character varying,
          regions character varying,
          departments character varying,
          holder character varying,
          holder_kind character varying,
          label character varying,
          label_level integer,
          labelled_in integer,
          validated_on date,
          themes text[] NOT NULL DEFAULT '{}',
          co_holders text[] NOT NULL DEFAULT '{}',
          communes_count integer NOT NULL DEFAULT 0,
          inhabitants integer,
          area_km2 numeric(12,2),
          farms_count integer,
          organic_farms_count integer,
          farmland_ha numeric(12,2),
          organic_farmland_ha numeric(12,2),
          farmland_share numeric(6,2),
          organic_farmland_share numeric(6,2),
          permanent_grassland_share numeric(6,2),
          legumes_share numeric(6,2),
          hedge_metres_per_ha numeric(10,2),
          irrigation_m3 numeric(16,2),
          nitrates_mg_per_l numeric(10,3),
          pesticides_ug_per_l numeric(10,3)
        );
      SQL

      builder.table(:registered_territorial_food_project_communes, sql: <<~SQL)
        CREATE TABLE registered_territorial_food_project_communes (
          project_id integer NOT NULL,
          insee_code character varying NOT NULL,
          through character varying,
          PRIMARY KEY (project_id, insee_code)
        );
        CREATE INDEX registered_territorial_food_project_communes_insee ON registered_territorial_food_project_communes (insee_code);
      SQL
    end

    def normalize
      kept = COLUMNS.values.map do |column, type|
        case type
        when 'integer' then "NULLIF(#{column}, '')::numeric::integer"
        when 'decimal' then "NULLIF(#{column}, '')::numeric"
        when 'date' then "NULLIF(#{column}, '')::date"
        else "NULLIF(#{column}, '')"
        end
      end

      query <<~SQL
        INSERT INTO registered_territorial_food_projects (#{COLUMNS.values.map(&:first).join(', ')}, label_level, themes, co_holders, communes_count)
          SELECT #{kept.join(', ')},
                 substring(label FROM 'Niveau ([0-9])')::integer,
                 COALESCE(string_to_array(NULLIF(themes, ''), '|'), '{}'),
                 COALESCE(string_to_array(NULLIF(co_holders, ''), '|'), '{}'),
                 (SELECT count(*) FROM #{name}.communes WHERE communes.project_id = projects.id)
            FROM #{name}.projects
           ORDER BY id::integer
      SQL
      query <<~SQL
        INSERT INTO registered_territorial_food_project_communes (project_id, insee_code, through)
          SELECT project_id::integer, insee_code, NULLIF(through, '') FROM #{name}.communes
           ORDER BY 1, 2
      SQL
    end

    private

      def project_of(sheet)
        COLUMNS.map { |source, (_, type)| value_of(sheet[source], type) } +
          [themes_of(sheet['axes_thematiques']).join('|'), co_holders_of(sheet).map(&:first).join('|')]
      end

      # Those who lead the project beside its holder, each with its kind: columns co_porteur_2, co_porteur_3…
      def co_holders_of(sheet)
        sheet.headers.grep(/\Aco_porteur_\d+\z/).filter_map do |column|
          holder = sheet[column].to_s.strip
          [holder.tr('|', ' '), sheet[column.sub('co_porteur_', 'co_porteur_type_')].to_s.strip] unless holder.empty?
        end
      end

      # Numbers are written the French way (« 67 666 », « 995,96 ») or the English one, dates as day/month/year
      def value_of(text, type)
        text = text.to_s.strip
        return nil if text.empty?

        case type
        when 'integer', 'decimal'
          number = text.gsub(/[[:space:]]/, '').tr(',', '.')
          raise "Not a number: #{text.inspect}" unless number.match?(/\A-?\d+(\.\d+)?\z/)

          number
        when 'date' then Date.strptime(text, '%d/%m/%Y').iso8601
        else text
        end
      end

      # The themes are given in one text, separated by commas, and some hold a comma themselves
      def themes_of(text)
        THEMES.select { |label, _| text.to_s.include?(label) }.values
      end

      # The communes the sheet lists, then those of the intercommunalities that co-lead the project when the
      # sheet forgot them: `through` names the co-holder a commune comes by.
      def communes_of(sheet, members)
        listed = sheet['communes_code_insee'].to_s.split(',').map(&:strip).reject(&:empty?).uniq
        listed.each do |code|
          raise "Not an INSEE code in project #{sheet['id']}: #{code.inspect}" unless code.match?(/\A\d[\dAB]\d{3}\z/)
        end

        brought = co_holders_of(sheet).select { |_, kind| INTERCOMMUNAL.include?(kind) }.flat_map do |holder, _|
          (members[folded(holder)] || []).map { |code| [code, holder] }
        end
        added = brought.uniq(&:first).reject { |code, _| listed.include?(code) }
        logger.debug "Project #{sheet['id']}: #{added.size} communes come by its co-holders" unless added.empty?

        listed.map { |code| [sheet['id'], code, nil] } + added.map { |code, holder| [sheet['id'], code, holder] }
      end

      # The member communes of each intercommunality, by its folded name, read from the ADMIN EXPRESS file
      # `postal_codes` collects. A name two intercommunalities share is left out.
      def members_of_intercommunalities
        gpkg = Dir.glob(dir.join('../postal_codes/archive/**/*.gpkg').to_s).first
        if gpkg.nil?
          logger.warn 'No ADMIN EXPRESS file in raw/postal_codes: communes of co-holders are not added'
          return {}
        end

        file = dir.join('intercommunalities.csv')
        file.delete if file.exist?
        execute "ogr2ogr -f CSV '#{file}' '#{gpkg}' -sql \"SELECT nom_officiel, codes_insee_des_communes_membres FROM epci\""
        CSV.read(file, headers: true)
           .group_by { |row| folded(row['nom_officiel']) }
           .select { |_, rows| rows.size == 1 }
           .transform_values { |rows| rows.first['codes_insee_des_communes_membres'].to_s.split('/') }
      end

      # A name without capitals, accents, punctuation, nor the words every intercommunality carries:
      # « Communauté de communes Coeur de Saintonge » and « CC Cœur de Saintonge » are one
      def folded(name)
        name.to_s.gsub(/[œŒ]/, 'oe').unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
            .gsub(/[^a-z0-9]+/, ' ').gsub(EPCI_WORDS, ' ').gsub(SMALL_WORDS, ' ').split.join(' ')
      end

      def write_csv(file, headers, rows)
        CSV.open(dir.join(file), 'w') do |csv|
          csv << headers
          rows.each { |row| csv << row }
        end
      end
  end
end
