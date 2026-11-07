module Datasources
  class Phytosanitary < Base
    description 'Phytosanitary products database from Ephy'
    credits name: 'Catalogues des produits de protection des végétaux', url: "https://www.data.gouv.fr/fr/datasets/donnees-ouvertes-du-catalogue-e-phy-des-produits-phytopharmaceutiques-matieres-fertilisantes-et-supports-de-culture-adjuvants-produits-mixtes-et-melanges/", provider: "ANSES", licence: "Open Licence", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2014/05/Licence_Ouverte.pdf", updated_at: "2026-09-01"
    credits name: "Autorisations de mise sur le marché d'une durée maximale de 120 jours", url: Derogations::PAGE_URL, provider: "Ministère de l'Agriculture", licence: "Licence Ouverte 2.0", licence_url: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf", updated_at: "2026-11-07"

    # 2: derogations of 120 days (`is_derogation` and their dates on usages and products)
    schema_revision 2
    # The latest decision, of E-Phy or of a derogation: the package only changes when a decision does
    source_date 'SELECT max(decision_date) FROM registered_phytosanitary_usages WHERE decision_date <= CURRENT_DATE'

    BASE_URL = "https://www.data.gouv.fr/api/1/datasets/r"

    def collect
      #Collect data from Data.gouv
      downloader.curl "#{BASE_URL}/cdbc887b-265e-4338-9509-5e9958df1a48", out: 'ephy_xml.zip'
      downloader.curl "#{BASE_URL}/cb51408e-2b97-43a4-94e2-c0de5c3bf5b2", out: 'ephy_csv.zip'

      # Collect each csv from Ekylibre
      FileUtils.cp Dir.glob('data/phytosanitary/*.csv'), dir #TO DO : add a command to generate execeptions and target_name_to_pfi_targets

      collect_derogations
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

      load_derogations
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
          record_checksum integer,
          is_derogation boolean NOT NULL DEFAULT false
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
          record_checksum integer,
          is_derogation boolean NOT NULL DEFAULT false,
          derogation_started_on date,
          derogation_stopped_on date,
          derogation_url character varying
        );

        CREATE INDEX registered_phytosanitary_usages_product_id ON registered_phytosanitary_usages(product_id);
        CREATE INDEX registered_phytosanitary_usages_species ON registered_phytosanitary_usages(species);
        CREATE INDEX registered_phytosanitary_usages_derogation ON registered_phytosanitary_usages(product_id) WHERE is_derogation;
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

      normalize_derogations

      query <<-SQL
        INSERT INTO registered_phytosanitary_cropsets (id, name, label, crop_names, crop_labels) -- Insert cropsets
          SELECT n, name, CONCAT('{"fra":"', label_fr, '"}')::JSONB, CONCAT('{', crop_names, '}')::TEXT[], CONCAT('{"fra":"', crop_labels_fr, '"}')::JSONB
          FROM phytosanitary.cropsets;

        UPDATE registered_phytosanitary_usages SET species = CONCAT('{', name, '}')::TEXT[] FROM registered_phytosanitary_cropsets -- Update usage species with cropsets
          WHERE registered_phytosanitary_usages.crop_label_fra = registered_phytosanitary_cropsets.label ->> 'fra';

        -- Update usage species with open nomenclature. OpenNomenclature used to load one raw
        -- table per nomenclature (open_nomenclature.varieties); since 19eb03f it loads a single
        -- `nomenclatures` table discriminated by its first column.
        UPDATE registered_phytosanitary_usages SET species[1] = crop_varieties.name
          FROM (SELECT usages.id, varieties.name
            FROM registered_phytosanitary_usages usages
            JOIN open_nomenclature.nomenclatures varieties
            ON varieties.nomenclature = 'varieties'
            AND usages.crop_label_fra = varieties.label ->> 'fra') crop_varieties
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

    # Derogations of 120 days: the page of the ministry, the PDF it lists, each read once by Mistral OCR. Nothing
    # here stops the collect of E-Phy: what fails is said, and the archive keeps what was collected before.
    def collect_derogations
      archive = Derogations::Archive.new(dir.join('derogations'))
      today = Date.today
      collect_derogation_pdfs(archive, today)
      read_derogations(archive)
    end

    def collect_derogation_pdfs(archive, today)
      page = fetch(Derogations::PAGE_URL, "derogations/page_#{today.iso8601}.html", again: true)
      notices = Derogations::Page.parse(page.read)
      if notices.empty?
        puts "No decision found in #{Derogations::PAGE_URL}: the page may have changed, the archive is kept".red
        return
      end

      by_url = archive.entries.each_with_object({}) { |entry, found| found[entry.notice['pdf_url']] = entry.sha if entry.notice }
      added = 0
      notices.each do |notice|
        sha = by_url[notice.pdf_url]
        if sha.nil?
          sha = archive.store(fetch(notice.pdf_url, 'derogations/incoming.pdf', again: true))
          added += 1
        end
        archive.see(sha, notice, today)
      rescue StandardError => e
        puts "Derogation #{notice.amm} #{notice.name} not downloaded (#{notice.pdf_url}): #{e.message}".red
      end
      puts "Derogations: #{notices.size} decisions on the page, #{added} new"
    rescue StandardError => e
      puts "Derogations: the page could not be read (#{e.message}), the archive is kept".red
    end

    def read_derogations(archive)
      unread = archive.entries.select { |entry| entry.ocr.nil? }
      return if unread.empty?

      api_key = ENV['MISTRAL_API_KEY'].presence
      if api_key.nil?
        puts "Derogations: #{unread.size} decisions not read, MISTRAL_API_KEY is not set".red
        return
      end

      reader = Derogations::Reader.new(api_key: api_key)
      unread.each do |entry|
        archive.keep_ocr(entry.sha, reader.read(entry.pdf.binread))
        puts "Derogation read: #{entry.notice&.dig('amm')} #{entry.notice&.dig('name')} (#{entry.sha})"
      rescue Derogations::Reader::RateLimited => e
        puts "Derogations: reading stopped, #{unread.size} decisions not read in all: #{e.message}".red
        break
      rescue StandardError => e
        puts "Derogation #{entry.sha} not read: #{e.message}".red
      end
    end

    # Checks every decision read and writes the raw tables, with no network
    def load_derogations
      decisions = Derogations::Archive.new(dir.join('derogations')).entries.filter_map do |entry|
        entry.ocr && Derogations::Decision.new(sha: entry.sha, notice: entry.notice, ocr: entry.ocr)
      end
      units = YAML.load_file(Pathname.new(__dir__).join('phytosanitary', 'units.yml'))
      rows = Derogations::Rows.new(decisions, today: Date.today, units: units)

      { 'derogation_products' => [Derogations::Rows::PRODUCT_HEADERS, rows.products],
        'derogation_usages' => [Derogations::Rows::USAGE_HEADERS, rows.usages],
        'derogation_risks' => [Derogations::Rows::RISK_HEADERS, rows.risks],
        'derogations_refused' => [Derogations::Rows::REFUSED_HEADERS, rows.refused_rows] }.each do |table, (headers, lines)|
        load_csv(write_csv("#{table}.csv", headers, lines), table)
      end

      puts "Derogations: #{rows.decisions.size} decisions kept, #{rows.usages.size} usages, #{rows.refused.size} refused"
      rows.refused.each { |decision| puts "  refused #{decision.sha} #{decision.name}: #{decision.errors.join(' ; ')}".red }
    end

    # Products absent from E-Phy, then usages. A product of E-Phy is never changed; the crop, target and treatment
    # of a usage are those of an E-Phy usage of the same code when there is one.
    def normalize_derogations
      query <<~SQL
        INSERT INTO registered_phytosanitary_products (id, reference_name, name, active_compounds, france_maaid,
            mix_category_codes, in_field_reentry_delay, state, started_on, stopped_on, firm_name, product_type, is_derogation)
          SELECT d.id::integer, d.reference_name, d.name, string_to_array(NULLIF(d.active_compounds, ''), ' | '), d.id,
            string_to_array(d.mix_category_codes, ',')::integer[], (d.in_field_reentry_hours || ' hours')::interval,
            d.state, d.started_on::date, d.stopped_on::date, d.firm_name, 'DEROGATION', true
          FROM phytosanitary.derogation_products d
        ON CONFLICT (id) DO NOTHING;

        INSERT INTO registered_phytosanitary_risks (product_id, risk_code, risk_phrase)
          SELECT r.product_id::integer, r.risk_code, r.risk_phrase
          FROM phytosanitary.derogation_risks r
          JOIN registered_phytosanitary_products p ON p.id = r.product_id::integer AND p.is_derogation
        ON CONFLICT DO NOTHING;

        WITH catalogue AS (
          SELECT DISTINCT ON (lib_court) lib_court, ephy_usage_phrase, crop, crop_label_fra, target_name,
            target_name_label_fra, treatment
          FROM registered_phytosanitary_usages
          WHERE NOT is_derogation AND lib_court IS NOT NULL
          ORDER BY lib_court, (state = 'authorized') DESC, id
        )
        INSERT INTO registered_phytosanitary_usages (id, lib_court, product_id, ephy_usage_phrase, crop, crop_label_fra,
            species, target_name, target_name_label_fra, treatment, dose_quantity, dose_unit, dose_unit_name,
            dose_unit_factor, pre_harvest_delay, applications_count, development_stage_min, development_stage_max,
            usage_conditions, untreated_buffer_aquatic, decision_date, state, is_derogation, derogation_started_on,
            derogation_stopped_on, derogation_url)
          SELECT d.id, d.lib_court::integer, d.product_id::integer,
            COALESCE(c.ephy_usage_phrase, d.ephy_usage_phrase),
            COALESCE(c.crop, jsonb_build_object('fra', d.crop_label_fra)),
            COALESCE(c.crop_label_fra, d.crop_label_fra),
            '{plant}',
            COALESCE(c.target_name, jsonb_build_object('fra', d.target_name_label_fra)),
            COALESCE(c.target_name_label_fra, d.target_name_label_fra),
            COALESCE(c.treatment, CASE WHEN d.treatment IS NOT NULL THEN jsonb_build_object('fra', d.treatment) END),
            d.dose_quantity::numeric, d.dose_unit, d.dose_unit_name, d.dose_unit_factor::real,
            (d.pre_harvest_days || ' days')::interval, d.applications_count::integer,
            d.development_stage_min::integer, d.development_stage_max::integer, d.usage_conditions,
            d.untreated_buffer_aquatic::integer, d.decision_date::date, d.state, true, d.started_on::date,
            d.stopped_on::date, d.url
          FROM phytosanitary.derogation_usages d
          LEFT JOIN catalogue c ON c.lib_court = d.lib_court::integer
          WHERE EXISTS (SELECT 1 FROM registered_phytosanitary_products p WHERE p.id = d.product_id::integer);
      SQL

      unknown = query(<<~SQL).first['count']
        SELECT count(*) FROM registered_phytosanitary_usages u
        WHERE u.is_derogation AND NOT EXISTS (
          SELECT 1 FROM registered_phytosanitary_usages e WHERE NOT e.is_derogation AND e.lib_court = u.lib_court)
      SQL
      puts "Derogations: #{unknown} usages whose code E-Phy does not know, crop drawn from their phrase" if unknown.to_i.positive?
    end

    def hash_table(table_name)
      column_list = query("SELECT column_name FROM information_schema.columns WHERE table_schema = 'lexicon' AND table_name = '#{table_name}'").to_a.map { |e| e["column_name"] }.join(',')
      concat_list = "('x'||substr(md5(concat(#{column_list})),1,8))::bit(32)::int"
      query("UPDATE #{table_name} SET record_checksum = #{concat_list}")
    end

  end
end
