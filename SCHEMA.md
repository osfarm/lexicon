# Schema

Structure of all tables in the lexicon schema, grouped by datasource.

---

## agroedi

### registered_agroedi_codes

| Column | Type | Constraints |
|---|---|---|
| `repository_id` | integer | NOT NULL |
| `reference_id` | integer | NOT NULL |
| `reference_code` | character varying | |
| `reference_label` | character varying | |
| `ekylibre_scope` | character varying | |
| `ekylibre_value` | character varying | |

Indexes: `reference_code`

### registered_agroedi_crops

| Column | Type | Constraints |
|---|---|---|
| `agroedi_code` | character varying | NOT NULL |
| `agroedi_name` | character varying | NOT NULL |
| `production` | character varying | |

Foreign keys: `production` → `master_productions.reference_name`

---

## budgets

### master_budgets

| Column | Type | Constraints |
|---|---|---|
| `activity_family` | character varying | NOT NULL |
| `budget_category` | character varying | NOT NULL |
| `variant` | character varying | NOT NULL |
| `mode` | character varying | |
| `proportionnal_key` | character varying | |
| `repetition` | integer | NOT NULL |
| `frequency` | character varying | NOT NULL |
| `start_month` | integer | NOT NULL |
| `quantity` | numeric(8,2) | NOT NULL |
| `unit_pretax_amount` | numeric(8,2) | NOT NULL |
| `tax_rate` | numeric(8,2) | NOT NULL |
| `unit` | character varying | NOT NULL |
| `direction` | character varying | NOT NULL |

Indexes: `variant`  
Foreign keys: `variant` → `master_variants.reference_name`, `unit` → `master_units.reference_name`

---

## cadastral_prices

### registered_cadastral_prices

| Column | Type | Constraints |
|---|---|---|
| `id` | SERIAL | PRIMARY KEY |
| `mutation_id` | character varying | |
| `mutation_date` | date | |
| `mutation_reference` | character varying | |
| `mutation_nature` | character varying | |
| `cadastral_price` | numeric(14,2) | |
| `cadastral_parcel_id` | character varying | |
| `building_nature` | character varying | |
| `building_area` | integer | |
| `cadastral_parcel_area` | integer | |
| `address` | character varying | |
| `postal_code` | character varying | |
| `city` | character varying | |
| `department` | character varying | |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `cadastral_parcel_id`, `department`, `centroid` (GIST)

---

## cadastre

### registered_cadastral_parcels

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `town_insee_code` | character varying | |
| `section_prefix` | character varying | |
| `section` | character varying | |
| `work_number` | character varying | |
| `net_surface_area` | integer | |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `town_insee_code`, `section_prefix`, `section`, `work_number`, `shape` (GIST), `centroid` (GIST)

---

## chart_of_accounts

### master_chart_of_accounts

| Column | Type | Constraints |
|---|---|---|
| `id` | integer | PRIMARY KEY |
| `reference_name` | character varying | |
| `previous_reference_name` | character varying | |
| `fr_pcga` | character varying | |
| `fr_pcg82` | character varying | |
| `name` | jsonb | |

Indexes: `reference_name`

---

## enterprises

### registered_enterprises

| Column | Type | Constraints |
|---|---|---|
| `establishment_number` | character varying | PRIMARY KEY |
| `french_main_activity_code` | character varying | NOT NULL |
| `name` | character varying | |
| `address` | character varying | |
| `postal_code` | character varying | |
| `city` | character varying | |
| `country` | character varying | |
| `centroid` | geometry(Point, 4326) | |

Indexes: `french_main_activity_code`, `name`

---

## eu_market_prices

### registered_eu_market_prices

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `nature` | character varying | |
| `category` | character varying | |
| `specie` | character varying | |
| `production_reference_name` | character varying | |
| `sector_code` | character varying | |
| `product_code` | character varying | |
| `product_label` | character varying | |
| `product_description` | character varying | |
| `unit_value` | integer | |
| `unit_name` | character varying | |
| `country` | character varying | |
| `price` | numeric(8,2) | |
| `start_date` | date | |
| `end_date` | date | |

Indexes: `id`, `category`, `sector_code`, `product_code`

---

## graphic_parcels

### registered_graphic_parcels

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | NOT NULL |
| `cap_crop_code` | character varying | |
| `city_name` | character varying | |
| `shape` | geometry(Polygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `city_name`, `shape` (GIST), `centroid` (GIST)

---

## hydrography

### registered_cadastral_buildings

| Column | Type | Constraints |
|---|---|---|
| `id` | SERIAL | PRIMARY KEY |
| `reference_name` | character varying | |
| `nature` | character varying | |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `reference_name`, `shape` (GIST), `centroid` (GIST)

### registered_area_items

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `name` | jsonb | |
| `nature` | character varying | |
| `point` | geometry(Point, 4326) | |
| `shape` | geometry(MultiPolygon, 4326) | |
| `lines` | geometry(MultiLineString, 4326) | |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `nature`, `shape` (GIST), `point` (GIST), `lines` (GIST), `centroid` (GIST)

### registered_hydrographic_items

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `name` | jsonb | |
| `nature` | character varying | |
| `point` | geometry(Point, 4326) | |
| `shape` | geometry(MultiPolygon, 4326) | |
| `lines` | geometry(MultiLineString, 4326) | |
| `centroid` | geometry(Point, 4326) | |

Indexes: `nature`, `shape` (GIST), `point` (GIST), `lines` (GIST), `centroid` (GIST)

---

## intervention_models

### intervention_models

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `name` | jsonb | |
| `category_name` | jsonb | |
| `number` | character varying | |
| `procedure_reference` | character varying | NOT NULL |
| `working_flow` | numeric(19,4) | |
| `working_flow_unit` | character varying | |

Indexes: `reference_name`, `name`, `procedure_reference`

### intervention_model_items

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `procedure_item_reference` | character varying | NOT NULL |
| `article_reference` | character varying | |
| `indicator_name` | character varying | |
| `indicator_value` | numeric(19,4) | |
| `indicator_unit` | character varying | |
| `intervention_model_id` | character varying | |

Indexes: `reference_name`, `procedure_item_reference`, `article_reference`, `intervention_model_id`  
Foreign keys: `intervention_model_id` → `intervention_models.reference_name`

---

## legal_positions

### master_legal_positions

| Column | Type | Constraints |
|---|---|---|
| `code` | character varying | PRIMARY KEY |
| `name` | jsonb | |
| `nature` | character varying | NOT NULL |
| `country` | character varying | NOT NULL |
| `insee_code` | character varying | NOT NULL |
| `fiscal_positions` | text[] | |

---

## phenological_stages

### master_phenological_stages

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `bbch_code` | character varying | NOT NULL |
| `variety` | character varying | NOT NULL |
| `biaggiolini` | character varying | |
| `eichhorn_lorenz` | character varying | |
| `chasselas_date` | character varying | |
| `label` | jsonb | |
| `description` | jsonb | |

---

## phytosanitary

### registered_phytosanitary_cropsets

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `name` | character varying | NOT NULL |
| `label` | jsonb | |
| `crop_names` | text[] | |
| `crop_labels` | jsonb | |
| `record_checksum` | integer | |

Indexes: `crop_names`

### registered_phytosanitary_products

| Column | Type | Constraints |
|---|---|---|
| `id` | integer | PRIMARY KEY |
| `reference_name` | character varying | NOT NULL |
| `name` | character varying | NOT NULL |
| `other_names` | text[] | |
| `natures` | text[] | |
| `active_compounds` | text[] | |
| `france_maaid` | character varying | NOT NULL |
| `mix_category_codes` | integer[] | |
| `in_field_reentry_delay` | interval | |
| `state` | character varying | NOT NULL |
| `started_on` | date | |
| `stopped_on` | date | |
| `allowed_mentions` | jsonb | |
| `restricted_mentions` | character varying | |
| `operator_protection_mentions` | text | |
| `firm_name` | character varying | |
| `product_type` | character varying | |
| `record_checksum` | integer | |

Indexes: `name`, `natures`, `france_maaid`, `firm_name`, `reference_name`

### registered_phytosanitary_usages

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `lib_court` | integer | |
| `product_id` | integer | NOT NULL |
| `ephy_usage_phrase` | character varying | NOT NULL |
| `crop` | jsonb | |
| `crop_label_fra` | character varying | |
| `species` | text[] | |
| `target_name` | jsonb | |
| `target_name_label_fra` | character varying | |
| `description` | jsonb | |
| `treatment` | jsonb | |
| `dose_quantity` | numeric(19,4) | |
| `dose_unit` | character varying | |
| `dose_unit_name` | character varying | |
| `dose_unit_factor` | real | |
| `pre_harvest_delay` | interval | |
| `pre_harvest_delay_bbch` | integer | |
| `applications_count` | integer | |
| `applications_frequency` | interval | |
| `development_stage_min` | integer | |
| `development_stage_max` | integer | |
| `usage_conditions` | character varying | |
| `untreated_buffer_aquatic` | integer | |
| `untreated_buffer_arthropod` | integer | |
| `untreated_buffer_plants` | integer | |
| `decision_date` | date | |
| `state` | character varying | NOT NULL |
| `extract_spray_volume_max_quantity` | character varying | |
| `extract_spray_volume_max_unit` | character varying | |
| `spray_volume_max_quantity` | numeric(19,4) | |
| `spray_volume_max_unit` | character varying | |
| `spray_volume_max_unit_name` | character varying | |
| `spray_volume_max_dose_quantity` | numeric(19,4) | |
| `spray_volume_max_dose_unit` | character varying | |
| `spray_volume_max_dose_unit_name` | character varying | |
| `record_checksum` | integer | |

Indexes: `product_id`, `species`

### registered_phytosanitary_risks

| Column | Type | Constraints |
|---|---|---|
| `product_id` | integer | NOT NULL, PK |
| `risk_code` | character varying | NOT NULL, PK |
| `risk_phrase` | character varying | NOT NULL |
| `record_checksum` | integer | |

Indexes: `product_id`

### registered_phytosanitary_symbols

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `symbol_name` | character varying | |

Indexes: `id`, `symbol_name`

### registered_phytosanitary_target_name_to_pfi_targets

| Column | Type | Constraints |
|---|---|---|
| `ephy_name` | character varying | PRIMARY KEY |
| `pfi_id` | integer | |
| `pfi_name` | character varying | |
| `default_pfi_treatment_type_id` | character varying | |

Indexes: `ephy_name`

---

## postal_codes

### registered_postal_codes

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `country` | character varying | NOT NULL |
| `code` | character varying | NOT NULL |
| `city_name` | character varying | NOT NULL |
| `postal_code` | character varying | NOT NULL |
| `city_delivery_name` | character varying | |
| `city_delivery_detail` | character varying | |
| `city_centroid` | geometry(Point, 4326) | |
| `city_shape` | geometry(MultiPolygon, 4326) | |

Indexes: `country`, `city_name`, `postal_code`, `city_centroid` (GIST), `city_shape` (GIST)

---

## prices

### master_prices

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `reference_name` | character varying | NOT NULL |
| `reference_article_name` | character varying | NOT NULL |
| `unit_pretax_amount` | numeric(19,4) | NOT NULL |
| `currency` | character varying | NOT NULL |
| `reference_packaging_name` | character varying | NOT NULL |
| `started_on` | date | NOT NULL |
| `variant_id` | character varying | |
| `packaging_id` | character varying | |
| `usage` | character varying | NOT NULL |
| `main_indicator` | character varying | |
| `main_indicator_unit` | character varying | |
| `main_indicator_minimal_value` | numeric(19,4) | |
| `main_indicator_maximal_value` | numeric(19,4) | |
| `working_flow_value` | numeric(19,4) | |
| `working_flow_unit` | character varying | |
| `threshold_min_value` | numeric(19,4) | |
| `threshold_max_value` | numeric(19,4) | |

Indexes: `reference_name`, `reference_article_name`, `reference_packaging_name`  
Foreign keys: `reference_article_name` → `master_variants.reference_name`, `reference_packaging_name` → `master_packagings.reference_name`

### master_doer_contracts

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `worker_variant` | character varying | NOT NULL |
| `salaried` | boolean | |
| `contract_end` | character varying | |
| `legal_monthly_working_time` | numeric(8,2) | NOT NULL |
| `legal_monthly_offline_time` | numeric(8,2) | NOT NULL |
| `min_raw_wage_per_hour` | numeric(8,2) | NOT NULL |
| `salary_charges_ratio` | numeric(8,2) | NOT NULL |
| `farm_charges_ratio` | numeric(8,2) | NOT NULL |
| `translation_id` | character varying | NOT NULL |

### master_phytosanitary_prices

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `reference_name` | character varying | NOT NULL |
| `reference_article_name` | integer | NOT NULL |
| `unit_pretax_amount` | numeric(19,4) | NOT NULL |
| `currency` | character varying | NOT NULL |
| `reference_packaging_name` | character varying | NOT NULL |
| `started_on` | date | NOT NULL |
| `usage` | character varying | NOT NULL |

Foreign keys: `reference_article_name` → `registered_phytosanitary_products.id`, `reference_packaging_name` → `master_packagings.reference_name`

---

## productions

### master_productions

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `activity_family` | character varying | NOT NULL |
| `specie` | character varying | |
| `usage` | character varying | |
| `started_on` | date | NOT NULL |
| `stopped_on` | date | NOT NULL |
| `agroedi_crop_code` | character varying | |
| `season` | character varying | |
| `life_duration` | interval | |
| `idea_botanic_family` | character varying | |
| `idea_specie_family` | character varying | |
| `idea_output_family` | character varying | |
| `color` | character varying | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`, `specie`, `activity_family`, `agroedi_crop_code`

### master_production_start_states

| Column | Type | Constraints |
|---|---|---|
| `production` | character varying | NOT NULL |
| `year` | integer | NOT NULL |
| `key` | character varying | NOT NULL |

Foreign keys: `production` → `master_productions.reference_name`

### master_crop_production_cap_codes

| Column | Type | Constraints |
|---|---|---|
| `cap_code` | character varying | NOT NULL, PK |
| `cap_label` | character varying | NOT NULL |
| `production` | character varying | NOT NULL, PK |
| `cap_precision` | character varying | |
| `cap_category` | character varying | |
| `is_seed` | boolean | |
| `year` | integer | NOT NULL, PK |

Foreign keys: `production` → `master_productions.reference_name`

### master_crop_production_cap_sna_codes

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `nature` | character varying | NOT NULL |
| `parent` | character varying | |
| `translation_id` | character varying | NOT NULL |

### master_crop_production_tfi_codes

| Column | Type | Constraints |
|---|---|---|
| `tfi_code` | character varying | NOT NULL |
| `tfi_label` | character varying | NOT NULL |
| `production` | character varying | |
| `tfi_crop_group` | character varying | |
| `campaign` | integer | NOT NULL |

Foreign keys: `production` → `master_productions.reference_name`

### master_production_yields

| Column | Type | Constraints |
|---|---|---|
| `department_zone` | character varying | NOT NULL |
| `specie` | character varying | NOT NULL |
| `production` | character varying | NOT NULL |
| `yield_value` | numeric(8,2) | NOT NULL |
| `yield_unit` | character varying | NOT NULL |
| `campaign` | integer | NOT NULL |

Indexes: `specie`, `production`, `campaign`  
Foreign keys: `production` → `master_productions.reference_name`, `specie` → `master_taxonomy.reference_name`

### master_production_prices

| Column | Type | Constraints |
|---|---|---|
| `department_zone` | character varying | NOT NULL |
| `started_on` | date | NOT NULL |
| `nature` | character varying | |
| `price_duration` | interval | NOT NULL |
| `specie` | character varying | NOT NULL |
| `waiting_price` | numeric(8,2) | NOT NULL |
| `final_price` | numeric(8,2) | NOT NULL |
| `currency` | character varying | NOT NULL |
| `price_unit` | character varying | NOT NULL |
| `product_output_specie` | character varying | NOT NULL |
| `production_reference_name` | character varying | |
| `campaign` | integer | |
| `organic` | boolean | |
| `label` | character varying | |

Indexes: `specie`, `department_zone`, `started_on`, `product_output_specie`  
Foreign keys: `specie` → `master_taxonomy.reference_name`

---

## protected_natural_zones

### registered_natural_zones

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | NOT NULL |
| `name` | character varying | |
| `nature` | character varying | NOT NULL |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `nature`, `shape` (GIST), `centroid` (GIST)

---

## protected_water_zones

### registered_protected_water_zones

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | NOT NULL |
| `administrative_zone` | character varying | |
| `creator_name` | character varying | |
| `name` | character varying | |
| `updated_on` | date | |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `shape` (GIST), `centroid` (GIST)

---

## quality_and_origin_signs

### registered_quality_and_origin_signs

| Column | Type | Constraints |
|---|---|---|
| `id` | integer | PRIMARY KEY |
| `ida` | integer | NOT NULL |
| `geographic_area` | character varying | |
| `fr_sign` | character varying | |
| `eu_sign` | character varying | |
| `product_human_name` | jsonb | |
| `product_human_name_fra` | character varying | |
| `reference_number` | character varying | |

---

## seed_varieties

### registered_seed_varieties

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `id_specie` | character varying | NOT NULL |
| `specie_name` | jsonb | |
| `specie_name_fra` | character varying | |
| `variety_name` | character varying | |
| `registration_date` | date | |

Indexes: `id`, `id_specie`  
Foreign keys: `id_specie` → `master_taxonomy.reference_name`

---

## soil

### registered_soil_depths

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `soil_depth_value` | numeric(19,4) | |
| `soil_depth_unit` | character varying | |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `shape` (GIST), `centroid` (GIST)

### registered_soil_available_water_capacities

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `available_water_reference_value` | integer | |
| `available_water_min_value` | numeric(19,4) | |
| `available_water_max_value` | numeric(19,4) | |
| `available_water_unit` | character varying | |
| `available_water_label` | character varying | |
| `shape` | geometry(MultiPolygon, 4326) | NOT NULL |
| `centroid` | geometry(Point, 4326) | |

Indexes: `id`, `shape` (GIST), `centroid` (GIST)

---

## taxonomy

### master_taxonomy

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `parent` | character varying | |
| `taxonomic_rank` | character varying | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

---

## technical_workflow_sequences

### technical_sequences

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `family` | character varying | |
| `production_reference_name` | character varying | NOT NULL |
| `production_system` | character varying | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`, `family`, `production_reference_name`  
Foreign keys: `production_reference_name` → `master_productions.reference_name`

### technical_workflow_sequences

| Column | Type | Constraints |
|---|---|---|
| `technical_sequence_id` | character varying | NOT NULL |
| `year_start` | integer | |
| `year_stop` | integer | |
| `technical_workflow_id` | character varying | NOT NULL |

Indexes: `technical_sequence_id`, `technical_workflow_id`  
Foreign keys: `technical_workflow_id` → `technical_workflows.reference_name`, `technical_sequence_id` → `technical_sequences.reference_name`

---

## technical_workflows

### technical_workflows

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `family` | character varying | |
| `production_reference_name` | character varying | |
| `production_system` | character varying | |
| `start_day` | integer | |
| `start_month` | integer | |
| `unit` | character varying | |
| `life_state` | character varying | |
| `life_cycle` | character varying | |
| `plant_density` | integer | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`, `family`, `production_reference_name`  
Foreign keys: `production_reference_name` → `master_productions.reference_name`

### technical_workflow_procedures

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `position` | integer | NOT NULL |
| `name` | jsonb | NOT NULL |
| `repetition` | integer | |
| `frequency` | character varying | |
| `period` | character varying | |
| `bbch_stage` | character varying | |
| `procedure_reference` | character varying | NOT NULL |
| `technical_workflow_id` | character varying | NOT NULL |

Indexes: `reference_name`, `technical_workflow_id`, `procedure_reference`  
Foreign keys: `technical_workflow_id` → `technical_workflows.reference_name`

### technical_workflow_procedure_items

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `actor_reference` | character varying | |
| `procedure_item_reference` | character varying | |
| `article_reference` | character varying | |
| `quantity` | numeric(19,4) | |
| `unit` | character varying | |
| `procedure_reference` | character varying | NOT NULL |
| `technical_workflow_procedure_id` | character varying | NOT NULL |

Indexes: `reference_name`, `technical_workflow_procedure_id`, `procedure_reference`  
Foreign keys: `technical_workflow_procedure_id` → `technical_workflow_procedures.reference_name`

---

## translations

### master_translations

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `fra` | character varying | NOT NULL |
| `eng` | character varying | NOT NULL |

---

## units

### master_dimensions

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `symbol` | character varying | NOT NULL |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

### master_units

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `dimension` | character varying | NOT NULL |
| `symbol` | character varying | NOT NULL |
| `a` | numeric(25,10) | |
| `d` | numeric(25,10) | |
| `b` | numeric(25,10) | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

### master_packagings

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `capacity` | numeric(25,10) | NOT NULL |
| `capacity_unit` | character varying | NOT NULL |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

---

## user_roles

### master_user_roles

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `accesses` | text[] | |
| `translation_id` | character varying | NOT NULL |

---

## variants

### master_variant_categories

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `family` | character varying | NOT NULL |
| `fixed_asset_account` | character varying | |
| `fixed_asset_allocation_account` | character varying | |
| `fixed_asset_expenses_account` | character varying | |
| `depreciation_percentage` | numeric(5,2) | |
| `purchase_account` | character varying | |
| `sale_account` | character varying | |
| `stock_account` | character varying | |
| `stock_movement_account` | character varying | |
| `default_vat_rate` | numeric(5,2) | |
| `payment_frequency_value` | integer | |
| `payment_frequency_unit` | character varying | |
| `pictogram` | character varying | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

### master_variant_natures

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `family` | character varying | NOT NULL |
| `population_counting` | character varying | NOT NULL |
| `frozen_indicators` | text[] | |
| `variable_indicators` | text[] | |
| `abilities` | text[] | |
| `variety` | character varying | NOT NULL |
| `derivative_of` | character varying | |
| `pictogram` | character varying | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`

### master_variants

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `family` | character varying | NOT NULL |
| `category` | character varying | NOT NULL |
| `nature` | character varying | NOT NULL |
| `sub_family` | character varying | |
| `default_unit` | character varying | NOT NULL |
| `target_specie` | character varying | |
| `specie` | character varying | |
| `indicators` | jsonb | |
| `pictogram` | character varying | |
| `name_tags` | text[] | |
| `translation_id` | character varying | NOT NULL |

Indexes: `reference_name`, `category`, `nature`  
Foreign keys: `category` → `master_variant_categories.reference_name`, `nature` → `master_variant_natures.reference_name`, `target_specie` → `master_taxonomy.reference_name`, `specie` → `master_taxonomy.reference_name`, `default_unit` → `master_units.reference_name`

---

## vine_varieties

### registered_vine_varieties

| Column | Type | Constraints |
|---|---|---|
| `id` | character varying | PRIMARY KEY |
| `short_name` | character varying | NOT NULL |
| `long_name` | character varying | |
| `category` | character varying | NOT NULL |
| `fr_validated` | boolean | |
| `utilities` | text[] | |
| `color` | character varying | |
| `custom_code` | character varying | |

Indexes: `id`

---

## weather

### registered_weather_stations

| Column | Type | Constraints |
|---|---|---|
| `reference_name` | character varying | PRIMARY KEY |
| `country` | character varying | NOT NULL |
| `country_zone` | character varying | NOT NULL |
| `station_code` | character varying | NOT NULL |
| `station_name` | character varying | NOT NULL |
| `elevation` | integer | |
| `centroid` | geometry(Point, 4326) | |

Indexes: `country`, `country_zone`, `reference_name`, `centroid` (GIST)

### registered_hourly_weathers

| Column | Type | Constraints |
|---|---|---|
| `station_id` | character varying | |
| `started_at` | timestamp | |
| `mesured_delay` | interval | |
| `average_temp` | numeric(19,4) | |
| `min_temp` | numeric(19,4) | |
| `max_temp` | numeric(19,4) | |
| `rain` | numeric(19,4) | |
| `max_wind_speed` | numeric(19,4) | |
| `wind_direction` | numeric(19,4) | |
| `frozen_duration` | numeric(19,4) | |
| `humidity` | numeric(19,4) | |
| `soil_state` | character varying | |
| `pressure` | numeric(19,4) | |
| `weather_description` | character varying | |

Indexes: `rain`, `station_id`, `started_at`, `average_temp`, `max_wind_speed`, `pressure`

---

## Récapitulatif

| Datasource | Tables |
|---|---|
| agroedi | registered_agroedi_codes, registered_agroedi_crops |
| budgets | master_budgets |
| cadastral_prices | registered_cadastral_prices |
| cadastre | registered_cadastral_parcels |
| chart_of_accounts | master_chart_of_accounts |
| enterprises | registered_enterprises |
| eu_market_prices | registered_eu_market_prices |
| graphic_parcels | registered_graphic_parcels |
| hydrography | registered_cadastral_buildings, registered_area_items, registered_hydrographic_items |
| intervention_models | intervention_models, intervention_model_items |
| legal_positions | master_legal_positions |
| phenological_stages | master_phenological_stages |
| phytosanitary | registered_phytosanitary_cropsets, registered_phytosanitary_products, registered_phytosanitary_usages, registered_phytosanitary_risks, registered_phytosanitary_symbols, registered_phytosanitary_target_name_to_pfi_targets |
| postal_codes | registered_postal_codes |
| prices | master_prices, master_doer_contracts, master_phytosanitary_prices |
| productions | master_productions, master_production_start_states, master_crop_production_cap_codes, master_crop_production_cap_sna_codes, master_crop_production_tfi_codes, master_production_yields, master_production_prices |
| protected_natural_zones | registered_natural_zones |
| protected_water_zones | registered_protected_water_zones |
| quality_and_origin_signs | registered_quality_and_origin_signs |
| seed_varieties | registered_seed_varieties |
| soil | registered_soil_depths, registered_soil_available_water_capacities |
| taxonomy | master_taxonomy |
| technical_workflow_sequences | technical_sequences, technical_workflow_sequences |
| technical_workflows | technical_workflows, technical_workflow_procedures, technical_workflow_procedure_items |
| translations | master_translations |
| units | master_dimensions, master_units, master_packagings |
| user_roles | master_user_roles |
| variants | master_variant_categories, master_variant_natures, master_variants |
| vine_varieties | registered_vine_varieties |
| weather | registered_weather_stations, registered_hourly_weathers |

**Total : 30 datasources, 56 tables**
