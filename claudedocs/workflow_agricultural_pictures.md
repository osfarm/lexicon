# Workflow — Datasource `agricultural_pictures`

**Stratégie :** systematic · **Profondeur :** deep · **Cible :** `lib/datasources/agricultural_pictures.rb`
**Date :** 2026-05-22 · **Auteur du plan :** Claude (sc:workflow)

> ⚠️ Ce document est un **plan d'implémentation uniquement**. Aucun code n'est écrit à ce stade. Utiliser `/sc:implement` après revue pour exécuter le plan.

---

## 1. Contexte & Intention

Ajouter un datasource `agricultural_pictures` qui collecte les **assets image** utilisés par Ekylibre depuis le dépôt GitHub `ekylibre/ekylibre`, et les expose dans le schéma `lexicon` sous forme d'une table unique avec le contenu binaire stocké en `BYTEA`.

Trois répertoires sont concernés (sur la branche `main` du dépôt) :

| `domain` (valeur de colonne) | Source GitHub |
|---|---|
| `varieties` | https://github.com/ekylibre/ekylibre/tree/main/app/assets/images/varieties |
| `activity_families` | https://github.com/ekylibre/ekylibre/tree/main/app/assets/images/activity_families |
| `countries` | https://github.com/ekylibre/ekylibre/tree/main/app/assets/images/countries |

Schéma cible (résumé) :

```sql
CREATE TABLE master_agricultural_pictures (
  id          SERIAL PRIMARY KEY NOT NULL,
  domain      character varying NOT NULL,   -- 'varieties' | 'activity_families' | 'countries'
  name        character varying NOT NULL,   -- nom du fichier sans extension
  extension   character varying,            -- 'png' | 'svg' | 'jpg' … (info utile, voir §2.4)
  picture     BYTEA NOT NULL,               -- contenu binaire du fichier
  UNIQUE (domain, name, extension)
);
CREATE INDEX master_agricultural_pictures_domain ON master_agricultural_pictures(domain);
CREATE INDEX master_agricultural_pictures_domain_name ON master_agricultural_pictures(domain, name);
```

---

## 2. Décisions de conception

### 2.1 Préfixe de table : `master_` vs `registered_`

Choisi **`master_`** parce que les assets sont **internes à Ekylibre** (commités dans le dépôt applicatif), pas issus d'un fournisseur externe officiel. Convention observée :

- `registered_*` → données d'organismes externes (INSEE, Agreste, ASP, etc.) — cf. `registered_msa_populations`, `registered_cap_beneficiaries`, `registered_postal_codes`.
- `master_*` → référentiels internes Ekylibre — cf. `master_productions`, `master_legal_positions`, `master_translations`.

Les images d'icônes/illustrations versionnées dans le repo applicatif relèvent du second cas.

### 2.2 Une table unique avec colonne `domain` (vs trois tables séparées)

Choisi **une seule table** parce que :
- Les trois domaines partagent exactement le même schéma (binaire + nom).
- L'usage côté ERP sera typiquement `SELECT … WHERE domain = ?` — filtrer sur une colonne indexée est aussi rapide qu'interroger une table dédiée pour ce volume (~quelques centaines de lignes par domaine, voir §3.2).
- Évite la duplication du schéma de table et facilite l'ajout futur d'un quatrième domaine sans migration de structure.

### 2.3 Stockage binaire : `BYTEA` (vs Large Object, vs URL externe)

Choisi **`BYTEA`** parce que :
- Demandé explicitement dans la spec.
- Les images concernées sont des **icônes/illustrations** typiques d'application : poids unitaire faible (PNG/SVG quelques Ko à quelques dizaines de Ko).
- Évite les Large Objects PostgreSQL (gestion plus complexe, ACL séparées) — sur-dimensionné pour ce cas.
- L'autosuffisance du package Lexicon (un seul artefact contenant tout) est cohérente avec le reste du projet ; stocker des URLs externes introduirait une dépendance réseau au runtime côté Ekylibre.

**Limite pratique** : BYTEA peut atteindre 1 GB par ligne, mais le `pg_dump` SQL du package Lexicon devient lourd au-delà de quelques MB par ligne. Vérifier en §3.2 que les volumes restent raisonnables.

### 2.4 Colonne `extension` non demandée mais ajoutée

La spec utilisateur demande seulement `domain`, `name`, `picture`. **On ajoute néanmoins une colonne `extension`** pour deux raisons :

1. **Désambiguïsation** : un même nom logique peut exister avec plusieurs extensions (`wheat.png` et `wheat.svg` par exemple). Sans extension, le couple `(domain, name)` ne serait pas unique. Mettre l'extension dans la PK logique permet de tout stocker sans collision.
2. **Servir à la consommation** : côté ERP, savoir si le blob est PNG, SVG ou JPG est nécessaire pour positionner le bon `Content-Type` HTTP (`image/svg+xml` vs `image/png`).

**Si l'équipe préfère strictement coller à la spec**, deux options de repli (à arbitrer en revue) :
- a) Stocker l'extension **dans le nom** (`wheat.png` au lieu de `wheat`) — contredit la spec « nom sans extension ».
- b) Imposer **une seule extension par couple `(domain, name)`** — perte d'information si plusieurs formats coexistent en amont.

Recommandation : **garder `extension` séparée**, c'est la solution la moins ambiguë.

### 2.5 Méthode de téléchargement : API GitHub Contents

Le pattern existant `downloader.curl(url, out: 'file')` (cf. `lib/lexicon/downloader.rb:21`) télécharge **un fichier à la fois** depuis une URL connue. Pour notre cas, **on ne connaît pas la liste des fichiers à l'avance** — il faut interroger l'API GitHub.

**Approche retenue** : utiliser l'**API Contents** de GitHub pour énumérer chaque répertoire, puis télécharger chaque fichier via son `download_url` retourné par l'API.

```text
GET https://api.github.com/repos/ekylibre/ekylibre/contents/app/assets/images/varieties?ref=main
GET https://api.github.com/repos/ekylibre/ekylibre/contents/app/assets/images/activity_families?ref=main
GET https://api.github.com/repos/ekylibre/ekylibre/contents/app/assets/images/countries?ref=main
```

Pour chaque entrée du JSON retourné (un tableau d'objets `{ name, path, type, download_url, … }`) :
- Filtrer `type == "file"` (ignorer sous-répertoires éventuels).
- `download_url` pointe sur `raw.githubusercontent.com/...` — téléchargement direct, **sans contre-coup sur le rate-limit API**.
- Sauver localement sous `raw/agricultural_pictures/<domain>/<filename>`.

**Limites & mitigations** :

| Limite | Mitigation |
|---|---|
| Rate-limit GitHub API non-authentifié = 60 req/h | 3 appels API au total (un par domaine) → marge énorme. Si l'équipe veut sécuriser, ajouter en-tête `Authorization: Bearer $GITHUB_TOKEN` lu depuis l'environnement (variable optionnelle, fallback non-authentifié). |
| Pagination GitHub Contents au-delà de 1000 entrées par répertoire | Très improbable pour `varieties` / `activity_families` / `countries` (estimation §3.2 < 300). Si dépassé, basculer sur l'API `git/trees/<branch>:<path>` qui retourne toute l'arborescence en un appel. Documenter la limite. |
| `download_url` peut être `null` pour les symlinks Git ou les fichiers > 1 MB | Filtrer + fallback sur l'API blob (`contents/<path>?ref=main` avec en-tête `Accept: application/vnd.github.raw`). À implémenter en défense, peu probable d'être déclenché par des icônes. |
| Variabilité dans le temps : la branche `main` évolue | Acceptable — c'est précisément la sémantique attendue : un run récolte l'état courant de la branche. Pour reproductibilité, alternative possible (hors scope) : pinner un commit SHA dans le code. |

**Pourquoi pas cloner le repo** : `git clone --depth 1 ekylibre/ekylibre` rapatrie plusieurs centaines de Mo (le repo applicatif complet) pour récupérer < 5 Mo d'assets. Surdimensionné.

### 2.6 Bypass de la phase `load` standard

Le pipeline trois-phases (collect / load / normalize) impose normalement :
- `collect` → écrit dans `raw/<datasource>/`
- `load` → import dans schéma `agricultural_pictures.*` via `load_csv` / `load_xls` / `load_shp`
- `normalize` → INSERT depuis le schéma raw vers les tables `master_*` / `registered_*`

**Pour les BYTEA, il n'y a pas de loader CSV natif applicable** (le `csv_loader` produit des colonnes VARCHAR uniquement). On a deux options :

**Option A (recommandée) — `load` écrit directement dans la table lexicon via `COPY … FROM STDIN`** :

Pattern existant : `Datasources::OpenNomenclature#load` (`lib/datasources/open_nomenclature.rb:8`) crée et remplit ses tables `lexicon` directement en `load`, sans passer par un schéma raw. C'est notre référence.

```ruby
database.copy_data "COPY master_agricultural_pictures (...) FROM STDIN" do |c|
  # itération sur fichiers, c.call "<row>\n"
end
```

`normalize` reste vide (no-op).

**Option B — passer par un schéma raw** : créer manuellement `agricultural_pictures.agricultural_pictures_raw` puis copier. Surcoût sans bénéfice pour notre cas (transformation triviale). À écarter.

→ **Décision : Option A.**

### 2.7 Encodage BYTEA pour COPY TEXT

`COPY … FROM STDIN` en **format TEXT** (par défaut) accepte les valeurs bytea sous la forme `\x<hex>` (préfixe « backslash-x » suivi du contenu hex-encodé).

Subtilité d'échappement : le backslash est lui-même un caractère d'échappement dans le flux COPY TEXT. Pour transmettre la chaîne littérale `\x<hex>` au parser bytea, il faut écrire dans le flux la séquence `\\x<hex>` (deux backslashes). En Ruby :

```ruby
hex = File.binread(path).unpack1('H*')
c.call "#{domain}\t#{name}\t#{ext}\t\\\\x#{hex}\n"
# en mémoire : "varieties\twheat\tpng\t\\x<hex>\n"
```

**Variante plus sûre** : utiliser le format binaire `COPY … FROM STDIN (FORMAT BINARY)` — mais c'est plus complexe à produire côté Ruby (header binaire + framing par colonne) et apporte peu pour ce volume. Le format TEXT est suffisant.

**Validation post-load** (cf. §6) : `SELECT length(picture) FROM master_agricultural_pictures LIMIT 5;` doit retourner des tailles cohérentes avec les fichiers source (`du -b raw/agricultural_pictures/varieties/*`).

### 2.8 Flavors

- Inclus dans tous les flavors par défaut (les images sont petites individuellement).
- `light.yml` (cf. `resources/flavors/light.yml`) supprime déjà les datasources volumineux ; **on n'ajoute pas `agricultural_pictures` à la liste `without`** sauf si le volume cumulé dépasse ~50 MB en BYTEA (à vérifier après premier run — voir §3.2).
- `test.yml` : ajouter un filtre pour n'embarquer qu'un sous-ensemble en test.

---

## 3. Architecture cible

### 3.1 Fichiers à créer / modifier

| Action | Chemin | Rôle |
|---|---|---|
| **Créer** | `lib/datasources/agricultural_pictures.rb` | Définition de la datasource (auto-découverte Zeitwerk) |
| **Modifier** | `resources/flavors/test.yml` | Ajouter un filtre minimal pour limiter le volume en test |
| **(Conditionnel)** | `resources/flavors/light.yml` | À ajouter dans `without` **si** le volume agrégé est jugé trop lourd (décision après premier run) |

> Pas de modification de `Lexicon::Application#register_services`. Zeitwerk auto-découvre le datasource.

### 3.2 Volumétrie attendue (à vérifier au §5)

Estimations à confirmer pendant l'implémentation :

| Domaine | # fichiers estimé | Taille unitaire | Taille totale estimée |
|---|---|---|---|
| `varieties` | ~100-200 (espèces végétales) | 5-50 Ko (PNG/SVG) | < 10 Mo |
| `activity_families` | ~30-50 (icônes catégorielles) | 5-30 Ko (SVG le plus souvent) | < 2 Mo |
| `countries` | ~250 (drapeaux ISO) | 1-20 Ko (PNG/SVG) | < 5 Mo |
| **Total** | **< 500 lignes** | — | **< 20 Mo** |

À l'issue de l'étape 4 du §5, **vérifier** avec :
```bash
du -sh raw/agricultural_pictures/
psql … -c "SELECT domain, COUNT(*), SUM(length(picture))/1024/1024 AS mb FROM master_agricultural_pictures GROUP BY domain;"
```

Si dépassement > 50 Mo agrégés → ouvrir une revue pour décider de l'inclusion dans les flavors lourds (`full`) seulement.

### 3.3 Structure du répertoire `raw/`

```
raw/agricultural_pictures/
├── varieties/
│   ├── wheat.png
│   ├── corn.svg
│   └── …
├── activity_families/
│   └── …
└── countries/
    └── …
```

Le sous-répertorisation par domaine évite les collisions de noms entre domaines (un fichier `france.svg` peut exister dans `varieties` et dans `countries`).

---

## 4. Implémentation du datasource (squelette de référence)

> Cette section est **descriptive**. `/sc:implement` produira le fichier réel.

```ruby
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'

module Datasources
  class AgriculturalPictures < Base
    description 'Pictures et icônes utilisées par Ekylibre (variétés, familles d''activité, pays)'
    credits name: 'Ekylibre assets',
            url: 'https://github.com/ekylibre/ekylibre',
            provider: 'Ekylibre SAS',
            licence: 'AGPL-3.0',
            licence_url: 'https://www.gnu.org/licenses/agpl-3.0.html',
            updated_at: '2026-05-22'

    GITHUB_REPO   = 'ekylibre/ekylibre'.freeze
    GITHUB_BRANCH = 'main'.freeze

    DOMAINS = {
      'varieties'         => 'app/assets/images/varieties',
      'activity_families' => 'app/assets/images/activity_families',
      'countries'         => 'app/assets/images/countries',
    }.freeze

    # ---------------------------------------------------------------------------
    # collect : liste chaque répertoire via l'API GitHub Contents, télécharge chaque
    # fichier dans raw/agricultural_pictures/<domain>/<filename>.
    # ---------------------------------------------------------------------------
    def collect
      DOMAINS.each do |domain, path|
        target_dir = dir.join(domain)
        FileUtils.mkdir_p(target_dir)
        entries = list_github_contents(path)
        entries.each do |entry|
          next unless entry['type'] == 'file'
          next if entry['download_url'].to_s.empty?
          dst = target_dir.join(entry['name'])
          next if dst.exist? # idempotence
          downloader.curl(entry['download_url'], out: "#{domain}/#{entry['name']}")
        end
        logger.debug "Collected #{entries.count { |e| e['type'] == 'file' }} files for domain=#{domain}"
      end
    end

    # ---------------------------------------------------------------------------
    # load : crée la table lexicon et copie le contenu via COPY FROM STDIN (TEXT).
    # On bypass volontairement un schéma raw intermédiaire (cf. décision §2.6).
    # ---------------------------------------------------------------------------
    def load
      # table_definitions garantit déjà la structure ; on TRUNCATE pour rejouabilité.
      query 'TRUNCATE TABLE master_agricultural_pictures RESTART IDENTITY'

      database.copy_data 'COPY master_agricultural_pictures (domain, name, extension, picture) FROM STDIN' do |c|
        DOMAINS.each_key do |domain|
          Dir.glob(dir.join(domain, '*')).sort.each do |file|
            next unless File.file?(file)
            basename  = File.basename(file)
            name      = File.basename(basename, '.*')
            extension = File.extname(basename).delete_prefix('.')
            hex       = File.binread(file).unpack1('H*')
            # COPY TEXT escape : backslash doublé pour passer "\x<hex>" au parser bytea
            c.call "#{escape(domain)}\t#{escape(name)}\t#{escape(extension)}\t\\\\x#{hex}\n"
          end
        end
      end
    end

    def self.table_definitions(builder)
      builder.table :master_agricultural_pictures, sql: <<-SQL
        CREATE TABLE master_agricultural_pictures (
          id        SERIAL PRIMARY KEY NOT NULL,
          domain    character varying NOT NULL,
          name      character varying NOT NULL,
          extension character varying,
          picture   BYTEA NOT NULL,
          UNIQUE (domain, name, extension)
        );
        CREATE INDEX master_agricultural_pictures_domain
          ON master_agricultural_pictures(domain);
        CREATE INDEX master_agricultural_pictures_domain_name
          ON master_agricultural_pictures(domain, name);
      SQL
    end

    def normalize
      # No-op : load écrit directement la table cible.
    end

    private

      # Liste le contenu d'un répertoire GitHub via l'API Contents.
      # Renvoie un tableau de hashes (au format API REST GitHub).
      def list_github_contents(path)
        url = URI.parse("https://api.github.com/repos/#{GITHUB_REPO}/contents/#{path}?ref=#{GITHUB_BRANCH}")
        req = Net::HTTP::Get.new(url)
        req['Accept'] = 'application/vnd.github+json'
        req['User-Agent'] = 'lexicon-datasource-agricultural-pictures'
        # Token optionnel si fourni en environnement (augmente le rate limit à 5000 req/h)
        token = ENV['GITHUB_TOKEN'].to_s
        req['Authorization'] = "Bearer #{token}" unless token.empty?

        res = Net::HTTP.start(url.host, url.port, use_ssl: true) { |http| http.request(req) }
        unless res.is_a?(Net::HTTPSuccess)
          raise "GitHub API #{url} returned #{res.code}: #{res.body[0, 200]}"
        end

        payload = JSON.parse(res.body)
        unless payload.is_a?(Array)
          raise "Unexpected GitHub API payload for #{path}: #{payload.class} (expected Array)"
        end
        payload
      end

      # Échappe les caractères spéciaux du format COPY TEXT (tab, newline, backslash).
      # Pour des noms d'images ces caractères ne devraient jamais apparaître, mais on
      # protège par précaution.
      def escape(s)
        s.to_s
         .gsub('\\', '\\\\')
         .gsub("\t", '\\t')
         .gsub("\n", '\\n')
         .gsub("\r", '\\r')
      end
  end
end
```

### Points d'attention pour l'implémenteur

1. **Pagination GitHub** : si l'un des répertoires dépasse 1000 entrées (peu probable), `list_github_contents` retournera une liste tronquée silencieusement. Si l'étape de validation §6 révèle un comptage plus faible que sur l'interface web GitHub, c'est probablement le cas — basculer sur l'API `git/trees/<branch>:<path>` (un seul appel renvoie l'intégralité).

2. **Idempotence de `collect`** : le `next if dst.exist?` reproduit le comportement de `Downloader#curl` (cf. `lib/lexicon/downloader.rb:33`). Bénéfice : un `./lexicon collect` rejoué ne re-télécharge pas. Coût : si le contenu d'un fichier change côté repo, il faut purger `raw/agricultural_pictures/` pour rafraîchir. Comportement standard du projet.

3. **TRUNCATE en `load`** : assure la rejouabilité. Sinon, second run ferait échouer la contrainte d'unicité. `RESTART IDENTITY` pour repartir `id=1`.

4. **Échappement BYTEA** : la séquence `"\\\\x#{hex}"` en code Ruby produit le tableau d'octets `\\x<hex>` envoyé sur le wire. Le parser COPY TEXT le décode en `\x<hex>`, que le parser bytea reconnaît comme format hex. **Tester en isolement** avec un PNG de quelques Ko avant de lancer sur l'ensemble — un bug d'échappement transforme tous les blobs en données corrompues silencieusement.

5. **Variable `GITHUB_TOKEN`** : facultative. Si l'équipe veut sécuriser le run en CI, ajouter `GITHUB_TOKEN` aux variables documentées dans `.env.dist` (sans valeur par défaut). Aucun changement de code requis pour activer le token — il suffit qu'il soit présent dans l'environnement.

6. **Politesse réseau** : si la collection d'un répertoire fait passer > 200 GETs sur `raw.githubusercontent.com` en quelques secondes, c'est acceptable (pas de rate-limit documenté sur les raw). Si jamais une 429 apparaît, ajouter un `sleep 0.05` entre appels. À ne mettre en place qu'en cas de problème observé.

7. **Licence des assets** : les images sont sous licence du dépôt Ekylibre (AGPL-3.0). Mentionné dans `credits`. Cohérent avec les autres datasources internes (`master_productions` est sous CC-BY-SA 4.0 mais c'est la convention d'origine, à clarifier en revue si nécessaire).

8. **Codes pays — alignement avec `registered_postal_codes` et `master_taxonomy`** (Iso 3166-1) : la spec n'impose pas de FK croisée, et les autres datasources Lexicon n'en mettent pas non plus. Mais en assertion de qualité (§6), vérifier que les `name` du domaine `countries` matchent bien des codes ISO connus (alpha-2 minuscule, en général).

---

## 5. Plan d'exécution séquentiel (pour `/sc:implement`)

| # | Phase | Action | Validation |
|---|---|---|---|
| 1 | **Préparation** | Aucune préparation de fichier statique à faire — tout est récupéré via API GitHub. | — |
| 2 | **Datasource Ruby** | Créer `lib/datasources/agricultural_pictures.rb` selon le squelette §4. | `./lexicon list` doit faire apparaître `agricultural_pictures`. |
| 3 | **Test isolé d'encodage** | Avant le run complet : sur un seul fichier (le plus petit du domaine `activity_families`), faire un `COPY` test depuis `./lexicon console`, puis `SELECT length(picture)` et comparer avec `wc -c` sur le fichier source. | Tailles identiques → encodage hex OK. Divergence → revoir §2.7. |
| 4 | **Run collect** | `./lexicon collect agricultural_pictures` | Sous-répertoires `raw/agricultural_pictures/{varieties,activity_families,countries}/` peuplés. `find raw/agricultural_pictures -type f \| wc -l` ≈ valeur attendue (cf. §3.2). |
| 5 | **Run load** | `./lexicon load agricultural_pictures` | Table `master_agricultural_pictures` peuplée. Compte de lignes ≈ nombre de fichiers téléchargés. |
| 6 | **Validation BD** | Exécuter les assertions §6 via `./lexicon console` ou `psql`. | Tous les checks passent. |
| 7 | **Validation visuelle** | Extraire 2-3 blobs via `SELECT picture FROM …` (via `\copy … TO 'file' WITH BINARY` ou export Ruby), vérifier ouverture dans une visionneuse. | Image décodable, contenu correct. |
| 8 | **Flavors** | Ajouter un filtre dans `resources/flavors/test.yml` pour ne garder que ~5 lignes par domaine. | `./lexicon dump all --flavor test` ne déborde pas en taille. |
| 9 | **Validation schéma** | `./lexicon validate` | Aucune erreur. |
| 10 | **Lint** | `./bin/rubocop lib/datasources/agricultural_pictures.rb` (datasources/ est globalement exclu mais validation manuelle utile). | OK |
| 11 | **Test pipeline complet** | `./lexicon clean && ./lexicon run agricultural_pictures` (run from scratch). | Run complet OK. |
| 12 | **(Conditionnel)** | Si volume cumulé > 50 Mo : ajouter `agricultural_pictures` dans `without` de `resources/flavors/light.yml`. | Décision documentée. |

---

## 6. Assertions de validation (à exécuter en §5.6)

```sql
-- 1. Volumétrie par domaine
SELECT domain, COUNT(*) AS n_files,
       pg_size_pretty(SUM(length(picture))) AS total_size,
       pg_size_pretty(MAX(length(picture))) AS max_size,
       pg_size_pretty(AVG(length(picture))::bigint) AS avg_size
  FROM master_agricultural_pictures
 GROUP BY domain
 ORDER BY domain;

-- 2. Aucun blob vide
SELECT COUNT(*) FROM master_agricultural_pictures WHERE length(picture) = 0;
-- attendu : 0

-- 3. Aucun nom vide
SELECT COUNT(*) FROM master_agricultural_pictures WHERE name IS NULL OR name = '';
-- attendu : 0

-- 4. Distribution des extensions par domaine
SELECT domain, extension, COUNT(*) AS n
  FROM master_agricultural_pictures
 GROUP BY domain, extension
 ORDER BY domain, extension;
-- vérifier : aucune extension vide ou exotique inattendue (.DS_Store, .keep, …)

-- 5. Détection des doublons potentiels logiques (même name, même domain, plusieurs extensions)
SELECT domain, name, COUNT(*) AS variants
  FROM master_agricultural_pictures
 GROUP BY domain, name
 HAVING COUNT(*) > 1
 ORDER BY domain, name;
-- attendu : peu ou aucun. Si lignes retournées, vérifier que les variantes sont bien
-- des formats différents légitimes (ex. icône .png ET .svg pour un même name).

-- 6. Première signature octet de chaque format (sanity check d'encodage)
SELECT extension, encode(substring(picture FROM 1 FOR 8), 'hex') AS magic, COUNT(*)
  FROM master_agricultural_pictures
 GROUP BY extension, magic
 ORDER BY extension, magic;
-- attendu (entre autres) :
--   png → magic commence par 89504e470d0a1a0a
--   jpg → magic commence par ffd8ff
--   svg → magic commence par 3c3f786d6c (`<?xml`) ou 3c737667 (`<svg`)
```

L'assertion #6 est **critique** : elle valide directement que l'encodage hex décrit en §2.7 n'a pas corrompu les blobs. Une magie PNG manquante = bug d'échappement à corriger avant de poursuivre.

---

## 7. Risques & points d'attention

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Bug d'échappement BYTEA (blobs corrompus silencieusement) | Moyenne | Élevé | Test d'encodage isolé §5.3 **avant** run complet. Assertion magique d'octets §6.6. |
| Rate-limit GitHub API atteint en CI partagée | Faible | Moyen | 3 appels API par run → marge énorme (60 req/h non-auth). Si CI partagée et plusieurs runs/h, prévoir `GITHUB_TOKEN` (5000 req/h). |
| Pagination silencieuse au-delà de 1000 entrées dans un répertoire | Très faible | Moyen | Compte de fichiers téléchargés vs comptage manuel via interface web GitHub. Basculer sur `git/trees/...` si déclenché. |
| Volume BYTEA fait gonfler le package Lexicon de façon disproportionnée | Moyenne | Moyen | Mesurer en §5.5. Si > 50 Mo agrégés, exclure du flavor `light` (§5.12). |
| Évolution du repo Ekylibre supprime un fichier référencé ailleurs côté ERP | Moyenne | Faible | C'est par nature un référentiel « live » de la branche main. Côté ERP, traiter l'absence d'image par un fallback. Hors scope ici. |
| Licence des images (AGPL repo source) propagée au package Lexicon | Faible | Moyen | À confirmer en revue juridique si les images sont redistribuées dans un package commercial. Mentionner explicitement dans `credits`. |
| Caractères exotiques dans les noms de fichiers (espaces, accents, …) | Faible | Faible | L'`escape` interne couvre tab/newline/backslash. Accents et espaces traversent intacts (UTF-8) — vérifier en §6.4 qu'aucun nom ne pose souci. |
| Conflit de nom datasource avec un fichier homonyme | Très faible | Faible | `ls lib/datasources/agricultural_pictures*` → aucun fichier préexistant constaté à la date du plan. |

---

## 8. Hors scope (à NE PAS faire dans ce workflow)

- ❌ **Resize / optimisation d'image** côté Lexicon : on stocke tel quel ; l'optimisation reste de la responsabilité du repo amont.
- ❌ **Pinning d'un commit SHA** plutôt que de la branche `main` : la spec demande la branche live, on respecte.
- ❌ **Détection de doublons binaires** (deux fichiers ayant le même contenu mais des noms différents) : pas demandé, et coûteux à valider proprement.
- ❌ **Génération d'un manifeste JSON** listant les images : redondant avec un `SELECT domain, name FROM master_agricultural_pictures`.
- ❌ **Intégration avec `master_taxonomy` ou `master_productions`** par FK : aucune table existante ne référence d'asset image, les jointures se feront côté ERP.
- ❌ **Ajout d'un quatrième domaine** : strictement les trois demandés. Ajouter un nouveau domaine = nouvelle revue + ajout dans la constante `DOMAINS`.
- ❌ **Mise en cache HTTP** (ETag / If-None-Match) : le mécanisme `if_missing` du downloader suffit.

---

## 9. Prochaine étape

Lancer `/sc:implement claudedocs/workflow_agricultural_pictures.md` après revue de ce plan. L'implémenteur devra :

1. **Démarrer par le test d'encodage isolé** (§5.3) sur **un seul fichier** avant de produire la version complète — c'est le risque #1 du tableau §7.
2. Valider la magie d'octets (§6.6) **immédiatement après le premier `load`**, avant de passer aux étapes suivantes.
3. Suivre la séquence §5 étape par étape.
4. Reporter au reviewer la volumétrie réelle observée en §3.2 + §6.1 pour décider de l'inclusion dans les flavors.
