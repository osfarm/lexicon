module Datasources
  class Cadastre < Base
    description 'Official cadastre'
    credits name: 'Parcelles du cadastre', url: "https://cadastre.data.gouv.fr/", provider: "Etalab", licence: "Open Licence 2.0", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf", updated_at: "2025-01-23"

    python :collect, :normalize

    def self.table_definitions(builder)
      builder.table :registered_cadastral_parcels, sql: <<-SQL
        CREATE TABLE registered_cadastral_parcels(
          id character varying PRIMARY KEY NOT NULL,
          town_insee_code character varying,
          section_prefix character varying,
          section character varying,
          work_number character varying,
          net_surface_area integer,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_cadastral_parcels_id ON registered_cadastral_parcels(id);
        CREATE INDEX registered_cadastral_parcels_town_insee_code ON registered_cadastral_parcels(town_insee_code);
        CREATE INDEX registered_cadastral_parcels_section_prefix ON registered_cadastral_parcels(section_prefix);
        CREATE INDEX registered_cadastral_parcels_section ON registered_cadastral_parcels(section);
        CREATE INDEX registered_cadastral_parcels_work_number ON registered_cadastral_parcels(work_number);
        CREATE INDEX registered_cadastral_parcels_shape ON registered_cadastral_parcels USING GIST (shape);
        CREATE INDEX registered_cadastral_parcels_centroid ON registered_cadastral_parcels USING GIST (centroid);
      SQL
    end

  end
end
