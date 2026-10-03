# Brainstorm — Lexicon v2

Cahier des charges issu du cadrage du 2026-10-03. Il reprend la conversation
<https://claude.ai/share/2bc02e86-a05c-42ca-887b-987609af61e5>, le `ROADMAP.md`
et l'état mesuré du projet. Il fixe les exigences ; l'architecture reste à
concevoir (`/sc:design`).

## 0. Décisions prises

| # | Sujet | Décision |
|---|---|---|
| D1 | Objectif premier | **Mises à jour indépendantes** : chaque datasource a sa version, son package, et se recharge seule en production |
| D2 | Compatibilité Ekylibre | **Aucune contrainte** : la v2 peut casser le schéma et le format de package actuels |
| D3 | Périmètre de données | **Tout le contenu actuel** est servi dès la première version |
| D4 | Briques de la première version | Couche de liaison, recettes pour contributeurs, serveur MCP, historique des versions |
| D5 | Serveur | Une machine, 32 Go de RAM, 800 Go de disque |
| D6 | Build | Sur la machine du mainteneur ; le serveur ne fait que charger et servir |
| D7 | API | `lexicon-rest-api` n'est pas imposée : elle est gardée si elle convient à la nouvelle architecture, remplacée sinon. Le choix se fait en conception |
| D8 | Dépôt | **Monorepo** de recettes, pas un dépôt par datasource |
| D9 | Base | **Postgres/PostGIS simple**. Supabase n'est retenu que si un besoin précis le justifie |
| D10 | Stockage des packages | Le **MinIO actuel va fermer**. Stockage externe gratuit s'il en existe un qui convient, sinon le disque du serveur |

## 1. État des lieux mesuré

### 1.1 Code

- La branche `v2` ne contient aucun code v2 : elle est au niveau de `main`.
- 47 fichiers dans `lib/datasources/`, un pipeline `collect` / `load` /
  `normalize` par datasource. Le **build** est déjà indépendant par datasource.
- Le **dump**, la **version** (`VERSION` global, 6.1.0) et le **chargement en
  production** sont monolithiques : un schéma `lexicon__<version>` complet.
- Le loader de production vit dans la gem `lexicon-common` (voir §1.5).

### 1.2 Volumes (base de dev locale)

| Élément | Taille |
|---|---:|
| Base complète (schémas bruts compris) | 412 Go |
| **Schéma `lexicon` (contenu publié)** | **278 Go** |
| `registered_cadastral_parcels` | 100 Go |
| `registered_area_items` | 56 Go |
| `registered_hourly_weathers` | 43 Go |
| `registered_cadastral_buildings` | 41 Go |
| `registered_graphic_parcels` | 12 Go |
| Autres tables cadastrales (prix, propriétaires, locaux) | ≈ 17 Go |
| `registered_hydrographic_items` | 6,5 Go |
| Tout le reste (référentiels, phyto, RICA, PAC, etc.) | < 4 Go |

- 33 clés étrangères, portées par 24 tables ; les grosses tables n'en ont pas.
- Machine de build : `raw/` 213 Go, `out/` 54 Go (dont 52 Go pour le seul
  package `6.0.2-full`), disque plein à 90 % (180 Go libres).

### 1.3 Périphérie

- **`lexicon-rest-api`** (Bun, TypeScript) : interface web et API hypermédia
  (HTML, JSON, CSV). Elle lit directement un schéma Postgres nommé par version
  et flavor (`DB_SCHEMA=lexicon__6_0_0-ekyviti`), avec un fichier par domaine
  dans `src/namespaces/`.
- Stockage objet MinIO utilisé aujourd'hui pour les packages (`remote upload`,
  `remote download`, bucket public) ; il va fermer (D10).
- Services `lexicon-n8n` et `lexicon-ai` déclarés dans l'environnement.

### 1.4 Trois visions à réconcilier

| Vision | Contenu | Statut après cadrage |
|---|---|---|
| `ROADMAP.md` | Un dépôt par datasource, CSV + `schema.json`, Supabase, `label jsonb` | Les idées de package, manifest, `index.json`, `_packages` et importer sont retenues. Le découpage en 40 dépôts et Supabase sont abandonnés (D8, D9). Le `ROADMAP.md` est à réécrire |
| Évolution du monorepo | Package et version par datasource, loader incrémental | C'est l'objectif D1 |
| Plateforme « de zéro » | Stockage fichiers, liaison, API unique, contributeurs, MCP | Liaison, recettes, MCP et historique sont retenus (D4). Le multi-moteur (ClickHouse, tuiles, CDN) est hors périmètre de la première version |

### 1.5 La gem `lexicon-common`

Lue sur <https://gitlab.com/ekylibre/lexicon/lexicon-common>, branche `dev`
(celle du `Gemfile`), dernier commit d'avril 2024, ≈ 1 550 lignes.

Ce qui sert déjà la v2 :

- Le format de package (version 2) est **déjà découpé par datasource** :
  `lexicon.json` liste, pour chaque datasource, un fichier de structure SQL et,
  par table, un ou plusieurs CSV compressés. `lexicon.sum` porte les
  checksums. Exemple : `out/6.1.0-cultia/`, 40 datasources, 98 fichiers.
- `load_package(only:, without:)` sait ne charger que certaines datasources.

Ce qui manque pour D1 :

- Une seule version pour tout le package ; aucune version par datasource.
- Le chargement vise toujours un schéma neuf `lexicon__<version>` : les
  structures de **toutes** les datasources sont créées à chaque fois, et
  charger dans un schéma existant échoue. Pas de schéma de staging, pas de
  transaction, pas de table de suivi.
- La mise en service (`production enable`, dans le CLI) renomme le schéma
  entier en `lexicon` : la bascule est globale.
- Un thread par fichier, sans limite : tous les CSV sont chargés en même
  temps, ce qui ne convient pas à un serveur de 32 Go (N2).
- Les index sont créés avec la structure, avant les données.
- Le stockage distant suppose S3 avec **un bucket par version** ; à remplacer
  de toute façon (D10).

Conséquence : le format de package est une base réutilisable ; le loader, la
bascule et le stockage distant sont à réécrire. La gem est petite et n'a pas
bougé depuis 2024 : la reprendre dans le monorepo (Q10) coûte peu.

## 2. Objectifs

1. Mettre à jour une datasource en production sans toucher aux autres, pour
   un coût proportionnel à sa taille.
2. Servir tout le contenu actuel depuis un serveur unique de 32 Go / 800 Go.
3. Relier les jeux entre eux par des clés pivots explicites.
4. Permettre à des tiers d'ajouter une datasource sans accès à la production.
5. Rendre les données interrogeables par des agents IA.
6. Garder l'historique des versions publiées.

## 3. Exigences fonctionnelles

### 3.1 Packages et versions (D1)

- F1 — Chaque datasource produit un package autonome : données, description
  du schéma, manifest (version, date de build, date de la source, licence,
  crédits, checksums).
- F2 — Chaque datasource a sa propre version. Le `VERSION` global disparaît
  ou ne désigne plus que l'outillage.
- F3 — Un registre unique liste les datasources, leurs versions disponibles
  et la version courante.
- F4 — Le manifest est publié en dernier : une version incomplète n'est
  jamais visible du serveur.
- F5 — Un package déclare ses dépendances envers d'autres datasources
  (clés étrangères, vocabulaires utilisés).
- F5b — La publication et la distribution des packages ne dépendent plus du
  MinIO actuel. Les packages encore utiles qui s'y trouvent sont rapatriés
  avant sa fermeture.

### 3.2 Chargement en production (D1)

- F6 — Le serveur détecte une nouvelle version et la charge sans intervention
  sur la machine de build.
- F7 — Le chargement d'une datasource ne rend indisponible aucune autre
  datasource, ni la version en service de celle qu'il remplace.
- F8 — La bascule vers la nouvelle version est atomique ; un échec de
  contrôle laisse l'ancienne version en service.
- F9 — Le serveur sait dire quelle version de chaque datasource est en
  service et depuis quand.
- F10 — Un retour à la version précédente est possible sans rebuild.
- F11 — Quand une datasource dont d'autres dépendent change, les dépendantes
  sont revalidées, et rechargées ou signalées si elles ne sont plus cohérentes.

### 3.3 Couche de liaison (D4)

- F12 — Un référentiel de clés pivots est défini : commune INSEE, SIREN et
  SIRET, parcelle cadastrale, parcelle PAC, numéro AMM, code culture PAC,
  taxon, production, station météo.
- F13 — Chaque datasource déclare les clés pivots qu'elle porte.
- F14 — Le taux de correspondance de chaque clé avec son référentiel est
  mesuré à chaque build et publié avec le package.
- F15 — Des fiches pré-jointes par entité pivot (au minimum commune, parcelle,
  entreprise) sont produites à la publication, pas à la requête.
- F16 — Aucune liaison ne permet d'identifier une personne physique.

### 3.4 Recettes pour contributeurs (D4)

- F17 — Une datasource se décrit par une recette versionnée dans Git :
  source, licence, fréquence, schéma, transformation, tests.
- F18 — Un contributeur peut créer, construire, tester et prévisualiser une
  recette sur sa machine, dans le même environnement que le build officiel.
- F19 — Une contribution arrive par pull request ; le build officiel est
  refait par la plateforme, jamais repris d'un fichier fourni.
- F20 — Des contrôles automatiques bloquent une contribution : licence non
  ouverte, données de personnes physiques, schéma non respecté, taux de
  liaison sous un seuil, chute anormale du nombre de lignes.
- F21 — Les datasources existantes sont exprimées dans ce format ; elles
  servent d'exemples.

### 3.5 API et serveur MCP (D4, D7)

- F22 — L'API continue d'exposer chaque ressource en HTML, JSON et CSV.
- F23 — L'API expose le catalogue : datasources, versions, licences, crédits,
  date de la source.
- F24 — L'API expose les fiches de la couche de liaison.
- F25 — Un serveur MCP donne accès au catalogue, aux ressources et aux fiches.
- F26 — Une mise à jour de datasource ne demande ni redéploiement ni
  reconfiguration de l'API.

### 3.6 Historique (D4)

- F27 — Plusieurs versions publiées d'une datasource sont conservées, selon
  une politique de rétention par datasource.
- F28 — Une version passée reste téléchargeable.
- F29 — Pour les datasources désignées, une version passée reste
  interrogeable par l'API (« tel qu'à telle date »).

### 3.7 Accès et administration (ajout du 2026-10-03)

- F30 — L'API reste consultable sans clé, avec un quota bas par adresse IP.
- F31 — Une clé d'API donne un quota plus élevé et, selon son plan, l'accès
  à des ressources réservées. Elle n'est délivrée qu'à un adhérent OSFarm et
  expire avec l'adhésion.
- F32 — Le débit est limité par clé, ou par adresse IP sans clé ; la réponse
  indique le quota restant.
- F33 — Une interface web réservée aux administrateurs permet de créer,
  révoquer et renouveler les clés, et de définir les plans.
- F34 — L'interface montre la consommation par clé et par jour.
- F35 — L'interface montre l'état des datasources en service.
- F36 — Une clé n'est jamais stockée ni réaffichée en clair.
- F37 — Les bundles privés ne sont téléchargeables qu'avec une clé autorisée.

## 4. Exigences non fonctionnelles

- N1 — **Disque** : contenu servi, marge de bascule, fiches, packages et
  historique tiennent dans 800 Go si le serveur héberge aussi les packages
  (D10). Budget indicatif : 278 Go de contenu, 100 Go de marge pour la plus
  grosse table, soit ≈ 380 Go ; un jeu complet de packages compressés pèse
  ≈ 54 Go aujourd'hui (`out/`). Il reste donc ≈ 365 Go pour les fiches et les
  versions passées, soit de l'ordre de cinq à six jeux complets au maximum.
- N2 — **Mémoire** : aucun traitement lancé sur le serveur ne dépasse 32 Go ;
  le chargement d'une datasource ne dégrade pas le service des autres.
- N3 — **Coût d'une mise à jour** : proportionnel à la datasource. Cible :
  phytosanitaire rechargé en moins de 15 minutes, contre un rechargement
  complet aujourd'hui.
- N4 — **Reproductibilité** : un même état des sources et de la recette
  produit un package identique.
- N5 — **Sécurité** : la base de production n'est pas exposée sur Internet.
  Si les packages vivent sur le serveur (D10), la machine de build y dépose
  des fichiers par un accès limité au dépôt de packages, sans accès à la base.
- N6 — **Licences** : la licence de chaque datasource est portée par le
  package et exposée par l'API. Les licences à partage à l'identique (ODbL)
  et non commerciales (rd_agri, CC BY-NC-SA) sont signalées dans les fiches
  qui les croisent.
- N7 — **RGPD** : les données nominatives de personnes physiques ne sont ni
  chargées ni reliées.
- N8 — **Exploitation** : une seule personne peut publier une mise à jour,
  suivre son chargement et revenir en arrière.

## 5. User stories et critères d'acceptation

**US1 — Mainteneur : mettre à jour une datasource.**
Je publie une nouvelle version de `phytosanitary` et elle est en service sans
que j'intervienne sur le serveur.
- Les autres datasources gardent leur version et restent disponibles.
- Le registre et l'API affichent la nouvelle version.
- Un contrôle en échec laisse l'ancienne version en service et me le signale.

**US2 — Mainteneur : revenir en arrière.**
Je repasse `phytosanitary` à la version précédente en une commande, sans
rebuild.

**US3 — Mainteneur : mettre à jour un référentiel dont d'autres dépendent.**
Je publie `taxonomy` ; les datasources qui s'y réfèrent sont revalidées, et je
vois lesquelles sont à reconstruire.

**US4 — Utilisateur de l'API : croiser.**
À partir d'une parcelle, j'obtiens sa commune, sa culture déclarée et les
produits phytosanitaires autorisés sur cette culture, en un appel.

**US5 — Utilisateur de l'API : savoir ce que je consulte.**
Chaque réponse indique la datasource, sa version, la date de la source et la
licence.

**US6 — Contributeur : proposer une datasource.**
J'écris une recette, je la teste chez moi, j'ouvre une pull request ; les
contrôles me disent quoi corriger.

**US7 — Agent IA : interroger.**
Par MCP, je liste les datasources, je lis une ressource et une fiche.

**US8 — Utilisateur : consulter une version passée.**
Je télécharge le RPG d'une version antérieure ; pour les datasources
désignées, je l'interroge par l'API.

## 6. Tensions à trancher en conception

1. **Historique contre disque.** Garder plusieurs versions du cadastre en
   base est exclu (100 Go la table). L'historique interrogeable (F29) doit
   être réservé à des datasources désignées ; le reste est téléchargeable
   (F28).
2. **Périmètre contre effort.** D1 seul était estimé à 20–30 jours. Les
   quatre briques de D4 ajoutent chacune plusieurs semaines. Un découpage en
   jalons est proposé au §8.
3. **Aucune contrainte Ekylibre (D2) contre l'API existante.** L'API lit le
   schéma actuel table par table : casser le schéma, c'est réécrire ses
   namespaces. D7 laisse le choix ouvert ; le critère est le coût
   d'adaptation de ses namespaces comparé à celui d'une API générée à partir
   des schémas de packages.
5. **Stockage gratuit contre volume.** Un jeu complet de packages pèse
   ≈ 54 Go. Les offres gratuites de stockage objet connues plafonnent autour
   de 10 Go (à vérifier sur les grilles actuelles) : elles ne couvrent que
   les petites datasources. Par défaut, les packages vivent sur le disque du
   serveur ; la sauvegarde hors serveur reste alors à prévoir.
4. **Build local contre disque local.** La machine de build est à 90 % ;
   l'historique et des packages par datasource y ajoutent du volume.

## 7. Questions ouvertes

Q1 à Q5 sont tranchées (D6 à D10).

- Q5b — Si les packages vivent sur le serveur, où est leur sauvegarde ? Un
  disque unique porterait à la fois la base, les packages et l'historique.
- Q6 — Traductions : garde-t-on `master_translations` ou passe-t-on à
  `label jsonb` par table ? D2 le permet ; l'API a son propre `Translator`.
- Q7 — Les flavors (`ekyviti`, `light`) ont-ils encore un sens sans
  contrainte Ekylibre ?
- Q8 — Quelles datasources doivent rester interrogeables dans le passé
  (F29), et combien de versions garder ?
- Q9 — Qui d'autre qu'Ekylibre consomme aujourd'hui les packages ou la base ?
  D2 les concerne aussi.
- Q10 — La gem `lexicon-common` est-elle conservée, ou son loader est-il
  réécrit dans la v2 ?
- Q11 — `lexicon-n8n` et `lexicon-ai` font-ils partie de la v2 ?
- Q12 — Les fiches doivent-elles inclure les propriétaires de parcelles
  (personnes morales uniquement) ? C'est le point le plus sensible de F16.

Réponses :
Q5b : On fera une sauvegarde sur un serveur S3 via Dokploy
Q6 : Je te laisse choisir la meilleur méthode (performance, simplificité d'ajout...)
Q7 : Oui, cela permettra à des personnes d'exporter une partie du Lexicon pour un usage edge par exemple sur une ferme où on veut uniquement les références spatiales autour d'un point ou d'une parcelle et pas la france entière.
Q8 : Fais moi un tableau que je compléterai
Q9 : Oui, le projet Cultia par exemple
Q10 : réécrit
Q11 : si on en a besoin oui, autrement non.
Q12 : oui

## 8. Découpage proposé

| Jalon | Contenu | Exigences |
|---|---|---|
| J1 — Mises à jour indépendantes | Package et version par datasource, registre, chargement et bascule côté serveur, retour arrière ; validation sur un référentiel et sur `phytosanitary`, puis toutes les datasources | F1–F11, N1–N5, N8 |
| J2 — Catalogue et historique | Catalogue dans l'API, rétention, versions passées téléchargeables puis interrogeables | F22, F23, F26–F29 |
| J3 — Liaison | Clés pivots déclarées et mesurées, fiches commune, parcelle, entreprise | F12–F16, F24 |
| J4 — Recettes et contributeurs | Format de recette, outil local, contrôles automatiques | F17–F21 |
| J5 — MCP | Serveur MCP sur le catalogue, les ressources et les fiches | F25 |
| J6 — Accès et administration | Clés d'API, quotas, limitation de débit, interface web de gestion. Indépendant de J2 à J5 ; conception dans `design_lexicon_v2_admin.md` | F30–F37 |

J1 conditionne tous les autres. J4 gagne à être anticipé dans J1 : si le
package de J1 est déjà décrit par une recette, J4 se réduit à l'outillage et
aux contrôles.

## 9. Hors périmètre de la première version

- Tuiles vectorielles, CDN, moteur analytique séparé.
- Interface web de dépôt de CSV pour non-développeurs.
- Builds lourds répartis chez des contributeurs.
- Second serveur dédié au build.
- Nouvelles sources de données (DVF, BD TOPO complète, SIRENE complet).

## 10. Prochaines étapes

1. `/sc:design` sur le jalon J1, en y tranchant D7 (API gardée ou remplacée)
   et Q10 (gem reprise dans le monorepo ou conservée).
2. Rapatrier les packages utiles du MinIO avant sa fermeture (F5b).
3. Réécrire `ROADMAP.md` une fois la conception validée.
