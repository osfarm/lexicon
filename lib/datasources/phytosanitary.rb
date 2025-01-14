module Datasources
  class Phytosanitary < Base
    description 'Phytosanitary products database from Ephy'
    credits name: 'Catalogues des produits de protection des végétaux', url: "https://www.data.gouv.fr/fr/datasets/donnees-ouvertes-du-catalogue-e-phy-des-produits-phytopharmaceutiques-matieres-fertilisantes-et-supports-de-culture-adjuvants-produits-mixtes-et-melanges/", provider: "ANSES", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: "2024-04-03"

    BASE_URL = "https://www.data.gouv.fr/fr/datasets/r"

    def collect
      #Collect data from Data.gouv
      downloader.curl "#{BASE_URL}/cdbc887b-265e-4338-9509-5e9958df1a48", out: 'ephy_xml.zip'
      downloader.curl "#{BASE_URL}/cb51408e-2b97-43a4-94e2-c0de5c3bf5b2", out: 'ephy_csv.zip'

      # Collect each csv from Ekylibre
      FileUtils.cp Dir.glob('data/phytosanitary/*.csv'), dir #TO DO : add a command to generate execeptions and target_name_to_pfi_targets
    end

    def load
      puts "Extracting EPHY XML..."
      unzip(dir.join('ephy_xml.zip'), dir.join('xml'))

      puts "Extracting EPHY CSV..."
      unzip(dir.join('ephy_csv.zip'), dir.join('csv'))

      puts "Loading CSV raw data EPHY..."
      load_csv(dir.join('csv/produits_usages_utf8.csv'), 'usages', col_sep: ';')
      load_csv(dir.join('csv/permis_de_commerce_parallele_utf8.csv'), 'commerce_parallele', col_sep: ';')

      puts "Clean leading/trailing spaces and tabs"
      query "SET intervalstyle = 'iso_8601';"
      query "UPDATE commerce_parallele SET nom_du_produit_importe = REGEXP_REPLACE(nom_du_produit_importe, '(^[\s\t]*|[\s\t]*$)', '', 'g');"
      query "UPDATE commerce_parallele SET produit_de_reference_francais = REGEXP_REPLACE(produit_de_reference_francais, '(^[\s\t]*|[\s\t]*$)', '', 'g');"

      query "DROP TABLE IF EXISTS phytosanitary.commerce_parallele_concat;"

      puts "Creates temp table with merged rows on permit number"
      query "CREATE TABLE commerce_parallele_concat AS
          SELECT DISTINCT(n_permis), nom_du_produit,
            array_agg(DISTINCT nom_du_produit_importe) as other_names,
            array_to_string(array_agg(DISTINCT produit_de_reference_francais), ' | ') as other_names_fra,
            LOWER(REGEXP_REPLACE(REGEXP_REPLACE(CONCAT(COALESCE(n_amm_de_reference_francais, n_permis), ' ', nom_du_produit), '[^a-zA-Z0-9]', '_', 'g'), '[^a-zA-Z0-9]$', '')) as reference_name,
            detenteur_pcp, n_amm_de_reference_francais
          FROM commerce_parallele GROUP BY nom_du_produit, n_permis, detenteur_pcp, n_amm_de_reference_francais;"

      load_csv(dir.join('phytosanitary - cropsets.csv'), 'cropsets')
      load_csv(dir.join('phytosanitary - exceptions.csv'), 'exceptions')
      load_csv(dir.join('phytosanitary - symbols.csv'), 'symbols')
      load_csv(dir.join('phytosanitary - target_name_to_pfi_targets.csv'), 'target_name_to_pfi_targets')
    end

    def self.table_definitions(builder)
      builder.table :registered_phytosanitary_cropsets, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_cropsets (
          id character varying PRIMARY KEY NOT NULL,
          name character varying NOT NULL,
          label jsonb,
          crop_names text[],
          crop_labels jsonb,
          record_checksum integer
        );

        CREATE INDEX registered_phytosanitary_cropsets_crop_names ON registered_phytosanitary_cropsets(crop_names);
      SQL

      builder.table :registered_phytosanitary_products, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_products (
          id integer PRIMARY KEY NOT NULL,
          reference_name character varying NOT NULL,
          name character varying NOT NULL,
          other_names text[],
          natures text[],
          active_compounds text[],
          france_maaid character varying NOT NULL,
          mix_category_codes integer[],
          in_field_reentry_delay interval,
          state character varying NOT NULL,
          started_on date,
          stopped_on date,
          allowed_mentions jsonb,
          restricted_mentions character varying,
          operator_protection_mentions text,
          firm_name character varying,
          product_type character varying,
          record_checksum integer
        );

        CREATE INDEX registered_phytosanitary_products_name ON registered_phytosanitary_products(name);
        CREATE INDEX registered_phytosanitary_products_natures ON registered_phytosanitary_products(natures);
        CREATE INDEX registered_phytosanitary_products_france_maaid ON registered_phytosanitary_products(france_maaid);
        CREATE INDEX registered_phytosanitary_products_firm_name ON registered_phytosanitary_products(firm_name);
        CREATE INDEX registered_phytosanitary_products_reference_name ON registered_phytosanitary_products(reference_name);
      SQL

      builder.table :registered_phytosanitary_usages, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_usages (
          id character varying PRIMARY KEY NOT NULL,
          lib_court integer,
          product_id integer NOT NULL,
          ephy_usage_phrase character varying NOT NULL,
          crop jsonb,
          crop_label_fra character varying,
          species text[],  --could be an array by is originaly a string--
          target_name jsonb,
          target_name_label_fra character varying,
          description jsonb,
          treatment jsonb,
          dose_quantity numeric(19,4),
          dose_unit character varying,
          dose_unit_name character varying,
          dose_unit_factor real,
          pre_harvest_delay interval,
          pre_harvest_delay_bbch integer,
          applications_count integer,
          applications_frequency interval,
          development_stage_min integer,
          development_stage_max integer,
          usage_conditions character varying,
          untreated_buffer_aquatic integer,
          untreated_buffer_arthropod integer,
          untreated_buffer_plants integer,
          decision_date date,
          state character varying NOT NULL,
          extract_spray_volume_max_quantity character varying,
          extract_spray_volume_max_unit character varying,
          spray_volume_max_quantity numeric(19,4),
          spray_volume_max_unit character varying,
          spray_volume_max_unit_name character varying,
          spray_volume_max_dose_quantity numeric(19,4),
          spray_volume_max_dose_unit character varying,
          spray_volume_max_dose_unit_name character varying,
          record_checksum integer
        );

        CREATE INDEX registered_phytosanitary_usages_product_id ON registered_phytosanitary_usages(product_id);
        CREATE INDEX registered_phytosanitary_usages_species ON registered_phytosanitary_usages(species);
      SQL

      builder.table :registered_phytosanitary_risks, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_risks (
          product_id integer NOT NULL,
          risk_code character varying NOT NULL,
          risk_phrase character varying NOT NULL,
          record_checksum integer,
          PRIMARY KEY(product_id, risk_code)
        );

        CREATE INDEX registered_phytosanitary_risks_product_id ON registered_phytosanitary_risks(product_id);
      SQL

      builder.table :registered_phytosanitary_symbols, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_symbols (
          id character varying PRIMARY KEY NOT NULL,
          symbol_name character varying
        );

        CREATE INDEX registered_phytosanitary_symbols_id ON registered_phytosanitary_symbols(id);
        CREATE INDEX registered_phytosanitary_symbols_symbol_name ON registered_phytosanitary_symbols(symbol_name);
      SQL

      builder.table :registered_phytosanitary_target_name_to_pfi_targets, sql: <<-SQL
        CREATE TABLE registered_phytosanitary_target_name_to_pfi_targets (
          ephy_name character varying PRIMARY KEY NOT NULL,
          pfi_id integer,
          pfi_name character varying,
          default_pfi_treatment_type_id character varying

        );

        CREATE INDEX registered_phytosanitary_target_name_to_pfi_targets_ephy_name ON registered_phytosanitary_target_name_to_pfi_targets(ephy_name);
      SQL
    end

    def normalize
      execute("python3 -c 'from lib.datasources.phytosanitary import *; load_products_from_xml()'")

      puts "Update applications_frequency with ephy_csv data"
      query("UPDATE registered_phytosanitary_usages SET applications_frequency=
        CONCAT('P', ephy_clean.applications_frequency, 'D')::interval FROM

        (SELECT numero_amm amm,
          identifiant_usage usage_phrase,
          stade_cultural_min_bbch::integer bbch_min,
          tade_cultural_max_bbch::integer bbch_max,
          nombre_max_d_application::integer applications_count,
          condition_emploi,
          intervalle_minimum_entre_applications_jour applications_frequency
          FROM phytosanitary.usages
          WHERE intervalle_minimum_entre_applications_jour IS NOT NULL AND etat_usage!='Retrait') ephy_clean

        WHERE registered_phytosanitary_usages.product_id::text=ephy_clean.amm
        AND registered_phytosanitary_usages.ephy_usage_phrase=ephy_clean.usage_phrase
        AND registered_phytosanitary_usages.development_stage_min IS NOT DISTINCT FROM ephy_clean.bbch_min
        AND registered_phytosanitary_usages.development_stage_max IS NOT DISTINCT FROM ephy_clean.bbch_max
        AND registered_phytosanitary_usages.applications_count IS NOT DISTINCT FROM ephy_clean.applications_count
        AND REPLACE(REPLACE(REPLACE(registered_phytosanitary_usages.usage_conditions,
          chr(10), ' '),
          chr(34), chr(39)),
          ';', '.')
        IS NOT DISTINCT FROM ephy_clean.condition_emploi", search_path: "phytosanitary, lexicon")

      puts "Updates product table with PCP products"
      query "INSERT INTO registered_phytosanitary_products as p (id, reference_name, name, other_names, france_maaid, state, firm_name, product_type)
              SELECT n_permis::integer, reference_name, nom_du_produit, other_names np, COALESCE(n_amm_de_reference_francais, n_permis), 'inherited', detenteur_pcp, 'PCP'
              FROM phytosanitary.commerce_parallele_concat WHERE n_amm_de_reference_francais IS NOT NULL
            ON CONFLICT (id) DO UPDATE SET other_names = excluded.other_names;"

      #Update PCP attributes with associate PPP
      query "UPDATE lexicon.registered_phytosanitary_products SET natures = ppp.natures,
      active_compounds = ppp.active_compounds,
      mix_category_codes = ppp.mix_category_codes,
      in_field_reentry_delay = ppp.in_field_reentry_delay,
      started_on = ppp.started_on,
      allowed_mentions = ppp.allowed_mentions,
      operator_protection_mentions = ppp.operator_protection_mentions
      FROM (SELECT * FROM lexicon.registered_phytosanitary_products WHERE product_type IN ('PPP', 'ADJUVANT', 'PRODUIT-MIXTE')) ppp
      WHERE lexicon.registered_phytosanitary_products.france_maaid = ppp.france_maaid"

      query <<-SQL
        INSERT INTO registered_phytosanitary_cropsets (id, name, label, crop_names, crop_labels) -- Insert cropsets
          SELECT n, name, CONCAT('{"fra":"', label_fr, '"}')::JSONB, CONCAT('{', crop_names, '}')::TEXT[], CONCAT('{"fra":"', crop_labels_fr, '"}')::JSONB
          FROM phytosanitary.cropsets;

        UPDATE registered_phytosanitary_usages SET species = CONCAT('{', name, '}')::TEXT[] FROM registered_phytosanitary_cropsets -- Update usage species with cropsets
          WHERE registered_phytosanitary_usages.crop_label_fra = registered_phytosanitary_cropsets.label ->> 'fra';

        UPDATE registered_phytosanitary_usages SET species[1] = crop_varieties.name -- Update usage species with open nomenclature
          FROM (SELECT usages.id, varieties.name
            FROM registered_phytosanitary_usages usages
            JOIN open_nomenclature.varieties varieties
            ON usages.crop_label_fra = varieties.label ->> 'fra') crop_varieties
          WHERE registered_phytosanitary_usages.id = crop_varieties.id AND species = '{plant}';

        UPDATE registered_phytosanitary_usages SET species = CONCAT('{', eky_species, '}')::TEXT[] FROM phytosanitary.exceptions -- Update usage species with exceptions
          WHERE crop_label_fra = ephy_crop_label;

        INSERT INTO registered_phytosanitary_symbols (id, symbol_name) -- Insert symbols
          SELECT mention_danger, code_pictogramme
          FROM phytosanitary.symbols;

        INSERT INTO registered_phytosanitary_target_name_to_pfi_targets (ephy_name, pfi_id, pfi_name, default_pfi_treatment_type_id) -- Insert link between ephy and pfi targets
          SELECT ephy_name, pfi_id::INTEGER, pfi_name, default_pfi_treatment_type_id
          FROM phytosanitary.target_name_to_pfi_targets
      SQL

      # Update Adjuvant dose by extracting maximum spraying volume
      puts "Updates usages table with spray_volume"
      # case ''
      query <<-SQL
        UPDATE registered_phytosanitary_usages SET
            extract_spray_volume_max_quantity = translate(( SELECT a.matches[1] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie : (\d+) (\S+)')) matches) a), ',', '.'),
            extract_spray_volume_max_unit = translate(translate(( SELECT a.matches[2] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie : (\d+) (\S+)')) matches) a), '.', ''),',', '')
          WHERE usage_conditions IS NOT NULL
            AND usage_conditions LIKE '%bouillie%'
            AND extract_spray_volume_max_quantity IS NULL;

        UPDATE registered_phytosanitary_usages SET
            extract_spray_volume_max_quantity = translate(( SELECT a.matches[1] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie de (\d+) (\S+)')) matches) a), ',', '.'),
            extract_spray_volume_max_unit = translate(translate(( SELECT a.matches[2] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie de (\d+) (\S+)')) matches) a), '.', ''),',', '')
          WHERE usage_conditions IS NOT NULL
            AND usage_conditions LIKE '%bouillie%'
            AND extract_spray_volume_max_quantity IS NULL;

        UPDATE registered_phytosanitary_usages SET
            extract_spray_volume_max_quantity = translate(( SELECT a.matches[1] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie: (\d+) (\S+)')) matches) a), ',', '.'),
            extract_spray_volume_max_unit = translate(translate(( SELECT a.matches[2] from
              ( SELECT (regexp_matches(usage_conditions, 'bouillie: (\d+) (\S+)')) matches) a), '.', ''),',', '')
          WHERE usage_conditions IS NOT NULL
            AND usage_conditions LIKE '%bouillie%'
            AND extract_spray_volume_max_quantity IS NULL;

      SQL


      hash_table("registered_phytosanitary_usages")
      hash_table("registered_phytosanitary_products")
      hash_table("registered_phytosanitary_risks")
      hash_table("registered_phytosanitary_cropsets")
    end

    def hash_table(table_name)
      column_list = query("SELECT column_name FROM information_schema.columns WHERE table_schema = 'lexicon' AND table_name = '#{table_name}'").to_a.map { |e| e["column_name"] }.join(',')
      concat_list = "('x'||substr(md5(concat(#{column_list})),1,8))::bit(32)::int"
      query("UPDATE #{table_name} SET record_checksum = #{concat_list}")
    end

  end
end
