# Bulletins de santé du végétal (BSV) — conception

Conception du 2026-11-08, à partir de `brainstorm_bsv.md` (exigences F1–F14, N1–N7, décisions) et de l'essai du même
jour (`bsv_essai/`). Le modèle est la lecture des dérogations de `phytosanitary`
(`design_phyto_derogations.md`) : archive de PDF jamais vidée, lecture par un modèle une seule fois par PDF, contrôle
sans réseau dans `load`.

## 0. Inventaire des sources (2026-11-08)

Fiches par région dans `bsv_essai/inventaire/`. Les 13 régions métropolitaines publient leurs BSV sur le site SPIP de
leur DRAAF (DRIAAF en Île-de-France), sous `/IMG/pdf/`, que leur `robots.txt` autorise (`Crawl-delay: 1`). Aucun n'a
de JavaScript ni de formulaire. Environ **2 400 PDF en 2026**.

| Région | Racine BSV sur la DRAAF | 2026 | Archives | À savoir |
|---|---|---:|---|---|
| Auvergne-Rhône-Alpes | `bulletin-de-sante-du-vegetal-r51.html` | ~170 | 2022 (2022–2024 à la chambre) | rubriques réutilisées d'une année à l'autre, année fausse dans le slug ; 2025 dans une rubrique d'archivage trouvée par le sitemap |
| Bourgogne-Franche-Comté | `bulletins-de-sante-du-vegetal-bsv-r345.html` | ~100 | 2018 | un article par filière et campagne, qui grossit en place ; grandes cultures à cheval sur deux ans |
| Bretagne | (DRAAF partielle) | ~132 à la chambre | 2016 DRAAF, 2022 chambre | **la chambre a tout** (TYPO3, dossier autorisé) ; la DRAAF n'a plus les légumes de transformation |
| Centre-Val de Loire | `acces-au-bsv-r37.html` | ~205 | 2015 | structure différente chaque année, slugs muets |
| Corse | `les-bulletins-de-sante-du-vegetal-bsv-r53.html` | ~48 | 2021 | la chambre a parfois plus (viticulture), mais son `robots.txt` l'interdit à la lettre |
| Grand Est | `bulletins-de-sante-du-vegetal-bsv-r75.html` | ~270 | 2015 | redirections `meta refresh` ; noms réguliers |
| Hauts-de-France | `les-bulletins-de-sante-du-vegetal-bsv-r37.html` | ~160 | 2016 | un article par bulletin ; date dans le titre de l'article |
| Île-de-France | `bulletins-de-sante-du-vegetal-bsv-r195.html`, `archives-bsv-r197.html` | ~120 | 2023 | PDF sans date ni année dans le nom |
| Normandie | `bulletin-de-sante-du-vegetal-r114.html` | ~170 | 2015 | « Campagne AAAA » à cheval sur deux ans pour céréales et colza |
| Nouvelle-Aquitaine | rubrique `r71`, puis une rubrique par année | ~438 | 2023 | l'article 2026 contient aussi les bilans 2025 |
| Occitanie | rubrique `r103` | ~320 | 2025 DRAAF, 2023 chambre | la chambre est plus complète (TYPO3, dossier autorisé) ; éditions Sud-Ouest communes avec la Nouvelle-Aquitaine |
| Pays de la Loire | `bulletins-de-sante-du-vegetal-a162.html` (page unique) | 166 | **aucune** | page réécrite chaque campagne : ce qui n'est pas collecté pendant la campagne est perdu ; viticulture reconnue à la section de la page |
| Provence-Alpes-Côte d'Azur | `bulletins-de-sante-du-vegetal-bsv-r267.html` | ~140 | 2015 | titres d'articles peu fiables (le nom du PDF l'est plus) ; bulletins d'alerte mêlés |

Conséquences :

- **Un lecteur SPIP générique** couvre les 13 DRAAF. Il découvre rubriques et articles par le **sitemap SPIP**
  (`spip.php?page=sitemap-rub.xml`, `sitemap-art.xml&annee=AAAA`) à partir de la racine BSV, suit la pagination
  `debut_listearticles` et les `meta refresh`. `sources.yml` ne donne que la racine de chaque site, pas une rubrique
  par année (les identifiants changent tous les ans).
- **Date et numéro lus dans le bulletin** (en-tête, par l'extraction), l'intitulé de l'article ou du lien gardé dans
  la notice comme second repère ; jamais le nom du fichier.
- **Doublons entre régions** : fruits à transformer (Bretagne, Pays de la Loire), châtaigne, noix, melon,
  horticulture-pépinière (Nouvelle-Aquitaine, Occitanie), grandes cultures « Arc méditerranéen » (PACA, Occitanie).
  L'empreinte du PDF couvre les copies identiques ; sinon même filière, numéro et date → un seul bulletin, couvrant
  les départements des deux régions.
- **Ecophytopic ne peut pas servir au contrôle de couverture** : son `robots.txt` interdit `/search/`. Le contrôle
  passe par une liste attendue (§3.8).
- **Les chambres** ne sont lues que là où la DRAAF manque des éditions et où le `robots.txt` l'autorise (Bretagne,
  peut-être Occitanie) : un second lecteur, TYPO3, à décider (§9). Pas les chambres de Corse et des Pays de la Loire
  (`robots.txt` qui les interdit à la lettre).

## 1. Vue d'ensemble

Deux datasources, parce qu'elles n'ont ni le même rythme ni la même source :

| Datasource | Contenu | Rythme | Accès |
|---|---|---|---|
| `bsv` | Les bulletins en ligne sur les sites des DRAAF : catalogue, texte des pages, lignes de risque extraites | chaque semaine | ouvert |
| `bsv_archive` | Le corpus PestObserver (1960–2016) : catalogue et texte, sans extraction | une fois | ouvert (CC-BY) |

```
                       collect (réseau)                         load (sans réseau)          normalize
sites DRAAF ──► Crawler ──► Archive raw/bsv/<sha>.pdf ──┐
  (sources.yml, sitemap)     <sha>.notice.json          │
                             <sha>.pages.json (pdftotext)│
                                                        ├──► Extraction ──► tables brutes ──► registered_bsv_*
Archive ──► Batch (Haiku 5.5, tous les nouveaux) ───────┤     (contrôles)                     + zones → départements
        └─► Batch (Opus 5.5, 5 par semaine) ──► Control ┘                                     + cultures → productions
                                                                                              + lieux → INSEE
editions.csv (attendu) ──► Coverage : ce qui manque, dit par le build                          + Zadoks → BBCH
```

`collect` est la seule phase qui touche le réseau et l'API Anthropic. Un build rejoué sans réseau ni clé redonne le
même paquet à partir de `raw/bsv/`.

## 2. Fichiers

```
lib/datasources/bsv.rb                      la datasource : collect, load, normalize, tables
lib/datasources/bsv/sources.rb              lit data/bsv/sources.yml
lib/datasources/bsv/crawler.rb              rubriques SPIP des DRAAF → articles → PDF (une requête par seconde)
lib/datasources/bsv/archive.rb              raw/bsv/ : PDF, notices, pages, extractions, lots en cours
lib/datasources/bsv/pages.rb                pdftotext page par page
lib/datasources/bsv/extractor.rb            lots Anthropic : envoi, reprise, relevé (gem anthropic)
lib/datasources/bsv/schema.rb               SCHEMA JSON et version de la consigne
lib/datasources/bsv/extraction.rb           contrôle d'une réponse (comme Derogations::Decision)
lib/datasources/bsv/control.rb              comparaison Haiku / Opus sur l'échantillon
lib/datasources/bsv/coverage.rb             éditions attendues (data/bsv/editions.csv) contre ce qui a été collecté
lib/datasources/bsv/rows.rb                 lignes des tables brutes
lib/datasources/bsv_archive.rb              PestObserver
data/bsv/consigne.md                        la consigne (prompt système), versionnée
data/bsv/sources.yml                        une entrée par région : site DRAAF, racine BSV, filtres
data/bsv/editions.csv                       éditions attendues par région (région, filière, zone, période de parution)
data/bsv/zones.csv                          région, zone → départements
data/bsv/cultures.csv                       nom de culture du bulletin → productions de Lexicon
data/bsv/zadoks.csv                         code Z → code BBCH (céréales)
doc/datasources/bsv.md                      la fiche
test/lexicon/datasources/bsv_test.rb        tests sans réseau ni base
test/fixtures/bsv/                          une rubrique, un article, deux réponses de lot
```

## 3. Composants

### 3.1 `Sources` et `data/bsv/sources.yml`

Une entrée par région métropolitaine (13), tirée de l'inventaire (§0) :

```yaml
grand-est:
  site: https://draaf.grand-est.agriculture.gouv.fr/
  root: bulletins-de-sante-du-vegetal-bsv-r75.html   # racine BSV ; les années se découvrent sous elle
  exclude: [note, fiche, poster]                       # noms de PDF qui ne sont pas des bulletins (catalogue seul)
pays-de-la-loire:
  site: https://draaf.pays-de-la-loire.agriculture.gouv.fr/
  pages: [bulletins-de-sante-du-vegetal-a162.html]     # page qui liste directement les PDF, par sections
  section_is_sector: true                              # la section de la page donne la filière (viticulture)
auvergne-rhone-alpes:
  site: https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/
  root: bulletin-de-sante-du-vegetal-r51.html
  extra_roots: [archivage-2025-r1672.html]             # rubrique d'archivage non liée depuis la racine
```

`since` (année) limite la reprise des archives ; par défaut l'année en cours et la précédente.

### 3.2 `Crawler`

- Lit le sitemap SPIP du site (`sitemap-rub.xml`, puis `sitemap-art.xml&annee=…` pour chaque année depuis
  `since`) et garde les rubriques et articles placés sous la racine BSV (la hiérarchie vient du sitemap ou de la
  page de la rubrique). Lit chaque article retenu, suit `meta refresh` et la pagination `debut_listearticles`, et
  relève les liens `IMG/pdf/*.pdf` avec leur intitulé et le titre de l'article.
- Une requête par seconde par site (`Crawl-delay: 1`), `User-Agent` `Lexicon OSFarm (+https://lexicon.osfarm.org)`,
  `robots.txt` lu et respecté (N1).
- Ne télécharge que les PDF dont l'URL n'est pas déjà dans l'archive (`Archive#known_urls`). Un article qui grossit
  en place (Bourgogne-Franche-Comté) est relu à chaque collecte ; seuls ses PDF nouveaux sont téléchargés.
- Rend, pour chaque PDF, une `Notice` : région, URL et titre de l'article, intitulé du lien, section de la page,
  URL et nom du PDF.

### 3.3 `Archive` (`raw/bsv/`)

Même principe que `Derogations::Archive`, jamais vidée :

```
raw/bsv/<sha>.pdf               le PDF, nommé par les 24 premiers caractères de son SHA-256
raw/bsv/<sha>.notice.json       région, article, URL, first_seen_on, last_seen_on
raw/bsv/<sha>.pages.json        le texte de chaque page (pdftotext), pour la recherche et le contrôle des citations
raw/bsv/<sha>.haiku.json        la réponse de Haiku, avec le modèle, la version de la consigne, l'usage en tokens
raw/bsv/<sha>.opus.json         la réponse d'Opus, pour les bulletins de l'échantillon de contrôle
raw/bsv/batches/<id>.json       un lot envoyé et pas encore relevé : identifiants, modèle, bulletins
raw/bsv/coverage_<date>.json    l'index d'Ecophytopic du jour
```

Un même PDF publié deux fois (même empreinte) n'est gardé qu'une fois. Un PDF déposé à la main est lu comme les
autres. Une extraction est refaite seulement si la version de la consigne ou le modèle changent **et** qu'on le
demande (`LEXICON_BSV_REEXTRACT=1`) : jamais d'office (N2).

### 3.4 `Extractor` (API Anthropic)

- **SDK** : la gem officielle `anthropic` (à ajouter au `Gemfile` ; le conteneur a Ruby 3.2.11). Clé
  `ANTHROPIC_API_KEY` du `.env`, comme `MISTRAL_API_KEY`. La forme exacte des appels de lot en Ruby
  (`client.messages.batches`) est à prendre dans le dépôt du SDK au moment de l'écrire.
- **Requête** (une par PDF) : `model`, `max_tokens: 32_000`, `system_` = la consigne avec
  `cache_control: { type: "ephemeral" }`, `output_config: { effort: "medium", format: { type: "json_schema",
  schema: SCHEMA } }`, un message utilisateur avec le PDF en `document` base64 puis une ligne de texte. Comme dans
  `bsv_essai/extract_claude.py`.
- **Lots** : tous les nouveaux bulletins vont à Haiku 5.5 (`claude-haiku-5-5`) ; cinq d'entre eux, tirés dans des
  filières différentes, vont aussi à Opus 5.5 (`claude-opus-5-5`) dans le même lot. Un lot ne dépasse pas 100 Mo
  (la limite est 256 Mo) : au-delà, plusieurs lots.
- **Attente** : `collect` attend la fin du lot jusqu'à `LEXICON_BSV_WAIT` (90 min par défaut), en relevant l'état
  toutes les minutes. Au-delà, le lot reste dans `raw/bsv/batches/` et la collecte suivante le relève d'abord ; les
  bulletins en attente n'entrent pas dans le paquet de cette semaine, et le build le dit.
- **Échecs** : une réponse `errored` ou `expired` est renvoyée au lot suivant (deux fois au plus, puis listée) ; une
  réponse `refusal` ou coupée (`max_tokens`) est gardée avec son motif et listée par `load`. Pas de repli
  automatique sur un autre modèle : l'API Batches ne le permet pas.
- **Garde-fou de coût** : au-delà de `LEXICON_BSV_MAX_NEW` bulletins nouveaux dans une collecte (300 par défaut),
  `collect` s'arrête avant d'envoyer et dit combien il en a trouvé ; la reprise des archives se fait avec la
  variable relevée, en connaissance de cause (environ 0,004 $ par bulletin avec Haiku).

### 3.5 `Schema` et `data/bsv/consigne.md`

La consigne est `bsv_essai/consigne_extraction.md` avec les décisions prises après l'essai. Champs ajoutés ou changés
par rapport à l'essai :

| Champ | Où | Pourquoi |
|---|---|---|
| `regions_citees` | en-tête | bulletins communs à plusieurs régions (« Normandie, Bretagne, Pays de la Loire ») |
| `zadoks_min`, `zadoks_max` | ligne | le modèle recopie le code Z tel qu'écrit ; Lexicon le convertit en BBCH (§4.4) |
| `conditionnel`, `condition` | ligne | risque qui dépend d'une condition : niveau le plus haut, drapeau, texte de la condition |

La version de la consigne est l'empreinte de `consigne.md` et de `SCHEMA` ; elle est écrite dans chaque
`<sha>.haiku.json`. Changer la consigne ne refait rien d'office (3.3).

### 3.6 `Extraction` (dans `load`, sans réseau)

Contrôle de chaque réponse, comme `Derogations::Decision`. Une **ligne** est refusée, et listée avec sa raison,
quand :

- sa phrase source ne se retrouve pas dans le texte des pages (normalisé : minuscules, accents et ponctuation
  retirés) — sauf pour un PDF sans texte (scanné), où le contrôle est sauté et le bulletin marqué `scanned` ;
- la culture est identique au bioagresseur ;
- un code BBCH ou Zadoks sort de 0 à 99, ou le minimum dépasse le maximum ;
- le niveau n'est pas dans l'échelle.

Un **bulletin** entre au catalogue sans lignes de risque quand sa nature est `bilan` ou `note` (décision), ou
quand sa réponse manque (refus, coupure, lot en attente). Sa date de publication est celle de l'en-tête ; un écart
de plus de 10 jours avec `first_seen_on` est signalé. Deux PDF d'un même bulletin (même région, filière, zone,
numéro et année : une version corrigée « _v2 ») : celui vu en dernier l'emporte, l'autre reste au catalogue
marqué `superseded_by`.

### 3.7 `Control` (échantillon Opus)

Pour chaque bulletin de l'échantillon, apparie les lignes Haiku et Opus (culture et bioagresseur normalisés, comme
dans l'essai) et compte : lignes d'Opus absentes chez Haiku, niveaux différents, niveaux donnés par Haiku seul.
Le build affiche le résultat de la semaine et un avertissement au-delà des seuils (part des lignes d'Opus
retrouvées sous 80 %, accord de niveau sous 85 %). Les comptes s'ajoutent à `raw/bsv/controls.csv` (une ligne par
semaine) pour suivre la tendance. Les lignes publiées sont toujours celles de Haiku : Opus mesure, il ne remplace
pas.

### 3.8 `Coverage`

`data/bsv/editions.csv` liste les éditions attendues (région, filière, zone, mois de parution), tirées de
l'inventaire. Le build dit les éditions sans aucun bulletin collecté, et celles sans bulletin depuis plus de
15 jours pendant leurs mois de parution (F3, N6). Une édition nouvelle, trouvée par le `Crawler` et absente du
fichier, est listée pour qu'on l'ajoute. (Ecophytopic ne sert pas : son `robots.txt` interdit `/search/`.)

## 4. Modèle de données (`bsv`)

### 4.1 Tables

```sql
CREATE TABLE registered_bsv_bulletins (
  id character varying PRIMARY KEY NOT NULL,     -- <sha> du PDF
  region character varying NOT NULL,             -- région émettrice (slug de sources.yml)
  zone character varying,                        -- édition infra-régionale (« Aquitaine »)
  department_codes character varying[] NOT NULL, -- territoire couvert (§4.4)
  sector character varying,                      -- filière
  subsector character varying,                   -- « kiwi », « fruits à noyau »
  number character varying,
  published_on date,                             -- date de l'en-tête
  first_seen_on date NOT NULL,
  nature character varying NOT NULL,             -- bulletin, bilan, note
  title character varying,
  article_url character varying NOT NULL,
  pdf_url character varying NOT NULL,
  pages_count integer,
  status character varying NOT NULL,             -- extracted, catalogue_only, pending, refused, scanned
  superseded_by character varying,
  model character varying,                       -- modèle de l'extraction publiée
  instructions_version character varying,
  citation character varying NOT NULL            -- « extrait du bulletin de santé du végétal … N°X du JJ/MM/AA » (F14)
);

CREATE TABLE registered_bsv_pages (
  bulletin_id character varying NOT NULL,
  page integer NOT NULL,
  text text NOT NULL,
  search tsvector NOT NULL DEFAULT ''::tsvector, -- comme rd_agri : français, accents retirés
  PRIMARY KEY (bulletin_id, page)
);

CREATE TABLE registered_bsv_risks (
  id character varying PRIMARY KEY NOT NULL,     -- <bulletin_id>:<rang>
  bulletin_id character varying NOT NULL,
  crop character varying NOT NULL,               -- tel qu'écrit dans le bulletin
  production_names character varying[],          -- rattachement (§4.4), vide si inconnu
  pest character varying,                        -- null : ligne de stade
  pest_type character varying,                   -- maladie, ravageur, adventice, auxiliaire, physiologique
  stage character varying,
  bbch_min integer, bbch_max integer,            -- écrits, ou convertis depuis Zadoks
  level character varying NOT NULL,              -- nul, faible, moyen, fort, tres_fort, non_precise
  level_text character varying,
  conditional boolean NOT NULL DEFAULT false,
  condition character varying,
  risk_period character varying,
  threshold character varying,
  observations text,
  page integer,
  source_quote text NOT NULL
);

CREATE TABLE registered_bsv_risk_places (       -- gardés, pas servis par l'API pour le moment (décision)
  risk_id character varying NOT NULL,
  name character varying NOT NULL,               -- tel qu'écrit (« Asques 33 »)
  insee_code character varying                   -- null si aucune ou plusieurs communes
);
```

Index : `bulletins(published_on)`, `bulletins USING GIN (department_codes)`, `risks(bulletin_id)`,
`risks USING GIN (production_names)`, `risks(pest)`, `pages USING GIN (search)`.

Clés étrangères dans le paquet : `pages.bulletin_id`, `risks.bulletin_id` et `risk_places.risk_id` vers leurs
tables. Aucune vers d'autres jeux : les productions et les communes sont rattachées par valeur, comme
`TabularDatasource` le fait pour `insee_code`.

### 4.2 Ce qui n'est pas publié

Les noms et adresses des animateurs (N4) : la consigne ne les demande pas et rien ne les reprend. Les comptes du
contrôle Opus restent dans `raw/` et la sortie du build.

### 4.3 Déclarations

```ruby
description 'Bulletins de santé du végétal : catalogue, texte et risques par culture et bioagresseur'
credits name: 'Bulletins de santé du végétal', provider: 'Réseaux d\'épidémiosurveillance (DRAAF, chambres d\'agriculture)',
        url: 'https://agriculture.gouv.fr/le-bulletin-de-sante-du-vegetal', licence: 'Reproduction autorisée avec mention de la source'
licence_exception 'Les bulletins autorisent la reproduction intégrale, et partielle avec la mention du bulletin ; chaque ligne la porte'
depends_on :postal_codes                      # lieux → INSEE pendant normalize
source_date 'SELECT max(published_on) FROM registered_bsv_bulletins'
```

Pas de `pivot` : le territoire d'un bulletin est une liste de départements, pas une commune.

Sans bulletin nouveau, `package` n'écrit pas de version (N5).

### 4.4 Ordre dans `normalize`

1. Bulletins et pages, depuis les tables brutes.
2. Territoire : `data/bsv/zones.csv` donne les départements d'une région et d'une zone ; s'y ajoutent ceux des
   `regions_citees`. Une zone inconnue est listée et le bulletin prend les départements de sa région émettrice.
3. Lignes de risque ; codes Zadoks convertis par `data/bsv/zadoks.csv` quand BBCH n'est pas écrit.
4. Cultures : `data/bsv/cultures.csv` (`crop`, `production_names` séparés par `|`) ; les noms sans correspondance
   sont listés par le build, pour compléter le fichier.
5. Lieux : nom et département cherchés dans `registered_postal_codes` (même normalisation que
   `TabularDatasource`) ; pas de code quand aucune ou plusieurs communes répondent.
6. `search` des pages : `setweight(to_tsvector('french', unaccent(text)), 'B')`, le titre en `A`.

Une ligne refusée par `Extraction` n'entre pas ; le bulletin garde ses autres lignes.

## 5. `bsv_archive` (PestObserver)

- `collect` : télécharge `reportsOCR.zip` (173 Mo) de data.gouv.fr une fois, garde le zip dans `raw/bsv_archive/`.
- `load` : lit les 23 542 textes et les 17 286 TEI XML ; déduit du nom de fichier et de l'en-tête la région
  (ancienne), la filière et la date quand c'est possible ; le reste est null.
- Tables : `registered_bsv_archive_documents (id, file_name, kind, old_region, department_codes, sector,
  published_on, title, text, search)`. `department_codes` vient d'une table ancienne région → départements
  (`data/bsv/old_regions.csv`, F11).
- Pas d'extraction de risques (décision). Construit une fois ; reconstruit seulement si le corpus change.

## 6. Côté `lexicon-rest-api`

**Fait** : en service depuis la 1.7.0 (2026-11-15), la recherche classée bulletins d'aujourd'hui d'abord et
la page d'accueil en 1.7.1 le même jour ; ce qui est servi est décrit dans `doc/datasources/bsv.md`, « Côté API ».
Le cadrage d'origine :

- `GET /bsv/risks?commune=<insee>&production=<name>&date=<AAAA-MM-JJ>` : les lignes du dernier bulletin de chaque
  filière qui couvre le département de la commune, à la date donnée, avec la citation et le lien du PDF.
- `GET /bsv/bulletins/<id>` : un bulletin, ses lignes, ses pages.
- `GET /bsv/search?q=…&department=…&from=…` : recherche plein texte dans `bsv` et `bsv_archive`.
- MCP `get_crop_health_risks(commune, crop)` : « quels risques sur mon colza à Agen cette semaine ? » (user story 1).
- Les lieux (`registered_bsv_risk_places`) ne sont pas servis. Un risque extrait n'est jamais présenté comme une
  observation officielle : la réponse dit qu'il est tiré du bulletin cité (N3).

## 7. Tests (sans réseau ni base)

- `Crawler` : une rubrique et un article SPIP enregistrés (`test/fixtures/bsv/`), pagination, filtres `exclude`.
- `Extraction` : citation retrouvée ou non, culture = bioagresseur, bornes BBCH et Zadoks, PDF scanné, bilan,
  version corrigée qui en remplace une autre.
- `Extractor` : relevé d'un lot à partir de deux réponses enregistrées (succès, refus), reprise d'un lot en attente,
  garde-fou `LEXICON_BSV_MAX_NEW`. Le client Anthropic est remplacé par un double ; aucun appel réel.
- `Control` : appariement et comptes sur deux réponses de l'essai.
- Zones, cultures, Zadoks : chaque ligne des fichiers de `data/bsv/` se lit, et les départements existent.

## 8. Mise en œuvre et vérification

1. ~~Inventaire des sites DRAAF~~ : fait le 2026-11-08 (§0, `bsv_essai/inventaire/`) ; reste à écrire
   `sources.yml`, `editions.csv` et `zones.csv` à partir des fiches.
2. Consigne v2 (`data/bsv/consigne.md`) et `SCHEMA` ; un passage de Haiku sur les 19 bulletins de l'essai pour
   vérifier les champs ajoutés (environ 0,10 $).
3. `Archive`, `Crawler`, `Pages` ; collecte des bulletins de 2026 d'une région, sans extraction.
4. `Extractor`, `Extraction`, `Control` ; une région de bout en bout en local (`./lexicon run bsv`).
   **Fait le 2026-11-09** sur les 19 bulletins de l'essai (Haiku 0,09 $, Opus 0,64 $ pour 5) : 448 lignes, 8 refusées
   (citation absente du texte), contrôle Haiku/Opus 78 % des lignes retrouvées, 94 % de niveaux identiques. Le schéma
   ne doit pas dépasser 16 champs nullables (limite de l'API) : `page` et `remarques` sont obligatoires. Zadoks pris
   tel quel comme BBCH (même code décimal pour les céréales), sans `zadoks.csv`. `Coverage` fait depuis.
5. Toutes les régions, campagne 2026 (environ 2 400 bulletins, une dizaine de dollars avec Haiku), puis les
   archives disponibles (2015–2025 selon les régions, de l'ordre de 20 000 bulletins, moins d'une centaine de
   dollars), garde-fou relevé à la main. **Pays de la Loire d'abord** : sa page est réécrite chaque campagne.
6. Relecture par David d'un échantillon des lignes publiées (Q9) ; `./lexicon ship bsv` en local, puis production
   après accord. **Fait** : relecture de 60 lignes ; plutôt qu'une relecture complète (48 $), une passe de
   correction (`Correction`, 4,35 $ pour 4 810 bulletins) ; `bsv` en production le 2026-11-10, puis 2026.11.10.2
   (dates d'en-tête impossibles écartées) le 2026-11-15.
7. `bsv_archive` : **fait**, 40 828 documents, en production le 2026-11-15 (2026.11.10.1).
8. `lexicon-rest-api` : routes et outil MCP (§6). **Fait**, 1.7.0 puis 1.7.1 le 2026-11-15.
9. Routine hebdomadaire : `./lexicon ship bsv` ajouté à `doc/datasources/intrants.md`, « Chaque semaine ». **Fait**.

## 9. Points ouverts pour la mise en œuvre

- ~~Un second lecteur pour les sites TYPO3 des chambres~~ : décidé le 2026-11-08, **plus tard**. La première
  version lit les 13 DRAAF ; il manque les légumes de transformation de Bretagne et une partie de l'Occitanie.

- La forme exacte des appels de lot dans la gem `anthropic` (à lire dans son dépôt) et la version de la gem
  compatible avec le `Gemfile.lock` (Bundler 2.2).
- Le seuil de 10 jours entre date d'en-tête et première collecte vaut pour les bulletins de la semaine ; pour la
  reprise des archives, `first_seen_on` est la date de collecte et l'écart n'est pas signalé.
- `cultures.csv` démarre avec les noms de l'essai ; il se complète à partir de la liste des inconnus du build.
