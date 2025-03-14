module Datasources
  class ProtectedNaturalZones < Base
    LAST_UPDATED = "2025-01-16"
    description 'protected natural zone'
    credits name: 'Zones Natura 2000', url: "https://www.data.gouv.fr/fr/datasets/inpn-donnees-du-programme-natura-2000/", provider: "MNHN", licence: "Aucune", licence_url: "", updated_at: LAST_UPDATED

    def collect
      puts "Download Zones..."
      downloader.curl 'https://www.data.gouv.fr/fr/datasets/r/939f828d-b070-44b4-843c-a465b6b2e440', out: 'sic.zip'
      downloader.curl 'https://www.data.gouv.fr/fr/datasets/r/879e29aa-75a4-42ff-88e7-d2e9b3f9e715', out: 'zps.zip'
      puts "Extracting Zones..."
      execute("7z x #{dir}/sic.zip -oraw/protected_natural_zones -aoa")
      execute("7z x #{dir}/zps.zip -oraw/protected_natural_zones -aoa")
    end

    def load
      # Load Natura 2000 zones (SIC : Directive Habitats | ZPS : Directive Oiseaux)
      load_shp(dir.join("sic.shp"), table_name: 'sic_zones', srid: 2154)
      load_shp(dir.join("zps.shp"), table_name: 'zps_zones', srid: 2154)
    end

    def self.table_definitions(builder)
      builder.table :registered_natural_zones, sql: <<-SQL
        CREATE TABLE registered_natural_zones (
          id character varying NOT NULL,
          name character varying,
          nature character varying NOT NULL,            
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );

        CREATE INDEX registered_natural_zones_id ON registered_natural_zones (id);
        CREATE INDEX registered_natural_zones_nature ON registered_natural_zones (nature);
        CREATE INDEX registered_natural_zones_shape ON registered_natural_zones USING GIST (shape);
        CREATE INDEX registered_natural_zones_centroid ON registered_natural_zones USING GIST (centroid);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_natural_zones (id, name, nature, shape)
          SELECT
            sitecode,
            sitename,
            'sic',
            postgis.ST_Transform(geom, 4326)
          FROM protected_natural_zones.sic_zones;
      SQL
      query <<-SQL
        INSERT INTO registered_natural_zones (id, name, nature, shape)
          SELECT
            sitecode,
            sitename,
            'zps',
            postgis.ST_Transform(geom, 4326)
          FROM protected_natural_zones.zps_zones;
      SQL
      logger.debug "Compute centroid on Natural zones..."
      query("UPDATE lexicon.registered_natural_zones SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")
    end
  end
end
