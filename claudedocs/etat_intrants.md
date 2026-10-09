# Intrants — état au 2026-10-09 au soir, et reprise

Chantier cadré dans `brainstorm_intrants.md`, conçu lot par lot dans `design_intrants_lot1_gnr.md` à
`design_intrants_lot7_contribution.md`. Vue d'ensemble des jeux : `doc/datasources/intrants.md`.

## Depuis le 2026-10-07 (sessions des 8 et 9 octobre)

Tout ce qui suit est commité en local sur `v2` (lexicon) et `feature/inputs` (lexicon-rest-api), **non poussé**, et
**rien n'est parti en production**.

| Sujet | Ce qui a été fait |
|---|---|
| Essai en local du 8 octobre | Tests, RuboCop, `check --static`, `ship fuel_prices`, `ship prices --no-build`, API du lot 6 : tout est passé |
| `contribute` | Refuse une fiche qui garde le texte du modèle ; accords au singulier |
| Interface web | `./lexicon contribute --web` (`http://localhost:8787`) : dépôt d'un tableau CSV, Excel ou LibreOffice, détection des colonnes, des types, de la clé et des liens (`Contribution::Import`), fiche en formulaire, relecture en direct sans rechargement |
| Nouveaux types de colonnes | `point` (latitude,longitude) et `datetime` |
| Nouveaux liens | clé `siret` ; code postal + nom de commune (`commune_postal_code`, `commune_name`), qui ajoutent une colonne `insee_code` à la construction |
| Guide du contributeur | Page `/contribute` du front (lexicon-rest-api) |
| `postal_codes` | Lit le GeoPackage ADMIN EXPRESS 4.0, communes et arrondissements municipaux |
| `enterprises` | Tous les codes APE : 44,3 millions d'établissements, 16 Go en base, package de 1,7 Go |
| `cadastre` | Téléchargement réparé (`curl -L`) ; colonne `has_enterprise_pm_owner` ; `schema_revision 2` |
| `cadastre_owners`, `commune_links` | Requête de marquage réécrite ; `enterprise_owner_parcels_count` ; `commune_links` en `schema_revision 2` |
| `PivotMeter` | Mesure d'un lien par existence dans la référence (8 s au lieu de plus de 4 min sur le SIREN) |
| Premier jeu contribué | `alim_confiance` (contrôles sanitaires, 71 549 lignes), dans `data/contributions/alim_confiance/` |
| Pile locale | En service en 2026.10.09.1 : `postal_codes`, `msa_populations`, `enterprises`, `cadastre`, `cadastre_owners`, `cap_beneficiaries`, `enterprise_links`, `commune_links`, `alim_confiance` |
| API locale | Tourne sur la copie de travail de `feature/inputs` (`docker-compose.server.api-dev.yml`) |

### À reprendre

- **`data/contributions/alim_confiance/` n'est pas commité** : son CSV pèse 43 Mo. À décider : le commiter tel quel, ou
  garder les gros tableaux hors du dépôt.
- **Relire avant de pousser** : le correctif de `lib/lexicon/packaging/pivot_meter.rb` touche la mesure des liens de tous
  les jeux ; l'interface web n'a été vue dans un navigateur que partiellement (aucune capture d'écran).
- **Noms restés « agricoles »** alors que `registered_enterprises` porte toutes les activités : le champ JSON
  `agricultural-enterprises` de la fiche commune et les descriptions des outils MCP (lexicon-rest-api).
- **`cadastre_owners`** : `has_enterprise_pm_owner` marque 88 % des parcelles de personnes morales ; elle ne distingue
  plus les exploitations. Si le besoin était « propriétaire agricole », il faut un filtre sur les codes APE 01 à 03.
- **`weather`** a été reconstruit mais pas empaqueté (217 millions de lignes, contenu a priori inchangé).
- **Non essayé contre une base** : la colonne `insee_code` tirée du code postal et du nom (seulement mesurée à la main :
  92 % des couples d'`alim_confiance` trouvent leur commune).
- **Production** : rien de tout cela n'y est. L'ordre reste celui de « Mise en production du code » ci-dessous ; l'API doit
  être publiée avec le nouveau `commune_links`, sinon le champ des parcelles de sociétés disparaît de la fiche commune.
- **À nettoyer** : le conteneur `lexicon-api-dev` (port 8890), qui fait double emploi avec l'API locale ; les schémas
  `enterprises` (10 Go de stock SIRENE brut) et `*__backup` de la base de build.

## Où en est chaque chose

| Chose | État |
|---|---|
| Données en production | Toutes publiées et en service : `fuel_prices` .1, `phytosanitary_substances` .1, `fertilizers` .2, `seeds` .6, `phytosanitary_prices` .1, `taxonomy` .1, `seed_varieties` .2, `variants` .2, `prices` .1, et les jeux reconstruits (`productions`, `industry_sector`, `rd_agri`, `budgets`, `technical_workflows`, `technical_workflow_sequences`) en .1, toutes datées 2026.10.07 |
| Seul jeu périmé en production | `agroedi` : absent du poste de build |
| Code `lexicon`, branche `v2` | Lots 1 à 3 commités en local, **non poussés**. Lots 4, 5, 7, `seed_varieties`, taxons, corrections : **non commités** (une quarantaine de fichiers) |
| Code `lexicon-rest-api`, branche `feature/inputs` | Lot 6 : **non commité**, ni fusionné, ni déployé |
| Production, côté code | Le loader tourne sur `origin/v2` d'avant ce chantier ; l'API sur la version 1.4.3, sans `/inputs` |
| Pile locale | En marche, alignée sur la production pour les données |

Les packages en production ont donc été construits par du code qui n'existe que sur ce poste.

## Reprise : essai en local, puis mise en production du code

### 1. Essai en local

```sh
cd ~/projects/lexicon
docker compose -f docker-compose-dev.yml up -d
docker compose -f docker-compose.server.yml -f docker-compose.server.local.yml up -d

# Tests, style, déclarations
docker compose -f docker-compose-dev.yml run --rm -T -v "$PWD/test:/lexicon/test:ro" lexicon_runner \
  sh -c 'for f in test/lexicon/*/*_test.rb; do bundle exec ruby -Itest $f || exit 1; done'      # 168 tests
docker compose -f docker-compose-dev.yml exec -T lexicon_runner bundle exec rubocop lib/lexicon
./lexicon check --static

# Le parcours en une commande, sur le jeu le plus simple puis sur celui qui lit les autres
./lexicon ship fuel_prices
./lexicon ship prices --no-build
./lexicon status
```

À regarder à la main :

- `http://localhost:8888/catalog` : les jeux, leurs versions, leurs accès ;
- la relecture d'une contribution : `./lexicon new essai --tabular`, un dossier dans `data/contributions/`, puis
  `./lexicon contribute essai` (retirer le dossier ensuite) ;
- l'API du lot 6, qui tourne dans le conteneur `lexicon-api-dev` sur `http://localhost:8890` : `/inputs`, une page
  ouverte, une page réservée (401 sans clé), et l'outil MCP `get_input_price`. Pour la relancer :

```sh
cd ~/projects/lexicon-rest-api
docker run --rm -u 1000:1000 -e HOME=/tmp -v "$PWD:/app" -w /app oven/bun:alpine bun test      # 136 tests
```

### 2. Mise en production du code

1. `lexicon` : relire, commiter, pousser `v2`. Redéployer la pile dans Dokploy pour que le loader prenne le
   nouveau code (il n'en a pas besoin pour charger les packages déjà publiés).
2. `lexicon-rest-api` : relire, commiter `feature/inputs`, fusionner dans `main`, publier une version
   (`bun run ./bin/tag.ts`, qui pousse et crée l'étiquette), redéployer la pile dans Dokploy : l'image de l'API
   est tirée à chaque déploiement.
3. Vérifier `https://lexicon.osfarm.org/inputs` et l'outil `get_input_price` sur `/mcp`.

`./lexicon ship --production` est écrit mais n'a pas été essayé contre la production.

### 3. Lundi 12 octobre

Première collecte hebdomadaire : voir `doc/datasources/intrants.md`, « Chaque semaine ». C'est elle qui dira si
les relevés s'additionnent bien d'une semaine à l'autre.

## À relire par quelqu'un du métier

| Sujet | Où |
|---|---|
| Seize alias EIQ et les rapprochements HRAC par forme ou isomère | `data/phytosanitary_substances/aliases.csv`, `doc/datasources/phytosanitary_substances.md` |
| Doses de semis des 53 espèces | `data/seeds/species.csv` |
| Noms français et anglais des 21 taxons ajoutés | `data/taxonomy/taxonomy - taxonomy.csv` |
| Les 37 espèces de `seed_varieties` rattachées au genre | `data/seed_varieties/seed_varieties - seed_species.csv` |
| 772 variétés disparues du catalogue officiel avec le nouveau fichier | `design_intrants_lot4_semences_phytos.md` |

## Ce qui reste ouvert

- Une seconde source de prix pour les produits phytosanitaires.
- Les semences vendues à la dose.
- Le runner de collecte sur le serveur.
- Le dépôt d'une contribution sans poste de build (question Q10 du cadrage).
- Les frictions non traitées : fin de `frictions_parcours.md`.

## À nettoyer sur le poste

- Le conteneur `lexicon-api-dev` (port 8890).
- La clé d'adhérent « Poste de dev », créée dans la base de service locale seulement.
