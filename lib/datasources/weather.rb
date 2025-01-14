module Datasources
  class Weather < Base
    description 'Historical weather'
    credits name: 'Données climatologiques de base - horaires', url: "https://meteo.data.gouv.fr/", provider: "Météo France", licence: "LO2.0", licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence", updated_at: "2024-04-08"
    
    BASE_URL = "https://object.files.data.gouv.fr/meteofrance/data/synchro_ftp/BASE/HOR"
    
    PERIODS = ["latest-2023-2024", "previous-2020-2022"].freeze
    
    DEPARTMENTS = [
      '01', '02', '03', '04', '05', '06', '07', '08', '09',
      '10', '11', '12', '13', '14', '15', '16', '17', '18', '19',
      '21', '22', '23', '24', '25', '26', '27', '28', '29',
      '30', '31', '32', '33', '34', '35', '36', '37', '38', '39',
      '40', '41', '42', '43', '44', '45', '46', '47', '48', '49',
      '50', '51', '52', '53', '54', '55', '56', '57', '58', '59',
      '60', '61', '62', '63', '64', '65', '66', '67', '68', '69',
      '70', '71', '72', '73', '74', '75', '76', '77', '78', '79',
      '80', '81', '82', '83', '84', '85', '86', '87', '88', '89',
      '90', '91', '92', '93', '94', '95'
    ].freeze
    
    def collect
      logger.debug "Download files..."
      files = []
      PERIODS.each do |period|
        DEPARTMENTS.each do |department|
          zip_name = "weather_#{period}_#{department}.zip"
          dl_file = dir.join(zip_name)
          if File.exist?(dl_file)
            logger.debug "File #{zip_name} exist"
            files << [zip_name, period, department]
          else
            url = "#{BASE_URL}/H_#{department}_#{period}.csv.gz"
            logger.debug "Download #{url}..."
            downloader.curl url, out: zip_name
            files << [zip_name, period, department]
          end
        end
      end
      
      logger.debug "Extracting files..."
      files.each do |(file, period, department)|
        if period && department
          exist_file = dir.join("#{period}/#{department}.csv")
          if File.exist?(exist_file)
            logger.debug "Files #{department} already extracted."
          else
            logger.debug "Extracting #{file}"
            archive = dir.join(file)
            execute("7z x #{archive} -o#{dir}/#{period} -aoa")
          end
        end
      end
    end
    
    def load
      logger.debug "Parse files to load in DB temp tables..."
      PERIODS.each do |period|
        DEPARTMENTS.each do |department|
          logger.debug "Load #{period} #{department}..."
          load_csv(dir.join("#{period}/H_#{department}_#{period}.csv"), "hourly_weather_#{period.gsub('-', '_')}_#{department}", col_sep: ';')
        end
      end
    end
    
    # code for ww, weather_description
    # https://www.nodc.noaa.gov/archive/arc0021/0002199/1.1/data/0-data/HTML/WMO-CODE/WMO4677.HTM
    # https://epic.awi.de/id/eprint/29966/1/WMO2011h.pdf
    def self.table_definitions(builder)
      builder.table :registered_weather_stations, sql: <<-SQL
        CREATE TABLE registered_weather_stations (
          reference_name character varying PRIMARY KEY NOT NULL,
          country character varying NOT NULL,
          country_zone character varying NOT NULL,
          station_code character varying NOT NULL,
          station_name character varying NOT NULL,
          elevation integer,
          centroid postgis.geometry(Point,4326)
        );
        
          CREATE INDEX registered_weather_stations_country ON registered_weather_stations(country);
          CREATE INDEX registered_weather_stations_country_zone ON registered_weather_stations(country_zone);
          CREATE INDEX registered_weather_stations_reference_name ON registered_weather_stations(reference_name);
          CREATE INDEX registered_weather_stations_centroid ON registered_weather_stations USING GIST (centroid);
      SQL
      
      builder.table :registered_hourly_weathers, sql: <<-SQL
        CREATE TABLE registered_hourly_weathers (
          station_id character varying,
          started_at timestamp,
          mesured_delay interval,
          average_temp numeric(19,4),
          min_temp numeric(19,4),
          max_temp numeric(19,4),
          rain numeric(19,4),
          max_wind_speed numeric(19,4),
          wind_direction numeric(19,4),
          frozen_duration numeric(19,4),
          humidity numeric(19,4),
          soil_state character varying,
          pressure numeric(19,4),
          weather_description character varying
        );
        
          CREATE INDEX registered_hourly_weathers_rain ON registered_hourly_weathers(rain);
          CREATE INDEX registered_hourly_weathers_station_id ON registered_hourly_weathers(station_id);
          CREATE INDEX registered_hourly_weathers_started_at ON registered_hourly_weathers(started_at);
          CREATE INDEX registered_hourly_weathers_average_temp ON registered_hourly_weathers(average_temp);
          CREATE INDEX registered_hourly_weathers_max_wind_speed ON registered_hourly_weathers(max_wind_speed);
          CREATE INDEX registered_hourly_weathers_pressure ON registered_hourly_weathers(pressure);
      SQL
    end
    
    def normalize
      DEPARTMENTS.each do |department|
        logger.debug "#{department} | Normalize weather station dataset..."
        query("INSERT INTO registered_weather_stations (reference_name, country, country_zone, station_code, station_name, elevation, centroid)
          SELECT 
          CONCAT('FR', TRIM(num_poste)),
          'FR',
          SUBSTR(TRIM(num_poste), 1, 2),
          TRIM(num_poste),
          TRIM(nom_usuel),
          CASE WHEN min(alti) IS NOT NULL THEN min(alti)::integer ELSE NULL END,
          postgis.ST_SetSRID(postgis.ST_MakePoint(lon::numeric, lat::numeric), 4326)
          FROM weather.hourly_weather_#{PERIODS.first.gsub('-', '_')}_#{department}
          GROUP BY num_poste, nom_usuel, lat, lon
          ORDER BY num_poste, nom_usuel, lat, lon ON CONFLICT DO NOTHING"
        )
      end

      PERIODS.each do |period|
        DEPARTMENTS.each do |department|
          logger.debug "#{department} | Normalize hourly weather #{period} dataset..."
          query("INSERT INTO registered_hourly_weathers (station_id, started_at, mesured_delay, average_temp, min_temp, max_temp, rain, max_wind_speed, wind_direction, frozen_duration, humidity,
            soil_state, pressure, weather_description)
            SELECT 
            CONCAT('FR', TRIM(num_poste)),
            TO_TIMESTAMP(aaaammjjhh, 'YYYYMMDDHH24'),
            interval '1 hour',
            CASE WHEN t IS NOT NULL THEN t::numeric ELSE NULL END,
            CASE WHEN tn IS NOT NULL THEN tn::numeric ELSE NULL END,
            CASE WHEN tx IS NOT NULL THEN tx::numeric ELSE NULL END,
            CASE WHEN rr1 IS NOT NULL THEN rr1::numeric ELSE NULL END,
            CASE WHEN fxi IS NOT NULL THEN fxi::numeric ELSE NULL END,
            CASE WHEN dxi IS NOT NULL THEN dxi::numeric ELSE NULL END,
            CASE WHEN dg IS NOT NULL THEN dg::numeric ELSE NULL END,
            CASE WHEN u IS NOT NULL THEN u::numeric ELSE NULL END,
            sol,
            CASE WHEN pstat IS NOT NULL THEN pstat::numeric ELSE NULL END,
            ww
            FROM weather.hourly_weather_#{period.gsub('-', '_')}_#{department} ON CONFLICT DO NOTHING"
          )
        end
      end
    end
    
  end
end
