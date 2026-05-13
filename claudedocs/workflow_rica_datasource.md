# Workflow — Datasource `rica` (Réseau d'Information Comptable Agricole)

> **Statut :** plan d'implémentation. Aucun code généré à ce stade.
> **Prochaine étape :** lancer `/sc:implement claudedocs/workflow_rica_datasource.md` pour exécuter pas à pas.

---

## 1. Objectif

Créer une datasource `Rica` (`lib/datasources/rica.rb`) qui collecte, charge et normalise les microdonnées comptables agricoles annuelles publiées par le SSP (Service de la statistique et de la prospective). Le périmètre couvre les millésimes 2016 → 2024 disponibles dans `raw/rica/`.

Les données RICA décrivent chaque année quelques milliers d'exploitations échantillonnées, avec ~1000 variables comptables (bilan, compte de résultat, structure, productions, charges, subventions, etc.). Chaque ligne représente une exploitation (`IDNUM`) sur un exercice (`MILEX`).

---

## 2. Analyse de `raw/rica/`

### 2.1 Structure des dossiers (hétérogène — à normaliser)

| Année | Chemin du CSV | Dictionnaire | Modalités | Méthodo |
|------:|---|---|---|---|
| 2016 | `RicaMicroDonnées2016/RICA2016.txt` | `Rica_France_micro_donnees_dictionnaire_2016.txt` | `Rica_France_micro_donnees_modalites_2016.txt` | PDF |
| 2017 | `RicaMicroDonnées2017/RICA2017.csv` (= `.txt`) | `..._dictionnaire_2017.txt` | `..._modalites_2017.txt` | PDF |
| 2018 | `RicaMicroDonnées2018/Rica2018MicroDonnées/RICA2018.csv` | idem | idem | PDF |
| 2019 | `RicaMicrodonnées2019/Rica_France_micro_Donnees_ex2019.csv` | `RICA2019_dictionnaire_modalite_FMD.xlsx` | (intégré au xlsx) | PDF |
| 2020 | `RicaMicrodonnées2020/Rica_France_micro_Donnees_ex2020.csv` | `RICA2020_dictionnaire_modalite_FMD.xlsx` | (intégré) | DOCX |
| 2021 | `RicaMicrodonnées2021/RicaMicrodonnées2021/Rica_France_micro_Donnees_ex2021.csv` | `RICA2021_..._FMD.xlsx` | (intégré) | DOCX |
| 2022 | `RicaMicrodonnées2022/RicaMicrodonnées2022/Rica_France_micro_Donnees_ex2022_corrige.csv` | `RICA2022_..._FMD.xlsx` | (intégré) | DOCX |
| 2023 | `RicaMicrodonnées2023/RicaMicrodonnées2023/Rica_France_micro_Donnees_ex2023.csv` | `RICA2023_dictionnaire_FMD.xlsx` | (intégré) | DOCX |
| 2024 | `RicaMicrodonnées2024/RicaMicrodonnées 2024/Rica_France_micro_Donnees_ex2024.csv` | `RICA2024_dictionnaire_FMD.xlsx` | (intégré) | DOCX |

**Variations à gérer :**
- Majuscules incohérentes (`RicaMicroDonnées` vs `RicaMicrodonnées`).
- Sous-dossiers imbriqués pour 2018, 2021-2024 (parfois avec espace : `"RicaMicrodonnées 2024"`).
- Noms de fichier de données différents (`RICA<YYYY>.txt/csv` vs `Rica_France_micro_Donnees_ex<YYYY>.csv`).
- Dictionnaire : texte semi-colonné jusqu'en 2018, puis Excel (xlsx).

### 2.2 Format des fichiers de données

- **Séparateur :** `;`
- **Encoding :** ASCII pour le CSV de données (uniquement chiffres et codes). Windows-1252 / extended-ASCII pour le dictionnaire (caractères accentués mal encodés, ex. `Libell�`, `num�ro`).
- **Fin de ligne :** CRLF.
- **Largeur :** très large — 985 à 1041 colonnes selon l'année.

### 2.3 Évolution du nombre de colonnes

| Année | Colonnes |
|------:|---------:|
| 2016 | 989 |
| 2017 | 989 |
| 2018 | 989 |
| 2019 | 985 |
| 2020 | 985 |
| 2021 | **1041** |
| 2022 | 988 |
| 2023 | 986 |
| 2024 | 985 |

**Conséquence :** pas de table « large » unique partagée entre années. Il faut soit une table raw par année (option A), soit un schéma long/EAV partagé (option B). Voir §4.

### 2.4 Variables-clés communes (observées dans le dictionnaire 2016)

- `IDNUM` (5) — numéro d'exploitation
- `MILEX` (4) — millésime de l'exercice
- `EXTR2` — coefficient d'extrapolation (poids dans l'échantillon)
- `NREG` / `REGIO` — région administrative
- `ZALTI` / `ZDEFA` / `ZENVI` — zones (altimétrique, défavorisée, environnementale)
- `OTEXE` / `OTE64F` / `OTEFDD` / `OTEFDA` — orientations technico-économiques
- `CDEXE` — classe de dimension économique
- `DCLOTC` — date de clôture d'exercice
- `FJURI` — forme juridique
- `SAUTI` / `SUTOT` — surfaces (SAU, totale)
- `PBRTO` / `EBEXP` / `RESEX` — soldes de gestion (PBR, EBE, résultat)
- … + ~900 autres variables (productions, charges détaillées, capital, financement, animaux par espèce…)

---

## 3. Comparaison avec datasources existantes

La datasource la plus proche est `cadastral_prices.rb` :
- Données multi-années (2021→2025).
- Une table raw par année (`cadastral_prices.cadastral_prices_<year>`).
- Une table cible normalisée unique (`registered_cadastral_prices`) alimentée par boucle annuelle dans `normalize`.
- Pas de téléchargement automatisé pour RICA (accès restreint) → on suit le modèle `Hydrography` pour `collect` (vérifie la présence locale, ne télécharge rien).

Patterns à reprendre :
- Constante `YEARS = [2016, 2017, …, 2024]`.
- Hash `YEAR → { csv_path:, dictionary_path:, sep: ';', encoding: … }` pour absorber l'hétérogénéité.
- `load_csv(file, table, col_sep: ';')` (signature de `Base#load_csv`).

---

## 4. Décisions d'architecture à valider en début d'implémentation

> Ces choix structurent toute la suite. À valider **avant** d'écrire le code (étape 1 du plan).

### Décision 1 — Stockage en lexicon schema

| Option | Avantages | Inconvénients |
|---|---|---|
| **A. Table large par année** : `registered_rica_holdings_<year>` (1 colonne SQL par variable) | Requêtes SQL directes, indexable | ~1000 colonnes → DDL massive et fragile, schéma différent chaque année, migrations lourdes |
| **B. Une table large unique** + UNION ALL avec coercion | Une seule cible | Schéma le plus large (≥1041 cols), beaucoup de NULL, idem fragilité |
| **C. (recommandé) Tall + dictionnaire** : `registered_rica_holdings(year, idnum, region, ote, …, data jsonb)` + `registered_rica_variables(year, code, label, type, length)` + `registered_rica_modalities(year, variable, code, label)` | Schéma stable, ajout d'année trivial, dictionnaire requêtable, JSONB indexable | JSONB un peu plus lent en lecture; il faut documenter les variables-clés extraites en colonnes natives |
| **D. EAV pur** : `registered_rica_values(year, idnum, variable, value)` | Stabilité maximale | Volumétrie x1000 lignes, joints coûteux |

**Proposition retenue dans ce plan : Option C** — extraction des ~15-20 colonnes structurantes en SQL natif (year, idnum, region, ote, sau, etc.) + payload JSONB pour le reste. À confirmer en début d'étape 1.

### Décision 2 — Couverture années

Inclure tous les millésimes présents dans `raw/rica/` (2016 → 2024). À confirmer si certains doivent être exclus (ex. 2016 si données restreintes, ou ne garder que les N derniers).

**Proposition retenue dans ce plan : On conserve tous les millésimes**

### Décision 3 — Source du dictionnaire/modalités

Trois formats coexistent :
- 2016-2018 : `.txt` séparés (dictionnaire + modalités)
- 2019-2024 : `.xlsx` unique combinant dictionnaire et modalités (`*_FMD.xlsx`)

À confirmer : on charge le dictionnaire de **toutes** les années (utile pour suivre l'évolution des libellés) ou uniquement le millésime le plus récent ?

**Proposition retenue dans ce plan : On charge le dictionnaire de toutes les années**

### Décision 4 — Encoding

Le dictionnaire .txt est en Windows-1252 (mojibake détecté). Convertir via `iconv -f WINDOWS-1252 -t UTF-8` dans `collect` ou directement à la lecture. Le CSV de données est ASCII-only (codes numériques), donc pas de conversion nécessaire.

**Proposition retenue dans ce plan : Convertir via `iconv -f WINDOWS-1252 -t UTF-8` dans `collect`**

---

## 5. Plan d'implémentation détaillé

### Phase 1 — Préparation (≤ 30 min)

- [ ] **1.1** Confirmer les 4 décisions d'architecture (§4) avec le responsable produit.
- [ ] **1.2** Lire `lib/datasources/cadastral_prices.rb` et `enterprises.rb` (déjà identifiés comme références) pour aligner le style.
- [ ] **1.3** Vérifier que `csv_loader` accepte `col_sep: ';'` et l'absence d'encoding UTF-8 sur le CSV brut (le loader utilise `psql COPY` → tester encoding `LATIN1` ou `UTF-8`).
- [ ] **1.4** Identifier la liste exacte des colonnes structurantes à promouvoir en colonnes SQL natives (proposition initiale : `idnum, milex, regio, nreg, otexe, ote64f, cdexe, zalti, zdefa, zenvi, fjuri, dclotc, sauti, sutot, pbrto, ebexp, resex, extr2`).

### Phase 2 — Squelette de la datasource (≤ 1h)

- [ ] **2.1** Créer `lib/datasources/rica.rb` héritant de `Datasources::Base`.
- [ ] **2.2** Renseigner `description` et `credits` (provider : SSP / Agreste ; licence à confirmer — Licence Ouverte 2.0 probable).
- [ ] **2.3** Déclarer les constantes :
  - `YEARS = (2016..2024).to_a`
  - `SOURCES = { 2016 => { data: 'RicaMicroDonnées2016/RICA2016.txt', dictionary: 'RicaMicroDonnées2016/Rica_France_micro_donnees_dictionnaire_2016.txt', modalities: '…', dict_format: :txt }, …, 2024 => { data: 'RicaMicrodonnées2024/RicaMicrodonnées 2024/Rica_France_micro_Donnees_ex2024.csv', dictionary: '…/RICA2024_dictionnaire_FMD.xlsx', dict_format: :xlsx } }`
  - `SCHEMA = 'rica'.freeze`

### Phase 3 — `collect` (≤ 30 min)

- [ ] **3.1** Pour chaque année, vérifier la présence du fichier de données et lever une erreur listant les fichiers manquants (cf. pattern `Hydrography#collect` mis à jour récemment).
- [ ] **3.2** Si `dict_format == :txt`, convertir le dictionnaire et le fichier de modalités en UTF-8 vers une copie de travail (`iconv -f WINDOWS-1252 -t UTF-8`).
- [ ] **3.3** Pas de téléchargement réseau (données fournies manuellement).

### Phase 4 — `load` (≤ 1h30)

- [ ] **4.1** `database.ensure_schema(SCHEMA)`.
- [ ] **4.2** Pour chaque année, charger le CSV de données via `load_csv(path, "rica_#{year}", col_sep: ';')` → produit une table raw par millésime (toutes colonnes en `text`).
- [ ] **4.3** Charger le dictionnaire :
  - Format `.txt` (2016-2018) : `load_csv(path, "dictionary_#{year}", col_sep: ';')`.
  - Format `.xlsx` (2019-2024) : `load_xlsx(path)` → table dérivée du nom du classeur. Renommer / standardiser en `dictionary_#{year}` et `modalities_#{year}` via `query "ALTER TABLE …"` si besoin.
- [ ] **4.4** Idem pour les modalités (texte séparé jusqu'en 2018, intégré au xlsx ensuite).

### Phase 5 — `table_definitions` (≤ 1h)

Selon la décision §4.1 (proposition C) :

```ruby
builder.table :registered_rica_holdings, sql: <<-SQL
  CREATE TABLE registered_rica_holdings (
    id SERIAL PRIMARY KEY NOT NULL,
    idnum INTEGER NOT NULL,
    year INTEGER NOT NULL,                  -- millex
    region_code character varying,          -- regio / nreg
    ote_17 character varying,               -- otexe
    ote_64 character varying,               -- ote64f
    economic_dimension_class character varying, -- cdexe
    legal_form character varying,           -- fjuri
    altitude_zone character varying,        -- zalti
    less_favoured_zone character varying,   -- zdefa
    environmental_zone character varying,   -- zenvi
    closing_date date,                      -- dclotc
    sau_ha numeric(10,2),                   -- sauti
    total_area_ha numeric(10,2),            -- sutot
    gross_product numeric(14,2),            -- pbrto
    gross_operating_surplus numeric(14,2),  -- ebexp
    operating_result numeric(14,2),         -- resex
    extrapolation_coefficient numeric(14,4),-- extr2
    data jsonb,                             -- toutes les autres variables
    UNIQUE (idnum, year)
  );
  CREATE INDEX registered_rica_holdings_year ON registered_rica_holdings(year);
  CREATE INDEX registered_rica_holdings_ote_17 ON registered_rica_holdings(ote_17);
  CREATE INDEX registered_rica_holdings_region ON registered_rica_holdings(region_code);
  CREATE INDEX registered_rica_holdings_data ON registered_rica_holdings USING GIN (data);
SQL

builder.table :registered_rica_variables, sql: <<-SQL
  CREATE TABLE registered_rica_variables (
    year INTEGER NOT NULL,
    code character varying NOT NULL,
    label character varying,
    data_type character varying,            -- num / char
    length integer,
    PRIMARY KEY (year, code)
  );
SQL

builder.table :registered_rica_modalities, sql: <<-SQL
  CREATE TABLE registered_rica_modalities (
    year INTEGER NOT NULL,
    variable_code character varying NOT NULL,
    modality_code character varying NOT NULL,
    label character varying,
    PRIMARY KEY (year, variable_code, modality_code)
  );
SQL
```

À ajuster selon décision §4.1.

### Phase 6 — `normalize` (≤ 2h)

- [ ] **6.1** Pour chaque année, INSERT vers `registered_rica_holdings` en mappant les colonnes natives et en construisant `data` via `to_jsonb(rica_<year>.*) - 'idnum' - 'milex' - <autres colonnes natives>` (PostgreSQL — soustraction de clés JSONB).
- [ ] **6.2** Conversion des types `text` → typés au cast (`::INTEGER`, `::NUMERIC`, `TO_DATE(dclotc, 'DDMMYYYY')`). Attention : le format de `DCLOTC` (date de clôture) à confirmer.
- [ ] **6.3** Pour `registered_rica_variables` et `registered_rica_modalities`, INSERT depuis les tables raw correspondantes.
- [ ] **6.4** Logger un compte de lignes insérées par année (cf. pattern `cadastral_prices`).

### Phase 7 — Validation (≤ 1h)

- [ ] **7.1** `./lexicon validate` pour vérifier le schéma vs définitions.
- [ ] **7.2** `./lexicon run rica` complet dans Docker.
- [ ] **7.3** Sanity checks SQL :
  - `SELECT year, COUNT(*) FROM registered_rica_holdings GROUP BY year ORDER BY year;` (≈ 7000-8000 par an attendus).
  - `SELECT * FROM registered_rica_holdings LIMIT 5;` — vérifier types et JSONB cohérents.
  - Vérifier qu'aucune `idnum, year` n'est dupliquée.
  - `SELECT COUNT(DISTINCT variable_code) FROM registered_rica_modalities WHERE year = 2024;`
- [ ] **7.4** Mettre à jour `doc/DATASOURCES.md` si une entrée par datasource y est attendue.
- [ ] **7.5** Vérifier l'inclusion / exclusion dans les flavors (`resources/flavors/*.yml`) — décider quels flavors incluent `registered_rica_*`.

### Phase 8 — Finition (≤ 30 min)

- [ ] **8.1** `./bin/rubocop lib/datasources/rica.rb` (note : `lib/datasources/` est exclu de RuboCop selon `.rubocop.yml` — confirmer).
- [ ] **8.2** Commit en suivant le pattern existant (cf. `15440ee Update hydrography datasource`).

---

## 6. Dépendances et points de vigilance

### Dépendances techniques
- `csv_loader` (`load_csv`) — déjà disponible via `Base`. Supporte `col_sep`.
- `roo_loader` (`load_xlsx`) — déjà disponible via `Base` — requis pour les dictionnaires 2019+.
- `iconv` — disponible dans l'image Docker (à confirmer côté `Dockerfile`).
- `database.ensure_schema` — pattern utilisé par `Hydrography`.

### Points de vigilance
1. **Volumétrie CSV : ~20 MB × 9 ans ≈ 180 MB** → tolérable.
2. **`COPY FROM` et encoding** : si `csv_loader` impose UTF-8, le fichier de données 2016 (ASCII pur) passera mais le dictionnaire (Windows-1252) non. → conversion explicite dans `collect`.
3. **CSV avec ~1000 colonnes** : tester que `psql COPY` (utilisé par `csv_loader`) gère cette largeur ; ajuster `client_min_messages` si nécessaire.
4. **`MILEX` vs `year`** : `MILEX` est dans le CSV (millésime de l'exercice) → préférer cette source plutôt que le nom de fichier.
5. **`DCLOTC` format** : `char(8)` — probablement `DDMMYYYY` ou `YYYYMMDD`. Vérifier sur un échantillon avant cast.
6. **Sous-dossiers à chemins variables** : mieux vaut un hash `SOURCES` que de la résolution magique par glob (limite les surprises).
7. **2017 et 2018 livrent `.txt` ET `.csv` identiques** : ne charger que l'un (choisir `.csv` ou `.txt` cohéremment).
8. **`Rica_France_micro_Donnees_ex2022_corrige.csv`** : le suffixe `_corrige` signale une correction post-publication ; c'est la version à utiliser (pas de fichier original à côté).
9. **Caractères accentués dans les noms de dossier** (`RicaMicrodonnées`) : les paths Ruby les acceptent en UTF-8, mais à tester dans le conteneur (locale).
10. **Données sensibles** : RICA est sous accord de diffusion contrôlé (CASD/SSP). Confirmer que la datasource peut être incluse dans un package public / quel flavor.

---

## 7. Effort estimé

| Phase | Estimation |
|---|---|
| 1. Préparation | 30 min |
| 2. Squelette | 1 h |
| 3. `collect` | 30 min |
| 4. `load` | 1 h 30 |
| 5. `table_definitions` | 1 h |
| 6. `normalize` | 2 h |
| 7. Validation | 1 h |
| 8. Finition | 30 min |
| **Total** | **~7-8 h** (1 journée) |

---

## 8. Critères d'acceptation

- `./lexicon run rica` se termine sans erreur sur les 9 millésimes.
- Les trois tables `registered_rica_holdings`, `registered_rica_variables`, `registered_rica_modalities` existent dans `lexicon` après `normalize`.
- `registered_rica_holdings` contient au moins une ligne pour chaque année 2016-2024.
- Le total de lignes correspond à la somme attendue (à valider sur les méthodologies SSP).
- `./lexicon validate` passe.
- La datasource apparaît dans `./lexicon list`.

---

## 9. Hors scope (à traiter séparément si besoin)

- Téléchargement automatique depuis le portail SSP (accès restreint → manuel).
- Liaison avec `registered_cadastral_*` ou `registered_postal_codes` (jointure géographique non incluse ici).
- Calculs agrégés (moyennes par OTE, par région) — domaine applicatif.
- Suppression des millésimes anciens lors de l'ajout d'un nouveau (politique de rétention non spécifiée).
- Documentation utilisateur du dictionnaire en UI.
