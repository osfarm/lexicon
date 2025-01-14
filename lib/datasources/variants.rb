module Datasources
  class Variants < Base
    description 'Articles, Equipments, Services, Crops, Animals, Workers and Zones'
    credits name: 'Catalogues d articles de référence', url: "https://ekylibre.com", provider: "Ekylibre SAS", licence: "CC-BY-SA 4.0", licence_url: "https://creativecommons.org/licenses/by-sa/4.0/deed.fr", updated_at: "2021-09-10"

    def collect
      #Collect each csv file in variants directory
      FileUtils.cp Dir.glob('data/variants/*.csv'), dir
      FileUtils.cp Dir.glob('data/variants/*.yml'), dir
    end

    def load
      load_csv(dir.join('variants - categories.csv'), 'categories')
      load_csv(dir.join('variants - natures.csv'), 'natures')
      load_csv(dir.join('variants - farm_products.csv'), 'farm_products')
      load_csv(dir.join('variants - seeds_and_plants.csv'), 'seeds_and_plants')
      load_csv(dir.join('variants - fertilizers.csv'), 'fertilizers')
      load_csv(dir.join('variants - other_articles.csv'), 'other_articles')
      load_csv(dir.join('variants - equipments.csv'), 'equipments')
      load_csv(dir.join('variants - services.csv'), 'services')
      load_csv(dir.join('variants - crops.csv'), 'crops')
      load_csv(dir.join('variants - animals.csv'), 'animals')
      load_csv(dir.join('variants - animal_groups.csv'), 'animal_groups')
      load_csv(dir.join('variants - workers.csv'), 'workers')
      load_csv(dir.join('variants - zones.csv'), 'zones')
    end

    def self.table_definitions(builder)
      builder.table :master_variant_categories, sql: <<~SQL
        CREATE TABLE master_variant_categories (
          reference_name character varying PRIMARY KEY NOT NULL,
          family character varying NOT NULL,
          fixed_asset_account character varying,
          fixed_asset_allocation_account character varying,
          fixed_asset_expenses_account character varying,
          depreciation_percentage numeric(5,2),
          purchase_account character varying,
          sale_account character varying,
          stock_account character varying,
          stock_movement_account character varying,
          default_vat_rate numeric(5,2),
          payment_frequency_value integer,
          payment_frequency_unit character varying,
          pictogram character varying,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_variant_categories_reference_name ON master_variant_categories(reference_name);
      SQL

      builder.table :master_variant_natures, sql: <<~SQL
        CREATE TABLE master_variant_natures (
          reference_name character varying PRIMARY KEY NOT NULL,
          family character varying NOT NULL,
          population_counting character varying NOT NULL,
          frozen_indicators text[],
          variable_indicators text[],
          abilities text[],
          variety character varying NOT NULL,
          derivative_of character varying,
          pictogram character varying,
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_variant_natures_reference_name ON master_variant_natures(reference_name);
      SQL

      builder.table(:master_variants, sql: <<-SQL).references(category: [:master_variant_categories, :reference_name], nature: [:master_variant_natures, :reference_name], target_specie: [:master_taxonomy, :reference_name], specie: [:master_taxonomy, :reference_name], default_unit: [:master_units, :reference_name])
        CREATE TABLE master_variants (
          reference_name character varying PRIMARY KEY NOT NULL,
          family character varying NOT NULL,
          category character varying NOT NULL,
          nature character varying NOT NULL,
          sub_family character varying,
          default_unit character varying NOT NULL,
          target_specie character varying,
          specie character varying,
          indicators jsonb,
          pictogram character varying,
          name_tags text[],
          translation_id character varying NOT NULL
        );

        CREATE INDEX master_variants_reference_name ON master_variants(reference_name);
        CREATE INDEX master_variants_category ON master_variants(category);
        CREATE INDEX master_variants_nature ON master_variants(nature);
      SQL
    end

    def normalize

      query "DELETE FROM master_translations WHERE id LIKE 'categories%'"
      query "DELETE FROM master_translations WHERE id LIKE 'natures%'"
      query "DELETE FROM master_translations WHERE id LIKE 'variants%'"

      query <<-SQL
        INSERT INTO master_variant_categories (reference_name, family, fixed_asset_account, fixed_asset_allocation_account, -- Categories
        fixed_asset_expenses_account, depreciation_percentage, purchase_account, sale_account, stock_account, stock_movement_account,
        default_vat_rate, payment_frequency_value, payment_frequency_unit, pictogram, translation_id)
          SELECT reference_name, family, fixed_asset_account, fixed_asset_allocation_account, fixed_asset_expenses_account,
          depreciation_percentage::NUMERIC, charge_account, product_account, stock_account, stock_movement_account,
          default_vat_rate::NUMERIC, payment_frequency_value::INTEGER, payment_frequency_unit, pictogram, CONCAT('categories_', reference_name)
          FROM variants.categories;

        INSERT INTO master_variant_natures (reference_name, family, population_counting, frozen_indicators, variable_indicators, -- natures
        abilities, variety, derivative_of, pictogram, translation_id)
          SELECT reference_name, family, population_counting, CONCAT('{', frozen_indicators, '}')::TEXT[], CONCAT('{', variable_indicators, '}')::TEXT[],
          CONCAT('{', abilities, '}')::TEXT[], variety, derivative_of, pictogram, CONCAT('natures_', reference_name)
          FROM variants.natures;

        INSERT INTO master_variants (reference_name, family, category, nature, sub_family, default_unit, -- Farm products
        target_specie, indicators, pictogram, translation_id)
          SELECT reference_name, 'article', category, nature, 'farm_product', default_unit, target_specie,
            CASE WHEN indicator_1_name IS NOT NULL
            THEN CONCAT('{"', indicator_1_name, '": "', indicator_1_value, indicator_1_unit, '"}')::JSONB
            ELSE '{}'::JSONB END, pictogram, CONCAT('variants_', reference_name)
          FROM variants.farm_products;

        INSERT INTO master_variants (reference_name, family, category, nature, sub_family, default_unit, target_specie, indicators, pictogram, translation_id) -- Seeds and plants
          SELECT reference_name, 'article', 'seed_and_plant', nature, 'seed_and_plant', default_unit, target_specie,
          CASE WHEN pmg IS NOT NULL
          THEN CONCAT('{', '"thousand_grains_mass": "', pmg, 'gram"','}')::JSONB
          ELSE '{"thousand_grains_mass": "50gram"}'::JSONB END,
          'uf989-seed.svg', CONCAT('variants_', reference_name)
          FROM variants.seeds_and_plants;

        INSERT INTO master_variants (reference_name, family, category, nature, sub_family, default_unit,  -- Fertilizers
        target_specie, indicators, pictogram, translation_id)
          SELECT reference_name, 'article', 'fertilizer', nature, 'fertilizer', default_unit, target_specie,
            REPLACE(CONCAT('{', -- Build indicators from field values
            CASE WHEN mass_volume_density IS NOT NULL THEN CONCAT('"mass_volume_density": "', mass_volume_density, 'kilogram_per_liter",') ELSE '' END,
            CASE WHEN nitrogen_concentration IS NOT NULL THEN CONCAT('"nitrogen_concentration": "', nitrogen_concentration, 'percent",') ELSE '' END,
            CASE WHEN phosphorus_concentration IS NOT NULL THEN CONCAT('"phosphorus_concentration": "', phosphorus_concentration, 'percent",') ELSE '' END,
            CASE WHEN potassium_concentration IS NOT NULL THEN CONCAT('"potassium_concentration": "', potassium_concentration, 'percent",') ELSE '' END,
            CASE WHEN sulfur_dioxide_concentration IS NOT NULL THEN CONCAT('"sulfur_dioxide_concentration": "', sulfur_dioxide_concentration, 'percent",') ELSE '' END,
            CASE WHEN magnesium_concentration IS NOT NULL THEN CONCAT('"magnesium_concentration": "', magnesium_concentration, 'percent",') ELSE '' END,
            CASE WHEN manganese_concentration IS NOT NULL THEN CONCAT('"manganese_concentration": "', manganese_concentration, 'percent",') ELSE '' END,
            CASE WHEN calcium_concentration IS NOT NULL THEN CONCAT('"calcium_concentration": "', calcium_concentration, 'percent",') ELSE '' END,
            CASE WHEN zinc_concentration IS NOT NULL THEN CONCAT('"zinc_concentration": "', zinc_concentration, 'percent",') ELSE '' END,
            CASE WHEN sodium_concentration IS NOT NULL THEN CONCAT('"sodium_concentration": "', sodium_concentration, 'percent",') ELSE '' END,
            CASE WHEN copper_concentration IS NOT NULL THEN CONCAT('"copper_concentration": "', copper_concentration, 'percent",') ELSE '' END, '}'),
            ',}', '}')::JSONB, -- Remove last comma
            'uf3d7-filter-tilt-shift.svg', CONCAT('variants_', reference_name)
          FROM variants.fertilizers;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, target_specie, indicators, pictogram, translation_id) -- Other articles
          SELECT reference_name, 'article', category, nature, default_unit, target_specie, '{}'::JSONB, pictogram, CONCAT('variants_', reference_name)
          FROM variants.other_articles;

        INSERT INTO master_variants (reference_name, family, category, nature, sub_family, default_unit, indicators, pictogram, translation_id) -- Equipments
          SELECT reference_name, 'equipment', category, nature, sub_family, 'unity', '{}'::JSONB, pictogram, CONCAT('variants_', reference_name)
          FROM variants.equipments;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, indicators, pictogram, translation_id) -- Services
          SELECT reference_name, 'service', category, nature, default_unit, '{}'::JSONB, pictogram, CONCAT('variants_', reference_name)
          FROM variants.services;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, specie, indicators, pictogram, translation_id) -- Crops
          SELECT reference_name, 'crop', category, nature, 'hectare', specie, '{}'::JSONB, 'uf940-seedling-solid.svg', CONCAT('variants_', reference_name)
          FROM variants.crops;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, specie, indicators, pictogram, translation_id) -- Animals
          SELECT reference_name, 'animal', category, nature, 'unity', specie, '{}'::JSONB, pictogram, CONCAT('variants_', reference_name)
          FROM variants.animals;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, specie, target_specie, indicators, pictogram, translation_id) -- Animals
          SELECT reference_name, 'animal', category, nature, 'unity', 'animal_group', derivative_of,
           CONCAT('{"sex ": "', sex, '", ', '"reproductor ": "', reproductor,'"}')::JSONB,
           pictogram, CONCAT('variants_', reference_name)
          FROM variants.animal_groups;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, indicators, pictogram, translation_id) -- Workers
          SELECT reference_name, 'worker', category, nature, 'unity', '{}'::JSONB, 'uf0d5-male.svg', CONCAT('variants_', reference_name)
          FROM variants.workers;

        INSERT INTO master_variants (reference_name, family, category, nature, default_unit, indicators, pictogram, translation_id) -- Zones
          SELECT reference_name, 'zone', category, nature, default_unit, '{}'::JSONB, pictogram, CONCAT('variants_', reference_name)
          FROM variants.zones;
      SQL

      insert_translations('variants', 'categories', 'categories')
      insert_translations('variants', 'natures', 'natures')
      insert_translations('variants', 'farm_products', 'variants')
      insert_translations('variants', 'seeds_and_plants', 'variants')
      insert_translations('variants', 'fertilizers', 'variants')
      insert_translations('variants', 'other_articles', 'variants')
      insert_translations('variants', 'equipments', 'variants')
      insert_translations('variants', 'services', 'variants')
      insert_translations('variants', 'crops', 'variants')
      insert_translations('variants', 'animals', 'variants')
      insert_translations('variants', 'animal_groups', 'variants')
      insert_translations('variants', 'workers', 'variants')
      insert_translations('variants', 'zones', 'variants')

      file = File.new(dir.join('variant_aliases.yml'))
      data = YAML.safe_load(file.read).deep_symbolize_keys
      data.each do |k, v|
        query "UPDATE lexicon.master_variants
               SET name_tags = '{#{v.map{ |s| s.downcase.strip}.join(',')}}'
               WHERE reference_name = '#{k.to_s}'"
      end

    end

  end
end
