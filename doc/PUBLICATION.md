# Publication des jeux de données (Lexicon v2)

Documentation technique : comment une datasource passe du poste de build au
serveur, ce que contient un package, et quoi faire quand une publication est
refusée. L'exploitation du serveur et la gestion des accès sont décrites dans
[ADMINISTRATION.md](ADMINISTRATION.md).

## 1. Vue d'ensemble

```
Poste de build                              Serveur
┌────────────────────────────┐              ┌──────────────────────────────────────┐
│ ./lexicon run <ds>         │              │ /home/ubuntu/lexicon/packages        │
│   base locale, schéma      │              │   index.json   (ce qu'il faut servir)│
│   `lexicon`                │              │   status.json  (ce qui est servi)    │
│ ./lexicon package <ds>     │   rsync      │   <ds>/<version>/…                   │
│   out/packages/<ds>/<v>/   │ ───────────▶ │          │                           │
│ ./lexicon publish <ds>     │   sur SSH    │          ▼                           │
│ ./lexicon status           │              │  loader : staging → contrôles →      │
└────────────────────────────┘              │           bascule dans `lexicon`     │
                                            └──────────────────────────────────────┘
```

Une datasource = un package = une version = une bascule. Publier une
datasource ne touche à aucune autre.

## 2. Prérequis

- Un accès SSH au serveur (`osfarm_lexicon` dans `~/.ssh/config`), utilisateur
  `ubuntu`. Le conteneur de build utilise vos clés, montées en lecture seule.
- Dans `.env` :

  ```
  LEXICON_PUBLISH_TARGET=osfarm_lexicon:lexicon/packages
  ```

- Une connexion filaire pour les gros packages : 105 Mo/s mesurés en filaire,
  1,4 à 4,2 Mo/s en Wi-Fi.

## 3. Publier une datasource

```sh
./lexicon run phytosanitary        # collect, load, normalize dans la base locale
./lexicon validate                 # tables remplies, clés étrangères présentes
./lexicon package phytosanitary    # out/packages/phytosanitary/<version>/
./lexicon publish phytosanitary    # envoi, puis désignation dans index.json
./lexicon status                   # local / publié / en service
```

Le loader du serveur regarde le dépôt toutes les cinq minutes. `status`
affiche la version en service dès qu'il a fini :

```
phytosanitary   local 2026.10.04.1  published 2026.10.04.1  in service 2026.10.04.1
```

| Mention de `status` | Signification |
|---|---|
| `to publish` | La dernière version locale n'est pas celle publiée |
| `not in service yet` | Publiée, pas encore chargée, ou refusée (voir §8) |
| `stale` | Construite contre une version de dépendance qui a changé depuis (§6) |
| `in service ?` | Le serveur ne publie pas de `status.json` |

Options utiles :

- `./lexicon package` sans nom construit toutes les datasources.
- `./lexicon package <ds> --jobs 8` exporte 8 tables à la fois (4 par défaut).
- `./lexicon package <ds> --no-validate` passe outre la validation. À éviter :
  elle est là pour ne pas publier une table vide.
- `./lexicon publish <ds>@<version>` désigne une version précise, par exemple
  pour revenir à une version déjà envoyée.

## 4. Ce que contient un package

```
out/packages/phytosanitary/2026.10.04.1/
├── manifest.json     # écrit en dernier : sans lui, la version n'existe pas
├── structure.sql     # CREATE TABLE (et la table de traductions)
├── indexes.sql       # CREATE INDEX, joués après le chargement des données
└── data/
    └── <table>_0.csv.gz
```

Champs de `manifest.json` :

| Champ | Rôle |
|---|---|
| `format` | 3 |
| `name`, `version` | Datasource et version `AAAA.MM.JJ.N` |
| `schema_revision` | Révision de structure déclarée par la datasource |
| `structure_hash` | Empreinte de `structure.sql` et `indexes.sql` |
| `built_at`, `tool_version` | Date de build, version de l'outil |
| `scope` | `open`, ou la portée exigée (`members`) |
| `flavor` | Nom du flavor pour un package de bundle, sinon `null` |
| `credits` | Fournisseur, licence, date de la source |
| `depends_on` | Dépendances, avec la version contre laquelle le package a été construit |
| `tables` | Par table : nombre de lignes, fichiers, `sha256`, taille, et `role` |
| `foreign_keys` | Clés étrangères à poser après la bascule |

Deux fichiers à la racine du dépôt :

- `index.json` : pour chaque datasource, `current` (la version à servir) et
  `versions`. C'est le seul fichier modifié en place ; `publish` l'écrit en
  dernier.
- `status.json` : écrit par le loader après chaque passage. Version en
  service, date de chargement, `stale`, et les dix derniers échecs avec leur
  raison.

## 5. Ce qu'une datasource déclare

Dans `lib/datasources/<nom>.rb`, en plus de `description` et `credits` :

```ruby
class RdAgri < Base
  schema_revision 2                       # à incrémenter quand une table change de forme
  depends_on :industry_sector, :phytosanitary   # lues pendant normalize, sans clé étrangère
  translations :industry_sectors          # préfixes d'identifiants écrits dans master_translations
  scope :members                          # réservée aux porteurs d'une clé
  packaged false                          # datasource de build uniquement
end
```

- **`depends_on`** : les dépendances par clé étrangère sont déduites de
  `references(...)`. Seules les lectures faites pendant `normalize` sont à
  déclarer.
- **`translations`** : côté build, `master_translations` reste une table
  unique. Le package embarque les lignes dont l'identifiant commence par un
  des préfixes, dans une table `<datasource>__translations`. Côté serveur,
  `master_translations` est une vue sur ces tables.
- **`scope`** : voir §9.

## 6. Dépendances entre datasources

| Datasource | Dépend de |
|---|---|
| `variants`, `productions` | `taxonomy`, `units` |
| `budgets` | `units`, `variants` |
| `prices` | `phytosanitary`, `units`, `variants` |
| `seed_varieties` | `taxonomy` |
| `agroedi`, `technical_workflows` | `productions` |
| `technical_workflow_sequences` | `productions`, `technical_workflows` |
| `industry_sector` | `productions`, `taxonomy`, `open_nomenclature` |
| `rd_agri` | `productions`, `taxonomy`, `industry_sector`, `open_nomenclature`, `administrative_areas`, `phytosanitary` |

Les autres datasources, dont toutes les grosses, n'ont aucune dépendance.

Règles :

- Publier dans l'ordre des dépendances : le référentiel d'abord. `package` et
  `publish` traitent les noms dans l'ordre donné ; le loader, lui, charge
  toujours les dépendances en premier.
- Quand un référentiel change, les packages construits contre son ancienne
  version passent `stale`. Ils restent servis ; il faut les reconstruire et
  les republier pour lever la mention.
- Si le nouveau référentiel supprime une valeur encore référencée, il est
  refusé. Il faut alors publier ensemble le référentiel et ce qui en dépend ;
  le serveur les bascule dans une seule transaction :

  ```sh
  ./lexicon-cli server sync taxonomy variants --together    # sur le serveur, conteneur loader
  ```

Exemple complet après une modification de `units` :

```sh
./lexicon run units
./lexicon package units variants productions prices budgets agroedi \
                  technical_workflows technical_workflow_sequences industry_sector
./lexicon publish units variants productions prices budgets agroedi \
                  technical_workflows technical_workflow_sequences industry_sector
```

## 7. Ce que fait le serveur

Pour chaque package dont la version désignée n'est pas celle en service :

1. **Avant chargement** : la table n'appartient pas à un autre package, les
   packages référencés sont en service, aucune table ne perd plus de 30 % de
   ses lignes, aucune vue étrangère ne dépend des tables à remplacer.
2. **Staging** : vérification des `sha256`, création des tables dans
   `lexicon_staging`, chargement, index, statistiques. Les données servies ne
   sont pas touchées.
3. **Après chargement** : nombre de lignes égal à celui du manifest, aucune
   référence orpheline, dans un sens comme dans l'autre.
4. **Bascule** : une transaction supprime les anciennes tables, déplace les
   nouvelles dans `lexicon`, repose les clés étrangères et reconstruit la vue
   `master_translations`.

Un échec à n'importe quelle étape laisse l'ancienne version en service.

Temps mesurés sur le serveur (12 cœurs, 30 Go) :

| Datasource | Lignes | Package | Construction | Chargement |
|---|---:|---:|---|---|
| RPG | 9,7 M | 3,6 Go | 54 s | moins de 3 min |
| Météo et prix cadastraux | 235 M | 2,9 Go | 3 min 35 | moins de 15 min |
| Cadastre | 93,5 M | 21 Go | 6 min | 12 min |
| Hydrographie | 3 tables | 24 Go | 9 min | environ 13 min |

## 8. Quand une publication est refusée

Les raisons sont dans `status.json` (`last_failures`), consultable par :

```sh
curl -s https://lexicon-packages.osfarm.org/status.json
```

| Raison | Cause | Que faire |
|---|---|---|
| `… is missing or corrupted` | Fichier altéré pendant l'envoi | Relancer `publish` |
| `N rows loaded, M expected` | Package incohérent | Reconstruire le package |
| `… rows, … in service (use --force to accept)` | Chute de volume de plus de 30 % | Vérifier la source ; si la baisse est voulue, `server sync <ds> --force` sur le serveur |
| `… has values missing from …` | Référence orpheline | Publier la dépendance d'abord, ou les deux avec `--together` |
| `the package … it references is not in service` | Dépendance absente du serveur | Publier la dépendance |
| `… already belongs to the package …` | Deux datasources déclarent la même table | Corriger la définition |
| `the view … depends on …` | Une vue créée à la main sur le serveur | La supprimer, publier, la recréer |
| `tables are in use: locks not obtained` | Requête longue en cours | Le loader réessaie au passage suivant |

`publish` lui-même reprend un envoi interrompu là où il s'était arrêté, et
abandonne au bout de deux minutes sans données plutôt que de rester figé.

## 9. Datasources réservées

Une datasource qui déclare `scope :members` (`rd_agri`, `cadastre_owners`)
est publiée lisible par son seul propriétaire (droits `700` / `600`) :

- le loader, qui tourne sous ce propriétaire, la met en service ;
- le serveur de fichiers public, qui tourne sans droits, répond `403`.

Ses données ne sont donc accessibles que par l'API, aux porteurs d'une clé.
Le nom du package reste visible dans `index.json` et `status.json`.

## 10. Bundles

Un bundle est un dépôt de packages filtré par un flavor
(`resources/flavors/<flavor>.yml` : datasources exclues, filtres SQL par
table). Il se charge ailleurs avec le même loader.

```sh
./lexicon bundle cultia                 # out/bundles/cultia/
./lexicon bundle test units soil        # seulement certaines datasources
./lexicon publish --bundle cultia       # envoi dans la zone privée du serveur
```

Le bundle publié est servi par l'API sous
`https://lexicon.osfarm.org/bundles/<flavor>/`, aux seules clés portant la
portée `bundle:<flavor>`.

Côté destinataire :

```sh
LEXICON_API_KEY=lex_… ./lexicon fetch https://lexicon.osfarm.org/bundles/cultia
LEXICON_SERVER_DATABASE_URL=postgres://… \
LEXICON_PACKAGES_ROOT=out/bundles/cultia ./lexicon server sync
```

`fetch` vérifie les `sha256` et attend quand le quota de la clé est atteint.

Un bundle n'est pas mis à jour automatiquement : après la republication d'une
datasource, reconstruire et republier le bundle.

## 11. Retour arrière et purge

Ces commandes s'exécutent sur le serveur, dans le conteneur `loader` :

```sh
./lexicon-cli server status              # versions en service, derniers chargements
./lexicon-cli server rollback <ds>       # remet la version remplacée
./lexicon-cli server prune               # liste ce qui est hors rétention
./lexicon-cli server prune --apply       # supprime
```

- `rollback` recharge le package précédent et le désigne dans `index.json`.
  La prochaine publication de la datasource reprend la main.
- La rétention par datasource est dans `resources/retention.yml`. La version
  en service et la version désignée ne sont jamais supprimées.

## 12. Tests

```sh
docker compose -f docker-compose-dev.yml run --rm -T -v "$PWD/test:/lexicon/test:ro" lexicon_runner \
  sh -c 'for f in test/lexicon/*/*_test.rb; do bundle exec ruby -Itest $f || exit 1; done'
```

Les tests du loader créent et suppriment une base temporaire sur le Postgres
de développement.

Pour essayer le côté serveur à la main, contre une base locale distincte de
la base de build :

```sh
docker compose -f docker-compose-dev.yml exec lexicon_runner sh -c \
  'LEXICON_SERVER_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:5432/lexicon_server_dev" ./lexicon-cli server sync'
```

La commande refuse de prendre pour cible la base de build.
