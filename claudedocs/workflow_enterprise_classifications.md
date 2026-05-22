# Workflow — Datasource `enterprise_classifications`

**Stratégie :** systematic · **Profondeur :** deep · **Cible :** `lib/datasources/enterprise_classifications.rb`
**Date :** 2026-05-22 · **Auteur du plan :** Claude (sc:workflow)

> ⚠️ Ce document est un **plan d'implémentation uniquement**. Aucun code n'est écrit à ce stade. Utiliser `/sc:implement` après revue pour exécuter le plan.

---

## 1. Contexte & Intention

Ajouter une nouvelle source de données `enterprise_classifications` qui regroupe les référentiels de classification des entreprises agricoles utilisés par les statistiques publiques françaises et européennes :

| Référentiel | Origine | Description |
|---|---|---|
| **NAF rév. 2** (sous-ensemble agricole) | INSEE | Codes NAF retenus comme « activités agricoles enregistrées » — sections A (agriculture/sylvi/pêche) + extraits IAA et énergie (`08.93Z` sel, `35.11Z` électricité, codes 10.xx / 11.xx pour l'agroalimentaire). |
| **OTEX v2** (15 + 64 codes) | Agreste / SSP — *Bilan annuel de l'emploi agricole n° 235*, Annexe 2 | Orientation Technico-Économique des Exploitations. Hiérarchie à deux niveaux : 15 regroupements (`1500`, `1600`…) → 64 codes détaillés (`1510`, `1520`…). |
| **Correspondance OTEX → NAF** | Source mixte (préparée manuellement) | Pour chaque code OTEX, la (ou les) classes NAF associées. Plusieurs NAF par OTEX possibles (relation 1-N). |

### Caractéristiques des sources (vérifiées)

| Fichier | Encodage | Sép. | Lignes utiles | Particularités |
|---|---|---|---|---|
| `data/enterprise_classifications/naf_rev2_ag.csv` | UTF-8 | `,` | 59 (hors en-tête) | Colonnes `code,label`. Aucune valeur manquante. |
| `data/enterprise_classifications/otex_v2.pdf` | PDF binaire (21 p.) | — | 64 codes (Annexe 2, p. 92-94) | À convertir en CSV **une seule fois** (extraction manuelle assistée). Le CSV produit est commité dans `data/`, et le PDF reste pour traçabilité. |
| `data/enterprise_classifications/otex_naf.csv` | UTF-8 | `,` | 63 (hors en-tête) | Colonnes `otex_code,otex_label,naf_codes,naf_labels`. Les multi-NAF sont sérialisés par `;` dans `naf_codes` et `naf_labels`. La ligne `9000` (« Exploitations non classées ») a `naf_codes`/`naf_labels` vides. |

### Décisions de conception

1. **PDF → CSV en *one-shot* hors pipeline.** Le PDF n'est pas téléchargeable de façon stable et ses tableaux sont graphiquement complexes. Plutôt qu'embarquer une dépendance (`pdfplumber`, `tabula`) dans le pipeline `collect`, on produit **une fois** le fichier `data/enterprise_classifications/otex_v2.csv` à partir du PDF, et on le commite. Le datasource ne fait que copier ce CSV → cohérent avec le pattern « source statique » de [`Datasources::LegalPositions`](../lib/datasources/legal_positions.rb).
   - **Pourquoi pas générer à `collect` ?** Le PDF est versionné (édition 2014 du n° 235) ; sa structure ne change pas. Réextraire à chaque run = surcoût zéro-bénéfice + introduction d'une dépendance fragile (`tabula-py` ou `pdftotext`) côté image Docker.
   - **Traçabilité** : le PDF reste dans `data/` à côté du CSV pour audit. Mention dans `credits` + `README`.

2. **Trois tables `registered_*` distinctes** plutôt qu'une seule table fusionnée :
   - `registered_agricultural_naf_codes` — référentiel NAF retenu (PK = `code`).
   - `registered_agricultural_otex_codes` — référentiel OTEX (PK = `code`), avec colonnes `parent_code` / `parent_label` pour matérialiser la hiérarchie 15→64.
   - `registered_agricultural_naf_otex_codes` — table d'association N:N (FK vers les deux précédentes).
   - **Pourquoi** : les usages consommateurs (Ekylibre) ont besoin de pouvoir interroger chacun des référentiels indépendamment, et la cardinalité OTEX↔NAF est 1-N côté OTEX et 1-N côté NAF (la même classe NAF apparaît dans plusieurs OTEX). Joindre dans une seule table noierait la sémantique.

3. **Préfixe `registered_agricultural_*`** (et non `master_*`) — aligné sur la convention observée :
   - `master_*` → tables référentielles internes Ekylibre (legal_positions, accounts, varieties…).
   - `registered_*` → données issues d'organismes officiels/externes (`registered_msa_populations`, `registered_postal_codes`, `registered_rica_holdings`, `registered_cap_beneficiaries`…). Les classifications NAF (INSEE) et OTEX (Agreste) entrent dans cette seconde catégorie.

4. **Hiérarchie OTEX matérialisée par colonnes plates** (`parent_code`, `parent_label`) plutôt que table parente séparée, parce que :
   - Seulement 15 parents → coût de duplication négligeable (~64 lignes × 2 colonnes courtes).
   - Évite une 4ᵉ table et un join de plus pour les requêtes typiques (« quelle est la grande famille de cet OTEX ? »).
   - Le code parent peut être identique au code lui-même quand l'OTEX est seul dans son groupe (p. ex. `4500 - Bovins lait` est à la fois groupe et code détaillé).

5. **Pas de jointure dure via FK SQL** entre la table de correspondance et les deux référentiels. Cohérent avec le reste du projet où l'intégrité référentielle est laissée à la couche applicative (cf. `registered_cap_beneficiaries`, qui ne FK pas vers `registered_postal_codes`). On ajoute en revanche des index sur les colonnes de jointure.

6. **Flavors** :
   - Inclus par défaut dans tous les flavors (référentiel léger : ~200 lignes au total).
   - Ajouter une entrée dans `resources/flavors/test.yml` pour filtrer à un petit sous-ensemble (p. ex. `WHERE code LIKE '01.%'` pour la table NAF). Pas de modification de `light.yml`, `cultia.yml`, etc.

---

## 2. Architecture cible

### 2.1 Fichiers à créer / modifier

| Action | Chemin | Rôle |
|---|---|---|
| **Créer** | `lib/datasources/enterprise_classifications.rb` | Définition de la datasource (auto-découverte Zeitwerk) |
| **Créer** | `data/enterprise_classifications/otex_v2.csv` | Extrait du PDF, commité (one-shot manuel) |
| **Conserver** | `data/enterprise_classifications/naf_rev2_ag.csv` | Déjà présent |
| **Conserver** | `data/enterprise_classifications/otex_naf.csv` | Déjà présent |
| **Conserver** | `data/enterprise_classifications/otex_v2.pdf` | Conservé pour traçabilité, jamais lu par le pipeline |
| **Modifier** | `resources/flavors/test.yml` | Ajouter filtres pour réduire le volume en test |

> Note : `lib/datasources/` est auto-découvert (Zeitwerk) — pas d'enregistrement manuel requis. Aucune modification de `Lexicon::Application#register_services` n'est nécessaire.

### 2.2 Génération du CSV OTEX (one-shot, hors pipeline)

Le PDF est `data/enterprise_classifications/otex_v2.pdf`, Annexe 2 (pages 92-94 du document, soit pages PDF 6-8). Structure : 2 colonnes par tableau :
- **Colonne gauche** : code de regroupement (15 valeurs) + libellé du groupe.
- **Colonne droite** : sous-codes (64 valeurs) + libellé détaillé.

**Procédure manuelle recommandée pendant `/sc:implement`** (à exécuter une seule fois) :

1. Extraction texte assistée des pages 6-8 du PDF (`pdftotext -layout` ou lecture multi-page Claude).
2. Construire un CSV avec en-têtes : `code,label,parent_code,parent_label`.
3. Pour chaque ligne de sous-code (colonne droite), renseigner :
   - `code` = sous-code (4 chiffres).
   - `label` = libellé détaillé (colonne droite).
   - `parent_code` = code de regroupement de la rangée (colonne gauche).
   - `parent_label` = libellé du regroupement.
4. Pour les groupes qui n'ont qu'un sous-code identique (`4500`, `4600`, `4700`, `4840`), `code == parent_code` et `label == parent_label`.
5. **Inclure le code `9000 - Exploitations non classées`** (visible page 94) avec `parent_code = '9000'`, `parent_label = 'Exploitations non classées'` (terminologie auto-référente, car non listé dans les 15 regroupements affichés).

**Résultat attendu** : ~64 lignes + en-tête.

**Validation** : croiser avec `otex_naf.csv` — chaque `otex_code` y figurant doit avoir un `code` correspondant dans `otex_v2.csv`. Le code `1650` (« Exploitations spécialisées en culture de coton »), présent dans le PDF mais **absent** de `otex_naf.csv`, est conservé dans le référentiel OTEX (il aura simplement zéro ligne de correspondance NAF).

### 2.3 Tables raw (créées implicitement par `load_csv`)

Le helper `load_csv` (cf. `lib/datasources/base.rb:59`) délègue au `csv_loader` qui crée la table cible avec toutes les colonnes en `VARCHAR`, dans le schéma `enterprise_classifications`.

| Table raw | Issue de | Colonnes (après normalisation des en-têtes) |
|---|---|---|
| `enterprise_classifications.naf_rev2_ag` | `naf_rev2_ag.csv` | `code`, `label` |
| `enterprise_classifications.otex_v2` | `otex_v2.csv` (généré) | `code`, `label`, `parent_code`, `parent_label` |
| `enterprise_classifications.otex_naf` | `otex_naf.csv` | `otex_code`, `otex_label`, `naf_codes`, `naf_labels` |

### 2.4 Tables lexicon cibles

```sql
-- Référentiel NAF agricole
CREATE TABLE registered_agricultural_naf_codes (
  code character varying PRIMARY KEY NOT NULL,
  label jsonb NOT NULL
);

-- Référentiel OTEX (64 codes détaillés + hiérarchie à 15 parents)
CREATE TABLE registered_agricultural_otex_codes (
  code character varying PRIMARY KEY NOT NULL,
  label jsonb NOT NULL,
  parent_code character varying NOT NULL,
  parent_label jsonb NOT NULL
);
CREATE INDEX registered_agricultural_otex_codes_parent_code
  ON registered_agricultural_otex_codes(parent_code);

-- Correspondance OTEX <-> NAF (N:N éclaté ligne par ligne)
CREATE TABLE registered_agricultural_naf_otex_codes (
  id SERIAL PRIMARY KEY NOT NULL,
  otex_code character varying NOT NULL,
  naf_code character varying NOT NULL,
  UNIQUE (otex_code, naf_code)
);
CREATE INDEX registered_agricultural_naf_otex_codes_otex_code
  ON registered_agricultural_naf_otex_codes(otex_code);
CREATE INDEX registered_agricultural_naf_otex_codes_naf_code
  ON registered_agricultural_naf_otex_codes(naf_code);
```

**Justifications** :

- **`label jsonb` plutôt que `varchar`** : aligné sur `master_legal_positions.name` et la majorité des tables référentielles Lexicon (multilingue par construction). Format `{"fra": "<libellé>"}`, anglais ajoutable ultérieurement sans migration de schéma.
- **PK textuelle sur `code`** pour NAF et OTEX : les codes sont stables et publics, sert directement pour les jointures applicatives.
- **`registered_agricultural_naf_otex_codes` éclaté ligne par ligne** : `otex_naf.csv` stocke les NAF multiples sérialisées (`01.21Z;01.42Z;…`). On dénormalise via `SPLIT` + `UNNEST` pendant le `normalize` → une ligne par couple (OTEX, NAF). C'est ce que cherchera côté ERP. Une `UNIQUE (otex_code, naf_code)` empêche les doublons.
- **Pas de FK explicite** vers les référentiels NAF/OTEX (cf. décision 5 §1). Les index couvrent les jointures.

---

## 3. Implémentation du datasource (squelette de référence)

> Cette section est **descriptive**. `/sc:implement` produira le fichier réel.

```ruby
module Datasources
  class EnterpriseClassifications < Base
    description 'Classifications des entreprises agricoles : codes NAF agricoles (INSEE) et OTEX (Agreste)'
    credits name: 'NAF rév. 2 (sous-ensemble agricole) et OTEX v2',
            url: 'https://www.insee.fr/fr/information/2120875',
            provider: 'INSEE / Agreste-SSP',
            licence: 'Licence Ouverte 2.0',
            licence_url: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence',
            updated_at: '2026-05-22'

    FILES = {
      'naf_rev2_ag.csv' => 'naf_rev2_ag',
      'otex_v2.csv'     => 'otex_v2',
      'otex_naf.csv'    => 'otex_naf'
    }.freeze

    def collect
      FILES.each_key do |filename|
        FileUtils.cp("data/enterprise_classifications/#{filename}", dir)
      end
    end

    def load
      FILES.each do |filename, table|
        load_csv(dir.join(filename), table)
      end
    end

    def self.table_definitions(builder)
      builder.table :registered_agricultural_naf_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_naf_codes (
          code character varying PRIMARY KEY NOT NULL,
          label jsonb NOT NULL
        );
      SQL

      builder.table :registered_agricultural_otex_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_otex_codes (
          code character varying PRIMARY KEY NOT NULL,
          label jsonb NOT NULL,
          parent_code character varying NOT NULL,
          parent_label jsonb NOT NULL
        );
        CREATE INDEX registered_agricultural_otex_codes_parent_code
          ON registered_agricultural_otex_codes(parent_code);
      SQL

      builder.table :registered_agricultural_naf_otex_codes, sql: <<-SQL
        CREATE TABLE registered_agricultural_naf_otex_codes (
          id SERIAL PRIMARY KEY NOT NULL,
          otex_code character varying NOT NULL,
          naf_code character varying NOT NULL,
          UNIQUE (otex_code, naf_code)
        );
        CREATE INDEX registered_agricultural_naf_otex_codes_otex_code
          ON registered_agricultural_naf_otex_codes(otex_code);
        CREATE INDEX registered_agricultural_naf_otex_codes_naf_code
          ON registered_agricultural_naf_otex_codes(naf_code);
      SQL
    end

    def normalize
      query <<-SQL
        INSERT INTO registered_agricultural_naf_codes (code, label)
          SELECT code, jsonb_build_object('fra', label)
          FROM enterprise_classifications.naf_rev2_ag
      SQL

      query <<-SQL
        INSERT INTO registered_agricultural_otex_codes (code, label, parent_code, parent_label)
          SELECT code,
                 jsonb_build_object('fra', label),
                 parent_code,
                 jsonb_build_object('fra', parent_label)
          FROM enterprise_classifications.otex_v2
      SQL

      query <<-SQL
        INSERT INTO registered_agricultural_naf_otex_codes (otex_code, naf_code)
          SELECT otex_code, trim(naf)
          FROM enterprise_classifications.otex_naf,
               UNNEST(string_to_array(naf_codes, ';')) AS naf
          WHERE naf_codes IS NOT NULL AND trim(naf_codes) <> ''
          ON CONFLICT (otex_code, naf_code) DO NOTHING
      SQL
    end
  end
end
```

### Points d'attention pour l'implémenteur

1. **Nom de colonne `label` vs `name`** : la convention Lexicon est mixte. `master_legal_positions` utilise `name`, `master_attachment_point_natures` utilise `name`, mais les tables de classification de données externes (codes INSEE etc.) utilisent souvent `label`. Choisi `label` ici car c'est un libellé descriptif d'un code, pas un nom propre. À confirmer avec l'équipe en cas de divergence avec une convention locale non écrite.

2. **`UNNEST` sur chaîne séparée `;`** : PostgreSQL natif via `string_to_array(col, ';')`. Pas besoin d'extension. Le `trim()` gère les espaces parasites éventuels.

3. **Ligne `9000` dans `otex_naf.csv`** : `naf_codes` est vide → la clause `WHERE naf_codes IS NOT NULL AND trim(naf_codes) <> ''` l'exclut proprement. Le code `9000` reste présent dans `registered_agricultural_otex_codes` mais n'a aucune ligne dans la table d'association — comportement correct.

4. **Code `1650` (coton)** : présent dans `otex_v2.csv` (extrait du PDF) mais absent de `otex_naf.csv`. Il sera donc dans `registered_agricultural_otex_codes` sans correspondance NAF — c'est le résultat voulu.

5. **Doublons potentiels OTEX→NAF** : la même classe NAF peut apparaître dans plusieurs OTEX (p. ex. `01.13Z` apparaît dans 1610, 1620, 1630, 2811, 2821, 2831…). Le `UNIQUE (otex_code, naf_code)` est sur le couple, donc pas de problème.

6. **Cohérence référentielle (validation post-load)** : ajouter (optionnel) une assertion en fin de `normalize` qui vérifie que tous les `naf_code` de la table d'association existent dans `registered_agricultural_naf_codes`. Si la validation échoue, lever une erreur explicite. Voir `lib/datasources/cap_beneficiaries.rb` pour le pattern.

---

## 4. Mise à jour des flavors

### `resources/flavors/test.yml` — ajouter :

```yaml
enterprise_classifications:
  registered_agricultural_naf_codes:
    filter: WHERE code LIKE '01.%' ORDER BY code
  registered_agricultural_otex_codes:
    filter: WHERE code IN ('1510', '4500', '9000') ORDER BY code
  registered_agricultural_naf_otex_codes:
    filter: WHERE otex_code IN ('1510', '4500') ORDER BY id
```

Aucune modification de `light.yml`, `cultia.yml`, `ekyagri.yml`, `ekyviti.yml`, `full.yml`, `innovation.yml`, `natais.yml`, `pv.yml`, `sydec.yml` — le référentiel est léger et utile partout.

---

## 5. Plan d'exécution séquentiel (pour `/sc:implement`)

| # | Phase | Action | Validation |
|---|---|---|---|
| 1 | **Préparation données** | Générer `data/enterprise_classifications/otex_v2.csv` depuis le PDF (extraction texte assistée + édition manuelle). En-têtes `code,label,parent_code,parent_label`. | `wc -l otex_v2.csv` ≈ 65 (64 lignes + en-tête). Tous les codes de `otex_naf.csv` ont une ligne correspondante. |
| 2 | **Datasource Ruby** | Créer `lib/datasources/enterprise_classifications.rb` selon le squelette §3. | `./lexicon list` doit faire apparaître `enterprise_classifications`. |
| 3 | **Run collect** | `./lexicon collect enterprise_classifications` | Trois CSV présents dans `raw/enterprise_classifications/`. |
| 4 | **Run load** | `./lexicon load enterprise_classifications` | Tables raw créées dans schéma `enterprise_classifications` ; comptes de lignes ≈ 59 / 64 / 63. |
| 5 | **Run normalize** | `./lexicon normalize enterprise_classifications` | Trois tables `registered_agricultural_*` peuplées. |
| 6 | **Validation BD** | Requêtes ad-hoc via `./lexicon console` ou `psql` : vérifier cohérence (cf. assertions §6). | Tous les checks passent. |
| 7 | **Flavors** | Mettre à jour `resources/flavors/test.yml`. | `./lexicon dump all --flavor test` produit un package contenant la table filtrée. |
| 8 | **Validation schéma** | `./lexicon validate` | Aucune erreur de validation. |
| 9 | **Lint** | `./bin/rubocop lib/datasources/enterprise_classifications.rb` | OK (le répertoire est globalement exclu, mais validation manuelle utile). |
| 10 | **Test pipeline complet** | `./lexicon run enterprise_classifications` from scratch (après `./lexicon clean`). | Run complet OK. |

---

## 6. Assertions de validation (à exécuter en §5.6)

```sql
-- 1. Nombre de lignes attendues
SELECT COUNT(*) FROM registered_agricultural_naf_codes;        -- attendu : 59
SELECT COUNT(*) FROM registered_agricultural_otex_codes;       -- attendu : ~64
SELECT COUNT(*) FROM registered_agricultural_naf_otex_codes;   -- attendu : ~120 après UNNEST

-- 2. Hiérarchie OTEX cohérente (parent_code ∈ ensemble des codes attendus)
SELECT DISTINCT parent_code FROM registered_agricultural_otex_codes ORDER BY parent_code;
-- attendu : 1500, 1600, 2800, 2900, 3500, 3900, 4500, 4600, 4700, 4813, 4840,
--          5100, 5200, 5374, 6184, 9000  (16 valeurs, en incluant 9000 auto-référent)

-- 3. Intégrité référentielle (chaque NAF de la table d'association existe dans le référentiel NAF)
SELECT no.naf_code
  FROM registered_agricultural_naf_otex_codes no
  LEFT JOIN registered_agricultural_naf_codes n ON n.code = no.naf_code
  WHERE n.code IS NULL;
-- attendu : 0 ligne ; toute ligne retournée est une incohérence à corriger.

-- 4. Intégrité référentielle (chaque OTEX de l'association existe dans le référentiel OTEX)
SELECT no.otex_code
  FROM registered_agricultural_naf_otex_codes no
  LEFT JOIN registered_agricultural_otex_codes o ON o.code = no.otex_code
  WHERE o.code IS NULL;
-- attendu : 0 ligne.

-- 5. Le code 9000 (non classées) existe dans OTEX mais n'a pas d'association
SELECT COUNT(*) FROM registered_agricultural_naf_otex_codes WHERE otex_code = '9000';
-- attendu : 0

-- 6. Tous les libellés non vides
SELECT COUNT(*) FROM registered_agricultural_naf_codes WHERE label IS NULL OR label = '{}';     -- 0
SELECT COUNT(*) FROM registered_agricultural_otex_codes WHERE label IS NULL OR label = '{}';    -- 0
```

Si **l'assertion #3 échoue**, c'est probablement un code NAF présent dans `otex_naf.csv` mais hors du sous-ensemble agricole de `naf_rev2_ag.csv`. **Décision attendue à ce moment-là** : soit ajouter le code manquant à `naf_rev2_ag.csv` (si pertinent), soit retirer la ligne de `otex_naf.csv` (si l'OTEX référence un NAF non agricole). À examiner cas par cas pendant `/sc:implement`.

---

## 7. Risques & points d'attention

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Extraction PDF imprécise (fautes d'OCR, lignes mal segmentées) | Moyenne | Moyen | Comparer le CSV produit avec le PDF visuellement page par page après extraction. Croiser avec `otex_naf.csv` pour validation croisée des codes. |
| Codes NAF manquants dans `naf_rev2_ag.csv` mais référencés par `otex_naf.csv` | Moyenne | Faible | Assertion §6.3 le détecte. Correction par ajout au CSV NAF ou retrait de l'association. |
| Convention `label` vs `name` divergente d'un standard local non écrit | Faible | Faible | Vérifier auprès de l'équipe ; rename trivial si nécessaire (pas encore consommé). |
| Le PDF est mis à jour côté Agreste avec une nouvelle révision OTEX | Faible | Moyen | Reflet d'une décision politique externe ; déclencher un nouveau cycle `/sc:workflow` à ce moment-là. Pas de mécanisme automatique. |
| Régression sur les flavors existants (rare mais possible si validation globale) | Très faible | Faible | Lancer `./lexicon dump all` sur chaque flavor concerné par le test (`light`, `cultia`, `test`) pour vérifier l'absence d'erreur. |

---

## 8. Hors scope (à NE PAS faire dans ce workflow)

- ❌ Téléchargement automatique du PDF depuis Agreste (URL pas garantie stable, valeur ajoutée nulle vs. fichier statique commité).
- ❌ Liaison FK SQL stricte entre les tables de référentiel et la table d'association — choix architectural projet (cohérence faible inter-tables, gérée côté ERP).
- ❌ Traduction anglaise des libellés — peut être ajoutée plus tard sans migration (champ `jsonb`).
- ❌ Ajout d'une table OTEX parente séparée (`registered_agricultural_otex_groups`) — la dénormalisation choisie suffit pour l'usage prévu ; à reconsidérer si une autre datasource introduit une dépendance vers les 15 groupes.
- ❌ Backfill historique d'autres révisions OTEX (v1) — seule la v2 est demandée.
- ❌ Intégration avec `registered_msa_populations` ou `registered_rica_holdings` — ces tables ont déjà leurs propres colonnes OTEX (`ote_17`, `ote_64`) mais la jointure se fera côté ERP.

---

## 9. Prochaine étape

Lancer `/sc:implement claudedocs/workflow_enterprise_classifications.md` après revue de ce plan. L'implémenteur devra :

1. Réaliser l'extraction PDF→CSV (§2.2) en premier — c'est le bloquant le plus long et le plus à risque humain.
2. Faire valider le CSV `otex_v2.csv` avant de passer aux étapes Ruby.
3. Suivre la séquence §5 étape par étape.
4. Documenter dans le commit le hash SHA-256 du PDF source pour traçabilité (`sha256sum data/enterprise_classifications/otex_v2.pdf`).
