# Dérogations 120 jours dans `phytosanitary` — conception

2026-11-07. Exigences : `brainstorm_phyto_derogations.md` (F1 à F10, NF1 à NF5, critères 1 à 6). Modèle :
`cropivia_backend` (`app/integrations/agri_gouv.py`, `app/services/phyto/derogations/`).

## 0. Ce que l'examen a tranché

| Question | Réponse | Sur quoi |
|---|---|---|
| Q1 — Envoi du PDF à Mistral | **En base64** (`data:application/pdf;base64,…` dans `document_url`) : ni dépôt public ni dépendance à l'URL `/telecharger/{id}` du ministère | cropivia devait d'abord déposer le PDF dans un bucket public |
| Q3 — Rapprochement des cultures | **Pas de fichier nouveau.** La colonne « Libellé de l'usage » de la décision est la phrase du catalogue E-Phy, avec son code : `16552204  Fraisier*Trt Irrigation loc.*Champignons (pythiacées)`. Le code est le `lib_court` des usages E-Phy (1 755 codes dans la base de build, 16552204 et 16551201 y sont avec `Fraisier`, `{fragaria}`) | PDF de SANTHAL GOLD lu par `pdftotext` ; `registered_phytosanitary_usages` |
| Q4 — Rythme | Reconstruire `phytosanitary` entier chaque semaine ; le builder ne pose pas de version quand rien n'a changé (`Packaging::Builder#build`) | `lib/lexicon/packaging/builder.rb` |
| Q5 — Clients | **API** : la recherche et la fiche de parcelle filtrent `u.state = 'authorized'` et `p.state = 'authorized'` ; l'énumération `ProductType` ne connaît que `PPP`, `PCP`, `ADJUVANT`. **Ekylibre** : sources absentes de ce poste, **non vérifié** | `lexicon-rest-api/src/phytosanitary/ProductSearch.ts`, `src/namespaces/Phytosanitary.ts` |
| Q6 — Conditions d'emploi | Dans `usage_conditions` de chaque usage, comme E-Phy, précédées de la restriction de culture et du milieu | forme de `condition-emploi` dans le XML E-Phy |
| Contrôle de lecture | Mistral OCR rend aussi le texte de chaque page (`pages[].markdown`) : l'AMM et les dates y sont relues par expression régulière et comparées à l'annotation. `pdftotext` n'est pas dans l'image du runner : on ne l'ajoute pas | `Dockerfile` |

## 0 bis. Écarts de la mise en œuvre (2026-11-07)

- **Rapprochement par code en SQL**, pas dans `Decision` : `load` passe avant `normalize` et ne voit pas encore les
  usages E-Phy construits. `Decision` contrôle la forme du code et de la phrase ; `normalize_derogations` prend la
  phrase, la culture, la cible et le traitement d'un usage E-Phy de même `lib_court`, et dit combien n'en ont pas.
- **La page donne plus que l'AMM** : chaque carte liste cultures, organisme, substance, date de délivrance et échéance.
  `Page::Notice` les garde dans `<sha>.notice.json`.
- **Mistral** : un 429 est repris après 5, 20 et 60 s, sauf si la limite annoncée est 0 (réglage du compte) ; un 429
  qui persiste arrête les lectures restantes (`Reader::RateLimited`). Le 2026-11-07, la clé du compte
  lexicon@osfarm.org avait une limite de 0 requête par minute : la fixture de SANTHAL GOLD est écrite à la main
  d'après le PDF, pas une réponse enregistrée.

## 1. Vue d'ensemble

```
collect (réseau)                              load (sans réseau)                    normalize (base)
─────────────────                             ──────────────────                    ────────────────
E-Phy : 2 zip, comme avant                    E-Phy : comme avant                   E-Phy : XML → tables, PCP (inchangé)
                                                                                        │
page du ministère ──▶ Page ──▶ avis           Archive ──▶ Decision (contrôles)          ▼
     │                         │              │            │                     derogation_products ──▶ produits absents
     ▼                         ▼              │            ▼                     derogation_usages  ──▶ usages DEROG:…
raw/…/derogations/  ◀── PDF nouveaux          │       CSV : products, usages,         │
     │                                        │             risks, refused            ▼
     └─ Reader (Mistral OCR) ─▶ <sha>.json ───┘       load_csv (schéma phytosanitary) cropsets / nomenclature / exceptions
        seulement s'il manque                                                        (rapprochement d'espèces, inchangé)
                                                                                        │
                                                                                     hash_table (inchangé)
```

Le réseau et Mistral ne servent qu'en `collect`. `load` et `normalize` ne lisent que `raw/` : un build rejoué sans
réseau ni clé donne le même paquet (critère 4).

## 2. Fichiers

```
lib/datasources/phytosanitary.rb                       collect/load/normalize appellent Derogations ; colonnes ; credits ; source_date
lib/datasources/phytosanitary/derogations.rb           module, constantes (URL de la page, modèle OCR, schéma JSON)
lib/datasources/phytosanitary/derogations/page.rb      HTML de la page → avis (pur)
lib/datasources/phytosanitary/derogations/archive.rb   raw/phytosanitary/derogations/ : PDF, extractions, avis vus
lib/datasources/phytosanitary/derogations/reader.rb    appel Mistral OCR (Net::HTTP), seul code réseau avec Page#fetch
lib/datasources/phytosanitary/derogations/decision.rb  extraction + avis + catalogue → décision contrôlée (pur)
lib/datasources/phytosanitary/derogations/rows.rb      décisions retenues → lignes des CSV (pur)
test/lexicon/datasources/phytosanitary_derogations_test.rb
test/fixtures/phytosanitary_derogations/                page.html réduite, extraction de SANTHAL GOLD
doc/datasources/phytosanitary.md                       fiche (nouvelle) : E-Phy, PCP, dérogations
```

Tout est en Ruby, comme `Datasources::FuelPrices::Readings` et les lecteurs de `fertilizers` ; le Python d'E-Phy
n'est pas touché.

## 3. Composants

### 3.1 `Page`

`Page.parse(html, base_url) → [Notice]`, où `Notice = Struct(:amm, :name, :crops, :pdf_url)`.

- Ancres `<a href="/telecharger/{id}">` dont le libellé commence par `n°{chiffres}` (les autres ancres sont des menus
  ou la notice générique de l'article 53).
- `crops` : le texte « Culture(s) concernée(s) : … » **avant** l'ancre, borné à l'ancre précédente (relevé de
  cropivia, vrai le 2026-11-07).
- Une page qui ne donne aucun avis, alors que l'archive en connaît, lève une erreur claire : la structure a changé
  (NF2). `collect` l'attrape, le dit, et continue avec l'archive.

### 3.2 `Archive`

Répertoire `raw/phytosanitary/derogations/` (gardé sur le poste de build, jamais vidé par `collect`) :

| Fichier | Contenu |
|---|---|
| `page_<AAAA-MM-JJ>.html` | la page du jour, comme `fuel_prices` |
| `<sha>.pdf` | le PDF, `<sha>` = 24 premiers caractères du SHA-256 (comme cropivia) |
| `<sha>.notice.json` | l'avis tel que la page le donnait, `first_seen_on`, `last_seen_on` |
| `<sha>.ocr.json` | la réponse de Mistral : `document_annotation` et `pages[].markdown` |

- Un PDF déjà présent n'est pas retéléchargé : on télécharge chaque `/telecharger/{id}` absent de l'index des avis,
  puis on range par empreinte (un même PDF sous deux id n'est gardé qu'une fois).
- `last_seen_on` dit qu'une décision est encore sur la page ; il ne sert qu'à l'information (F8 : une décision
  disparue reste construite).
- Ajouter une décision à la main (critère 2, SANTHAL GOLD) : déposer le PDF dans le répertoire ; `collect` crée
  l'avis manquant (AMM et nom lus ensuite dans l'extraction) et le lit.

### 3.3 `Reader`

`Reader.new(api_key:, model: 'mistral-ocr-latest').read(pdf_bytes) → Hash` :

- `POST https://api.mistral.ai/v1/ocr`, corps :
  `{model, document: {type: 'document_url', document_url: 'data:application/pdf;base64,…'},
  document_annotation_format: {type: 'json_schema', json_schema: {name: 'derogation', strict: true, schema: SCHEMA}},
  include_image_base64: false}`.
- `SCHEMA` : celui de cropivia **sans** `is_fraisier`, avec `amm`, `name`, `titulaire`, `substances[]`,
  `danger_statements[]` (code H et phrase), `conditions[]`, `derogation_start`, `derogation_end`, et `usages[]` :
  `code_usage`, `libelle`, `crop_restriction` (« Pépinière de Fraisier »), `milieu`, `dose_max`, `unite_dose_max`,
  `max_application_phrase`, `bbch_min`, `bbch_max`, `dar_jour`.
- Limite de `document_annotation` : 8 pages. Une décision plus longue est refusée par `Decision` (le texte des pages
  reste gardé) et listée.
- Clé : `MISTRAL_API_KEY` du `.env` (compte lexicon@osfarm.org), déjà passée au runner par `env_file`. Sans clé,
  `collect` dit combien de PDF n'ont pas d'extraction et s'arrête là pour eux (NF1).
- Une erreur sur un PDF n'arrête pas les autres ; elle est affichée avec l'URL.

### 3.4 `Decision`

`Decision.new(notice:, ocr:, catalogue:)`, où `catalogue` est `{lib_court => ephy_usage_phrase}` tiré de la table
brute E-Phy. Expose `valid?`, `errors` (phrases), `amm`, `name`, `started_on`, `stopped_on`, `usages`, et les champs du
produit.

Contrôles (F3) :

1. AMM de l'annotation = AMM de l'avis = AMM relue dans le texte (`Numéro d’AMM\s+(\d{7})`).
2. Dates de l'annotation = dates relues (`délivrée en France du (\d\d/\d\d/\d{4}) au (\d\d/\d\d/\d{4})`) ;
   début ≤ fin ; fin − début ≤ 130 jours (120 et une marge pour un arrondi de publication).
3. Au moins un usage.
4. Pour chaque usage : code connu du catalogue E-Phy, sinon libellé de la forme `Culture*…*…` ; dose positive ;
   stades entre 0 et 99, min ≤ max ; milieu reconnu (`plein champ`, `sous abri`, ou absent).
5. Quand le code est connu, la phrase du catalogue remplace celle de l'OCR (l'OCR découpe
   `loc.* Champignons`).

Une décision invalide va dans `derogations_refused.csv` avec ses raisons ; le build affiche le compte et la liste.

**Choix entre plusieurs PDF** d'une même décision (F9) : la clé d'une décision est `(amm, started_on)`. Deux PDF de
même clé (décision corrigée, republiée) : le plus récemment vu l'emporte. Une décision de même AMM avec un autre début
(prolongation, nouvelle saison) est **une autre décision** : les deux restent, la première échue.

### 3.5 `Rows`

Décisions retenues → trois CSV chargés par `load_csv` dans le schéma brut `phytosanitary` :

- `derogation_products` : une ligne par AMM, tirée de sa décision la plus récente ; `started_on` = plus ancien début,
  `stopped_on` = plus récente fin.
- `derogation_usages` : une ligne par usage de chaque décision.
- `derogation_risks` : codes H et phrases (pour les produits absents d'E-Phy).

## 4. Modèle de données

### 4.1 Colonnes ajoutées (`schema_revision 2`)

```sql
-- registered_phytosanitary_usages
is_derogation boolean NOT NULL DEFAULT false,
derogation_started_on date,
derogation_stopped_on date,
derogation_url character varying          -- URL du PDF sur agriculture.gouv.fr (F10)

-- registered_phytosanitary_products
is_derogation boolean NOT NULL DEFAULT false   -- vrai pour les seuls produits créés depuis une dérogation
```

Colonnes ajoutées en fin de table : le Python d'E-Phy insère par position (`INSERT … VALUES (%s × 27)`) les
27 premières colonnes et laisse les autres à leur défaut. Un index partiel
`registered_phytosanitary_usages_derogation ON (product_id) WHERE is_derogation` sert à les retrouver.

### 4.2 Usage dérogatoire

| Colonne | Valeur |
|---|---|
| `id` | `DEROG:{amm}:{code}:{milieu}:{AAAAMMJJ du début}` (`milieu` ∈ `plein_champ`, `sous_abri`, `na`) — le code seul n'est pas unique dans une décision, et une AMM peut revenir à une autre saison |
| `lib_court` | le code de l'usage |
| `product_id` | l'AMM |
| `ephy_usage_phrase`, `crop`, `crop_label_fra`, `target_name`, `target_name_label_fra`, `treatment`, `species` | **copiés d'un usage E-Phy de même `lib_court`** quand il en existe (même rapprochement d'espèces que lui) ; sinon tirés de la phrase par le même découpage (`Culture*Traitement*Fonction`), et `species` laissé au rapprochement par cropsets, nomenclature et `exceptions` de `normalize` |
| `dose_quantity`, `dose_unit_name`, `dose_unit`, `dose_unit_factor` | dose et unité de la décision, unité normalisée par `units.yml` (le fichier du Python, lu par Ruby) |
| `applications_count` | premier entier de « Nombre maximum d'applications » |
| `development_stage_min`, `_max` | stades BBCH |
| `pre_harvest_delay` | délai en jours ; « / » donne `P3D`, comme le Python d'E-Phy pour un usage sans délai |
| `usage_conditions` | « Autorisé uniquement sur : {restriction} ({milieu}). » + nombre et intervalle d'applications en toutes lettres + conditions d'emploi de la décision |
| `untreated_buffer_aquatic` | la ZNT de `SPe 3 : … zone non traitée de N mètres`, si la décision en donne une |
| `decision_date` | début de la dérogation |
| `state` | `authorized` si la date du build est entre début et fin, `withdrawn` sinon |
| `is_derogation`, `derogation_started_on`, `derogation_stopped_on`, `derogation_url` | |

### 4.3 Produit absent d'E-Phy

Inséré **après** E-Phy et les PCP, `ON CONFLICT (id) DO NOTHING` : un produit E-Phy n'est jamais touché, et une AMM
dérogatoire qui entre plus tard dans E-Phy y prend sa ligne E-Phy.

| Colonne | Valeur |
|---|---|
| `id`, `france_maaid` | l'AMM |
| `reference_name` | même règle que les PCP : `lower(regexp_replace(amm || ' ' || nom, '[^a-zA-Z0-9]', '_'))` |
| `name`, `firm_name` | nom commercial, titulaire (première ligne) |
| `active_compounds` | substances et concentrations, au format des produits E-Phy |
| `natures` | vide (la décision ne le dit pas) |
| `state` | `authorized` si une de ses décisions court, `withdrawn` sinon |
| `started_on`, `stopped_on` | plus ancien début, plus récente fin |
| `product_type` | `DEROGATION` |
| `is_derogation` | vrai |

Ses mentions de danger vont dans `registered_phytosanitary_risks`.

### 4.4 Ordre dans `normalize`

1. Python E-Phy, `applications_frequency`, PCP (inchangés).
2. **Dérogations** : produits absents, puis usages (copie des colonnes de culture depuis un usage E-Phy de même
   `lib_court`).
3. Cropsets, nomenclature, `exceptions`, symboles, cibles PFI, volumes de bouillie (inchangés, ils voient aussi les
   usages dérogatoires sans `species`).
4. `hash_table` (inchangé).

### 4.5 Déclarations

```ruby
schema_revision 2
credits name: 'Autorisations de mise sur le marché d’une durée maximale de 120 jours', url: PAGE_URL,
        provider: 'Ministère de l’Agriculture', licence: 'Licence Ouverte 2.0', licence_url: …, updated_at: …
source_date 'SELECT max(decision_date) FROM registered_phytosanitary_usages'
```

`credits` s'ajoute à celui de l'ANSES (le DSL garde une liste). `source_date` porte la date de la décision la plus
récente, E-Phy comprise.

## 5. Conséquences à connaître

- **L'état n'est juste qu'au jour du build.** Une dérogation qui finit un mercredi reste `authorized` jusqu'au build
  du lundi suivant. Un client qui veut la date exacte lit `derogation_stopped_on`.
- **Produit E-Phy retiré avec une dérogation en cours** (MOVENTO, DESOGERME) : son usage dérogatoire est
  `authorized`, mais le produit reste `withdrawn` (décision du cadrage). La recherche de l'API, qui exige les deux, ne
  le montrera pas ; Ekylibre selon son propre filtre.
- **`lexicon-rest-api`** : ajouter `DEROGATION` (et `PRODUIT-MIXTE`, déjà absent) à `ProductType` ; afficher
  « dérogation jusqu'au … » sur un usage `is_derogation`. Hors de ce chantier, à faire dans l'API.
- **Ekylibre** : à vérifier sur ses sources (aucune sur ce poste) qu'un id d'usage non numérique, un
  `product_type` inconnu et des colonnes en plus ne cassent pas la synchronisation. Ce point bloque la mise en
  production, pas le développement.
- **Coût Mistral** : 37 PDF de 4 pages environ au premier passage, puis quelques-uns par semaine.

## 6. Tests (sans réseau ni base)

- `Page` : la page du 2026-11-07 réduite à trois cartes, dont une avec plusieurs cultures et l'ancre de la notice
  générique, donne trois avis avec leurs cultures.
- `Decision` : l'extraction de SANTHAL GOLD (réponse Mistral enregistrée une fois et gardée en fixture) donne
  4 usages, ids `DEROG:2230002:16552204:plein_champ:20260702`…, dates du 02/07 au 30/10/2026 ; AMM, dates ou code
  faussés un à un donnent chacun une raison de refus ; phrase OCR remplacée par celle du catalogue.
- Choix entre deux PDF de même `(amm, started_on)` ; deux saisons d'une même AMM restent deux décisions.
- `Rows` : état `withdrawn` au 2026-11-07, `authorized` au 2026-08-01 (date passée en argument).
- `Reader` : corps de requête construit (sans appel), réponse illisible → erreur claire.

## 7. Mise en œuvre et vérification

1. `Page`, `Archive`, `Reader` et `collect` ; premier passage sur le poste de build (37 PDF, extraction gardée).
2. `Decision`, `Rows`, `load` ; relire `derogations_refused.csv`.
3. Colonnes, `normalize`, `schema_revision 2`, credits, `source_date`.
4. `./lexicon run phytosanitary`, `./lexicon check phytosanitary`, puis vérifier les critères 1 à 5 en SQL.
5. Ekylibre (critère 6) et API avant `ship --production`.
6. Ajouter `phytosanitary` à la routine du lundi (`doc/datasources/intrants.md`, « Chaque semaine ») ; fiche
   `doc/datasources/phytosanitary.md` ; CLAUDE.md.
