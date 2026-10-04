module Datasources
  # RPG : les parcelles déclarées à la PAC, par campagne. `registered_graphic_parcels` porte la dernière
  # campagne, `registered_graphic_parcels_history` les précédentes, pour connaître la culture d'un lieu
  # dans le passé.
  class GraphicParcels < Base
    # Une campagne par millésime : le nom de la couche et de sa colonne géométrique ont changé avec les
    # versions du RPG. Les identifiants de parcelles ne sont pas stables d'une campagne à l'autre.
    CAMPAIGNS = {
      2022 => { layer: 'parcelles_graphiques', geometry: 'the_geom' }, # RPG 2.0
      2023 => { layer: 'PARCELLES_GRAPHIQUES', geometry: 'geom' },     # RPG 2.2
      2024 => { layer: 'RPG_Parcelles', geometry: 'geom' },            # RPG 3.0
      2025 => { layer: 'RPG_Parcelles', geometry: 'geom' }             # RPG 4.0
    }.freeze
    CURRENT_CAMPAIGN = CAMPAIGNS.keys.max
    PAST_CAMPAIGNS = (CAMPAIGNS.keys - [CURRENT_CAMPAIGN]).freeze
    LAST_UPDATED = "#{CURRENT_CAMPAIGN}-01-01".freeze

    description "RPG — Parcelles agricoles déclarées à la PAC (France métropolitaine), campagnes #{CAMPAIGNS.keys.min} à #{CURRENT_CAMPAIGN}"
    credits name: 'RPG — Registre Parcellaire Graphique',
            url: "https://geoservices.ign.fr/rpg",
            provider: "IGN / ASP / MASA",
            licence: "Licence Ouverte 2.0",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf",
            updated_at: LAST_UPDATED
    schema_revision 2
    pivot :cap_crop_code, table: :registered_graphic_parcels, column: :cap_crop_code
    pivot :cap_crop_code, table: :registered_graphic_parcels_history, column: :cap_crop_code

    # The RPG GeoPackages are provided manually: drop the parcel layer of each campaign
    # (France métropolitaine, Lambert-93 / EPSG:2154) into `raw/graphic_parcels/`,
    # named `RPG_Parcelles_<campaign>.gpkg`.
    SCHEMA = 'graphic_parcels'.freeze
    # Raw table of the time when a single campaign was loaded
    FORMER_RAW_TABLE = 'parcelles_graphiques'.freeze

    def self.gpkg_file(campaign)
      "RPG_Parcelles_#{campaign}.gpkg"
    end

    def self.raw_table(campaign)
      "parcels_#{campaign}"
    end

    def collect
      missing = CAMPAIGNS.keys.reject { |campaign| File.exist?(dir.join(self.class.gpkg_file(campaign))) }
      unless missing.empty?
        files = missing.map { |campaign| self.class.gpkg_file(campaign) }.join(', ')
        raise "Missing #{files} in #{dir}. Drop the parcel GeoPackage (Lambert-93) of each campaign there before running."
      end

      logger.debug "Found the GeoPackages of campaigns #{CAMPAIGNS.keys.join(', ')}"
    end

    def load
      logger.debug "Loading communes shapefile..."
      FileUtils.cp_r 'data/graphic_parcels/.', dir
      load_shp(dir.join("COMMUNE_CARTO.shp"), table_name: 'cities')

      query <<-SQL
        ALTER TABLE cities
         ALTER COLUMN geom TYPE postgis.geometry(MultiPolygon, 4326)
          USING postgis.ST_Transform(geom, 4326);
      SQL

      database.ensure_schema(SCHEMA)
      query "DROP TABLE IF EXISTS #{SCHEMA}.#{FORMER_RAW_TABLE}"
      conn = pg_connection_string

      CAMPAIGNS.each do |campaign, source|
        gpkg = dir.join(self.class.gpkg_file(campaign))
        table = self.class.raw_table(campaign)

        # Only what normalize reads is loaded, and without spatial index: nothing searches these tables
        logger.debug "Loading campaign #{campaign} from #{gpkg.basename} into #{SCHEMA}.#{table}..."
        execute <<~BASH
          ogr2ogr \
            -f PostgreSQL "#{conn}" \
            -overwrite \
            -lco SCHEMA=#{SCHEMA} \
            -lco GEOMETRY_NAME=geom \
            -lco FID=ogc_fid \
            -lco SPATIAL_INDEX=NONE \
            -nlt MULTIPOLYGON \
            -t_srs EPSG:4326 \
            -nln #{table} \
            -sql "SELECT id_parcel, code_cultu, #{source[:geometry]} FROM #{source[:layer]}" \
            "#{gpkg}"
        BASH
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_graphic_parcels, sql: <<-SQL
        CREATE TABLE registered_graphic_parcels (
          id character varying NOT NULL,
          campaign integer NOT NULL,
          cap_crop_code character varying,
          city_name character varying,
          shape postgis.geometry(Polygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_graphic_parcels_id ON registered_graphic_parcels(id);
        CREATE INDEX registered_graphic_parcels_city_name ON registered_graphic_parcels(city_name);
        CREATE INDEX registered_graphic_parcels_shape ON registered_graphic_parcels USING GIST (shape);
        CREATE INDEX registered_graphic_parcels_centroid ON registered_graphic_parcels USING GIST (centroid);
      SQL

      builder.table :registered_graphic_parcels_history, sql: <<-SQL
        CREATE TABLE registered_graphic_parcels_history (
          campaign integer NOT NULL,
          id character varying NOT NULL,
          cap_crop_code character varying,
          shape postgis.geometry(Polygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_graphic_parcels_history_campaign_id ON registered_graphic_parcels_history(campaign, id);
        CREATE INDEX registered_graphic_parcels_history_shape ON registered_graphic_parcels_history USING GIST (shape);
      SQL
    end

    def normalize
      logger.debug "Insert the parcels of campaign #{CURRENT_CAMPAIGN} into registered_graphic_parcels..."
      query <<~SQL
        INSERT INTO registered_graphic_parcels (id, campaign, cap_crop_code, shape, centroid)
        #{parcels_of(CURRENT_CAMPAIGN, 'id_parcel, campaign, code_cultu, shape, centroid')}
      SQL

      logger.debug "Resolve city_name via spatial join on communes..."
      query <<~SQL
        UPDATE registered_graphic_parcels p
           SET city_name = c.nom_com
          FROM #{SCHEMA}.cities c
         WHERE postgis.ST_Intersects(p.centroid, c.geom);
      SQL

      PAST_CAMPAIGNS.each do |campaign|
        logger.debug "Insert the parcels of campaign #{campaign} into registered_graphic_parcels_history..."
        query <<~SQL
          INSERT INTO registered_graphic_parcels_history (campaign, id, cap_crop_code, shape, centroid)
          #{parcels_of(campaign, 'campaign, id_parcel, code_cultu, shape, centroid')}
        SQL
      end
    end

    private

      # The parcels of a campaign, one row per polygon: a parcel made of several pieces gives as many rows.
      def parcels_of(campaign, columns)
        <<~SQL
          SELECT #{columns}
            FROM (
              SELECT id_parcel, #{campaign} AS campaign, code_cultu, piece.geom AS shape, postgis.ST_Centroid(piece.geom) AS centroid
                FROM #{SCHEMA}.#{self.class.raw_table(campaign)},
                     LATERAL postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(geom), 0.0)) AS piece
            ) AS parcels
        SQL
      end

      def pg_connection_string
        host = ENV.fetch('POSTGRES_HOST', 'localhost')
        port = ENV.fetch('POSTGRES_PORT', '5432')
        user = ENV.fetch('POSTGRES_USER', 'lexicon')
        password = ENV.fetch('POSTGRES_PASSWORD', '')
        name = ENV['POSTGRES_NAME'] || ENV.fetch('POSTGRES_DB', 'lexicon')

        parts = ["host=#{host}", "port=#{port}", "user=#{user}", "dbname=#{name}"]
        parts << "password=#{password}" unless password.empty?
        "PG:#{parts.join(' ')}"
      end
  end
end
