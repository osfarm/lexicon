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
| Premier jeu contribué | `alim_confiance` (contrôles sanitaires, 71 549 lignes) : fiche dans `data/contributions/alim_confiance/`, tableau de 43 Mo dans `raw/alim_confiance/` |
| Pile locale | En service en 2026.10.09.1 : `postal_codes`, `msa_populations`, `enterprises`, `cadastre`, `cadastre_owners`, `cap_beneficiaries`, `enterprise_links`, `commune_links`, `alim_confiance` |
| API locale | Tourne sur la copie de travail de `feature/inputs` (`docker-compose.server.api-dev.yml`) |

### À reprendre

- **Commité le 2026-10-10, non poussé** : la fiche `data/contributions/alim_confiance/dataset.yml`, et le changement qui laisse un
  gros tableau dans `raw/<nom>/` (`Sheet#path`, `Review`, `TabularDatasource#collect`, interface web, guide). Décision du
  2026-10-10 : le CSV de 43 Mo reste dans `raw/`, hors du dépôt.
- **Interface web vue dans Chrome le 2026-10-10** : liste, `alim_confiance` lu depuis `raw/`, création d'un jeu, dépôt d'un CSV
  à point-virgule, formulaire et relecture en direct, sans erreur de console. Non essayé : dépôt Excel ou LibreOffice,
  glisser-déposer à la souris. Case « Accès » étirée : corrigée dans `pages.rb`.
- **Noms « agricoles » corrigés dans lexicon-rest-api (2026-10-10, commité, non poussé)** : le champ JSON de la fiche commune
  `agricultural-enterprises` devient `establishments` (changement visible des clients de `/links/communes`), les
  descriptions MCP de `get_commune` et `get_enterprise`, le titre de `/enterprises/enterprises`. L'identificateur de
  parcelle garde son nom : il filtre bien les codes APE 01.
- **Outil de contribution en ligne (2026-10-10, commité, non poussé)** : Q10 est tranchée. L'outil est servi sous
  `/contribute/outil` aux détenteurs d'une clé, par le service `contribute` de la pile, relayé par l'API ; un jeu proposé
  reste sur le serveur et un mainteneur le rapatrie (`contribute --proposed`, `--fetch`). Essayé de bout en bout sur la
  pile locale. **Pas déployé** : il faut publier l'API, créer le dossier des contributions sur le serveur et définir
  `LEXICON_CONTRIBUTE_SECRET` dans Dokploy (`doc/PUBLICATION.md` §17). Gros tableaux (commité le 2026-10-10, non poussé) : envoi par morceaux
  de 4 Mo et lecture en arrière-plan, essayés avec les 43 Mo d'`alim_confiance` à travers l'API locale.
- **Outils de l'API (2026-10-10, lexicon-rest-api)** : identificateur de parcelle et Duke refaits (commité), puis, **non
  commité** : documentation `/documentation` complétée (63 routes), identificateur enrichi (eau à proximité, bâtiments,
  prix et produit brut de la culture, usages phytosanitaires, documents de R&D, itinéraires techniques), pages
  `/phytosanitary/usages` et `/production/technical-workflows`, et côté MCP les outils `get_parcel`, `get_crop_figures`,
  `search_phytosanitary_products` avec des tableaux compacts pour `read_resource`. Dix-sept jeux en service ne sont
  encore lus par aucune route (budgets, taxonomie, unités, signes de qualité, stades phénologiques, `alim_confiance`…).
  Le même jour, la fiche lit davantage du paquet `hydrography` (BD TOPO) : habitations à moins de 100 m et la plus proche, mètres de haie en bordure, bois, vignes et vergers sur la parcelle ou à moins de 100 m, emprise au sol des bâtiments, et les points d'eau ponctuels (sources, fontaines) que la recherche d'eau ignorait. Le paquet ne garde ni la permanence ni la largeur des cours d'eau, jusqu'à l'édition suivante : `hydrography` 2026.10.10.1 (BD TOPO 3.5 du 2026-09-15, en service en local seulement) garde le statut des cours d'eau (police de l'eau, permanent, fossé, largeur), le nombre de logements et l'état des bâtiments, la hauteur des haies, et ajoute sites sensibles, espaces protégés, forêts publiques et lignes électriques (`doc/datasources/hydrography.md`). La fiche et `get_parcel` les lisent.
  Le 2026-10-11, nouveau jeu ouvert `phytosanitary_purchases` (achats de produits phytosanitaires estimés à la commune, BNV-D du SDES, 2020 à 2024, métropole, 57,6 millions de lignes ; `doc/datasources/phytosanitary_purchases.md`), en service en local seulement. L'image de construction gagne `duckdb` pour lire le Parquet. Côté API : trois pages sous `/phytosanitary`, une section sur la fiche de commune avec le chiffre à l'hectare, `get_commune` enrichi et l'outil `get_phytosanitary_purchases`.
  Le même jour, nouveau jeu ouvert `pat` (projets alimentaires territoriaux de l'observatoire France PAT : 471 projets, 27 455 communes couvertes, dont 34 rattachées par une intercommunalité co-porteuse que la fiche France PAT oublie ; `doc/datasources/pat.md`), en service en local seulement. La fiche de parcelle affiche les PAT de la commune, `get_parcel` les rend, et `/geographical-references/food-projects` les liste.
  Le 2026-10-11, `pat` 2026.10.10.2, `phytosanitary_purchases` 2026.10.10.1 et `weather` 2026.10.10.1 sont en service en production. `hydrography` 2026.10.10.1 reste en local : l'API de production (branche `main`) lit `registered_area_items` avec ses géométries et afficherait les natures brutes des nouvelles zones ; publier ce paquet après le déploiement de la branche `feature/inputs` de `lexicon-rest-api`. Les propriétaires de la fiche ne dépendent plus de `EXPOSE_OWNERS` (variable retirée, y compris de `docker-compose.yml`) : une clé d'adhérent suffit, un anonyme lit « réservé aux adhérents », et une parcelle sans personne morale le dit.
- **`cadastre_owners`** : `has_enterprise_pm_owner` marque 88 % des parcelles de personnes morales ; elle ne distingue
  plus les exploitations. Si le besoin était « propriétaire agricole », il faut un filtre sur les codes APE 01 à 03.
- **`weather` (2026-10-10, commité, non poussé)** : Météo-France a déplacé ses fichiers horaires ; l'ancienne adresse
  (`object.files.data.gouv.fr`) est figée au 24 juin 2026. `BASE_URL` pointe sur `meteofrance.s3.sbg.io.cloud.ovh.net`.
  Reconstruit (34 min), empaqueté et en service en local en 2026.10.10.1 : 221,2 millions de relevés jusqu'au 10 octobre.
  `collect` ne retélécharge pas un fichier déjà présent : retirer `raw/weather/weather_latest-*.zip` avant de reconstruire.
- **Vérifié le 2026-10-10** : `PivotMeter` donne les mêmes chiffres que l'ancienne requête sur les 21 liens déclarés
  (les trois liens SIREN recomptés par intersection) ; la colonne `insee_code` tirée du code postal et du nom, construite
  de bout en bout sur les 71 549 lignes d'`alim_confiance`, trouve 95,7 % des lignes et aucun code faux.
- **Paris, Lyon, Marseille (2026-10-10, commité, non poussé)** : `postal_codes` ajoute les communes entières 75056, 69123 et
  13055 sous chaque code postal de leurs arrondissements ; la recherche d'`insee_code` prend le nom de la commune avant
  les noms d'acheminement (« Paris » donne 75056, « Paris 15 » donne 75115). Sur `alim_confiance` : 68 454 codes trouvés,
  tous ceux de la source. `postal_codes` et `commune_links` sont reconstruits dans la base de build, **pas empaquetés**.
- **Fiches commune de Paris, Lyon, Marseille (2026-10-10, commité, non poussé)** : `commune_links` ajoute à la fiche de la commune
  entière ce que comptent ses arrondissements (parcelles, surface, parcelles de sociétés, établissements), le cadastre et
  SIRENE codant par arrondissement. Paris : 3 794 570 établissements ; Lyon : 564 381 ; Marseille : 719 863.
- **Le cadastre ne porte aucune parcelle de Paris** (aucun `town_insee_code` en 75) : la fiche de Paris et de ses
  arrondissements compte 0 parcelle. Cause : `"75"` n'est pas dans `DEPTS` de `lib/datasources/cadastre/__init__.py`,
  depuis le premier commit ; l'outre-mer y est en commentaire. Décision du 2026-10-10 : ne pas les ajouter.
- **Production** : rien de tout cela n'y est. L'ordre reste celui de « Mise en production du code » ci-dessous ; l'API doit
  être publiée avec le nouveau `commune_links`, sinon le champ des parcelles de sociétés disparaît de la fiche commune.
- **À nettoyer** : le conteneur `lexicon-api-dev` (port 8890), qui fait double emploi avec l'API locale ; les schémas
  `enterprises` (10 Go de stock SIRENE brut) et `*__backup` de la base de build.

## Où en est chaque chose

| Chose | État |
|---|---|
| Données en production | Toutes publiées et en service : `fuel_prices` .1, `phytosanitary_substances` .1, `fertilizers` .2, `seeds` .6, `phytosanitary_prices` .1, `taxonomy` .1, `seed_varieties` .2, `variants` .2, `prices` .1, et les jeux reconstruits (`productions`, `industry_sector`, `rd_agri`, `budgets`, `technical_workflows`, `technical_workflow_sequences`) en .1, toutes datées 2026.10.07 |
| Seul jeu périmé en production | `agroedi` : absent du poste de build |
| Code `lexicon`, branche `v2` | Tout est commité en local (10 commits d'avance sur `origin/v2` au 2026-10-10), **non poussé** |
| Code `lexicon-rest-api`, branche `feature/inputs` | Lot 6 et guide du contributeur commités en local, **ni poussés, ni fusionnés, ni déployés** |
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
