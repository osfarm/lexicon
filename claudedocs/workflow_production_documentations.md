# Workflow — Datasource `production_documentations`

**Stratégie :** systematic · **Profondeur :** deep · **Cible :** `lib/datasources/production_documentations.rb`
**Date :** 2026-05-22 · **Auteur du plan :** Claude (sc:workflow)

> ⚠️ Ce document est un **plan d'implémentation uniquement**. Aucun code n'est écrit à ce stade. Utiliser `/sc:implement` après revue pour exécuter le plan.

---

## 1. Contexte & Intention

Ajouter un datasource `production_documentations` qui produit une table `master_production_documentations` reliant chaque `master_productions.reference_name` à une **URL de documentation externe**. Pour cette première itération, la seule source intégrée est le wiki **Triple Performance** (`https://wiki.tripleperformance.fr`).

Exemple cible (donné par l'utilisateur) :

| production_reference_name | source | url |
|---|---|---|
| `winter_common_wheat` | `tripleperformance` | `https://wiki.tripleperformance.fr/wiki/Bl%C3%A9_tendre` |

### Structure du wiki source (vérifiée par WebFetch)

Le wiki est organisé en deux niveaux :

1. **Page d'accueil Productions** (`/wiki/Productions`) — pointe vers 9 catégories thématiques :
   - Grandes cultures, Élevage, Viticulture, Arboriculture, Maraîchage, PPAM (Plantes à parfum, aromatiques, médicinales), Apiculture, Cultures tropicales, Sylviculture.

2. **Page de catégorie** (ex. `/wiki/Grandes_cultures`) — contient une section « Cultures » avec ~50 vignettes pointant chacune vers une page de production individuelle (ex. `/wiki/Bl%C3%A9_tendre`, `/wiki/Ma%C3%AFs_grain`).

Les URLs des pages individuelles utilisent le titre de page MediaWiki (FR) URL-encodé.

### Échantillon de noms à mettre en correspondance (vérifié en BD)

| `reference_name` | `master_translations.fra` (BD) | URL wiki attendue |
|---|---|---|
| `winter_common_wheat` | Blé tendre d'hiver | `/wiki/Bl%C3%A9_tendre` |
| `spring_common_wheat` | Blé tendre de printemps | `/wiki/Bl%C3%A9_tendre` *(même page que winter)* |
| `winter_hard_wheat` | Blé dur d'hiver | `/wiki/Bl%C3%A9_dur` |
| `grain_corn` | Maïs grain | `/wiki/Ma%C3%AFs_grain` *(match exact)* |
| `silage_corn` | Maïs ensilage | `/wiki/Ma%C3%AFs_ensilage` *(à confirmer côté wiki)* |
| `winter_barley` | Orge d'hiver | `/wiki/Orge` *(probable, page wiki générique)* |
| `buckwheat` | Sarrasin | `/wiki/Sarrasin` *(match exact)* |

→ **Trois cas observés** :
- **a) Match exact** sur `master_translations.fra` (ex. `Sarrasin`, `Maïs grain`).
- **b) Match par préfixe** : la page wiki couvre la culture générique sans seasonality ; plusieurs `reference_name` (spring/winter) pointent vers la même URL.
- **c) Pas de page wiki** pour certaines productions très spécifiques (ex. `popcorn`, `seed_corn`).

---

## 2. Décisions de conception

### 2.1 Préfixe de table : `master_`

`master_production_documentations` — référence interne Ekylibre (jointure sur `master_productions`), aligné sur la convention `master_production_*` déjà en place (`master_production_yields`, `master_production_prices`, `master_production_start_states`).

### 2.2 Colonne `source` pour extensibilité future

Bien que seul Triple Performance soit intégré aujourd'hui, on ajoute une colonne `source` (`character varying`) avec PK composite `(production_reference_name, source)`. Bénéfices :

- Wikipédia, Wikifarmer, Itab, etc. pourront être ajoutés plus tard sans migration de schéma.
- Évite le pattern « une table par source ».
- Coût marginal nul (une colonne courte, un index supplémentaire).

**Alternative écartée** : table dédiée `master_production_tripleperformance_links` — moins extensible, et la couche ERP devra de toute façon agréger les sources côté lecture.

### 2.3 Stratégie de matching `wiki_label` ↔ `master_productions.reference_name`

Trois niveaux, dans cet ordre, appliqués pendant `normalize` :

1. **Manual overrides** (CSV statique commité dans `data/`) — autorité finale, non-écrasable.
2. **Match exact** (normalisé) entre `wiki_label` et `master_translations.fra`.
3. **Match par préfixe** : `master_translations.fra` commence par `wiki_label` + un séparateur d'attribut connu (`" d'"`, `" de "`, `" d’"`, `" du "`). Capture les variantes saisonnières/qualité (« Blé tendre d'hiver » ⊂ « Blé tendre »).

**Normalisation appliquée pour les comparaisons** (sans modifier les valeurs stockées) :
- Trim, collapse des espaces multiples.
- Apostrophe typographique `’` (U+2019) → apostrophe droite `'`.
- Lowercase (les noms FR ne sont pas case-sensitive).
- **Pas** de suppression d'accents : les URL wiki les conservent (URL-encodés), donc on les garde aussi côté BD pour préserver la fidélité.

**Ce qui est volontairement écarté** :
- Levenshtein / similarité floue : trop de faux positifs sur des noms courts.
- Substring match (`wiki_label` apparaît n'importe où dans `fra`) : casse « Mâche » ↔ « Mâche maraîchère » mais surtout produit des faux positifs (« Pomme » match « Pomme de terre »). Skip.

### 2.4 Stockage temporaire : un seul CSV scrapé + un CSV d'overrides

Comme demandé par l'utilisateur, le scraping produit **un fichier temporaire** dans `raw/` (intermédiaire, regénéré à chaque `collect`), et un fichier **statique** dans `data/` (commité, source de vérité pour les overrides manuels).

| Fichier | Statut | Rôle |
|---|---|---|
| `raw/production_documentations/wiki_links.csv` | **Temporaire** (regénéré par `collect`) | Liste exhaustive `(category, fr_label, url_path, url)` extraite du wiki |
| `data/production_documentations/overrides.csv` | **Commité** | Mappings manuels `(production_reference_name, source, url)` — autorité finale |

Le CSV d'overrides est facultatif au démarrage (peut être vide à part l'en-tête). Il se remplit au fil des révisions selon les besoins identifiés par les assertions de validation §6.

### 2.5 Stratégie de crawl

**Approche retenue** : crawl en **deux passes HTTP**.

1. **Passe 1** : `GET /wiki/Productions` → extraire les 9 URLs de catégorie.
2. **Passe 2** : pour chacune des 9 catégories, `GET /wiki/<Catégorie>` → extraire la section « Cultures » (ou équivalente).

**Outils** :
- **`Net::HTTP`** pour les requêtes (stdlib, déjà utilisé dans `agricultural_pictures.rb`).
- **`Nokogiri`** pour le parsing HTML (déjà dans le `Gemfile` du projet, jamais utilisé jusqu'ici par un datasource).
- Pas d'utilisation de l'API MediaWiki (`api.php?action=parse&prop=links`) : retourne les titres mais pas les sections, donc on filtrerait moins finement. L'extraction HTML directe via Nokogiri permet de cibler la section « Cultures » et d'éliminer les liens parasites (navigation, footer, infobox).

**Sélection des liens valides** dans une page de catégorie :
- Liens internes (`href` commence par `/wiki/`).
- Hors namespace MediaWiki (rejet de `/wiki/Catégorie:*`, `/wiki/Spécial:*`, `/wiki/Fichier:*`, `/wiki/Aide:*`, `/wiki/Discussion:*`, `/wiki/Mod%C3%A8le:*`, etc.).
- Hors ancrages internes (`href` ne contient pas `#`, ou alors prendre la partie avant le `#`).
- Hors red links (les pages inexistantes ont la classe `new` — Nokogiri permet de les filtrer via `[not(contains(@class,'new'))]`).
- Texte d'ancrage non vide.

**Politesse réseau** :
- User-Agent identifié (`lexicon-production-documentations`).
- Un sleep court (~200 ms) entre les 9 requêtes de catégorie.
- Pas de rate-limit documenté côté Triple Performance ; le volume (10 GETs total) est négligeable.

### 2.6 Pas de validation HTTP des URLs cibles

Le `collect` ne vérifie pas que chaque URL de production individuelle (~500) résout en 200. Coût/bénéfice défavorable :
- 500 GETs supplémentaires à chaque `collect`.
- Les liens présents sur la page de catégorie sont par construction des liens du wiki (pas des URLs externes).
- Les red links sont déjà filtrés (cf. §2.5).
- Si une URL devient orpheline plus tard, c'est un défaut côté ERP qui sera détecté côté consommateur.

### 2.7 Stockage de l'URL : forme finale `https://...` (vs path relatif)

On stocke l'**URL complète absolue** (`https://wiki.tripleperformance.fr/wiki/Bl%C3%A9_tendre`) plutôt qu'un path relatif (`/wiki/Bl%C3%A9_tendre`). Justifications :
- Le consommateur (ERP) n'a pas à connaître le hostname.
- Le préfixe `https://wiki.tripleperformance.fr` est court ; surcoût négligeable.
- Si une autre source ajoute des liens (cf. §2.2), les URLs sont déjà autonomes.

### 2.8 Flavors

- Inclus par défaut dans tous les flavors — référentiel léger (< 500 lignes, chaque ligne ~150 octets).
- `test.yml` : ajouter un filtre minimal sur quelques productions emblématiques.
- Pas d'exclusion dans `light.yml`, `cultia.yml`, etc.

---

## 3. Architecture cible

### 3.1 Fichiers à créer / modifier

| Action | Chemin | Rôle |
|---|---|---|
| **Créer** | `lib/datasources/production_documentations.rb` | Définition du datasource (auto-découvert par Zeitwerk) |
| **Créer** | `data/production_documentations/overrides.csv` | CSV statique d'overrides manuels (en-tête + lignes optionnelles) |
| **Modifier** | `resources/flavors/test.yml` | Ajouter un filtre minimal |

Aucune modification de `Lexicon::Application#register_services` : Zeitwerk auto-découvre.

### 3.2 Schéma de la table cible

```sql
CREATE TABLE master_production_documentations (
  production_reference_name character varying NOT NULL,
  source                    character varying NOT NULL,
  url                       character varying NOT NULL,
  PRIMARY KEY (production_reference_name, source)
);
CREATE INDEX master_production_documentations_source
  ON master_production_documentations(source);
```

**Pas de FK SQL stricte** vers `master_productions(reference_name)` — cohérent avec le reste du projet (cf. décision similaire dans `workflow_enterprise_classifications.md` §1.5). On ajoute toutefois une assertion §6 vérifiant que chaque ligne référence bien une production existante.

### 3.3 Schéma raw

Le `csv_loader` natif crée la table raw avec toutes les colonnes en `VARCHAR`, dans le schéma `production_documentations`.

| Table raw | Issue de | Colonnes |
|---|---|---|
| `production_documentations.wiki_links` | `wiki_links.csv` (généré par `collect`) | `category`, `fr_label`, `url_path`, `url` |
| `production_documentations.overrides` | `overrides.csv` (statique) | `production_reference_name`, `source`, `url` |

### 3.4 Format du CSV `wiki_links.csv` (généré)

```csv
category,fr_label,url_path,url
Grandes cultures,Blé tendre,Bl%C3%A9_tendre,https://wiki.tripleperformance.fr/wiki/Bl%C3%A9_tendre
Grandes cultures,Maïs grain,Ma%C3%AFs_grain,https://wiki.tripleperformance.fr/wiki/Ma%C3%AFs_grain
...
Élevage,Bovins lait,Bovins_lait,https://wiki.tripleperformance.fr/wiki/Bovins_lait
...
```

**Volume estimé** : 200-400 lignes (sur les 9 catégories cumulées).

### 3.5 Format du CSV `overrides.csv` (statique)

```csv
production_reference_name,source,url
# Exemple : forcer une URL pour une production que l'auto-matching ne capture pas
# winter_triticale,tripleperformance,https://wiki.tripleperformance.fr/wiki/Triticale
```

Vide au démarrage (juste l'en-tête). Se remplit au fur et à mesure si l'auto-matching laisse des trous identifiés par les assertions §6.

---

## 4. Implémentation du datasource (squelette de référence)

> Section **descriptive**. `/sc:implement` produira le fichier réel.

```ruby
require 'csv'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'fileutils'

module Datasources
  class ProductionDocumentations < Base
    description 'Liens entre les productions Ekylibre et la documentation Triple Performance'
    credits name: 'Triple Performance',
            url: 'https://wiki.tripleperformance.fr/wiki/Productions',
            provider: 'Triple Performance (collectif)',
            licence: 'CC-BY-SA 4.0',
            licence_url: 'https://creativecommons.org/licenses/by-sa/4.0/deed.fr',
            updated_at: '2026-05-22'

    SOURCE_KEY = 'tripleperformance'.freeze
    WIKI_HOST  = 'https://wiki.tripleperformance.fr'.freeze
    ROOT_PATH  = '/wiki/Productions'.freeze

    # Namespaces MediaWiki à exclure (préfixes en URL-encodé inclus)
    EXCLUDED_NAMESPACES = %w[
      Cat%C3%A9gorie: Sp%C3%A9cial: Fichier: Aide: Discussion: Mod%C3%A8le: Aide_:
      Catégorie: Spécial: Fichier: Aide: Discussion: Modèle:
      File: Special: Help: Talk: Template: Category:
    ].freeze

    def collect
      FileUtils.mkdir_p(dir)
      # Passe 1 : page d'accueil → liste des catégories
      categories = extract_category_links(http_get(ROOT_PATH))
      logger.debug "#{categories.size} catégorie(s) détectée(s)"

      # Passe 2 : pour chaque catégorie, extraire ses cultures
      rows = []
      categories.each do |cat|
        html = http_get(cat[:url_path])
        culture_links = extract_culture_links(html)
        culture_links.each do |link|
          rows << [cat[:label], link[:label], link[:url_path], "#{WIKI_HOST}#{link[:url_path]}"]
        end
        sleep 0.2 # politesse réseau
      end

      CSV.open(dir.join('wiki_links.csv'), 'w', write_headers: true,
                                               headers: %w[category fr_label url_path url]) do |out|
        rows.uniq.each { |r| out << r }
      end
      logger.debug "Wrote #{rows.uniq.size} liens dans wiki_links.csv"

      # Copie du CSV d'overrides statique vers raw/
      overrides_src = Pathname.new('data/production_documentations/overrides.csv')
      FileUtils.cp(overrides_src, dir.join('overrides.csv'))
    end

    def load
      load_csv(dir.join('wiki_links.csv'), 'wiki_links')
      load_csv(dir.join('overrides.csv'),  'overrides')
    end

    def self.table_definitions(builder)
      builder.table :master_production_documentations,
                    sql: <<-SQL
        CREATE TABLE master_production_documentations (
          production_reference_name character varying NOT NULL,
          source                    character varying NOT NULL,
          url                       character varying NOT NULL,
          PRIMARY KEY (production_reference_name, source)
        );
        CREATE INDEX master_production_documentations_source
          ON master_production_documentations(source);
      SQL
    end

    def normalize
      # 1) Overrides manuels (autorité finale)
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT production_reference_name, source, url
            FROM production_documentations.overrides
           WHERE production_reference_name IS NOT NULL
             AND source IS NOT NULL
             AND url IS NOT NULL
          ON CONFLICT (production_reference_name, source) DO UPDATE SET url = EXCLUDED.url
      SQL

      # 2) Auto-match exact (normalisé) — n'écrase pas les overrides (ON CONFLICT DO NOTHING)
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT mp.reference_name, '#{SOURCE_KEY}', wl.url
            FROM master_productions mp
            JOIN master_translations mt ON mt.id = mp.translation_id
            JOIN production_documentations.wiki_links wl
              ON LOWER(TRANSLATE(mt.fra, '’', '''')) = LOWER(TRANSLATE(wl.fr_label, '’', ''''))
          ON CONFLICT (production_reference_name, source) DO NOTHING
      SQL

      # 3) Auto-match par préfixe (séparateurs d'attribut : d', de, du, d’)
      query <<~SQL
        INSERT INTO master_production_documentations (production_reference_name, source, url)
          SELECT mp.reference_name, '#{SOURCE_KEY}', wl.url
            FROM master_productions mp
            JOIN master_translations mt ON mt.id = mp.translation_id
            JOIN production_documentations.wiki_links wl
              ON LOWER(TRANSLATE(mt.fra, '’', '''')) SIMILAR TO
                 LOWER(TRANSLATE(wl.fr_label, '’', '''')) || ' (d''|de |du |d ){1}%'
          ON CONFLICT (production_reference_name, source) DO NOTHING
      SQL
    end

    private

      def http_get(path)
        uri = URI.parse("#{WIKI_HOST}#{path}")
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'lexicon-production-documentations'
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        raise "GET #{uri} returned #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        Nokogiri::HTML(res.body)
      end

      # Détecte les 9 (ou N) liens de catégorie en page d'accueil Productions.
      # Heuristique : tous les liens internes /wiki/* hors namespaces, dans
      # le contenu principal #mw-content-text, qui ne sont pas des cultures
      # individuelles (différenciation : voir §5 du workflow).
      def extract_category_links(doc)
        # Cible la grille principale en haut de page ; à ajuster après inspection
        # réelle du HTML (cf. plan §5.2).
        doc.css('#mw-content-text a[href^="/wiki/"]').filter_map do |a|
          href = a['href'].split('#').first
          next if EXCLUDED_NAMESPACES.any? { |ns| href.start_with?("/wiki/#{ns}") }
          next if a['class'].to_s.include?('new') # red link
          label = a.text.strip
          next if label.empty?

          { label: label, url_path: href }
        end.uniq { |h| h[:url_path] }
      end

      # Extrait les liens de la section « Cultures » (ou équivalente) d'une
      # page de catégorie. Le sélecteur exact est à confirmer par inspection.
      def extract_culture_links(doc)
        # Hypothèse à valider §5.2 : section avec id="Cultures" ou un h2
        # contenant "Cultures". Fallback : tous les liens du contenu.
        scope = doc.at_css('#mw-content-text')
        return [] unless scope

        scope.css('a[href^="/wiki/"]').filter_map do |a|
          href = a['href'].split('#').first
          next if EXCLUDED_NAMESPACES.any? { |ns| href.start_with?("/wiki/#{ns}") }
          next if a['class'].to_s.include?('new')
          label = a.text.strip
          next if label.empty?

          { label: label, url_path: href }
        end.uniq { |h| h[:url_path] }
      end
  end
end
```

### Points d'attention pour l'implémenteur

1. **Sélecteurs HTML à confirmer (étape §5.2)** : les `css('#mw-content-text a[href^="/wiki/"]')` ratissent trop large (toute la page de contenu). Il faut **inspecter le HTML réel** des pages `/wiki/Productions` et `/wiki/Grandes_cultures` pour trouver le sélecteur précis qui isole :
   - Sur `/wiki/Productions` : uniquement les 9 cartes de catégorie (pas la nav, pas le footer).
   - Sur une page de catégorie : uniquement la section « Cultures » (pas les sections thématiques comme « Désherbage », « Fertilisation »).

   Sans cette précision, le CSV `wiki_links.csv` contiendra du bruit (liens de navigation, etc.) qui sera ensuite filtré par le matching mais bruite les assertions de validation.

2. **Apostrophe typographique vs droite** : `Blé tendre d’hiver` (apostrophe U+2019) est ce qu'on a en BD, mais le wiki utilise probablement la même. Le `TRANSLATE(..., '’', '''')` du `normalize` neutralise la différence dans tous les cas. Vérifier avec une ligne de test après load.

3. **Filtrage des red links** : `a['class'].to_s.include?('new')` détecte les pages inexistantes. À vérifier dans le HTML réel — la classe peut varier (`new`, `mw-redlink`, etc.).

4. **Pages de catégorie sans section « Cultures »** : Apiculture, Sylviculture, Cultures tropicales peuvent avoir une structure différente. L'extracteur doit dégrader proprement (renvoyer un tableau vide plutôt que crasher).

5. **Encodage URL** : Nokogiri retourne les `href` URL-encodés (`Bl%C3%A9_tendre`). On les stocke tels quels. Pour comparer avec les noms FR, le `wiki_label` extrait du texte d'ancrage est lui en clair (`Blé tendre`). On compare sur `fr_label`, pas sur `url_path`.

6. **Idempotence de `collect`** : ré-exécuter `collect` doit écraser `wiki_links.csv` (le fichier est temporaire par construction). Pas de check `if_missing` ici, contrairement à `Downloader#curl`.

7. **Doublons inter-catégories** : une même page peut apparaître dans plusieurs catégories (rare mais possible). Le `rows.uniq` dans `collect` plus le DISTINCT implicite via les contraintes du `normalize` couvrent ce cas.

8. **Pattern `SIMILAR TO` PostgreSQL** : la regex `' (d''|de |du |d ){1}%'` capture « d'hiver », « de printemps », « du nord », etc. Tester sur quelques cas concrets avant de valider — risque de faux positifs (« Pomme de terre » sera matché par une page « Pomme » si elle existe). **Mitigation** : si test §5 révèle un cas tordu, retirer le préfixe-match de l'auto-loader et basculer sur overrides manuels.

9. **Cas « Maïs grain » vs « Maïs ensilage »** : ces noms n'ont pas de séparateur d'attribut (`d'`, `de`). Le match exact suffit, à condition que le wiki ait des pages avec exactement ces titres. À valider.

---

## 5. Plan d'exécution séquentiel (pour `/sc:implement`)

| # | Phase | Action | Validation |
|---|---|---|---|
| 1 | **Préparation données** | Créer `data/production_documentations/overrides.csv` avec uniquement l'en-tête `production_reference_name,source,url`. | Fichier présent, taille ≈ 60 octets. |
| 2 | **Inspection HTML wiki** | Avant le code : récupérer manuellement `/wiki/Productions` et `/wiki/Grandes_cultures` (`curl ... \| html2text -nobs`, ou inspection navigateur). Identifier le sélecteur CSS qui isole précisément les cartes/cultures. Documenter le sélecteur retenu dans un commentaire du code. | Sélecteur identifié, testé sur 2 pages au moins. |
| 3 | **Datasource Ruby** | Créer `lib/datasources/production_documentations.rb` selon §4. **Adapter les sélecteurs CSS** au résultat de l'étape 2. | `./lexicon list` montre `production_documentations`. |
| 4 | **Test isolé du parser** | Avant `collect` global : tester `extract_category_links` et `extract_culture_links` via `./lexicon console` sur une page locale (fichier HTML sauvé en étape 2). Compter les liens retournés vs la valeur observée à l'œil. | Compte identique (±2 pour ancres internes). |
| 5 | **Run collect** | `./lexicon collect production_documentations` | `raw/production_documentations/wiki_links.csv` créé. `wc -l` ≈ 250-400. Inspection visuelle d'un échantillon pour vérifier absence de bruit (Catégorie:, Spécial:, etc.). |
| 6 | **Run load** | `./lexicon load production_documentations` | Tables raw `production_documentations.wiki_links` et `.overrides` créées. |
| 7 | **Run normalize** | `./lexicon normalize production_documentations` | Table `master_production_documentations` peuplée. |
| 8 | **Validation BD** | Exécuter assertions §6. | Tous les checks passent ; les écarts détectés par #6.4 et #6.5 sont passés en revue pour décider d'ajouter des overrides ou pas. |
| 9 | **Itération sur overrides** | Pour chaque production importante non matchée (cf. #6.5), ajouter une ligne dans `data/production_documentations/overrides.csv`. Relancer §7. | Couverture finale ≥ 80% des productions plant_farming. |
| 10 | **Flavors** | Ajouter dans `resources/flavors/test.yml` : `production_documentations.master_production_documentations` avec filtre `WHERE production_reference_name IN ('winter_common_wheat', 'grain_corn', 'buckwheat')` (ces 3 sont stables et représentatives). | `./lexicon dump all --flavor test` OK. |
| 11 | **Validation schéma** | `./lexicon validate` | Aucune erreur. |
| 12 | **Pipeline complet** | `./lexicon clean && ./lexicon run production_documentations` | Run from scratch OK. |

---

## 6. Assertions de validation

```sql
-- 1. Comptes par source
SELECT source, COUNT(*) FROM master_production_documentations GROUP BY source ORDER BY source;
-- attendu : tripleperformance, 200-500 lignes

-- 2. URLs toutes bien formées
SELECT COUNT(*) FROM master_production_documentations
 WHERE url NOT LIKE 'https://%';
-- attendu : 0

-- 3. Intégrité référentielle vers master_productions
SELECT mpd.production_reference_name
  FROM master_production_documentations mpd
  LEFT JOIN master_productions mp ON mp.reference_name = mpd.production_reference_name
  WHERE mp.reference_name IS NULL;
-- attendu : 0 ligne

-- 4. Productions plant_farming sans documentation (à inspecter pour overrides)
SELECT mp.reference_name, mt.fra
  FROM master_productions mp
  JOIN master_translations mt ON mt.id = mp.translation_id
  LEFT JOIN master_production_documentations mpd
    ON mpd.production_reference_name = mp.reference_name AND mpd.source = 'tripleperformance'
  WHERE mp.activity_family = 'plant_farming' AND mpd.production_reference_name IS NULL
  ORDER BY mp.reference_name;
-- attendu : liste à examiner. Objectif : < 20% du total plant_farming après itération §5.9.

-- 5. Entrées wiki_links non utilisées (pages wiki sans match)
SELECT wl.fr_label, wl.url
  FROM production_documentations.wiki_links wl
  LEFT JOIN master_production_documentations mpd ON mpd.url = wl.url
  WHERE mpd.url IS NULL
  ORDER BY wl.category, wl.fr_label;
-- attendu : liste à examiner. Les entrées sans correspondance peuvent être :
--   (a) du bruit (sections thématiques, pages génériques) — à filtrer en upstream
--   (b) des productions absentes de master_productions (rien à faire)

-- 6. Cas du user prompt (winter_common_wheat)
SELECT * FROM master_production_documentations
 WHERE production_reference_name = 'winter_common_wheat';
-- attendu : 1 ligne pointant sur https://wiki.tripleperformance.fr/wiki/Bl%C3%A9_tendre

-- 7. Productions partageant la même URL (sanity : winter + spring versions)
SELECT url, array_agg(production_reference_name ORDER BY production_reference_name) AS productions
  FROM master_production_documentations
  GROUP BY url
  HAVING COUNT(*) > 1
  ORDER BY url;
-- attendu : quelques regroupements (Blé tendre / Blé dur / Orge…)
```

L'assertion **#6** est le test du cas utilisateur — bloquant si elle échoue.

---

## 7. Risques & points d'attention

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Sélecteur HTML mal calibré → bruit massif ou productions ratées | Élevée | Élevé | Étape §5.2 d'inspection manuelle obligatoire, validée §5.4 avant lancement global. |
| Le wiki ré-architecte la page Productions (refonte UX) | Faible | Élevé | Erreur explicite levée par `extract_category_links` si 0 lien trouvé. À déclencher un nouveau cycle workflow. |
| Match par préfixe trop laxiste (faux positifs « Pomme » ↔ « Pomme de terre ») | Moyenne | Moyen | Test §5.8 (assertion #4 + #5) ; si trop de faux positifs, désactiver le bloc « auto-match par préfixe » et tout passer en overrides manuels. |
| Apostrophe typographique non normalisée → match raté | Moyenne | Faible | `TRANSLATE('’', '''')` dans toutes les comparaisons. Test §5.8 (assertion #6 sur `winter_common_wheat`). |
| Pages catégorie sans section « Cultures » identifiable | Moyenne | Faible | Fallback : tous les liens internes valides de `#mw-content-text` (avec un peu de bruit, filtré au matching). |
| Productions hors plant_farming (Élevage, Apiculture) non couvertes | Moyenne | Moyen | Hors scope v1. Si demandé plus tard, ajouter d'autres ancres de catégorie sans changer la structure. |
| Triple Performance disponibilité réseau pendant CI | Faible | Moyen | Le run `collect` est manuel (pas en CI). Le pipeline cassera si offline ; comportement acceptable. |
| Surcoût du `SIMILAR TO` en SQL (pas indexé) | Faible | Faible | Volume très petit (~500 productions × ~400 wiki_links = 200k comparaisons), tient en < 1s. |

---

## 8. Hors scope (à NE PAS faire dans ce workflow)

- ❌ **Stocker le contenu des pages wiki** (texte, images) en BD. Seul le lien est demandé.
- ❌ **Crawl récursif au-delà des deux niveaux** (page d'accueil → catégorie). Pas de descente dans les pages individuelles.
- ❌ **Validation périodique des URLs** (HEAD requests pour vérifier que les pages existent toujours).
- ❌ **Intégration d'autres sources** (Wikipédia, ITAB, Wikifarmer). Le schéma `(reference_name, source, url)` permet d'en ajouter plus tard ; à faire dans un nouveau workflow.
- ❌ **Couverture exhaustive de toutes les activity_family** (animal_farming, processing, service…). v1 cible plant_farming et vine_farming. Couverture extensible via overrides manuels au cas par cas.
- ❌ **API REST côté Lexicon** pour exposer ces liens. Côté ERP, requête SQL standard.
- ❌ **Backfill historique** de versions précédentes du wiki. La table est un snapshot du dernier `collect`.

---

## 9. Prochaine étape

Lancer `/sc:implement claudedocs/workflow_production_documentations.md` après revue. L'implémenteur devra :

1. **Démarrer par §5.2 — inspection HTML manuelle**. Sans sélecteurs CSS précis, tout le reste produit du bruit.
2. **Valider l'auto-match exact sur `winter_common_wheat`** (assertion #6) avant de débugger les autres cas.
3. Inspecter les assertions #4 et #5 pour décider si le préfixe-match cause trop de faux positifs ; si oui, le désactiver et basculer entièrement sur overrides manuels.
4. Itérer §5.9 : remplir `data/production_documentations/overrides.csv` au fur et à mesure des productions importantes non matchées.
