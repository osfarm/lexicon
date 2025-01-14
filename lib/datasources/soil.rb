module Datasources
  class Soil < Base
    description 'Agronomical soil data from INRAE'
    credits name: 'Données de références sur le sol', url: "https://data.inrae.fr/dataverse/bdgsf", provider: "INRAE", licence: "LOOL", licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence", updated_at: "2022-01-12"

    # need to reproj origin file in 4326 with Qgis
    # bdgsf_classe_ru > soil_available_water
    # bdgsf_classe_prof > soil_depth
    def collect
      FileUtils.cp Dir.glob('data/soil/available_water_capacities/*.*'), dir
      FileUtils.cp Dir.glob('data/soil/depths/*.*'), dir
    end

    def load
      load_shp(dir.join("soil_available_water.shp"), table_name: 'soil_available_water_capacities', srid: 4326)
      load_shp(dir.join("soil_depth.shp"), table_name: 'soil_depths', srid: 4326)
    end

    def self.table_definitions(builder)
      builder.table :registered_soil_depths, sql: <<-SQL
        CREATE TABLE registered_soil_depths (
          id character varying PRIMARY KEY NOT NULL,
          soil_depth_value numeric(19,4),
          soil_depth_unit character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL
        );
        CREATE INDEX registered_soil_depths_id ON registered_soil_depths (id);
        CREATE INDEX registered_soil_depths_shape ON registered_soil_depths USING GIST (shape);
      SQL

      builder.table :registered_soil_available_water_capacities, sql: <<-SQL
        CREATE TABLE registered_soil_available_water_capacities (
          id character varying PRIMARY KEY NOT NULL,
          available_water_reference_value integer,
          available_water_min_value numeric(19,4),
          available_water_max_value numeric(19,4),
          available_water_unit character varying,
          available_water_label character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL
        );
        CREATE INDEX registered_soil_available_water_capacities_id ON registered_soil_available_water_capacities (id);
        CREATE INDEX registered_soil_available_water_capacities_shape ON registered_soil_available_water_capacities USING GIST (shape);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_soil_depths (id, soil_depth_value, soil_depth_unit, shape)
        SELECT
          prof_id, --id
          pr_cl, --soil_depth_value
          'centimeter', --soil_depth_unit
          geom
        FROM soil.soil_depths
      SQL

      query <<-SQL
        INSERT INTO registered_soil_available_water_capacities (id, available_water_reference_value, available_water_unit, shape)
        SELECT
          reserve_id, --id
          classe::int, --available_water_reference_value
          'millimeter', --available_water_unit
          geom
        FROM soil.soil_available_water_capacities
      SQL

      transcode_water_reference = { 1 => [ 0.0, 50.0, '< 50 mm'],
                                    2 => [ 50.0, 100.0, '50 - 100 mm'],
                                    3 => [ 100.0, 150.0, '100 - 150 mm'],
                                    4 => [ 150.0, 200.0, '150 - 200 mm'],
                                    5 => [ 200.0, 300.0, '> 200 mm'],
                                    9 => [ 0.0, 0.0, '--']
                                  }

      transcode_water_reference.each do |reference, data|
        query " UPDATE registered_soil_available_water_capacities
                SET available_water_min_value = #{data[0]},
                    available_water_max_value = #{data[1]},
                    available_water_label = '#{data[2]}'
                WHERE available_water_reference_value = #{reference}"
      end

    end
  end
end
