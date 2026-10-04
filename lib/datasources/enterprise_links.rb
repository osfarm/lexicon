module Datasources
  # Fiche par entreprise (personnes morales uniquement) : ce qu'elle possède au
  # cadastre, ses établissements agricoles et ses aides PAC.
  #
  # La base est le fichier des parcelles des personnes morales : aucune personne
  # physique n'y figure, et aucun nom de bénéficiaire individuel n'est repris.
  class EnterpriseLinks < Base
    description 'Fiches par entreprise (personnes morales) : parcelles possédées, établissements agricoles, aides PAC'
    credits name: 'Fiches entreprises Lexicon',
            url: 'https://lexicon.osfarm.org',
            provider: 'OSFarm',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf',
            updated_at: '2026-10-04'
    depends_on :cadastre_owners, :enterprises, :cap_beneficiaries
    # Elles relient des propriétaires à leurs parcelles : réservées aux adhérents
    scope :members
    pivot :siren, table: :link_enterprises, column: :siren

    def self.table_definitions(builder)
      builder.table(:link_enterprises, sql: <<~SQL)
        CREATE TABLE link_enterprises (
          siren character varying PRIMARY KEY NOT NULL,
          name character varying,
          legal_form character varying,
          owned_parcels_count integer NOT NULL DEFAULT 0,
          owned_area_m2 bigint NOT NULL DEFAULT 0,
          owned_communes_count integer NOT NULL DEFAULT 0,
          establishments_count integer NOT NULL DEFAULT 0,
          main_activity_code character varying,
          cap_year integer,
          cap_total numeric(14,2)
        );
      SQL
    end

    def normalize
      %w[registered_cadastral_owners registered_cadastral_parcel_owners].each do |table|
        next if query("SELECT 1 FROM #{table} LIMIT 1").any?

        raise "#{name} : #{table} est vide. Lancer d'abord : ./lexicon run cadastre_owners"
      end

      query <<~SQL
        INSERT INTO link_enterprises (
          siren, name, legal_form, owned_parcels_count, owned_area_m2, owned_communes_count,
          establishments_count, main_activity_code, cap_year, cap_total
        )
        SELECT o.siren, o.name, o.legal_form,
               COALESCE(p.parcels, 0), COALESCE(p.area, 0), COALESCE(p.communes, 0),
               COALESCE(e.establishments, 0), e.main_activity_code, c.year, c.total
          FROM (
            SELECT siren, min(denomination) AS name, min(legal_form_short) AS legal_form
              FROM registered_cadastral_owners
             WHERE siren IS NOT NULL AND siren <> ''
             GROUP BY siren
          ) o
          LEFT JOIN (
            SELECT siren,
                   count(DISTINCT cadastral_parcel_id) AS parcels,
                   sum(suf_surface_area::bigint) AS area,
                   count(DISTINCT town_insee_code) AS communes
              FROM registered_cadastral_parcel_owners
             WHERE siren IS NOT NULL
             GROUP BY siren
          ) p ON p.siren = o.siren
          LEFT JOIN (
            SELECT siren, count(*) AS establishments, min(french_main_activity_code) AS main_activity_code
              FROM registered_enterprises
             GROUP BY siren
          ) e ON e.siren = o.siren
          LEFT JOIN (
            SELECT DISTINCT ON (siren) siren, year,
                   COALESCE(feaga_total, 0) + COALESCE(feader_total, 0) AS total
              FROM registered_cap_beneficiaries
             WHERE siren IS NOT NULL
             ORDER BY siren, year DESC
          ) c ON c.siren = o.siren
      SQL

      total = query('SELECT count(*) FROM link_enterprises').getvalue(0, 0)
      logger.debug "#{name} : #{total} entreprises"
    end
  end
end
