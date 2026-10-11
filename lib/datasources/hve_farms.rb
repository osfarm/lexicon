# frozen_string_literal: true

require 'csv'

module Datasources
  # Farms certified « Haute Valeur Environnementale », the third and highest level of the environmental
  # certification of farms, as the ministry of agriculture lists them twice a year. Only the farms that agreed
  # to be listed are there: what is counted in a commune is a minimum.
  class HveFarms < Base
    description 'Annuaire des exploitations certifiées Haute Valeur Environnementale (HVE) : nom, SIRET, commune, activités, vente directe et date de certification'
    credits name: 'Annuaire des exploitations certifiées « Haute Valeur Environnementale »',
            url: 'https://www.data.gouv.fr/datasets/annuaire-des-exploitations-certifiees-haute-valeur-environnementale',
            provider: "Ministère de l'Agriculture",
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-09-03'

    schema_revision 1
    depends_on :postal_codes, :enterprises
    # Many of these farms bear the name of a person: reserved to API key holders
    scope :members
    # The directory is as recent as the last certification it lists
    source_date 'SELECT max(certified_on) FROM registered_hve_farms'
    pivot :commune, table: :registered_hve_farms, column: :insee_code, minimum: 0.95
    pivot :siret, table: :registered_hve_farms, column: :siret, minimum: 0.95
    pivot :siren, table: :registered_hve_farms, column: :siren, minimum: 0.95

    DATASET = 'annuaire-des-exploitations-certifiees-haute-valeur-environnementale'

    # A column of the source for each column kept
    COLUMNS = {
      'Nom ou Raison sociale' => 'name',
      'Siret' => 'siret',
      'Cvi' => 'cvi',
      'Adresse' => 'address',
      'Code Postal' => 'postal_code',
      'Région' => 'region',
      'Département' => 'department',
      'Commune' => 'city',
      'Site Internet' => 'website',
      'Activité animale' => 'animal_activity',
      'Activité végétale' => 'plant_activity',
      'Vente directe' => 'direct_sales',
      'Date début certification' => 'certified_on'
    }.freeze

    # The latest directory in CSV. The earlier ones are kept: a past collect can be replayed.
    def collect
      latest = data_gouv_resources(DATASET).select { |resource| resource['format'] == 'csv' }
                                           .max_by { |resource| resource['last_modified'].to_s }
      raise "No CSV file in the dataset #{DATASET}" if latest.nil?

      fetch(latest.fetch('url'), File.basename(latest['url']))
    end

    # Reads the directory, checks it, and writes it with one column per column kept
    def load
      file = Pathname.glob(dir.join('annuaire-*.csv')).max_by(&:mtime)
      raise "No file annuaire-*.csv in #{dir}: run the collect phase first" if file.nil?

      farms = CSV.read(file, col_sep: ';', headers: true, encoding: 'bom|utf-8')
      missing = COLUMNS.keys - farms.headers
      raise "#{file.basename} lacks the columns #{missing.join(', ')}" unless missing.empty?
      raise "#{file.basename} lists #{farms.size} farms only" if farms.size < 5_000

      rows = farms.each_with_index.map { |farm, index| [index + 1] + COLUMNS.keys.map { |column| value_of(column, farm[column]) } }
      load_csv(write_csv('farms.csv', ['id'] + COLUMNS.values, rows), 'farms')
    end

    def self.table_definitions(builder)
      builder.table(:registered_hve_farms, sql: <<~SQL)
        CREATE TABLE registered_hve_farms (
          id integer PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          siret character varying,
          siren character varying,
          siret_checked boolean NOT NULL,
          cvi character varying,
          address character varying,
          postal_code character varying,
          city character varying,
          insee_code character varying,
          located_by character varying,
          department character varying,
          region character varying,
          website character varying,
          animal_activity character varying,
          plant_activity character varying,
          direct_sales boolean,
          certified_on date
        );
        CREATE INDEX registered_hve_farms_insee ON registered_hve_farms (insee_code);
        CREATE INDEX registered_hve_farms_siret ON registered_hve_farms (siret);
        CREATE INDEX registered_hve_farms_siren ON registered_hve_farms (siren);
      SQL
    end

    # The commune of a farm is the one SIRENE gives its establishment; failing that, the one of its postal
    # code that bears the name the directory writes. `located_by` says which.
    def normalize
      named = Lexicon::Contribution::TabularDatasource.commune_sql(postal_code: 'postal_code', name: 'city')

      query <<~SQL
        INSERT INTO registered_hve_farms
          (id, name, siret, siren, siret_checked, cvi, address, postal_code, city, insee_code, located_by, department,
           region, website, animal_activity, plant_activity, direct_sales, certified_on)
          WITH communes AS MATERIALIZED (SELECT DISTINCT code FROM registered_postal_codes),
               known AS (
                 SELECT farms.id, min(establishment.insee_code) AS insee_code
                   FROM #{name}.farms
                   JOIN registered_enterprises AS establishment ON establishment.establishment_number = farms.siret
                   JOIN communes ON communes.code = establishment.insee_code
                  GROUP BY farms.id
               ),
               named AS (SELECT source.id, #{named} AS insee_code FROM #{name}.farms AS source)
          SELECT farms.id::integer, farms.name, farms.siret, left(farms.siret, 9),
                 EXISTS (SELECT 1 FROM registered_enterprises AS establishment WHERE establishment.establishment_number = farms.siret),
                 farms.cvi, farms.address, farms.postal_code, farms.city,
                 COALESCE(known.insee_code, named.insee_code),
                 CASE WHEN known.insee_code IS NOT NULL THEN 'sirene' WHEN named.insee_code IS NOT NULL THEN 'postal_code' END,
                 farms.department, farms.region, farms.website, farms.animal_activity, farms.plant_activity,
                 CASE lower(farms.direct_sales) WHEN 'oui' THEN true WHEN 'non' THEN false END,
                 farms.certified_on::date
            FROM #{name}.farms
            LEFT JOIN known USING (id)
            LEFT JOIN named USING (id)
           ORDER BY farms.id::integer
      SQL
    end

    private

      # A SIRET that is not fourteen digits is kept as written; a postal code gets back the zero a sheet took
      # from it; a date is written day/month/year.
      def value_of(column, text)
        text = text.to_s.strip
        return nil if text.empty?

        case column
        when 'Code Postal' then text.match?(/\A\d{4}\z/) ? "0#{text}" : text
        when 'Date début certification' then Date.strptime(text, '%d/%m/%Y').iso8601
        else text
        end
      end
  end
end
