module Datasources
  class Hydrography < Base
    LAST_UPDATED = "2024-03-15"
    description 'hydro data from IGN'
    credits name: 'BD TOPO Hydrographie', url: "https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#bd-topo", provider: "IGN", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: LAST_UPDATED

    # https://files.opendatarchives.fr/professionnels.ign.fr/bdtopo/BDTOPO_3-0_2021-03-15/
    # https://files.opendatarchives.fr/professionnels.ign.fr/bdtopo/BDTOPO_3-0_2021-03-15/BDTOPO_3-0_TOUSTHEMES_SHP_LAMB93_D001_2021-03-15.7z
    # FTP IGN suck so we use CQ mirror
    # OLD URL url = "ftp://BDTOPO_V3_ext:Aish3ho8!!!@ftp3.ign.fr/BDTOPO_3-0_#{LAST_UPDATED}/BDTOPO_3-0_TOUSTHEMES_SHP_#{zone}_#{departement}_#{LAST_UPDATED}.7z"

    BASE_URL = "https://files.opendatarchives.fr/professionnels.ign.fr/bdtopo/BDTOPO_3-3"
    #C_Q_URL = "http://data.cquest.org/ign/bdtopo/BDTOPO_3-0"
    #MIRROR_1_URL = "https://mirror1.opendatarchives.fr/professionnels.ign.fr/bdtopo/BDTOPO_3-0"
    #MIRROR_2_URL = "https://mirror2.opendatarchives.fr/professionnels.ign.fr/bdtopo/BDTOPO_3-0"
    #BASE_IGN_URL = "ftp://BDTOPO_V3_ext:Aish3ho8!!!@ftp3.ign.fr/BDTOPO_3-0"
    #BASE_IGN_2_URL = "ftp://BDTOPO_V3_NL_ext:Ohp3quaz2aideel4@ftp3.ign.fr/BDTOPO_3-0"
    #PROXY_URL = "https://sandbox.geo.api.gouv.fr/ign-ftp-proxy/ftp://BDTOPO_V3_ext:Aish3ho8!!!@ftp3.ign.fr/BDTOPO_3-0"

    ZONES = {
      "LAMB93" => "2154",
      "RGAF09UTM20" => "5490",
      "RGR92UTM40S" => "2975",
      "UTM22RGFG95" => "2972",
      "RGSPM06U21" => "4467",
      "RGM04UTM38S" => "4471"
    }.freeze

    DEPARTMENTS = {
      "LAMB93" => ["D001", "D002", "D003", "D004", "D005", "D006",
                   "D007", "D008", "D009", "D010", "D011", "D012",
                   "D013", "D014", "D015", "D016", "D017", "D018",
                   "D019", "D02A", "D02B", "D021", "D022", "D023",
                   "D024", "D025", "D026", "D027", "D028", "D029",
                   "D030", "D031", "D032", "D033", "D034", "D035",
                   "D036", "D037", "D038", "D039", "D040", "D041",
                   "D042", "D043", "D044", "D045", "D046", "D047",
                   "D048", "D049", "D050", "D051", "D052", "D053",
                   "D054", "D055", "D056", "D057", "D058", "D059",
                   "D060", "D061", "D062", "D063", "D064", "D065",
                   "D066", "D067", "D068", "D069", "D070", "D071",
                   "D072", "D073", "D074", "D075", "D076", "D077",
                   "D078", "D079", "D080", "D081", "D082", "D083",
                   "D084", "D085", "D086", "D087", "D088", "D089",
                   "D090", "D091", "D092", "D093", "D094", "D095"], # France From 01 to 95 with no 20 and 2A 2B
      "RGAF09UTM20" => ["D971", "D972", "D977", "D978"], # Guadeloupe / Martinique
      "UTM22RGFG95" => ["D973"], # Guyanne
      "RGR92UTM40S" => ["D974"], # Réunion
      "RGSPM06U21" => ["D975"], # St pierre and miquelon
      "RGM04UTM38S" => ["D976"] # Mayotte
    }.freeze

    EXTS = %w(shp shx cpg dbf prj).freeze

    WATER_DATASETS = %w(SURFACE_HYDROGRAPHIQUE DETAIL_HYDROGRAPHIQUE TRONCON_HYDROGRAPHIQUE).freeze

    BUILDING_DATASETS = %w(BATIMENT PYLONE).freeze

    AREA_DATASETS = %w(HAIE ZONE_DE_VEGETATION).freeze

    def collect
      # TODO if curl lauch too many process, try to download in batch
      logger.debug "Download files..."
      files = []
      ZONES.each do |(zone, _v)|
        DEPARTMENTS[zone].each do |department|
          zip_name = "hydro_#{zone}_#{department}.zip"
          dl_file = dir.join(zip_name)
          if File.exist?(dl_file)
            logger.debug "File #{zip_name} exist"
            files << [zip_name, zone, department]
          else
            url = "#{BASE_URL}_#{LAST_UPDATED}/BDTOPO_3-3_TOUSTHEMES_SHP_#{zone}_#{department}_#{LAST_UPDATED}.7z"
            logger.debug "Download #{url}..."
            downloader.curl url, out: zip_name
            files << [zip_name, zone, department]
          end
        end
      end

      logger.debug "Extracting files..."
      files.each do |(file, zone, department)|
        if zone && department
          exist_file = dir.join("#{zone}/#{department}/#{AREA_DATASETS.last}.shp")
          if File.exist?(exist_file)
            logger.debug "Files  #{zone}/#{department} already extracted."
          else
            logger.debug  "Extracting #{file}"
            archive = dir.join(file)
            execute("7z x #{archive} -o#{dir}/archive -aoa")
            # create directory
            logger.debug "Create final folder #{zone}/#{department}/..."
            FileUtils.mkdir_p(dir.join("#{zone}/#{department}/"))
            # Hydro
            WATER_DATASETS.each do |dataset|
              logger.debug "Extract #{dataset}..."
              EXTS.each do |ext|
                archive_glob = dir.join("archive/BDTOPO_3-3_TOUSTHEMES_SHP_#{zone}_#{department}_#{LAST_UPDATED}/BDTOPO/1_DONNEES_LIVRAISON_*/BDT_3-3_SHP_#{zone}_#{department}-ED#{LAST_UPDATED}/HYDROGRAPHIE/#{dataset.upcase}.#{ext}")
                archive_path = Dir.glob(archive_glob).first if archive_glob.present?
                if archive_path.present? && File.exist?(archive_path)
                  target_path = Dir.glob(dir.join("#{zone}/#{department}/")).first
                  logger.debug  "Copy #{dataset}.#{ext} into #{zone}/#{department}/"
                  FileUtils.cp(archive_path, target_path)
                else
                  logger.error "Missing file #{archive_path} in archive"
                end
              end
            end
            # Building
            BUILDING_DATASETS.each do |dataset|
              logger.debug "Extract #{dataset}..."
              EXTS.each do |ext|
                archive_glob = dir.join("archive/BDTOPO_3-3_TOUSTHEMES_SHP_#{zone}_#{department}_#{LAST_UPDATED}/BDTOPO/1_DONNEES_LIVRAISON_*/BDT_3-3_SHP_#{zone}_#{department}-ED#{LAST_UPDATED}/BATI/#{dataset.upcase}.#{ext}")
                archive_path = Dir.glob(archive_glob).first if archive_glob.present?
                if archive_path.present? && File.exist?(archive_path)
                  target_path = Dir.glob(dir.join("#{zone}/#{department}/")).first
                  logger.debug  "Copy #{dataset}.#{ext} into #{zone}/#{department}/"
                  FileUtils.cp(archive_path, target_path)
                else
                  logger.error "Missing file #{archive_path} in archive"
                end
              end
            end
            # Area
            AREA_DATASETS.each do |dataset|
              logger.debug "Extract #{dataset}..."
              EXTS.each do |ext|
                archive_glob = dir.join("archive/BDTOPO_3-3_TOUSTHEMES_SHP_#{zone}_#{department}_#{LAST_UPDATED}/BDTOPO/1_DONNEES_LIVRAISON_*/BDT_3-3_SHP_#{zone}_#{department}-ED#{LAST_UPDATED}/OCCUPATION_DU_SOL/#{dataset.upcase}.#{ext}")
                archive_path = Dir.glob(archive_glob).first if archive_glob.present?
                if archive_path.present? && File.exist?(archive_path)
                  target_path = Dir.glob(dir.join("#{zone}/#{department}/")).first
                  logger.debug  "Copy #{dataset}.#{ext} into #{zone}/#{department}/"
                  FileUtils.cp(archive_path, target_path)
                else
                  logger.error "Missing file #{archive_path} in archive"
                end
              end
            end
            # remove tmp folder
            logger.debug "Remove #{department} extract folder..."
            FileUtils.remove_dir(dir.join("archive/BDTOPO_3-3_TOUSTHEMES_SHP_#{zone}_#{department}_#{LAST_UPDATED}"))
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
      imports = []
      # Codes for metropolitan France and overseas and associate epsg
      logger.debug "Parse files to load in DB temp tables..."
      ZONES.each do |(zone_name, zone_proj)|
        DEPARTMENTS[zone_name].each do |department|
          WATER_DATASETS.each do |dataset|
            logger.debug "Load #{department} #{dataset}..."
            archive_glob = dir.join("#{zone_name}/#{department}/#{dataset.upcase}.shp")
            archive_path = Dir.glob(archive_glob).first if archive_glob.present?
            if archive_path.present? && File.exist?(archive_path)
              logger.debug "Parse files #{archive_path}..."

              imports << {
                shp: dir.join(archive_path),
                zone_proj: zone_proj,
                dataset: dataset.downcase,
                table_name: "#{dataset.downcase}_#{zone_name}_#{department}"
              }
            else
              logger.error "No file present for  #{department} #{dataset}..."
            end
          end
          BUILDING_DATASETS.each do |dataset|
            logger.debug "Load #{department} #{dataset}..."
            archive_glob = dir.join("#{zone_name}/#{department}/#{dataset.upcase}.shp")
            archive_path = Dir.glob(archive_glob).first if archive_glob.present?
            if archive_path.present? && File.exist?(archive_path)
              logger.debug "Parse files #{archive_path}..."

              imports << {
                shp: dir.join(archive_path),
                zone_proj: zone_proj,
                dataset: dataset.downcase,
                table_name: "#{dataset.downcase}_#{zone_name}_#{department}"
              }
            else
              logger.error "No file present for  #{department} #{dataset}..."
            end
          end
          AREA_DATASETS.each do |dataset|
            logger.debug "Load #{department} #{dataset}..."
            archive_glob = dir.join("#{zone_name}/#{department}/#{dataset.upcase}.shp")
            archive_path = Dir.glob(archive_glob).first if archive_glob.present?
            if archive_path.present? && File.exist?(archive_path)
              logger.debug "Parse files #{archive_path}..."

              imports << {
                shp: dir.join(archive_path),
                zone_proj: zone_proj,
                dataset: dataset.downcase,
                table_name: "#{dataset.downcase}_#{zone_name}_#{department}"
              }
            else
              logger.error "No file present for  #{department} #{dataset}..."
            end
          end
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
       builder.table :registered_cadastral_buildings, sql: <<-SQL
         CREATE TABLE registered_cadastral_buildings(
          id SERIAL PRIMARY KEY NOT NULL,
          reference_name character varying,
          nature character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_cadastral_buildings_id ON registered_cadastral_buildings(id);
        CREATE INDEX registered_cadastral_buildings_reference_name ON registered_cadastral_buildings(reference_name);
        CREATE INDEX registered_cadastral_buildings_shape ON registered_cadastral_buildings USING GIST (shape);
        CREATE INDEX registered_cadastral_buildings_centroid ON registered_cadastral_buildings USING GIST (centroid);
      SQL

      builder.table :registered_area_items, sql: <<-SQL
        CREATE TABLE registered_area_items (
          id character varying PRIMARY KEY NOT NULL,
          name jsonb,
          nature character varying,
          point postgis.geometry(Point,4326),
          shape postgis.geometry(MultiPolygon,4326),
          lines postgis.geometry(MultiLineString,4326),
          centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_area_items_id ON registered_area_items(id);
        CREATE INDEX registered_area_items_nature ON registered_area_items(nature);
        CREATE INDEX registered_area_items_shape ON registered_area_items USING GIST (shape);
        CREATE INDEX registered_area_items_point ON registered_area_items USING GIST (point);
        CREATE INDEX registered_area_items_lines ON registered_area_items USING GIST (lines);
        CREATE INDEX registered_area_items_centroid ON registered_area_items USING GIST (centroid);
      SQL

       builder.table :registered_hydrographic_items, sql: <<-SQL
         CREATE TABLE registered_hydrographic_items (
           id character varying PRIMARY KEY NOT NULL, 
           name jsonb,
           nature character varying,
           point postgis.geometry(Point,4326),
           shape postgis.geometry(MultiPolygon,4326),
           lines postgis.geometry(MultiLineString,4326),
           centroid postgis.geometry(Point, 4326)
        );
        CREATE INDEX registered_hydrographic_items_nature ON registered_hydrographic_items(nature);
        CREATE INDEX registered_hydrographic_items_shape ON registered_hydrographic_items USING GIST (shape);
        CREATE INDEX registered_hydrographic_items_point ON registered_hydrographic_items USING GIST (point);
        CREATE INDEX registered_hydrographic_items_lines ON registered_hydrographic_items USING GIST (lines);
        CREATE INDEX registered_hydrographic_items_centroid ON registered_hydrographic_items USING GIST (centroid);
      SQL
    end

    def normalize
      # Codes for metropolitan France and overseas
      logger.debug "Load in DB Lexicon table..."
      ZONES.each do |zone_name, zone_proj|
        DEPARTMENTS[zone_name].each do |department|
          logger.debug "Load #{department} 3 Water datasets..."

          query("INSERT INTO registered_hydrographic_items (id, name, nature, point)
          SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || toponyme || '\"}')::jsonb,
          nature, (postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom
          FROM hydrography.detail_hydrographique_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

          query("INSERT INTO registered_hydrographic_items (id, name, nature, shape)
          SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || nom_p_eau || '\"}')::jsonb,
          nature, postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom)
          FROM hydrography.surface_hydrographique_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

          query("INSERT INTO registered_hydrographic_items (id, name, nature, lines)
          SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || nom_c_eau || '\"}')::jsonb,
          nature, postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom)
          FROM hydrography.troncon_hydrographique_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

          logger.debug "Load #{department} Building dataset..."

          query("INSERT INTO registered_cadastral_buildings (reference_name, nature, shape)
          SELECT id, usage1,
          postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom)
          FROM hydrography.batiment_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

          # because all D90% have not edge and others
          if department.start_with?("D0")
            logger.debug "Load #{department} 3 Area datasets..."
            query("INSERT INTO registered_area_items (id, name, nature, lines)
            SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || 'haie' || '\"}')::jsonb, 'edge',
            postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom)
            FROM hydrography.haie_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

            query("INSERT INTO registered_area_items (id, name, nature, shape)
            SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || nature || '\"}')::jsonb, 'green_zone',
            postgis.ST_Multi((postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom)
            FROM hydrography.zone_de_vegetation_#{zone_name}_#{department} ON CONFLICT DO NOTHING")

            query("INSERT INTO registered_area_items (id, name, nature, point)
            SELECT CONCAT(id,'_fra_','#{department}'), ('{\"fra\": \"' || 'pylone' || '\"}')::jsonb, 'electric_pole',
            (postgis.ST_Dump(postgis.ST_Force2D(postgis.ST_Transform(geom,4326)))).geom
            FROM hydrography.pylone_#{zone_name}_#{department} ON CONFLICT DO NOTHING")
          end
        end
      end
      logger.debug "Compute centroid on Building..."
      query("UPDATE lexicon.registered_cadastral_buildings SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")

      logger.debug "Compute centroid on Area items..."
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(lines) WHERE lines IS NOT NULL AND postgis.ST_IsValid(lines) = true")
      query("UPDATE lexicon.registered_area_items SET centroid = postgis.ST_Centroid(point) WHERE point IS NOT NULL AND postgis.ST_IsValid(point) = true")

      logger.debug "Compute centroid on Hydrographic items..."
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(shape) WHERE shape IS NOT NULL AND postgis.ST_IsValid(shape) = true")
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(lines) WHERE lines IS NOT NULL AND postgis.ST_IsValid(lines) = true")
      query("UPDATE lexicon.registered_hydrographic_items SET centroid = postgis.ST_Centroid(point) WHERE point IS NOT NULL AND postgis.ST_IsValid(point) = true")
      
      logger.debug "Delete items where centroid is missing on Building, Area items and Hydrographic items..."
      query("DELETE FROM lexicon.registered_cadastral_buildings WHERE centroid IS NULL")
      query("DELETE FROM lexicon.registered_hydrographic_items WHERE centroid IS NULL")
      query("DELETE FROM lexicon.registered_area_items WHERE centroid IS NULL")
    end
  end
end
