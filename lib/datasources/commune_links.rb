module Datasources
  # Fiche par commune : ce que les autres jeux de données savent d'elle, réuni
  # une fois pour toutes au moment du build. L'API n'a plus qu'à lire une ligne.
  class CommuneLinks < Base
    description 'Fiches par commune : cadastre, entreprises agricoles, population MSA, station météo la plus proche'
    credits name: 'Fiches communales Lexicon',
            url: 'https://lexicon.osfarm.org',
            provider: 'OSFarm',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-04'
    depends_on :postal_codes, :administrative_areas, :cadastre, :enterprises, :msa_populations, :weather
    pivot :commune, table: :link_communes, column: :insee_code, minimum: 1.0
    pivot :department, table: :link_communes, column: :department_code
    pivot :weather_station, table: :link_communes, column: :weather_station

    def self.table_definitions(builder)
      builder.table(:link_communes, sql: <<~SQL)
        CREATE TABLE link_communes (
          insee_code character varying PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          postal_codes text[] NOT NULL DEFAULT '{}',
          department_code character varying,
          region_code character varying,
          cadastral_parcels_count integer NOT NULL DEFAULT 0,
          cadastral_area_m2 bigint NOT NULL DEFAULT 0,
          agricultural_owner_parcels_count integer NOT NULL DEFAULT 0,
          enterprises_count integer NOT NULL DEFAULT 0,
          msa_year integer,
          msa_farm_chiefs integer,
          weather_station character varying
        );

        CREATE INDEX link_communes_department_code ON link_communes(department_code);
      SQL
    end

    def normalize
      check_prerequisites

      query <<~SQL
        INSERT INTO link_communes (
          insee_code, name, postal_codes, department_code, region_code, cadastral_parcels_count, cadastral_area_m2,
          agricultural_owner_parcels_count, enterprises_count, msa_year, msa_farm_chiefs, weather_station
        )
        SELECT c.insee_code, c.name, c.postal_codes, d.code, d.parent_code,
               COALESCE(p.parcels, 0), COALESCE(p.area, 0), COALESCE(p.agricultural_owner_parcels, 0),
               COALESCE(e.enterprises, 0), m.year, m.farm_chiefs, s.reference_name
          FROM (
            SELECT code AS insee_code,
                   min(city_name) AS name,
                   array_agg(DISTINCT postal_code ORDER BY postal_code) AS postal_codes,
                   (array_agg(city_centroid))[1] AS centroid
              FROM registered_postal_codes
             GROUP BY code
          ) c
          -- Les départements d'outre-mer ont un code à trois chiffres
          LEFT JOIN registered_administrative_areas d
            ON d.kind = 'department'
           AND d.code = CASE WHEN c.insee_code LIKE '97%' THEN left(c.insee_code, 3) ELSE left(c.insee_code, 2) END
          LEFT JOIN (
            SELECT town_insee_code,
                   count(*) AS parcels,
                   sum(net_surface_area::bigint) AS area,
                   count(*) FILTER (WHERE has_agricultural_pm_owner) AS agricultural_owner_parcels
              FROM registered_cadastral_parcels
             GROUP BY town_insee_code
          ) p ON p.town_insee_code = c.insee_code
          LEFT JOIN (
            SELECT insee_code, count(*) AS enterprises FROM registered_enterprises GROUP BY insee_code
          ) e ON e.insee_code = c.insee_code
          LEFT JOIN (
            SELECT DISTINCT ON (insee_code) insee_code, year, farm_chiefs
              FROM registered_msa_populations
             ORDER BY insee_code, year DESC
          ) m ON m.insee_code = c.insee_code
          LEFT JOIN LATERAL (
            SELECT reference_name
              FROM registered_weather_stations
             WHERE c.centroid IS NOT NULL
             ORDER BY centroid <-> c.centroid
             LIMIT 1
          ) s ON true
      SQL

      total = query('SELECT count(*) FROM link_communes').getvalue(0, 0)
      logger.debug "#{name} : #{total} communes"
    end

    private

      def check_prerequisites
        %w[registered_postal_codes registered_administrative_areas registered_cadastral_parcels registered_enterprises
           registered_weather_stations].each do |table|
          next if query("SELECT 1 FROM #{table} LIMIT 1").any?

          raise "#{name} : #{table} est vide. Lancer d'abord les datasources dont dépendent les fiches."
        end
      end
  end
end
