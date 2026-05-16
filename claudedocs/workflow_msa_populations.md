# Workflow — Datasource `msa_populations`

**Stratégie :** systematic · **Profondeur :** deep · **Cible :** `lib/datasources/msa_populations.rb`
**Date :** 2026-05-16 · **Auteur du plan :** Claude (sc:workflow)

> ⚠️ Ce document est un **plan d'implémentation uniquement**. Aucun code n'est écrit à ce stade. Utiliser `/sc:implement` après revue pour exécuter le plan.

---

## 1. Contexte & Intention

Ajouter une nouvelle source de données `msa_populations` qui agrège trois indicateurs MSA (Mutualité Sociale Agricole) par commune INSEE et par année :

| Fichier source | Indicateur | Colonnes utiles |
|---|---|---|
| `COTAS_EMPLOI.csv` | Nouveaux installés (cotisants solidaires/contrats d'emploi) | `Commune 2020`, `Libellé`, `Annee`, `Nb. Contrats` |
| `COTNS_CHEF.csv` | Chefs d'exploitation ou d'entreprise agricole (non salariés) | `Commune 2020`, `Libellé`, `Annee`, `Nb. chefs d'exploit. ou d'entr. Agricole` |
| `RET_STOCK.csv` | Retraités (stocks) salariés et non-salariés agricoles | `Commune 2020`, `Libellé`, `Annee`, `retraités non-salariés agricoles`, `retraités salariés agricoles` |

### Caractéristiques des fichiers (vérifiées)
- Encodage : **ISO-8859-15 / Latin-1** (`Libellé`, `Clémenciat`, `Ambérieu` ne sont pas UTF-8 valides en l'état).
- Séparateur : `;`
- Fin de ligne : `CRLF`
- Marqueur de valeur manquante : la chaîne littérale `N/A - secret statistique` → à convertir en `NULL` lors de la normalisation.
- Année embarquée dans la donnée (colonne `Annee`), pas dans le nom de fichier — la table normalisée doit être indexée par couple `(insee_code, year)`.

### Décisions de conception

1. **Localisation des fichiers source.** `raw/` est gitignored et normalement repeuplé par `collect`. Pour rendre la source de données reproductible, on déplace les CSV dans **`data/msa_populations/`** (commité) et `collect` les copie vers `dir` — pattern identique à `Datasources::Budgets` (voir `lib/datasources/budgets.rb:7`).
2. **Schéma cible.** Une **table large unique** `registered_msa_populations` clé `(insee_code, year)` plutôt que trois tables ou format long, parce que :
   - Les trois indicateurs partagent la dimension `(commune, année)`.
   - L'ERP consommateur (Ekylibre) interrogera typiquement « pour cette commune, quels indicateurs MSA ? » — c'est un usage join-friendly.
   - Les années peuvent diverger d'un fichier à l'autre ; `FULL OUTER JOIN` lors du `normalize` gère la divergence.
3. **Pas de jointure dure** avec `registered_postal_codes` au niveau schéma : on garde `insee_code` comme `VARCHAR` indexé pour join applicatif côté ERP (cohérent avec `postal_codes.rb`).
4. **Pas de flavor exclusion** ajouté dans `resources/flavors/` — la table reste incluse partout par défaut (équivalent au comportement de `cadastral_prices`). Si un flavor doit l'exclure plus tard, ce sera un patch séparé.

---

## 2. Architecture cible

### 2.1 Fichiers à créer / modifier

| Action | Chemin | Rôle |
|---|---|---|
| **Créer** | `lib/datasources/msa_populations.rb` | Définition de la datasource (auto-découverte Zeitwerk) |
| **Créer** | `data/msa_populations/COTAS_EMPLOI.csv` | Données statiques embarquées (déplacement) |
| **Créer** | `data/msa_populations/COTNS_CHEF.csv` | idem |
| **Créer** | `data/msa_populations/RET_STOCK.csv` | idem |
| **Supprimer** | `raw/msa_populations/*.csv` | Une fois la copie effectuée — `raw/` doit redevenir une zone de travail régénérable |

> Note : `lib/datasources/` est auto-découvert (Zeitwerk) — pas d'enregistrement manuel requis. Aucune modification de `Lexicon::Application#register_services` n'est nécessaire.

### 2.2 Tables raw (créées implicitement par `load_csv`)

Le helper `load_csv` (cf. `lib/datasources/base.rb:59`) délègue au `csv_loader` qui crée la table cible avec toutes les colonnes en `VARCHAR`. Les tables raw vivent dans le schéma `msa_populations` (préfixe automatique = nom de la datasource).

| Table raw | Issue de | Colonnes (après normalisation des en-têtes par le loader) |
|---|---|---|
| `msa_populations.cotas_emploi` | `COTAS_EMPLOI.csv` | `commune_2020`, `libelle`, `annee`, `nb_contrats` |
| `msa_populations.cotns_chef` | `COTNS_CHEF.csv` | `commune_2020`, `libelle`, `annee`, `nb_chefs_d_exploit_ou_d_entr_agricole` |
| `msa_populations.ret_stock` | `RET_STOCK.csv` | `commune_2020`, `libelle`, `annee`, `retraites_non_salaries_agricoles`, `retraites_salaries_agricoles` |

> Les noms exacts dépendent de la normalisation effectuée par `Lexicon::Loader::Csv` — à confirmer pendant `/sc:implement` via un `./lexicon load msa_populations` puis inspection avec `./lexicon console`. Si la normalisation produit autre chose, ajuster les `SELECT` du `normalize`.

### 2.3 Table lexicon cible

```sql
CREATE TABLE registered_msa_populations (
  id SERIAL PRIMARY KEY NOT NULL,
  insee_code character varying NOT NULL,
  city_name character varying,
  year integer NOT NULL,
  new_contracts integer,             -- COTAS_EMPLOI (nouveaux installés)
  farm_chiefs integer,               -- COTNS_CHEF
  retired_non_salaried integer,      -- RET_STOCK
  retired_salaried integer,          -- RET_STOCK
  UNIQUE (insee_code, year)
);

CREATE INDEX registered_msa_populations_insee_code ON registered_msa_populations(insee_code);
CREATE INDEX registered_msa_populations_year ON registered_msa_populations(year);
```

Justification colonnes :
- `id SERIAL` — cohérent avec `registered_cadastral_prices` (clé technique stable).
- `UNIQUE (insee_code, year)` — invariant métier : un seul enregistrement par commune et année.
- Quatre colonnes nullable pour les indicateurs : un fichier peut couvrir une année qu'un autre ne couvre pas.

---

## 3. Implémentation du datasource (squelette de référence)

> Cette section est **descriptive**. `/sc:implement` produira le fichier réel.

```ruby
module Datasources
  class MsaPopulations < Base
    description 'MSA populations: retraités, chefs d'exploitation et nouveaux installés par commune'
    credits name: 'Observatoire ESS / Statistiques MSA',
            url: 'https://statistiques.msa.fr/',
            provider: 'Caisse Centrale de la Mutualité Sociale Agricole (CCMSA)',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: '2026-05-16'

    FILES = {
      'COTAS_EMPLOI.csv' => 'cotas_emploi',
      'COTNS_CHEF.csv'   => 'cotns_chef',
      'RET_STOCK.csv'    => 'ret_stock',
    }.freeze

    def collect
      FILES.each_key do |filename|
        FileUtils.cp("data/msa_populations/#{filename}", dir)
      end
    end

    def load
      FILES.each do |filename, table|
        load_csv(dir.join(filename), table, col_sep: ';', encoding: 'ISO-8859-15')
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_msa_populations, sql: <<-SQL
        CREATE TABLE registered_msa_populations (
          id SERIAL PRIMARY KEY NOT NULL,
          insee_code character varying NOT NULL,
          city_name character varying,
          year integer NOT NULL,
          new_contracts integer,
          farm_chiefs integer,
          retired_non_salaried integer,
          retired_salaried integer,
          UNIQUE (insee_code, year)
        );
        CREATE INDEX registered_msa_populations_insee_code ON registered_msa_populations(insee_code);
        CREATE INDEX registered_msa_populations_year ON registered_msa_populations(year);
      SQL
    end

    def normalize
      query <<-SQL
        WITH cleaned_cotas AS (
          SELECT commune_2020 AS insee, libelle AS city, annee::int AS year,
                 NULLIF(NULLIF(nb_contrats, 'N/A - secret statistique'), '')::int AS value
            FROM msa_populations.cotas_emploi
        ),
        cleaned_chef AS (
          SELECT commune_2020 AS insee, libelle AS city, annee::int AS year,
                 NULLIF(NULLIF(nb_chefs_d_exploit_ou_d_entr_agricole, 'N/A - secret statistique'), '')::int AS value
            FROM msa_populations.cotns_chef
        ),
        cleaned_ret AS (
          SELECT commune_2020 AS insee, libelle AS city, annee::int AS year,
                 NULLIF(NULLIF(retraites_non_salaries_agricoles, 'N/A - secret statistique'), '')::int AS non_sal,
                 NULLIF(NULLIF(retraites_salaries_agricoles, 'N/A - secret statistique'), '')::int AS sal
            FROM msa_populations.ret_stock
        ),
        merged AS (
          SELECT insee, MAX(city) AS city, year,
                 MAX(new_contracts) AS new_contracts,
                 MAX(farm_chiefs)   AS farm_chiefs,
                 MAX(retired_non_salaried) AS retired_non_salaried,
                 MAX(retired_salaried)     AS retired_salaried
            FROM (
              SELECT insee, city, year, value AS new_contracts,
                     NULL::int AS farm_chiefs, NULL::int AS retired_non_salaried, NULL::int AS retired_salaried
                FROM cleaned_cotas
              UNION ALL
              SELECT insee, city, year, NULL, value, NULL, NULL FROM cleaned_chef
              UNION ALL
              SELECT insee, city, year, NULL, NULL, non_sal, sal FROM cleaned_ret
            ) u
           GROUP BY insee, year
        )
        INSERT INTO registered_msa_populations
          (insee_code, city_name, year, new_contracts, farm_chiefs, retired_non_salaried, retired_salaried)
          SELECT insee, city, year, new_contracts, farm_chiefs, retired_non_salaried, retired_salaried
            FROM merged;
      SQL
    end
  end
end
```

**Points subtils à vérifier pendant l'implémentation :**
- Les noms exacts des colonnes produits par `load_csv` (le loader nettoie/snake_case les en-têtes — confirmer via `\d msa_populations.cotas_emploi` dans `./lexicon console`).
- L'argument `encoding:` est passé au CSV loader ; vérifier qu'il est bien supporté (sinon, pré-convertir avec `iconv` dans `collect`).
- La signature de `load_csv` accepte `col_sep` mais pas formellement `encoding` dans `base.rb:59` — **regarder `lib/lexicon/loader/csv*.rb`** pour confirmer. Si non supporté, alternative : `execute("iconv -f ISO-8859-15 -t UTF-8 #{src} > #{utf8}")` dans `collect`.

---

## 4. Phases d'exécution & checkpoints

### Phase 1 — Préparation des données statiques *(estimation : 5 min)*

- **Tâche 1.1** Créer le répertoire `data/msa_populations/`.
- **Tâche 1.2** Déplacer (et non copier — éviter la duplication) les trois CSV depuis `raw/msa_populations/` vers `data/msa_populations/`.
- **Tâche 1.3** Vérifier que `.gitignore` ne couvre pas `data/msa_populations/` (regarder `.gitignore` racine — `raw/` est attendu ignoré, `data/` ne devrait pas l'être).
- ✅ **Checkpoint :** `git status` montre les 3 CSV en `Untracked` sous `data/msa_populations/`.

### Phase 2 — Écriture du datasource *(estimation : 20 min)*

- **Tâche 2.1** Créer `lib/datasources/msa_populations.rb` selon le squelette §3.
- **Tâche 2.2** Vérifier que Zeitwerk charge bien la classe : `./lexicon list | grep msa_populations`.
- ✅ **Checkpoint :** `msa_populations` apparaît dans `./lexicon list`.

### Phase 3 — Validation collect + load *(estimation : 10 min)*

- **Tâche 3.1** Lancer `./lexicon collect msa_populations` → vérifier que `raw/msa_populations/*.csv` est repeuplé depuis `data/`.
- **Tâche 3.2** Lancer `./lexicon load msa_populations` → vérifier sans erreur d'encodage.
- **Tâche 3.3** Dans `./lexicon console`, inspecter :
  ```ruby
  database.query("SELECT * FROM msa_populations.cotas_emploi LIMIT 3")
  database.query("SELECT * FROM msa_populations.cotns_chef LIMIT 3")
  database.query("SELECT * FROM msa_populations.ret_stock LIMIT 3")
  ```
  → confirmer (a) les en-têtes accentués sont lisibles, (b) les noms de colonnes effectifs.
- ✅ **Checkpoint :** Les 3 tables raw existent, contiennent des données, accents corrects.
- ⚠️ **Si encodage cassé :** revenir en 2.1 et ajouter une étape `iconv` dans `collect` ; relancer.

### Phase 4 — Ajustement et validation normalize *(estimation : 20 min)*

- **Tâche 4.1** Ajuster les noms de colonnes dans la requête `normalize` selon ce que Phase 3.3 a révélé.
- **Tâche 4.2** Lancer `./lexicon normalize msa_populations`.
- **Tâche 4.3** Vérifier la qualité de la sortie :
  ```sql
  SELECT COUNT(*), COUNT(DISTINCT insee_code), MIN(year), MAX(year) FROM registered_msa_populations;
  SELECT * FROM registered_msa_populations WHERE insee_code = '01001';
  SELECT COUNT(*) FROM registered_msa_populations
    WHERE new_contracts IS NULL AND farm_chiefs IS NULL
      AND retired_non_salaried IS NULL AND retired_salaried IS NULL;
  -- doit retourner 0 (sinon des lignes vides ont passé le filtre)
  ```
- ✅ **Checkpoint :** Table peuplée, contrainte `UNIQUE` respectée, valeurs `secret statistique` converties en NULL.

### Phase 5 — Validation globale & dump *(estimation : 10 min)*

- **Tâche 5.1** `./lexicon validate` → la nouvelle table doit être conforme au schéma déclaré.
- **Tâche 5.2** Sanity : `./lexicon run msa_populations` complet (depuis zéro) doit être idempotent.
- **Tâche 5.3** (optionnel) `./lexicon dump msa_populations` pour vérifier l'export.
- ✅ **Checkpoint final :** Pipeline complet vert, données dans `lexicon.registered_msa_populations`.

### Phase 6 — Documentation & commit *(estimation : 5 min)*

- **Tâche 6.1** Mettre à jour le `README.md` (déjà modifié — la modif courante doit-elle inclure cette source ? À vérifier).
- **Tâche 6.2** Commit séparé : un commit pour les fichiers `data/`, un pour le datasource (clarté de revue).
- ✅ Demander confirmation utilisateur avant le commit (instruction CLAUDE.md : ne pas commiter sans demande explicite).

---

## 5. Carte des dépendances

```
Phase 1 (data/)
   │
   ▼
Phase 2 (datasource file) ─── dépend Zeitwerk autoload (rien à modifier)
   │
   ▼
Phase 3 (collect + load) ─── dépend Phase 1 + 2 + container DI (csv_loader)
   │
   ▼
Phase 4 (normalize) ─── dépend noms colonnes confirmés en 3.3
   │
   ▼
Phase 5 (validate + dump) ─── dépend table_definitions correctes
   │
   ▼
Phase 6 (doc + commit)
```

Aucune phase n'est parallélisable utilement — chaîne strictement séquentielle. Estimation totale : **~70 min** (hors imprévu d'encodage).

---

## 6. Risques & mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| `load_csv` ne supporte pas `encoding:` | Moyenne | Bloquant load | Pré-convertir avec `iconv` dans `collect` (cf. §3 note) |
| Noms de colonnes générés différents de ceux prévus | Élevée | Requête `normalize` casse | Inspection obligatoire en Phase 3.3 avant d'écrire la requête définitive |
| Doublons `(insee, year)` au sein d'un fichier | Faible | Violation `UNIQUE` | Le `GROUP BY` du CTE `merged` absorbe naturellement les doublons via `MAX()` |
| Codes INSEE Corse (`2A`/`2B`) ou DOM non gérés | Faible | Données manquantes | `insee_code VARCHAR` — pas de cast int, donc OK par construction |
| `raw/msa_populations/` toujours présent après déplacement | Faible | Confusion | Supprimer explicitement en Phase 1.2 |

---

## 7. Critères d'acceptation

- [ ] `./lexicon list` affiche `msa_populations` avec sa description.
- [ ] `./lexicon run msa_populations` s'exécute de bout en bout sans erreur depuis une base vide.
- [ ] `registered_msa_populations` contient ≥ 30 000 lignes (ordre de grandeur : ~35 000 communes × années couvertes ÷ couverture moyenne).
- [ ] Aucune ligne avec les 4 colonnes indicateurs à NULL.
- [ ] Les valeurs `N/A - secret statistique` apparaissent comme `NULL` (pas comme chaîne).
- [ ] Les caractères accentués (`Clémenciat`, `Ambérieu`) sont stockés correctement.
- [ ] `./lexicon validate` est vert.

---

## 8. Hors-périmètre (à ne PAS faire dans ce ticket)

- Jointure dure / FK avec `registered_postal_codes` — laissé pour usage applicatif.
- Géocodage / enrichissement spatial — pas de besoin exprimé.
- Filtre par flavor — table incluse partout par défaut.
- Pipeline de mise à jour automatique depuis le portail MSA — pour l'instant, données statiques en `data/`.
- Tables séparées par indicateur — décidé en faveur de la table large unique (§1).

---

## 9. Prochaine étape

Lancer `/sc:implement claudedocs/workflow_msa_populations.md` pour exécuter le plan phase par phase. Recommandation : exécuter avec confirmation à chaque checkpoint (Phases 3.3 et 4.3 surtout, où les hypothèses de colonnes raw doivent être validées).
