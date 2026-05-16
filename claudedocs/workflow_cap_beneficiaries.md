# Workflow — Datasource `cap_beneficiaries` (Bénéficiaires des subventions PAC)

> **Statut :** plan d'implémentation. Aucun code généré à ce stade.
> **Prochaine étape :** lancer `/sc:implement claudedocs/workflow_cap_beneficiaries.md` pour exécuter étape par étape.

---

## 1. Objectif

Créer une datasource `CapBeneficiaries` (`lib/datasources/cap_beneficiaries.rb`) qui charge et normalise la liste des bénéficiaires des aides PAC (Politique Agricole Commune) publiée annuellement par l'État français. Le millésime initialement couvert est **2024** (campagne FEAGA/FEADER 2023-2024), à partir de `raw/cap_beneficiaries/cap_beneficiaries_2024.csv`.

Valeur ajoutée principale : **faire le lien `SIREN` ↔ `registered_enterprises`** déjà chargé par la datasource `enterprises` (base SIRENE). Le `SIREN` du bénéficiaire PAC sert de clé de jointure pour enrichir le bénéficiaire avec son adresse, ses établissements, son code APE et ses coordonnées géographiques.

---

## 2. Analyse de la source

### 2.1 Fichier source

| Élément | Valeur |
|---|---|
| Chemin | `raw/cap_beneficiaries/cap_beneficiaries_2024.csv` |
| Taille | 1 616 819 lignes (1 ligne d'en-tête + 1 616 818 lignes de données) |
| Lignes "bénéficiaire" (SIREN renseigné) | ~284 575 |
| Lignes "opération" (SIREN vide, intervention renseignée) | ~1 332 243 |
| Séparateur | `,` |
| Encodage | UTF-8 |
| Quotage | guillemets doubles (texte avec virgules, accents et apostrophes typographiques `’`) |

### 2.2 Schéma du fichier (18 colonnes)

| # | En-tête FR | Description | Type cible |
|--:|---|---|---|
| 1 | `Nom du bénéficiaire / entité légale / association` | Raison sociale ou nom personne physique | text |
| 2 | `Prénom du bénéficiaire` | Prénom (personne physique uniquement) | text |
| 3 | `Nom de la société` | Souvent vide (redondant avec col. 1) | text |
| 4 | `Numéro de SIREN` | **9 chiffres** — clé métier | varchar(9) |
| 5 | `Nom de la commune` | Commune du siège (texte libre, MAJUSCULES) | text |
| 6 | `Code nomenclature intervention UE` | Code de l'intervention (ex. `08020401`) | varchar |
| 7 | `Type d'intervention UE` | Libellé court (ex. `I.1 - Aide de base au revenu...`) | text |
| 8 | `Objectifs spécifiques de l'intervention` | Description longue de l'objectif | text |
| 9 | `Date de début de l'intervention` | ISO `YYYY-MM-DD` | date |
| 10 | `Date de fin de l'intervention` | ISO `YYYY-MM-DD` | date |
| 11 | `Montant FEAGA pour l'opération et pour le bénéficiaire` | Montant FEAGA par opération | numeric(14,2) |
| 12 | `Montant FEAGA total pour le bénéficiaire` | Total FEAGA bénéficiaire (présent sur ligne en-tête uniquement) | numeric(14,2) |
| 13 | `Montant FEADER pour l'opération et pour le bénéficiaire` | Montant FEADER par opération | numeric(14,2) |
| 14 | `Montant FEADER total pour le bénéficiaire` | Total FEADER bénéficiaire | numeric(14,2) |
| 15 | `Montant cofinancé pour l'opération et pour le bénéficiaire` | Cofinancement national par opération | numeric(14,2) |
| 16 | `Montant cofinancé total pour le bénéficiaire` | Total cofinancement bénéficiaire | numeric(14,2) |
| 17 | `Montant total FEADER et cofinancé pour le bénéficiaire` | Total FEADER + cofinancé bénéficiaire | numeric(14,2) |
| 18 | `Montant total financé par l'UE et cofinancé pour le bénéficiaire` | Grand total UE + cofinancé | numeric(14,2) |

### 2.3 Structure hiérarchique (clé du chargement)

Le CSV alterne deux types de lignes :

**Ligne A — en-tête bénéficiaire** (cols 1-5 + 12,14,16,17,18 renseignées, cols 6-11,13,15 vides) :
```csv
"2'S EQUI-NATURE",,,"518602826",NEUSSARGUES EN PINATELLE,,,,,,,8736.92,,4540.49,,2648.63,7189.12,15926.04
```

**Ligne B — opération** (cols 1-5 + 12,14,16,17,18 vides, cols 6-11,13,15 renseignées) :
```csv
,,,,,"08020401",I.1 - Aide de base au revenu...,L'aide de base...,2023-04-29,2023-12-13,3967.71,,0.00,,0.00,,,
```

Chaque bénéficiaire = 1 ligne A suivie de N lignes B. Cette hiérarchie **n'est exprimée que par l'ordre des lignes** — aucun identifiant ne relie une opération à son bénéficiaire. Le pipeline doit donc **propager (forward-fill)** `SIREN` / nom / commune sur les lignes B avant ou pendant la normalisation.

### 2.4 Particularités à gérer

- Apostrophes typographiques (`’`, U+2019) dans les libellés — pas un problème pour PostgreSQL mais à valider en encoding UTF-8.
- Virgules à l'intérieur de champs texte → toujours quotés, le `csv_loader` (psql COPY) gère ça.
- Les communes sont en texte libre, sans code INSEE → pas de jointure fiable directe vers `administrative_areas`. La jointure géographique passera par `registered_enterprises.city` (lui-même issu de la base SIRENE) ou par le code postal de l'établissement principal.
- Le millésime 2024 mélange dates 2023 (campagne) et 2024 (paiement). On le considère comme **année de publication 2024**.

---

## 3. Datasource de référence et choix d'architecture

### 3.1 Comparaison

| Datasource | Pertinent ? | Pourquoi |
|---|---|---|
| `enterprises.rb` | ✅ source du SIREN à joindre, fournit `registered_enterprises(siren)` indexé |
| `rica.rb` | ✅ même pattern « fichier déjà fourni dans `raw/`, pas de téléchargement » + multi-table normalisée + tables `registered_*` |
| `cadastral_prices.rb` | ⚠️ pattern par année (multi-CSV) — utile si on étend à plusieurs millésimes plus tard |

**Choix :** s'inspirer de `rica.rb` pour le pattern « collect en no-op (fichier déjà présent, on valide juste son existence) » et pour la structure multi-table avec `registered_*`.

### 3.2 Modèle de données cible (2 tables `registered_*`)

```
registered_cap_beneficiaries     ←  une ligne par (SIREN × year)
       │
       │ siren (varchar 9)
       │
       ├──► registered_cap_subsidies     ←  une ligne par opération
       │
       └──► [jointure externe] registered_enterprises.siren
                                      (1 SIREN → N établissements)
```

**Pourquoi deux tables plutôt qu'une seule ?**
- Les totaux par bénéficiaire (cols 12,14,16,17,18) sont **redondants** sur chaque ligne d'opération — les éclater dans une seule table dénormalisée gaspillerait l'espace et créerait des incohérences.
- Beaucoup de cas d'usage côté Ekylibre ne s'intéressent qu'au montant agrégé par exploitation (filtrage, classement) → table dédiée plus rapide.
- Les opérations sont une dimension analytique distincte (par code intervention, par dates) → table dédiée.

**Pas de clé étrangère vers `registered_enterprises`** :
- Les tables `registered_*` sont versionnées et dumpées par flavor — une FK croiserait deux datasources avec des cycles de vie indépendants (ex. flavor `light` exclut `enterprises`).
- Tous les bénéficiaires PAC n'ont pas forcément un établissement dans la tranche d'APE agricole filtrée par `enterprises` (CODES_APE).
- Le `siren` est conservé comme **colonne indexée** ; la jointure se fait à la requête.

---

## 4. Étapes d'implémentation

### Étape 0 — Préparation (à valider)

- [ ] Confirmer que `raw/cap_beneficiaries/cap_beneficiaries_2024.csv` est **commité** dans `data/` ou laissé dans `raw/` (gitignored). Vu la taille (~1.6M lignes, plusieurs centaines de Mo une fois décompressé), **garder dans `raw/`** et documenter la source de téléchargement dans le `credits`.
- [ ] Identifier l'URL officielle de publication (data.gouv.fr / Agence de Services et de Paiement) pour la note `credits`. À défaut, marquer `url: nil` et documenter manuellement.

### Étape 1 — Squelette de la datasource

Créer `lib/datasources/cap_beneficiaries.rb` :

```ruby
module Datasources
  class CapBeneficiaries < Base
    LAST_UPDATED = "2024-12-31" # à ajuster selon la date de publication réelle
    SCHEMA = 'cap_beneficiaries'.freeze
    YEARS = [2024].freeze

    description "Bénéficiaires des subventions de la Politique Agricole Commune (PAC) — FEAGA & FEADER"
    credits name: 'Bénéficiaires des aides de la PAC',
            url: 'https://www.data.gouv.fr/fr/datasets/...',  # TODO confirmer
            provider: 'Agence de Services et de Paiement (ASP)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: LAST_UPDATED

    def collect; end       # cf. Étape 2
    def load; end          # cf. Étape 3
    def normalize; end     # cf. Étape 5
    def self.table_definitions(builder); end  # cf. Étape 4
  end
end
```

Zeitwerk auto-découvre la classe — pas de registre à modifier.

### Étape 2 — `collect` : validation + pré-traitement (forward-fill)

Deux options pour propager SIREN sur les lignes d'opération.

**Option A — Pré-traitement Ruby dans `collect` (recommandée)**
- Lire le CSV ligne par ligne, maintenir un état `current_siren / current_name / current_commune / current_totals`.
- Écrire un CSV nettoyé `cap_beneficiaries_2024_filled.csv` avec SIREN propagé sur chaque ligne + colonne `row_kind` (`'beneficiary'` ou `'operation'`).
- Avantage : la table raw devient directement requêtable, pas besoin de fenêtre SQL sur l'ordre des lignes (l'ordre n'est pas garanti après COPY).
- Coût : ~10-15 s, IO-bound, < 500 Mo en mémoire (streaming).

**Option B — Forward-fill en SQL avec `row_number`**
- Ajouter une colonne `row_index BIGSERIAL` à la table raw, propager via `last_value(... IGNORE NULLS) OVER (ORDER BY row_index)`.
- Plus fragile : repose sur la stabilité d'ordre de COPY, et le SQL devient lourd.

**Décision : Option A.** Sketch :

```ruby
def collect
  src = dir.join('cap_beneficiaries_2024.csv')
  raise "Missing #{src}" unless File.exist?(src)

  dst = dir.join('cap_beneficiaries_2024_filled.csv')
  preprocess(src, dst)
end

private

def preprocess(src, dst)
  current = { siren: nil, name: nil, firstname: nil, company: nil,
              commune: nil, feaga_total: nil, feader_total: nil,
              cofinanced_total: nil, total_feader_cof: nil, total_eu_cof: nil }

  CSV.open(dst, 'wb') do |out|
    out << OUTPUT_HEADERS  # cf. table_definitions
    CSV.foreach(src, headers: true) do |row|
      if row['Numéro de SIREN'].to_s.strip != ''
        current[:siren]            = row['Numéro de SIREN'].strip
        current[:name]             = row['Nom du bénéficiaire / entité légale / association']
        current[:firstname]        = row['Prénom du bénéficiaire']
        current[:company]          = row['Nom de la société']
        current[:commune]          = row['Nom de la commune']
        current[:feaga_total]      = row['Montant FEAGA total pour le bénéficiaire']
        current[:feader_total]     = row['Montant FEADER total pour le bénéficiaire']
        current[:cofinanced_total] = row['Montant cofinancé total pour le bénéficiaire']
        current[:total_feader_cof] = row['Montant total FEADER et cofinancé pour le bénéficiaire']
        current[:total_eu_cof]     = row['Montant total financé par l\'UE et cofinancé pour le bénéficiaire']
        out << beneficiary_output_row(current)
      else
        out << operation_output_row(current, row)
      end
    end
  end
end
```

### Étape 3 — `load` : ingestion dans le schéma `cap_beneficiaries`

```ruby
def load
  database.ensure_schema(SCHEMA)
  load_csv(dir.join('cap_beneficiaries_2024_filled.csv'),
           'cap_beneficiaries_2024',
           col_sep: ',')
end
```

Le `csv_loader` crée automatiquement la table raw en inspectant l'en-tête. Pour éviter les noms de colonnes FR avec accents/espaces dans le schéma raw, on émet en sortie de l'étape 2 un en-tête en **snake_case ASCII** :

```
row_kind, siren, beneficiary_name, beneficiary_firstname, company_name, commune,
intervention_code, intervention_label, intervention_objective,
intervention_start_date, intervention_end_date,
feaga_amount, feaga_total, feader_amount, feader_total,
cofinanced_amount, cofinanced_total, total_feader_cofinanced, total_eu_cofinanced
```

### Étape 4 — `table_definitions` : tables `registered_*`

```ruby
def self.table_definitions(builder)
  builder.table :registered_cap_beneficiaries, sql: <<-SQL
    CREATE TABLE registered_cap_beneficiaries (
      id SERIAL PRIMARY KEY NOT NULL,
      siren character varying(9) NOT NULL,
      year integer NOT NULL,
      beneficiary_name character varying,
      beneficiary_firstname character varying,
      company_name character varying,
      commune character varying,
      feaga_total numeric(14,2),
      feader_total numeric(14,2),
      cofinanced_total numeric(14,2),
      total_feader_cofinanced numeric(14,2),
      total_eu_cofinanced numeric(14,2),
      UNIQUE (siren, year)
    );

    CREATE INDEX registered_cap_beneficiaries_siren ON registered_cap_beneficiaries(siren);
    CREATE INDEX registered_cap_beneficiaries_year ON registered_cap_beneficiaries(year);
    CREATE INDEX registered_cap_beneficiaries_commune ON registered_cap_beneficiaries(commune);
  SQL

  builder.table :registered_cap_subsidies, sql: <<-SQL
    CREATE TABLE registered_cap_subsidies (
      id SERIAL PRIMARY KEY NOT NULL,
      siren character varying(9) NOT NULL,
      year integer NOT NULL,
      intervention_code character varying NOT NULL,
      intervention_label character varying,
      intervention_objective text,
      intervention_start_date date,
      intervention_end_date date,
      feaga_amount numeric(14,2),
      feader_amount numeric(14,2),
      cofinanced_amount numeric(14,2)
    );

    CREATE INDEX registered_cap_subsidies_siren ON registered_cap_subsidies(siren);
    CREATE INDEX registered_cap_subsidies_year ON registered_cap_subsidies(year);
    CREATE INDEX registered_cap_subsidies_intervention_code ON registered_cap_subsidies(intervention_code);
    CREATE INDEX registered_cap_subsidies_siren_year ON registered_cap_subsidies(siren, year);
  SQL
end
```

**Choix justifiés :**
- Pas de FK `registered_cap_subsidies → registered_cap_beneficiaries` (datasources versionnées indépendamment ; cohérence assurée à la normalisation via les SIREN partagés du même CSV).
- `UNIQUE (siren, year)` sur les bénéficiaires : un SIREN ne devrait apparaître qu'une fois par millésime. À vérifier sur les données → si doublons, fallback `ON CONFLICT DO UPDATE` qui somme les totaux.
- `intervention_objective` en `text` (descriptions parfois > 1 ko).
- Pas d'unicité stricte sur `registered_cap_subsidies` : un même bénéficiaire peut avoir plusieurs paiements sous le même code intervention (dates différentes).

### Étape 5 — `normalize` : peuplement des tables

```ruby
def normalize
  YEARS.each do |year|
    logger.debug "Normalizing CAP beneficiaries #{year}..."
    insert_beneficiaries(year)
    logger.debug "Normalizing CAP subsidies #{year}..."
    insert_subsidies(year)
  end
end

private

def insert_beneficiaries(year)
  query <<~SQL
    INSERT INTO registered_cap_beneficiaries
      (siren, year, beneficiary_name, beneficiary_firstname, company_name, commune,
       feaga_total, feader_total, cofinanced_total,
       total_feader_cofinanced, total_eu_cofinanced)
    SELECT
      siren,
      #{year},
      MAX(beneficiary_name),
      MAX(beneficiary_firstname),
      MAX(company_name),
      MAX(commune),
      MAX(NULLIF(feaga_total, '')::numeric(14,2)),
      MAX(NULLIF(feader_total, '')::numeric(14,2)),
      MAX(NULLIF(cofinanced_total, '')::numeric(14,2)),
      MAX(NULLIF(total_feader_cofinanced, '')::numeric(14,2)),
      MAX(NULLIF(total_eu_cofinanced, '')::numeric(14,2))
    FROM #{SCHEMA}.cap_beneficiaries_#{year}
    WHERE row_kind = 'beneficiary' AND siren IS NOT NULL AND siren <> ''
    GROUP BY siren
    ON CONFLICT (siren, year) DO NOTHING
  SQL
end

def insert_subsidies(year)
  query <<~SQL
    INSERT INTO registered_cap_subsidies
      (siren, year, intervention_code, intervention_label, intervention_objective,
       intervention_start_date, intervention_end_date,
       feaga_amount, feader_amount, cofinanced_amount)
    SELECT
      siren,
      #{year},
      intervention_code,
      intervention_label,
      intervention_objective,
      NULLIF(intervention_start_date, '')::date,
      NULLIF(intervention_end_date, '')::date,
      NULLIF(feaga_amount, '')::numeric(14,2),
      NULLIF(feader_amount, '')::numeric(14,2),
      NULLIF(cofinanced_amount, '')::numeric(14,2)
    FROM #{SCHEMA}.cap_beneficiaries_#{year}
    WHERE row_kind = 'operation'
      AND siren IS NOT NULL AND siren <> ''
      AND intervention_code IS NOT NULL AND intervention_code <> ''
  SQL
end
```

### Étape 6 — Lien `SIREN` ↔ `registered_enterprises`

Aucun changement de schéma. Le lien est documenté et testé via des requêtes types — exposées dans `doc/DATASOURCES.md` et vérifiées en console.

**Requête type 1 — Bénéficiaire avec son adresse SIRENE :**
```sql
SELECT cb.siren, cb.beneficiary_name, cb.commune,
       cb.total_eu_cofinanced,
       re.name AS sirene_name, re.address, re.postal_code, re.city,
       re.french_main_activity_code
FROM   registered_cap_beneficiaries cb
LEFT JOIN registered_enterprises re
       ON re.siren = cb.siren
      AND re.french_main_activity_code LIKE '01.%'  -- siège agricole probable
WHERE  cb.year = 2024;
```

**Requête type 2 — Tous les établissements d'un bénéficiaire :**
```sql
SELECT cb.siren, cb.beneficiary_name,
       re.establishment_number, re.name, re.postal_code, re.city, re.centroid
FROM   registered_cap_beneficiaries cb
JOIN   registered_enterprises re ON re.siren = cb.siren
WHERE  cb.siren = '518602826' AND cb.year = 2024;
```

**Taux de couverture attendu** (à mesurer à l'implémentation) :
```sql
SELECT COUNT(DISTINCT cb.siren) FILTER (WHERE re.siren IS NOT NULL) AS matched,
       COUNT(DISTINCT cb.siren) AS total,
       ROUND(100.0 * COUNT(DISTINCT cb.siren) FILTER (WHERE re.siren IS NOT NULL)
             / COUNT(DISTINCT cb.siren), 2) AS pct
FROM   registered_cap_beneficiaries cb
LEFT JOIN registered_enterprises re ON re.siren = cb.siren
WHERE  cb.year = 2024;
```

> ⚠️ La datasource `enterprises` filtre sur les codes APE agricoles (cf. `CODES_APE` dans `enterprises.rb`). Des bénéficiaires PAC peuvent avoir un siège classé hors APE agricoles (ETA, SCEA en gestion, holdings). Si le taux de couverture est insuffisant (< 80 %), envisager d'élargir `CODES_APE` ou de charger les SIREN non couverts depuis l'API SIRENE en complément (hors scope de cette tâche).

### Étape 7 — Flavors

Mettre à jour `resources/flavors/*.yml` :
- `light.yml` : ajouter `cap_beneficiaries` dans `without:` (cohérent avec l'exclusion de `enterprises` ; les bénéficiaires sans la base SIRENE perdent leur valeur).
- `ekyagri.yml`, `full.yml`, `ekyviti.yml` : à vérifier — la nouvelle datasource est incluse par défaut (les flavors fonctionnent par exclusion). Aucun changement nécessaire **sauf si** une de ces flavors a une liste `without:` qui devrait s'aligner avec le choix `enterprises`.

### Étape 8 — Validation

- [ ] `./lexicon list` montre `cap_beneficiaries` dans la liste.
- [ ] `./lexicon validate` passe (cohérence schéma ↔ `table_definitions`).
- [ ] `./lexicon run cap_beneficiaries` exécute collect + load + normalize sans erreur.
- [ ] Vérifier les comptages :
  - `SELECT COUNT(*) FROM cap_beneficiaries.cap_beneficiaries_2024;` ≈ 1 616 818
  - `SELECT COUNT(*) FROM registered_cap_beneficiaries WHERE year = 2024;` ≈ 280-285 k
  - `SELECT COUNT(*) FROM registered_cap_subsidies WHERE year = 2024;` ≈ 1.3 M
- [ ] Vérifier le taux de couverture SIREN ↔ `registered_enterprises` (requête de l'étape 6).
- [ ] Vérifier qu'un échantillon de 10 SIREN connus retourne le bon bénéficiaire avec ses opérations.

### Étape 9 — Documentation

- [ ] Mettre à jour `doc/DATASOURCES.md` (section sur `cap_beneficiaries` + requêtes types de jointure).
- [ ] Mettre à jour le README si nécessaire (liste des datasources).
- [ ] Pas de changement CLAUDE.md (le pattern reste générique).

### Étape 10 — Linting & commit

- [ ] `./bin/rubocop lib/datasources/cap_beneficiaries.rb` (datasources/ est exclus globalement de rubocop d'après CLAUDE.md, mais on peut faire un passage manuel).
- [ ] Commit unique avec message du type :
  ```
  Add cap_beneficiaries datasource (PAC subsidy beneficiaries 2024)

  - Two tables: registered_cap_beneficiaries (per-SIREN totals)
    and registered_cap_subsidies (per-operation amounts)
  - SIREN column indexed for join with registered_enterprises
  - Exclude from light flavor (depends on enterprises for full value)
  ```

---

## 5. Risques & points d'attention

| Risque | Impact | Mitigation |
|---|---|---|
| Doublons de SIREN dans la ligne en-tête (même SIREN apparaît 2× pour scinder ses aides) | Insert échoue sur UNIQUE | `GROUP BY siren` + `MAX(...)` dans l'INSERT (déjà appliqué) ; valider en amont avec un `SELECT siren, COUNT(*) FROM ... WHERE row_kind='beneficiary' GROUP BY 1 HAVING COUNT(*) > 1` |
| Mémoire CSV.foreach sur 1.6M lignes | OOM si on charge tout | `CSV.foreach` est streaming (ligne par ligne) — pas de risque |
| Encodage des apostrophes `’` | Bug d'affichage | Forcer `encoding: 'UTF-8'` à l'ouverture CSV ; le CSV source est déjà en UTF-8 |
| Communes en texte libre (pas de code INSEE) | Pas de jointure géographique directe | Documenté ; passer par `registered_enterprises.city` ou enrichissement future via `administrative_areas` (fuzzy match hors scope) |
| Taux de couverture SIREN < attendu | Valeur ajoutée réduite | Mesurer à l'étape 6 ; si < 80 %, ouvrir un ticket pour élargir `CODES_APE` |
| Le fichier `cap_beneficiaries_2024.csv` n'est pas commité | Build échoue en CI | Vérifier la stratégie : soit le commiter dans `data/` (si licence le permet et taille raisonnable après compression), soit ajouter une étape `collect` qui télécharge depuis data.gouv.fr |
| Nouvelle structure de fichier l'an prochain | Refactor | Constante `YEARS` + `SOURCES` à la `rica.rb` quand le 2e millésime arrivera |

---

## 6. Estimation

| Étape | Effort estimé |
|---|---|
| 1 — Squelette | 15 min |
| 2 — Pré-traitement CSV (forward-fill) | 1 h |
| 3 — Load | 15 min |
| 4 — `table_definitions` | 30 min |
| 5 — `normalize` | 1 h |
| 6 — Jointure & docs | 45 min |
| 7 — Flavors | 15 min |
| 8 — Validation & tests | 1 h |
| 9 — Documentation | 30 min |
| 10 — Lint & commit | 15 min |
| **Total** | **~5 h 30** |

Premier `./lexicon run cap_beneficiaries` end-to-end attendu : **3-8 min** (CSV pre-process : ~30 s ; COPY : ~1-2 min ; normalize : ~1-2 min ; index : ~30 s).

---

## 7. Hors scope (futurs travaux)

- Téléchargement automatique du fichier annuel depuis data.gouv.fr (`collect` réel).
- Enrichissement par code INSEE de commune (résolution fuzzy `commune` libre → code INSEE).
- Tables agrégées : `registered_cap_subsidies_by_intervention` (totaux par code intervention × département).
- Multi-millésime (2022, 2023, 2025 dès qu'ils seront publiés).
- Vue matérialisée joignant `registered_cap_beneficiaries` × `registered_enterprises` pour des requêtes accélérées.
