module Datasources
  class GraphicParcels < Base
    LAST_UPDATED = "2023-01-01"
    description 'Graphic parcels'
    credits name: 'RPG', url: "https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#rpg", provider: "IGN", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: LAST_UPDATED

    ZONES = {
      "LAMB93" => "2154",
      "RGAF09UTM20" => "5490",
      "UTM22RGFG95" => "2972",
      "RGR92UTM40S" => "2975",
      "RGM04UTM38S" => "4471"
    }.freeze

    REGIONS = {
      "LAMB93" => ["R11", "R24", "R27", "R28", "R32", "R44", "R52", 
                     "R53", "R75", "R76", "R84", "R93", "R94"], # France From 01 to 95 with no 20 and 2A 2B
      "RGAF09UTM20" => ["R01", "R02"], # Guadeloupe, Martinique
      "RGR92UTM40S" => ["R04"], # Réunion
      "UTM22RGFG95" => ["R03"], # Guyanne
      "RGM04UTM38S" => ["R06"] # Mayotte
    }.freeze
    
    def collect
      # if downloader.curl 'http://files.opendatarchives.fr/professionnels.ign.fr/rpg/2019/RPG_2-0_SQL_LAMB93_FR-2019_2019-01-15.7z', out: 'rpg.7z'
      #  puts "Extracting RPG..."
      #  execute("7z x #{dir}/rpg.7z -oraw/graphic_parcels/archive -aoa")
      # end
      # https://data.geopf.fr/telechargement/download/RPG/RPG_2-2__SHP_LAMB93_R75_2023-01-01/RPG_2-2__SHP_LAMB93_R75_2023-01-01.7z
      logger.debug "Download files...(download manualy before into folder raw/graphic_parcels if does not work)"
      files = []
      ZONES.each do |(zone, _v)|
        REGIONS[zone].each do |region|
          zip_name = "RPG_2-2__SHP_#{zone}_#{region}_#{LAST_UPDATED}.7z"
          logger.debug  "Download #{zip_name}"
          downloader.curl "https://data.geopf.fr/telechargement/download/RPG/RPG_2-2__SHP_#{zone}_#{region}_#{LAST_UPDATED}/RPG_2-2__SHP_#{zone}_#{region}_#{LAST_UPDATED}.7z", out: zip_name
          files << [zip_name, zone, region]
        end
      end

      logger.debug "Extracting files..."
      files.each do |(file, zone, region)|
        if zone && region
          logger.debug  "Extracting #{file}"
          archive = dir.join(file)
          if File.exist?(archive)
            execute("7z x #{archive} -o#{dir}/archive -aoa")
            # create directory
            logger.debug "Create final folder #{zone}/#{region}/..."
            FileUtils.mkdir_p(dir.join("#{zone}/#{region}/"))
            ['shp', 'shx', 'dbf', 'prj'].each do |ext|
              archive_glob = dir.join("archive/RPG_2-2__SHP_#{zone}_#{region}_#{LAST_UPDATED}/RPG/1_DONNEES_LIVRAISON_*/RPG_2-2__SHP_#{zone}_#{region}_*/PARCELLES_GRAPHIQUES.#{ext}")
              archive_path = Dir.glob(archive_glob).first
              target_path = Dir.glob(dir.join("#{zone}/#{region}/")).first
              logger.debug  "Copy PARCELLES_GRAPHIQUES.#{ext} into #{zone}/#{region}/"
              FileUtils.cp(archive_path, target_path)
            end
            # remove tmp folder
            logger.debug "Remove #{region} extract folder..."
            FileUtils.remove_dir(dir.join("archive/RPG_2-2__SHP_#{zone}_#{region}_#{LAST_UPDATED}"))
          else
            logger.error  "File not present : #{archive}"
          end
        else
          logger.debug  "Skipping #{file}"
        end
      end

    end

    def create_table_command(file, proj: nil, table:, search_path: [])
      "(echo 'SET search_path TO #{search_path.join(',')};' & shp2pgsql -p -s #{proj} #{file} #{table}) | psql #{Lexicon.build_db_url} -v ON_ERROR_STOP=1 -q"
    end

    def import_shp_command(file, proj: nil, table:, search_path: [])
      "(echo 'SET search_path TO #{search_path.join(',')};' & shp2pgsql -c -a -s #{proj} -D #{file} #{table}) | psql #{Lexicon.build_db_url} -v ON_ERROR_STOP=1 -q"
    end

    def load
      # Load France cities
      FileUtils.cp_r 'data/graphic_parcels/.', dir
      load_shp(dir.join("COMMUNE_CARTO.shp"), table_name: 'cities')

      query <<-SQL
        ALTER TABLE cities
         ALTER COLUMN geom TYPE postgis.geometry(MultiPolygon, 4326)
          USING postgis.ST_Transform(geom, 4326);
      SQL
      # Create temp table
      query <<-SQL
        CREATE TABLE ilotscom (ilot varchar primary key, commune varchar);
        CREATE INDEX ON ilotscom (ilot);
      SQL

      imports = []
      # Codes for metropolitan France and overseas and associate epsg
      logger.debug "Parse files to load in DB temp tables..."
      ZONES.each do |(zone_name, zone_proj)|
        REGIONS[zone_name].each do |region|
          archive_glob = dir.join("#{zone_name}/#{region}/PARCELLES_GRAPHIQUES.shp")
          next unless File.exist?(archive_glob)

          archive_path = Dir.glob(archive_glob).first
          logger.debug "Parse files #{archive_path}..."

          imports << {
            shp: dir.join(archive_path),
            zone_proj: zone_proj,
            dataset: 'parcelles_graphiques',
            table_name: "parcelles_graphiques_#{zone_name}_#{region}"
          }
        end
      end

      logger.debug "Load in DB temp tables..."
      # because psql client don't work up to 50 parallel connection, limit to 10
      threads = []

      imports.each do |import|
        load_shp(import[:shp], table_name: import[:table_name], load: false, srid: import[:zone_proj])
      end

      imports.map do |import|
        if(Thread.list.count % 10 != 0)
          psql_thread = Thread.new do
            load_shp(import[:shp], table_name: import[:table_name], create: false, srid: import[:zone_proj])
          end
          threads << psql_thread
        else
          # Wait for open psql threads to finish executing before starting new one
          threads.each do |thread|
            thread.join
          end
          # Start psql thread again
          psql_thread = Thread.new do
            load_shp(import[:shp], table_name: import[:table_name], create: false, srid: import[:zone_proj])
          end
          threads << psql_thread
        end
      end

      # Wait for psql threads to finish executing before exiting the load task
      threads.each &:join
    end

    def self.table_definitions(builder)
      builder.table :registered_graphic_parcels, sql: <<-SQL
        CREATE TABLE registered_graphic_parcels (
          id character varying NOT NULL,
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
    end

    def normalize
      logger.debug "Load in DB Lexicon table..."
      ZONES.each do |zone_name, zone_proj|
        REGIONS[zone_name].each do |region|
          logger.debug "Normalize #{region} in DB Lexicon table..."
          query <<-SQL
            INSERT INTO registered_graphic_parcels (id, cap_crop_code, shape, centroid)
              SELECT
                id_parcel, --id
                code_cultu, --cap_crop_code
                (postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)), 0.0))).geom, --shape
                postgis.ST_Centroid((postgis.ST_Dump(postgis.ST_Buffer(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)), 0.0))).geom) --centroid
              FROM graphic_parcels.parcelles_graphiques_#{zone_name}_#{region};

            -- Fill table with parcel barycenter corresponding city name
            WITH sub AS (
              SELECT z.id id, c.nom_com city_name
              FROM registered_graphic_parcels z, graphic_parcels.cities c
              WHERE postgis.ST_Intersects(z.centroid, c.geom)
            )
            INSERT INTO graphic_parcels.ilotscom (ilot, commune)
              SELECT id, city_name
              FROM sub
            ON CONFLICT DO NOTHING;

            -- Set names in final table
            UPDATE registered_graphic_parcels crop
              SET city_name = (SELECT commune FROM graphic_parcels.ilotscom WHERE crop.id = ilot);
          SQL
        end
      end
    end
  end
end
