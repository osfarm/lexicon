module Datasources
  class ProtectedWaterZones < Base
    LAST_UPDATED = "2025-01-27"
    description 'protected water zone from SANDRE'
    credits name: 'Zones de captages protégées', url: "https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#bd-topo", provider: "IGN", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: LAST_UPDATED

    BASE_URL = "https://services.sandre.eaufrance.fr/geo/zgr?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&typename=AAC_FXX&SRSNAME=EPSG:4326&OUTPUTFORMAT=SHAPEZIP"

    def collect
      if downloader.curl BASE_URL, out: 'acc.7z'
        puts "Extracting RPG..."
        execute("7z x #{dir}/acc.7z -oraw/protected_water_zones/archive -aoa")
      end
    end

    def load
      # Load France cities
      load_shp(dir.join("archive/AAC_FXX.shp"), table_name: 'aac_zones', srid: 4326)
    end

    def self.table_definitions(builder)
      builder.table :registered_protected_water_zones, sql: <<-SQL
        CREATE TABLE registered_protected_water_zones (
          id character varying NOT NULL,
          administrative_zone character varying,
          creator_name character varying,
          name character varying,
          updated_on date,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL
        );

        CREATE INDEX registered_protected_water_zones_id ON registered_protected_water_zones (id);
        CREATE INDEX registered_protected_water_zones_shape ON registered_protected_water_zones USING GIST (shape);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_protected_water_zones (id, name, updated_on, creator_name, administrative_zone, shape)
          SELECT
            gid, --id
            nomdeaac_1, --name
            to_date(datemajaac, 'YYYY-MM-DD'), --updated_on
            auteuraac, --creator_name
            nomcircadm, --administrative_zone
            geom
          FROM protected_water_zones.aac_zones;
      SQL
    end
  end
end
