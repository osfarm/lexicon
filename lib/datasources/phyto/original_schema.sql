DROP SCHEMA IF EXISTS phyto CASCADE;

CREATE SCHEMA phyto;

-- CREATE UNLOGGED TABLE phytodata_tmp.version (
--   date INTEGER PRIMARY KEY
-- );

CREATE UNLOGGED TABLE phyto.phyto (
  product_code CHAR(8) PRIMARY KEY,
  name VARCHAR(80),
  nature VARCHAR(10),
  maaid VARCHAR(25),
  detailed_usage_packaging VARCHAR(10),
  usage_packaging VARCHAR(10),
  formulation VARCHAR(10),
  firm_name INTEGER,
  in_premises_reentry_delay INTEGER,
  in_field_reentry_delay INTEGER,
  seed_treatment BOOLEAN,
  organic_product BOOLEAN,
  toxicity VARCHAR(100),
  environnemental_indice VARCHAR(50),
  end_of_use_date VARCHAR(10),
  unknonw_1 VARCHAR(30),
  unknonw_2 VARCHAR(30),
  unknonw_3 VARCHAR(30),
  unknonw_4 VARCHAR(30),
  unknonw_5 VARCHAR(30),
  unknonw_6 VARCHAR(30),
  unknonw_7 VARCHAR(30),
  caution_text VARCHAR(10),
  unknonw_8 BOOLEAN
);

CREATE UNLOGGED TABLE phyto.type_phyto (
  code VARCHAR(10) PRIMARY KEY,
  text VARCHAR(80),
  class VARCHAR(3)
);

CREATE UNLOGGED TABLE phyto.usage (
  product_code CHAR(8),
  culture INTEGER,
  cible INTEGER,
  treatment INTEGER,
  dose_quantity REAL,
  dose_unit INTEGER,
  znt INTEGER,
  znt_info VARCHAR(500),
  znt_terr_zone_cultivee VARCHAR(255),
  znt_terr_zone_non_cultivee VARCHAR(255),
  applications_count INTEGER,
  applications_frequency VARCHAR(500),
  info_avant_dar VARCHAR(255),
  pre_harvest_delay VARCHAR(100),
  stade_limite_info VARCHAR(500),
  stade_limite VARCHAR(20),
  stade_debut VARCHAR(20),
  stade_fin VARCHAR(20),
  info_apres_dar TEXT,
  dre_animaux VARCHAR(255),
  dre_animaux_comment VARCHAR(50),
  abeilles VARCHAR(255),
  zone_vegetalisee VARCHAR(255),
  recommandations VARCHAR(255),
  unknown_06 VARCHAR(10),
  unknown_07 VARCHAR(10),
  unknown_08 VARCHAR(100),
  unknown_09 VARCHAR(10),
  unknown_10 VARCHAR(255),
  unknown_11 VARCHAR(10),
  unknown_12 VARCHAR(255),
  unknown_13 VARCHAR(10),
  unknown_14 VARCHAR(255),
  unknown_15 VARCHAR(10),
  unknown_16 VARCHAR(10),
  unknown_17 VARCHAR(10),
  unknown_18 VARCHAR(10)
);

CREATE UNLOGGED TABLE phyto.formulation (
  code CHAR(2) PRIMARY KEY,
  text VARCHAR(100)
);

CREATE UNLOGGED TABLE phyto.firme (
  code INTEGER PRIMARY KEY,
  name VARCHAR(100),
  address_1 VARCHAR(100),
  address_2 VARCHAR(100),
  zip_code CHAR(7),
  city VARCHAR(100),
  web VARCHAR(100)
);

CREATE UNLOGGED TABLE phyto.culture (
  code INTEGER PRIMARY KEY,
  nom VARCHAR(100)
);

CREATE UNLOGGED TABLE phyto.cible (
  code INTEGER PRIMARY KEY,
  cible VARCHAR(255),
  type_cible INTEGER
);

CREATE UNLOGGED TABLE phyto.type_cible (
  code INTEGER PRIMARY KEY,
  nom VARCHAR(20)
);

CREATE UNLOGGED TABLE phyto.traitement (
  code INTEGER PRIMARY KEY,
  phrase VARCHAR(100)
);

CREATE UNLOGGED TABLE phyto.unite_usage (
  code INTEGER PRIMARY KEY,
  unite VARCHAR(30)
);

CREATE UNLOGGED TABLE phyto.clp_phyto (
  product_code CHAR(8),
  code VARCHAR(100)
);

CREATE UNLOGGED TABLE phyto.clp (
  code VARCHAR(100) PRIMARY KEY,
  libelle VARCHAR(700),
  type_phrase VARCHAR(2)
);

CREATE UNLOGGED TABLE phyto.phrase (
  code VARCHAR(100) PRIMARY KEY,
  phrase VARCHAR(700),
  classe VARCHAR(2)
);

CREATE UNLOGGED TABLE phyto.phrase_phyto (
  product_code CHAR(8),
  phrase VARCHAR(20)
);