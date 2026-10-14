# Bundles suivis, et chargement par Cultia : conception

Du 2026-10-13. Exigences : `claudedocs/brainstorm_bundles_cultia.md` (B1–B14,
C1–C8, N1–N5). Ce document décide de l'architecture ; il ne contient pas de
code. Suite : `/sc:implement`, lot par lot (§ 9).

## 0. Décisions

| # | Sujet | Décision |
|---|---|---|
| A1 | Où se compose un bundle suivi | **Sur le serveur, par le loader**, à partir du dépôt publié. La machine de build n'envoie que la définition du bundle (une liste de noms) |
| A2 | Comment | **Liens physiques** vers les packages publiés : aucune copie, aucun transfert, mêmes `sha256` par construction |
| A3 | Quelle version | Celle que `lexicon_meta` dit **en service**, pas `current` de l'index : un bundle ne devance jamais l'API |
| A4 | Quand | À chaque tour de `server watch`, après les chargements et avant l'écriture de `status.json` |
| A5 | Bundle filtré (`around`) | Inchangé : construit depuis la base de build, envoyé entier par `publish --bundle` |
| A6 | Chargeur de Cultia | Python, dans `cultia_back`, **une transaction pour tout le chargement** |
| A7 | Versions chez Cultia | `lexicon/index.json` commité fige ce qui est chargé ; `--update` le rafraîchit depuis le bundle |

### Pourquoi le serveur et non `ship` (écart avec B9)

B9 demandait que `ship` reconstruise et republie le bundle. Trois faits
plaident pour le loader :

1. Le dépôt publié et la zone `_bundles/` sont deux répertoires du même
   volume du serveur (`LEXICON_PACKAGES_DIR`). Le loader y écrit déjà ; l'API
   lit `_bundles/` en lecture seule. Un lien physique y coûte zéro octet.
2. `out/packages` de ce poste s'arrête au 4 octobre (42 jeux) quand la
   production en sert 54, dont `fertilizers`, `seeds`, `fuel_prices` et
   `phytosanitary_prices`, absents d'ici. Un bundle composé sur un poste de
   build dépend de ce que ce poste a gardé ; composé sur le serveur, il ne
   dépend que de ce qui est en service.
3. Un `publish` ou un `server rollback` fait à la main, hors de `ship`, met
   aussi le bundle à jour.

`ship` garde un rôle : il attend que le bundle désigne la version livrée, et
le dit (§ 5). L'intention de D4 est tenue : livrer une datasource suffit.

## 1. Vue d'ensemble

```
 Poste de build                       Serveur osfarm_lexicon                    Cultia
┌──────────────────────────┐        ┌─────────────────────────────────────┐   ┌──────────────────────┐
│ resources/flavors/       │        │ /packages                           │   │ cultia_back          │
│   cultia.yml (tracked)   │        │   index.json                        │   │  lexicon/index.json  │
│                          │ rsync  │   units/2026.10.03.5/…   ◀──┐       │   │   (commité)          │
│ publish --bundle cultia ─┼───────▶│   _bundles/cultia/          │ liens │   │                      │
│   → bundle.json seul     │        │     bundle.json             │       │   │ load_lexicon         │
│                          │        │     units/2026.10.03.5/… ───┘       │   │  1 lit l'index       │
│ ship fuel_prices         │ rsync  │     index.json   (écrit en dernier) │   │  2 télécharge        │
│   --production ──────────┼───────▶│     state.json                      │   │  3 attente + COPY    │
│   attend : en service,   │        │        ▲                            │   │  4 bascule, 1 tx     │
│   puis bundle à jour     │        │  ┌─────┴────┐      ┌─────┐  HTTPS   │   │  5 vue, droits, RICA │
│                          │        │  │  loader  │      │ API │◀─────────┼───│                      │
└──────────────────────────┘        │  │  watch   │      └─────┘ clé      │   └──────────────────────┘
                                    │  └──┬───────┘  /bundles/cultia/…    │
                                    │     ▼ lexicon_meta (versions en service)
                                    └─────────────────────────────────────┘
```

## 2. Flavors

### 2.1 Format

`resources/flavor.schema.json` gagne une propriété :

| Propriété | Type | Sens |
|---|---|---|
| `tracked` | booléen, faux par défaut | Le bundle est tenu à jour par le serveur |

Règles, vérifiées par `FlavorLoader` (échec nommant la règle, B7 bis) :

- `tracked: true` exige `only`, non vide ;
- `tracked: true` interdit `datasources` (aucun filtre) et `without`.

`LexiconFlavor` gagne `tracked?`.

### 2.2 `resources/flavors/cultia.yml`

```yaml
name: cultia
tracked: true
only:
  - agricultural_pictures
  - budgets
  - chart_of_accounts
  - enterprise_classifications
  - fertilizers
  - fuel_prices
  - intervention_models
  - open_nomenclature
  - phytosanitary
  - phytosanitary_prices
  - prices
  - productions
  - rica
  - seeds
  - taxonomy
  - technical_workflow_sequences
  - technical_workflows
  - units
  - variants
```

Ce que la fermeture par clés étrangères impose de plus (§ 2.3) s'ajoute à la
main quand `publish --bundle` le réclame : la liste reste lisible et complète.
Sur les 15 jeux présents ici, la fermeture n'ajoute rien ; elle reste à
calculer pour `fertilizers`, `seeds`, `phytosanitary_prices` et `fuel_prices`.

Retirés (D9) : `ekyagri.yml`, `ekyviti.yml`, `natais.yml`, `sydec.yml`,
`pv.yml`, `innovation.yml`. Restent `cultia`, `around`, `full`, `light`, `test`.

### 2.3 `Packaging::BundleDefinition` (nouveau)

Ce qu'un bundle suivi contient, sous la forme envoyée au serveur.

| Méthode | Rôle |
|---|---|
| `.from_flavor(flavor, resolver:, definitions:)` | Construit la définition ; lève `ArgumentError` si le flavor n'est pas suivi, nomme une datasource inconnue ou non packagée, ou laisse une clé étrangère sortir de la liste (« `seeds` référence `seed_varieties`, absent du bundle ») — B3 |
| `.load(file)` / `#write(dir)` | Lit et écrit `bundle.json` |
| `#name`, `#datasources` | |

`resolver` est le `DependencyResolver` existant ; seules les dépendances
`foreign_key` comptent. Les dépendances `normalize` ne sont pas exigées :
`prices` se charge sans ses quatre sources, qui sont dans le bundle par choix
(D6) et non par contrainte.

`_bundles/<flavor>/bundle.json` :

```json
{ "format": 1, "name": "cultia", "datasources": ["agricultural_pictures", "…"], "defined_at": "2026-10-13T09:00:00Z" }
```

## 3. Composition : `Packaging::BundleAssembler` (nouveau)

Une seule classe compose un bundle suivi, sur le serveur comme sur un poste.

```
BundleAssembler.new(source: Repository, root: Pathname)   # root : …/_bundles ou out/bundles
  #assemble(definition, versions:) → Outcome
      versions : { nom => version } à désigner (en service côté serveur, `current` en local)
      Outcome  : linked [nom@version], kept [nom], missing [{name, reason}], pruned [nom@version]
```

Pour chaque nom de la définition, dans l'ordre :

1. pas de version demandée, ou package absent de `source` : le jeu est
   `missing`, ce que le bundle en a déjà reste en place ;
2. une dépendance `foreign_key` du manifest est `missing` : le jeu l'est aussi ;
3. `root/<flavor>/<nom>/<version>/manifest.json` existe : rien à faire ;
4. sinon, l'arbre du package est lié fichier par fichier dans
   `<nom>/.assembling-<version>/`, puis renommé. Sur deux systèmes de fichiers
   (`EXDEV`), copie à la place du lien.

Puis :

5. `index.json` est écrit à part et renommé, **en dernier** (B12), par
   `Repository#set_current` ;
6. sont retirées du bundle les versions que `source` n'a plus, sauf celle que
   l'index désigne : `resources/retention.yml` et `server prune` gouvernent
   donc aussi les bundles (B14), sans réglage de plus ;
7. sont retirés les jeux sortis de la définition ;
8. `state.json` est écrit : `assembled_at`, `missing`.

Propriétés :

- **Idempotent** : un second passage sans changement ne touche à rien, pas
  même à `index.json` (B8, N3).
- **Mêmes fichiers** : le manifest n'est pas réécrit, `flavor` y reste `null`.
  Un package du bundle *est* le package publié (B6, B7).
- **Droits** : les répertoires sont créés en `0700` ; un fichier lié garde le
  mode de l'original (`0644` pour un jeu ouvert), ce qui ne l'expose pas : le
  serveur de fichiers public n'entre pas dans `_bundles/` (N2).
- **Traductions** (B5) : chaque package porte sa table `<nom>__translations` ;
  qui charge le bundle reconstruit la vue à partir de ce qu'il a chargé.
- Un téléchargement en cours pendant une composition lit l'ancien index, dont
  les packages restent en place tant que le dépôt publié les garde.

## 4. Côté serveur

### 4.1 `Server::Bundles` (nouveau)

```
Server::Bundles.new(repository:, meta:, assembler:)
  #assemble_all → { flavor => Outcome }
```

Lit chaque `_bundles/*/bundle.json`, demande à `meta` la version en service de
chaque jeu, appelle l'assembleur. Un répertoire sans `bundle.json` est un
bundle filtré, envoyé entier : il n'y touche pas. Un `bundle.json` illisible
est signalé et n'empêche pas les autres.

### 4.2 `server watch`

```
loop:
  loader.sync
  bundles.assemble_all        ← nouveau ; une erreur est affichée, jamais fatale (B10)
  status_file.write
  meta.record_repository
```

L'ordre compte : quand `status.json` annonce une version en service, le
bundle la désigne déjà. `ship` n'a donc pas de fenêtre d'attente à gérer.

Nouvelle commande `./lexicon server bundles` : le même passage, à la main,
avec le détail de chaque `Outcome`.

### 4.3 Ce qui ne change pas

- La route `/bundles/<flavor>/*` de l'API et la portée `bundle:<flavor>`.
  `bundle.json` et `state.json` deviennent lisibles par le détenteur de la
  clé : ils ne disent que ce que l'index dit déjà.
- `status.json`, public, ne nomme aucun bundle : un nom de flavor est un nom
  de client.
- Le service `backup` recopie `_bundles/` vers S3 comme le reste. C'est une
  redite de quelques centaines de Mo ; `--exclude "/_bundles/*/*/**"` la
  retire si elle gêne.

## 5. Côté build : commandes

| Commande | Flavor suivi | Flavor filtré |
|---|---|---|
| `./lexicon bundle <flavor>` | Compose `out/bundles/<flavor>` par liens depuis `out/packages`, versions `current`. Sert à l'essai local | Inchangé : export depuis la base |
| `./lexicon publish --bundle <flavor> [--production]` | Vérifie la définition (§ 2.3), envoie `bundle.json` seul, en `D700,F600` | Inchangé : envoi du répertoire |
| `./lexicon status --bundles [--production]` | Pour chaque bundle : jeu, version du bundle, version en service, `missing` de `state.json` (B13) | Liste ses jeux, sans comparaison |
| `./lexicon ship … [--production]` | Étape de plus, ci-dessous | Ignoré (B11) |

`Publisher` gagne :

| Méthode | Rôle |
|---|---|
| `publish_definition(definition)` | Envoie `bundle.json` |
| `bundle_names` | Sous-répertoires de `_bundles/` (liste par rsync) |
| `bundle_index(flavor)`, `bundle_state(flavor)` | Lus par rsync, comme `remote_index` |

`ship`, après « In service » de chaque cible :

```
── Bundles (production)
        cultia: fuel_prices 2026.10.14.1
```

Pour chaque flavor suivi de `resources/flavors` dont `only` contient un des
noms livrés : le bundle distant doit désigner la version livrée. S'il ne le
fait pas (bundle jamais défini sur cette cible, jeu `missing`), `ship` le
dit et sort en erreur, la datasource restant en service (B10). Un bundle
absent de la cible locale n'est qu'un avertissement : on peut ne publier une
définition qu'en production.

## 6. Côté Cultia : `cultia_back`

### 6.1 Fichiers

| Fichier | Rôle |
|---|---|
| `lexicon/index.json` | Commité (exception à ajouter au `.gitignore`). Les versions à charger, copie de l'index du bundle à l'instant de `--update` |
| `lexicon/packages/<jeu>/<version>/` | Cache des téléchargements, hors dépôt |
| `scripts/load_lexicon.py` | Ligne de commande ; garde la phase RICA |
| `scripts/lexicon_bundle.py` (nouveau) | Lecture de l'index et des manifests, téléchargement, attente, bascule. Sans rien de propre à Cultia, donc testable seul |

### 6.2 Commande

```
python -m scripts.load_lexicon              # charge ce que dit lexicon/index.json
python -m scripts.load_lexicon --update     # rafraîchit d'abord lexicon/index.json depuis le bundle
python -m scripts.load_lexicon --all        # recharge même ce qui est à jour
python -m scripts.load_lexicon --only rica  # ces jeux seulement, s'ils diffèrent
python -m scripts.load_lexicon --dry-run    # dit ce qui serait téléchargé et chargé
python -m scripts.load_lexicon --reset      # première bascule depuis l'ancien format (§ 6.5)
```

Variables : `LEXICON_BUNDLE_URL`, `LEXICON_API_KEY` (N1), `DIRECT_URL`.
`LEXICON_VERSION` disparaît avec l'ancien format (C8).

### 6.3 État en base

Schéma `lexicon_meta`, tenu par le chargeur, non exposé par Supabase :

```sql
CREATE TABLE lexicon_meta.packages (
  name      text PRIMARY KEY,
  version   text NOT NULL,
  manifest  jsonb NOT NULL,     -- tables, rôles, clés étrangères : ce qu'il faut pour remplacer le jeu
  loaded_at timestamptz NOT NULL DEFAULT now()
);
```

### 6.4 Déroulé

```
1  lire lexicon/index.json            (--update : le télécharger d'abord, l'écrire à la fin si tout a réussi)
2  à charger = jeux dont current ≠ lexicon_meta.packages.version      (C4)
   à retirer = jeux de lexicon_meta absents de l'index
3  télécharger ce qui manque au cache : manifest, structure.sql, indexes.sql, data/*
   contrôle du sha256 de chaque fichier ; 429 → attendre Retry-After   (C2)
4  refuser, avant d'écrire, si une clé étrangère d'un jeu à charger vise un jeu
   ni chargé ni à charger, ou si une vue hors de lexicon dépend d'une table remplacée
5  BEGIN
     CREATE SCHEMA lexicon_staging
     par jeu : SET LOCAL search_path = lexicon_staging, <schéma postgis>
               structure.sql (postgis. réécrit comme aujourd'hui) ; COPY … (FORMAT csv)
               lignes chargées = rows du manifest, sinon échec          (C5)
               indexes.sql
     DROP VIEW lexicon.master_translations
     retirer les clés étrangères des jeux installés qui visent une table remplacée
     DROP des tables des anciennes versions (lues dans lexicon_meta.manifest)
     ALTER TABLE lexicon_staging.<t> SET SCHEMA lexicon
     reposer les clés étrangères : celles des jeux chargés, celles retirées
     CREATE VIEW lexicon.master_translations AS … UNION ALL des tables de rôle translations
     droits USAGE / SELECT aux rôles Supabase
     mettre à jour lexicon_meta.packages
     DROP SCHEMA lexicon_staging
   COMMIT
6  si rica a changé : contrôle des tranches, rica_group_stats, rica_activity_stats,
   et rappel de redémarrer l'API                                        (C6)
```

Une seule transaction (A6) : un échec, où qu'il tombe, laisse la base comme
elle était (C4), et `prices` ne se trouve jamais à côté de sources d'une autre
semaine. Le bundle pèse quelques centaines de Mo, `rica` en fait l'essentiel :
la transaction dure des minutes, pas des heures. C'est la mécanique du loader
du Lexicon (`Stager`, `Checker`, `Swapper`), réduite à ce dont un seul
consommateur a besoin : pas de retour arrière, pas de journal, pas de verrou
entre chargeurs.

### 6.5 Première bascule

Une base chargée en ancien format n'a pas de `lexicon_meta` : le chargeur ne
sait pas à qui sont les tables de `lexicon`. Il s'arrête et demande `--reset`,
qui fait une dernière fois `DROP SCHEMA lexicon CASCADE` dans la même
transaction que le chargement complet. Tant que `lexicon/index.json` n'existe
pas, le script charge l'ancien format comme aujourd'hui.

### 6.6 Avant la bascule (C7)

Comparer, sur une base jetable, les tables et colonnes de `6.1.0-cultia` et
celles du bundle, limité à ce que `prisma/schema.prisma` et le code lisent.
Écarts déjà connus : `master_translations` devient une vue (colonnes `id`,
`fra`, `eng`) ; les tables `<jeu>__translations` apparaissent, et
`prisma db pull` les introspectera.

## 7. Exigences couvertes

| Exigence | Par |
|---|---|
| B1, B2, B4 | § 2.2 : liste blanche ; un jeu réservé n'entre que nommé |
| B3 | § 2.3 à la publication, § 3 étapes 1–2 à la composition, § 6.4 étape 4 au chargement |
| B5 | Tables de traductions par package ; vue reconstruite par qui charge |
| B6, B7, B8 | § 3 : liens vers les packages en service |
| B7 bis, B11 | § 2.1 : `tracked` |
| B9 | § 4.2 et § 5, avec l'écart du § 0 |
| B10 | § 4.2 jamais fatal ; § 5 `ship` sort en erreur sans défaire |
| B12 | § 3 étape 5 |
| B13 | `status --bundles` |
| B14 | § 3 étape 6 |
| C1–C6 | § 6.4 |
| C7 | § 6.6 |
| C8 | Lot 6 |
| N2 | § 3, Droits |
| N3 | Composition par liens : quelques millisecondes par jeu |
| N4 | À mesurer au lot 5 : nombre de requêtes d'un téléchargement complet |

## 8. Tests

| Fichier | Ce qu'il garantit |
|---|---|
| `test/lexicon/flavor/flavor_loader_test.rb` | `tracked` sans `only`, ou avec filtres, est refusé |
| `test/lexicon/packaging/bundle_definition_test.rb` | Clé étrangère sortante refusée et nommée ; dépendance `normalize` tolérée ; aller-retour de `bundle.json` |
| `test/lexicon/packaging/bundle_assembler_test.rb` | Mêmes inodes que la source ; index écrit en dernier ; second passage sans effet ; jeu manquant laisse l'ancien ; version disparue de la source retirée ; jeu sorti de la définition retiré |
| `test/lexicon/server/bundles_test.rb` | Version en service et non `current` ; répertoire sans `bundle.json` intact ; définition illisible n'arrête pas les autres |
| `test/lexicon/packaging/publisher_test.rb` (ajouts) | `bundle.json` envoyé en `600` ; lecture de l'index et de l'état d'un bundle |
| `cultia_back/tests/test_lexicon_bundle.py` | Sur un bundle d'essai de deux jeux liés et une base jetable : chargement, rechargement d'un seul jeu, `sha256` faux refusé, nombre de lignes faux → base inchangée, vue des traductions, clé étrangère entre jeux reposée |

## 9. Lots

| # | Contenu | Dépôt | Durée |
|---|---|---|---|
| 1 | Flavors : `tracked`, `cultia.yml` en liste blanche, retrait de six flavors, `BundleDefinition` | lexicon | 0,5 j |
| 2 | `BundleAssembler`, `./lexicon bundle` pour un flavor suivi | lexicon | 1 j |
| 3 | `Server::Bundles`, `server watch`, `server bundles`, `publish --bundle` qui envoie la définition | lexicon | 1 j |
| 4 | `status --bundles`, étape de `ship`, documentation (`doc/PUBLICATION.md`, `doc/ADMINISTRATION.md`, `CLAUDE.md`, `ROADMAP.md`) | lexicon | 0,5 j |
| 5 | Mise en service : pile locale, puis redéploiement et `publish --bundle cultia --production` ; clé de Cultia ; `fetch` et `server sync` sur une base vide ; mesure du quota | serveur | 0,5 j |
| 6 | `lexicon_bundle.py`, `load_lexicon.py`, tests, `doc/lexicon.md` ; comparaison des schémas ; staging, puis production ; retrait de `lexicon/6.*-cultia` | cultia_back | 2–3 j |

Les lots 1 à 5 se suivent. Le lot 6 peut commencer dès le lot 2, sur un bundle
composé localement.

## 10. Points à surveiller

1. **Fermeture des quatre jeux d'intrants.** Leurs clés étrangères ne sont pas
   lisibles d'ici (pas de package local). `publish --bundle` les donnera ; si
   elles tirent un gros jeu, la liste est à revoir avec vous.
2. **Le bundle déjà en zone privée.** S'il y en a un (du 4 octobre, format
   « envoyé entier »), ses packages portent des versions qui ne sont celles
   d'aucun package publié. Le plus net est de vider `_bundles/cultia/` avant
   d'y envoyer `bundle.json` : c'est une suppression sur le serveur, à faire
   avec votre accord au lot 5.
3. **Redéploiement.** Le loader ne compose rien tant que la pile n'est pas
   redéployée avec le lot 3. D'ici là, `publish --bundle cultia` d'un flavor
   suivi n'a aucun effet visible.
4. **Vues de Cultia sur `lexicon`.** Une vue de `public` qui lit une table du
   Lexicon bloque son remplacement ; le chargeur la nomme et s'arrête
   (§ 6.4, étape 4). À recenser au lot 6.
5. **Relevés par marchand.** `fertilizers`, `seeds` et `phytosanitary_prices`
   arrivent entiers chez Cultia ; ce qui en est montré se décide là-bas.

## 11. État (2026-10-13)

Lots 1 à 4 faits dans ce dépôt, testés (28 tests nouveaux, 242 en tout) et
essayés sur une base et un dépôt jetables. Écarts avec ce qui précède :

- **Fermeture du bundle `cultia` (§ 10, point 1) : levée.** Les 19 jeux se
  suffisent : aucune clé étrangère ne sort de la liste, `fertilizers`,
  `seeds`, `phytosanitary_prices` et `fuel_prices` n'en ont aucune.
- `status --bundles` ne montre que les flavors suivis de `resources/flavors` ;
  il ne liste pas les bundles filtrés présents sur le serveur.
  `Publisher#bundle_names` n'a donc pas été écrit.
- `ship` : un bundle non défini sur une cible, locale ou de production, n'est
  qu'une ligne d'information. L'erreur est réservée au bundle défini qui ne
  désigne pas la version mise en service.
- Dans `server watch`, un jeu manquant n'est affiché qu'au tour où le bundle
  change ; `state.json` et `status --bundles` le disent à tout moment.

Restent le lot 5 (redéploiement du loader, `publish --bundle cultia
--production`, clé de Cultia) et le lot 6 (`cultia_back`).

