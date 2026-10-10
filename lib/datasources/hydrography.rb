module Datasources
  class Hydrography < Base
    LAST_UPDATED = "2026-09-15"
    description 'water, buildings, hedges, vegetation, sensitive sites, protected areas and power lines from IGN (national BD TOPO GeoPackage)'
    credits name: 'BD TOPO',
            url: "https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BD-TOPO",
            provider: "IGN",
            licence: "Open Licence",
            licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf",
            updated_at: LAST_UPDATED

    schema_revision 1

    # The BD TOPO comes as one archive for metropolitan France, holding one
    # GeoPackage per layer: extract each `<layer>.gpkg` named below into
    # `raw/hydrography/` (see doc/datasources/hydrography.md).
    SCHEMA = 'hydrography'.freeze

    # The columns read from each layer: a layer is loaded with these alone
    LAYERS = {
      'surface_hydrographique' => %w(cleabs nature persistance position_par_rapport_au_sol etat_de_l_objet
                                     cpx_toponyme_de_plan_d_eau cpx_toponyme_de_cours_d_eau cpx_toponyme_d_entite_de_transition),
      'detail_hydrographique' => %w(cleabs nature toponyme),
      'troncon_hydrographique' => %w(cleabs nature persistance fosse classe_de_largeur inventaire_police_de_l_eau
                                     position_par_rapport_au_sol etat_de_l_objet
                                     cpx_toponyme_de_cours_d_eau cpx_toponyme_d_entite_de_transition),
      'cours_d_eau' => %w(cleabs toponyme caractere_permanent),
      'plan_d_eau' => %w(cleabs nature toponyme caractere_permanent),
      'batiment' => %w(cleabs nature usage_1 usage_2 construction_legere etat_de_l_objet nombre_de_logements hauteur),
      'pylone' => %w(cleabs),
      'haie' => %w(cleabs hauteur largeur),
      'zone_de_vegetation' => %w(cleabs nature),
      'zone_d_activite_ou_d_interet' => %w(cleabs categorie nature nature_detaillee toponyme etat_de_l_objet),
      'parc_ou_reserve' => %w(cleabs nature toponyme),
      'foret_publique' => %w(cleabs nature toponyme),
      'ligne_electrique' => %w(cleabs voltage etat_de_l_objet)
    }.freeze

    # Places where vulnerable people stay, near which treatments are restricted:
    # schools, hospitals, homes for the elderly and for disabled people
    SENSITIVE_NATURES = [
      'Enseignement primaire', 'Collège', 'Lycée', "Autre établissement d'enseignement",
      "Structure d'accueil pour personnes handicapées",
      'Maison de retraite', 'Hôpital', 'Etablissement hospitalier', 'Résidence autonomie'
    ].freeze

    def collect
      missing = LAYERS.keys.reject { |layer| File.exist?(gpkg_path_for(layer)) }
      unless missing.empty?
        raise "Missing GeoPackage file(s) in #{dir}: #{missing.map { |l| "#{l}.gpkg" }.join(', ')}"
      end

      LAYERS.each_key { |layer| logger.debug "Found GeoPackage: #{gpkg_path_for(layer)}" }
    end

    def load
      database.ensure_schema(SCHEMA)
      conn = pg_connection_string

      LAYERS.each do |layer, columns|
        path = gpkg_path_for(layer)
        raise "Missing GeoPackage file: #{path}" unless File.exist?(path)

        logger.debug "Loading layer #{layer} into #{SCHEMA}.#{layer}..."
        execute <<~BASH
          ogr2ogr \
            -f PostgreSQL "#{conn}" \
            -overwrite \
            -select #{columns.join(',')} \
            -lco SCHEMA=#{SCHEMA} \
            -lco GEOMETRY_NAME=geom \
            -lco FID=ogc_fid \
            -nlt PROMOTE_TO_MULTI \
            -t_srs EPSG:4326 \
            -nln #{layer} \
            "#{path}" #{layer}
        BASH
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_cadastral_buildings, sql: <<-SQL
        CREATE TABLE registered_cadastral_buildings(
          id SERIAL PRIMARY KEY NOT NULL,
          reference_name character varying,
          nature character varying,
          shape postgis.geometry(MultiPolygon, 4326) NOT NULL,
          centroid postgis.geometry(Point, 4326),
          kind character varying,
          secondary_nature character varying,
          dwellings_count integer,
          height numeric(6,2),
          light boolean,
          state character varying
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
          centroid postgis.geometry(Point, 4326),
          kind character varying,
          height numeric(6,2),
          width numeric(6,2)
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
          centroid postgis.geometry(Point, 4326),
          permanent boolean,
          persistence character varying,
          ditch boolean,
          width_class character varying,
          water_police character varying,
          underground boolean
        );
        CREATE INDEX registered_hydrographic_items_nature ON registered_hydrographic_items(nature);
        CREATE INDEX registered_hydrographic_items_shape ON registered_hydrographic_items USING GIST (shape);
        CREATE INDEX registered_hydrographic_items_point ON registered_hydrographic_items USING GIST (point);
        CREATE INDEX registered_hydrographic_items_lines ON registered_hydrographic_items USING GIST (lines);
        CREATE INDEX registered_hydrographic_items_centroid ON registered_hydrographic_items USING GIST (centroid);
      SQL
    end

    def normalize
      # A geometry is kept whole: dumping its parts under one id kept the first part only
      whole = 'postgis.ST_Multi(postgis.ST_Force2D(geom))'
      name_of = ->(column) { "CASE WHEN #{column} IS NOT NULL THEN jsonb_build_object('fra', #{column}) END" }
      # Persistance of the BD TOPO: Permanent, Intermittent, Sec, Ephémère, Inconnue
      permanent = "CASE WHEN persistance = 'Permanent' THEN true WHEN persistance IN ('Intermittent', 'Sec', 'Ephémère') THEN false END"
      underground = "CASE WHEN position_par_rapport_au_sol ~ '^-?[0-9]+$' THEN position_par_rapport_au_sol::integer < 0 END"

      logger.debug "Load Water layers into registered_hydrographic_items..."
      query("INSERT INTO registered_hydrographic_items (id, name, nature, point)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')},
      nature, (postgis.ST_Dump(postgis.ST_Force2D(geom))).geom
      FROM #{SCHEMA}.detail_hydrographique ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items (id, name, nature, shape, permanent, persistence, underground)
      SELECT CONCAT(cleabs, '_fra'),
      #{name_of.call('COALESCE(cpx_toponyme_de_plan_d_eau, cpx_toponyme_de_cours_d_eau, cpx_toponyme_d_entite_de_transition)')},
      nature, #{whole}, #{permanent}, persistance, #{underground}
      FROM #{SCHEMA}.surface_hydrographique
      WHERE etat_de_l_objet = 'En service' ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items
        (id, name, nature, lines, permanent, persistence, ditch, width_class, water_police, underground)
      SELECT CONCAT(cleabs, '_fra'),
      #{name_of.call('COALESCE(cpx_toponyme_de_cours_d_eau, cpx_toponyme_d_entite_de_transition)')},
      nature, #{whole}, #{permanent}, persistance, fosse,
      NULLIF(NULLIF(classe_de_largeur, 'Sans objet'), 'En attente de mise à jour'),
      inventaire_police_de_l_eau, #{underground}
      FROM #{SCHEMA}.troncon_hydrographique
      WHERE etat_de_l_objet = 'En service' ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items (id, name, nature, lines, permanent)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')},
      'watercourse', #{whole}, caractere_permanent
      FROM #{SCHEMA}.cours_d_eau ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_hydrographic_items (id, name, nature, shape, permanent)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')},
      nature, #{whole}, caractere_permanent
      FROM #{SCHEMA}.plan_d_eau ON CONFLICT DO NOTHING")

      logger.debug "Load Building layer into registered_cadastral_buildings..."
      query("INSERT INTO registered_cadastral_buildings
        (reference_name, nature, shape, kind, secondary_nature, dwellings_count, height, light, state)
      SELECT cleabs, usage_1, #{whole},
      nature, usage_2, nombre_de_logements, hauteur, construction_legere, etat_de_l_objet
      FROM #{SCHEMA}.batiment")

      logger.debug "Load Area layers into registered_area_items..."
      query("INSERT INTO registered_area_items (id, name, nature, lines, height, width)
      SELECT CONCAT(cleabs, '_fra'), jsonb_build_object('fra', 'haie'), 'edge', #{whole},
      hauteur, largeur
      FROM #{SCHEMA}.haie ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, shape, kind)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('nature')}, 'green_zone', #{whole}, nature
      FROM #{SCHEMA}.zone_de_vegetation ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, point)
      SELECT CONCAT(cleabs, '_fra'), jsonb_build_object('fra', 'pylone'), 'electric_pole',
      (postgis.ST_Dump(postgis.ST_Force2D(geom))).geom
      FROM #{SCHEMA}.pylone ON CONFLICT DO NOTHING")

      natures = SENSITIVE_NATURES.map { |nature| "'#{nature.gsub("'", "''")}'" }.join(', ')
      query("INSERT INTO registered_area_items (id, name, nature, shape, kind)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')}, 'sensitive_site', #{whole},
      COALESCE(nature_detaillee, nature)
      FROM #{SCHEMA}.zone_d_activite_ou_d_interet
      WHERE etat_de_l_objet = 'En service' AND nature IN (#{natures}) ON CONFLICT DO NOTHING")

      # Natura 2000 sites are in registered_natural_zones already
      query("INSERT INTO registered_area_items (id, name, nature, shape, kind)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')}, 'protected_area', #{whole}, nature
      FROM #{SCHEMA}.parc_ou_reserve
      WHERE nature <> 'Site Natura 2000' ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, shape, kind)
      SELECT CONCAT(cleabs, '_fra'), #{name_of.call('toponyme')}, 'public_forest', #{whole}, nature
      FROM #{SCHEMA}.foret_publique ON CONFLICT DO NOTHING")

      query("INSERT INTO registered_area_items (id, name, nature, lines, kind)
      SELECT CONCAT(cleabs, '_fra'), jsonb_build_object('fra', 'ligne électrique'), 'power_line', #{whole}, voltage
      FROM #{SCHEMA}.ligne_electrique
      WHERE etat_de_l_objet = 'En service' AND voltage <> 'Hors tension' ON CONFLICT DO NOTHING")

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

    private

      # @return [Pathname]
      def gpkg_path_for(layer)
        dir.join("#{layer}.gpkg")
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
