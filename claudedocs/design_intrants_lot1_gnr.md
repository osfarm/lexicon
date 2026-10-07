# Conception — Lot 1 : prix du GNR et parcours de validation

Conception du 2026-10-07. Besoins et décisions : `claudedocs/brainstorm_intrants.md`
(F12 à F14, F18 à F23, NF1 à NF7, décisions D1 à D13). Points P1 à P5 confirmés.
Implémenté le 2026-10-07 jusqu'à l'étape 8 du parcours : voir §8.

Ce lot a deux objets : un petit jeu de données, le prix du gazole non routier,
et la méthode pour faire passer un jeu du poste de build à la production. Le
jeu est choisi pour sa simplicité ; c'est la méthode qui compte.

## 0. Décisions de conception

| # | Sujet | Décision |
|---|---|---|
| C1 | Nom et périmètre | Datasource `fuel_prices`. Tables faites pour plusieurs produits pétroliers, **remplies du seul GNR** dans ce lot |
| C2 | Source | Classeur « Prix HTT et TTC depuis janvier 2020 » de la DGEC, feuille « Carburants non routiers ». Licence Ouverte 2.0 |
| C3 | Adresse du classeur | Lue dans la page du ministère à chaque collecte, pas écrite en dur : le nom du fichier porte un suffixe qui change |
| C4 | Deux tables | Les relevés du vendredi tels que publiés, et la moyenne par mois **calculée par Lexicon** à partir des relevés |
| C5 | Trois prix | Hors toutes taxes et TTC viennent de la source ; hors TVA est calculé (TTC / 1,20). C'est le prix hors TVA qui sert à chiffrer une intervention |
| C6 | Garde-fous de collecte | Une collecte douteuse fait échouer la construction : rien n'est empaqueté, la version en service reste |
| C7 | Cible de publication | `publish` vise la pile locale par défaut. La production se demande explicitement (`--production`) et exige que la même version soit en service en local |
| C8 | Sans changement | Une collecte qui ne rapporte rien de neuf ne produit pas de nouveau package |
| C9 | API | Aucune route dans ce lot : le jeu apparaît dans `/catalog`, qui se nourrit des manifestes. Les routes viennent au lot 6 |
| C10 | `master_prices` | Pas touché dans ce lot. L'article GNR et sa dernière valeur viennent au lot 5 |

### Pourquoi des tables à plusieurs produits (C1)

Le même classeur contient les carburants routiers et le fioul domestique, avec
la même forme. Une colonne `product` ne coûte rien et évite une révision de
schéma le jour où on les veut. On ne les charge pas maintenant : chaque produit
chargé est un produit à contrôler et à présenter, et le besoin (F12) ne porte
que sur le GNR.

### Pourquoi recalculer la moyenne mensuelle (C4)

Le classeur donne sa propre moyenne mensuelle, mais sans le nombre de relevés
et seulement pour les mois terminés ou en cours selon la date de mise à jour.
La calculer à partir des relevés donne le nombre de relevés (F13), un mois en
cours cohérent avec le dernier vendredi, et la même méthode que pour les prix
des lots suivants. Le bloc mensuel de la DGEC sert de contrôle (§2.4).

### Pourquoi la production n'est pas la cible par défaut (C7)

| Option | Pour | Contre |
|---|---|---|
| Une variable `LEXICON_PUBLISH_TARGET`, changée à la main | Rien à écrire | On publie en production en croyant publier en local, ou l'inverse ; rien ne vérifie le passage par le local |
| Deux commandes distinctes | Explicite | Deux chemins de code à maintenir pour le même envoi |
| **Une commande, la production en option, avec condition** | Un seul chemin ; l'erreur par défaut est sans conséquence ; le passage par le local est vérifié par la machine | Une variable de plus dans `.env` |

## 1. Vue d'ensemble

```
ecologie.gouv.fr ──collect──► raw/fuel_prices/        (classeur daté, conservé)
                                    │ load
                                    ▼
                          schéma de travail fuel_prices
                                    │ normalize + garde-fous (C6)
                                    ▼
                    base de build, schéma lexicon
                    registered_fuel_prices, registered_fuel_monthly_prices
                                    │ check, package
                                    ▼
                    out/packages/fuel_prices/<version>/
                                    │ publish                     (C7)
              ┌─────────────────────┴──────────────────────┐
              ▼                                            ▼
   out/published  (pile locale)                 osfarm_lexicon:lexicon/packages
   loader local, 5 min au plus                  loader de production
   http://localhost:8888/catalog                https://lexicon.osfarm.org/catalog
              │                                            ▲
              └──── même version en service en local ──────┘
                    condition de `publish --production`
```

## 2. Datasource `fuel_prices`

### 2.1 Déclarations

| Déclaration | Valeur |
|---|---|
| `description` | Prix moyens nationaux des produits pétroliers relevés chaque vendredi par la DGEC ; gazole non routier |
| `credits` | « Prix des produits pétroliers », ministère de la Transition écologique (DGEC), <https://www.ecologie.gouv.fr/politiques-publiques/prix-produits-petroliers>, Licence Ouverte 2.0 |
| `updated_at` | Date du dernier relevé chargé, pas la date du jour (voir §2.5) |
| `schema_revision` | 1 |
| `scope` | ouvert (défaut) |
| `depends_on`, `pivot`, `translations`, `personal_data` | aucun |

### 2.2 Ce que contient la source

Feuille « Carburants non routiers », observée le 2026-10-07 (fichier modifié le
2026-10-05) :

| Lignes | Contenu |
|---|---|
| 1 et 2 | En-têtes : « PRIX DE VENTE H.T.T. (en euro par litre) », « PRIX DE VENTE T.T.C. », produit « Gazole non routier (livraisons inférieures à 5 000 litres) » |
| 3 à 358 environ | Un relevé par vendredi depuis le 2020-01-03 : date (numéro de série Excel), prix HTT, prix TTC |
| « MOYENNES MENSUELLES » | Une ligne par mois, datée du premier du mois |
| « MOYENNES ANNUELLES » | Une ligne par année terminée, l'année en colonne A |

Champ : France métropolitaine hors Corse. Publication chaque lundi.

### 2.3 Tables publiées

```sql
CREATE TABLE registered_fuel_prices (
  id character varying PRIMARY KEY NOT NULL,       -- non_road_diesel_2026-10-02
  product character varying NOT NULL,              -- non_road_diesel
  observed_on date NOT NULL,                       -- le vendredi du relevé
  price_excluding_taxes numeric(8,4) NOT NULL,     -- hors toutes taxes, source
  price_excluding_vat numeric(8,4) NOT NULL,       -- TTC / 1,20, calculé
  price_including_taxes numeric(8,4) NOT NULL,     -- TTC, source
  currency character varying NOT NULL,             -- EUR
  unit character varying NOT NULL                  -- liter
);
CREATE INDEX registered_fuel_prices_product_observed_on
  ON registered_fuel_prices (product, observed_on);

CREATE TABLE registered_fuel_monthly_prices (
  id character varying PRIMARY KEY NOT NULL,       -- non_road_diesel_2026-10
  product character varying NOT NULL,
  month date NOT NULL,                             -- premier jour du mois
  price_excluding_taxes numeric(8,4) NOT NULL,     -- moyenne des relevés du mois
  price_excluding_vat numeric(8,4) NOT NULL,
  price_including_taxes numeric(8,4) NOT NULL,
  observations integer NOT NULL,                   -- nombre de relevés du mois
  last_observed_on date NOT NULL,                  -- dernier relevé compté
  currency character varying NOT NULL,
  unit character varying NOT NULL
);
CREATE INDEX registered_fuel_monthly_prices_product_month
  ON registered_fuel_monthly_prices (product, month);
```

Volumes attendus : environ 355 relevés et 82 mois, une cinquantaine de lignes
de plus par an.

Le mois en cours figure dans la table mensuelle avec les relevés déjà parus :
`observations` et `last_observed_on` disent qu'il est partiel (F18).

Vérification sur les valeurs d'Itinera pour octobre 2026, un relevé : HTT
1,321, TTC 2,027, hors TVA 2,027 / 1,20 = 1,689. Les trois concordent.

### 2.4 Phases

| Phase | Ce qu'elle fait |
|---|---|
| `collect` | Télécharge la page du ministère, y trouve le lien dont le libellé commence par « Prix HTT et TTC depuis janvier 2020 », télécharge le classeur dans `raw/fuel_prices/` sous un nom daté. Échoue si le lien est introuvable ou si le fichier n'est pas un classeur |
| `load` | Lit la feuille « Carburants non routiers » **par son nom**, garde les lignes dont la colonne A est une date postérieure à 2019 et située avant la ligne « MOYENNES MENSUELLES », les charge dans `fuel_prices.readings`. Charge à part le bloc mensuel de la DGEC dans `fuel_prices.source_months` |
| `normalize` | Remplit les deux tables, puis applique les garde-fous |

Garde-fous (C6), chacun arrête la construction avec un message qui dit quoi
regarder :

| Contrôle | Seuil | Ce qu'il attrape |
|---|---|---|
| En-têtes de la feuille | Libellés attendus en lignes 1 et 2 | Colonnes déplacées, produit ajouté |
| Nombre de relevés | Au moins 350 | Feuille tronquée, mauvais bloc lu |
| Jour des relevés | Tous des vendredis | Décalage de dates |
| Fraîcheur | Dernier relevé de moins de 21 jours | Page figée, mauvais fichier |
| Plage des prix | HTT entre 0,20 et 3,00 €/L ; TTC supérieur à HTT | Unité changée, colonnes inversées |
| Moyennes | Écart de moins de 0,005 €/L avec le bloc mensuel de la DGEC, sur les mois terminés | Erreur de calcul ou de lecture |

Le contrôle de volume de `./lexicon check` (moins de 70 % des lignes de la
version précédente) s'y ajoute sans rien écrire.

### 2.5 Date de la source et fraîcheur (NF4)

`updated_at` des crédits est aujourd'hui une constante écrite dans le fichier
Ruby. Pour un jeu rafraîchi chaque semaine, elle serait fausse dès la deuxième
collecte. Deux options :

| Option | Pour | Contre |
|---|---|---|
| Laisser la constante, la modifier à la main | Rien à écrire | Oubli certain ; le catalogue annonce une date fausse |
| **Date tirée des données à l'empaquetage** : une datasource peut dire quelle requête donne la date de sa source | Juste par construction ; servira à tous les jeux de prix | Une déclaration de plus dans le DSL, et le manifeste à adapter |

Retenu : la seconde. Pour `fuel_prices`, la date est le dernier `observed_on`.
C'est aussi elle qui permettra de dire qu'un jeu est périmé : plus de 21 jours
pour celui-ci.

### 2.6 Collecte sans nouveauté (C8)

Lancée chaque semaine, la collecte rapportera parfois le même classeur (jour
férié, lancement un lundi matin). `package` compare alors les empreintes des
fichiers de données avec celles du dernier package local : identiques, il
n'écrit rien et le dit. Sans cela, le dépôt accumule des versions jumelles et
la rétention en garde de fausses.

Rétention proposée dans `resources/retention.yml` : les 8 dernières versions.

## 3. Parcours de validation

### 3.1 Les étapes

| # | Étape | Commande | Ce qui est vérifié | Où regarder |
|---|---|---|---|---|
| 1 | Créer | `./lexicon new fuel_prices > lib/datasources/fuel_prices.rb` | — | — |
| 2 | Déclarations | `./lexicon check fuel_prices --static` | Description, crédits, licence, données personnelles | Sortie de la commande |
| 3 | Construire | `./lexicon run fuel_prices` | Collecte, chargement, garde-fous du §2.4 | Sortie ; `raw/fuel_prices/` |
| 4 | Données | `./lexicon check fuel_prices` | Tables non vides, volume, taux de liaison | Sortie |
| 5 | Empaqueter | `./lexicon package fuel_prices` | Clés étrangères, export, empreintes | `out/packages/fuel_prices/<version>/manifest.json` |
| 6 | Publier en local | `./lexicon publish fuel_prices` | Envoi identique à la source | Sortie : nom de la cible |
| 7 | Mise en service locale | `./lexicon status` (5 minutes au plus) | Chargement, contrôles du loader, bascule | `in service <version>` ; `http://localhost:8889/status.json` |
| 8 | Rendu local | Navigateur et requête SQL | Le jeu est au catalogue, les valeurs sont justes | `http://localhost:8888/catalog` ; base `localhost:5556` |
| 9 | Publier en production | `./lexicon publish fuel_prices --production` | Version identique à celle en service en local | Sortie |
| 10 | Mise en service en production | `./lexicon status --production` | Idem étape 7 | `https://lexicon-packages.osfarm.org/status.json` |
| 11 | Rendu en production | Navigateur | Idem étape 8 | `https://lexicon.osfarm.org/catalog` |

Retour arrière à toute étape après la 7 : `server rollback fuel_prices` dans le
conteneur `loader` de la pile concernée.

### 3.2 Deux cibles (C7, F20)

Variables de `.env` :

| Variable | Rôle | Valeur sur ce poste |
|---|---|---|
| `LEXICON_PUBLISH_TARGET` | Cible par défaut de `publish` et de `status` | `/lexicon/out/published` |
| `LEXICON_PRODUCTION_TARGET` | Cible de `publish --production` et de `status --production` | `osfarm_lexicon:lexicon/packages` |

Comportement de `publish --production` :

1. Sans `LEXICON_PRODUCTION_TARGET`, la commande s'arrête et le dit.
2. Elle lit `status.json` de la cible par défaut. Si le package n'y est pas en
   service **dans la version demandée**, elle refuse : « fuel_prices
   2026.10.12.1 n'est pas en service en local ».
3. Elle affiche la cible, le nom et la version, puis envoie.
4. `--force` passe outre la condition 2, pour un poste sans pile locale.

`publish` sans option affiche lui aussi sa cible. Une cible qui est un
répertoire local se reconnaît à l'absence de `hôte:`.

Le poste a besoin de `rsync` vers `osfarm_lexicon` par SSH : `~/.ssh` est déjà
monté dans le runner, l'alias est dans `~/.ssh/config` depuis le 2026-10-07.

### 3.3 Modifier un jeu plutôt qu'en ajouter un (F21)

Ce lot n'y est pas confronté ; le lot 2 (EIQ et HRAC sur `phytosanitary`) le
sera. Ce que le parcours doit déjà dire :

| Situation | Ce qui change dans le parcours |
|---|---|
| Colonne ajoutée, retirée ou retypée | Incrémenter `schema_revision` ; prévenir les lecteurs (Ekylibre, API) avant l'étape 9 |
| Le jeu lit un autre jeu pendant `normalize` | La base de build doit contenir cet autre jeu : le construire d'abord (la base de build de ce poste est vide) |
| Volume en baisse de plus de 30 % | `check` et le loader refusent ; si la baisse est voulue, `server sync <nom> --force` |
| Clé étrangère vers un jeu modifié en même temps | Publier ensemble, et `server sync a b --together` |
| Jeux dérivés (`commune_links`, `enterprise_links`) | Les reconstruire et republier après leurs sources |

### 3.4 Quand une collecte échoue (F22)

| Où | Effet | Ce que voit le mainteneur |
|---|---|---|
| `collect` (page ou lien absent) | `run` s'arrête, rien n'est chargé | Message nommant l'adresse et le libellé cherché |
| Garde-fou de `normalize` | `run` s'arrête ; les tables de build sont incomplètes, rien n'est empaqueté | Message nommant le contrôle et la valeur |
| `check` | Code de sortie 1 | Liste des erreurs |
| Loader | La version précédente reste en service | `last_failures` de `status.json` |

Dans les quatre cas la version en service ne bouge pas. Le classeur fautif
reste dans `raw/fuel_prices/` pour examen (NF3).

### 3.5 Le rendez-vous hebdomadaire (D8)

Chaque lundi après-midi, depuis ce poste :

```sh
./lexicon run fuel_prices && ./lexicon check fuel_prices \
  && ./lexicon package fuel_prices && ./lexicon publish fuel_prices
./lexicon status                          # attendre « in service »
./lexicon publish fuel_prices --production
```

Une seule commande qui enchaîne le tout serait tentante. On ne l'écrit pas dans
ce lot : c'est exactement ce que l'outil du temps 2 devra faire, et il vaut
mieux en connaître les frictions avant (F23).

### 3.6 Relevé des frictions (F23)

Un fichier `claudedocs/frictions_parcours.md`, une ligne par accroc rencontré
en suivant le parcours : étape, ce qui a gêné, ce qui aurait évité la gêne.
Trois sont déjà connues :

| Étape | Friction |
|---|---|
| Installation | `docker/db/z_initdb_postgis.sql` finit par un `GRANT` invalide : la base redémarre une fois à sa création |
| 7 | Rien ne dit quand le loader passera : on attend jusqu'à 5 minutes sans retour |
| 8 | Un jeu neuf n'a pas de route dans l'API : on ne peut le voir que dans le catalogue ou en SQL |

## 4. Ce qui change dans le dépôt

| Fichier | Changement |
|---|---|
| `lib/datasources/fuel_prices.rb` | Nouveau |
| `lib/lexicon/dsl/` | Déclaration de la date de la source tirée des données (§2.5) |
| `lib/lexicon/packaging/builder.rb`, `manifest.rb` | Date de la source dans le manifeste ; pas de package sans changement (§2.6) |
| `lib/lexicon/cli.rb`, `application.rb` | `--production` sur `publish` et `status`, condition de mise en service locale (§3.2) |
| `resources/retention.yml` | Rétention de `fuel_prices` |
| `.env.dist` | `LEXICON_PRODUCTION_TARGET`, commentaire sur les deux cibles |
| `docker-compose.server.local.yml` | À versionner : le parcours en dépend |
| `doc/PUBLICATION.md`, `doc/datasources/fuel_prices.md`, `CLAUDE.md`, `README.md` | Parcours en onze étapes, les deux cibles, le jeu |
| `test/lexicon/packaging/` | Publication vers la production refusée sans mise en service locale ; package non réécrit sans changement |
| `test/lexicon/datasources/` (nouveau) | Lecture d'un classeur d'exemple réduit ; chaque garde-fou déclenché par un classeur fautif |

## 5. Critères d'acceptation du lot

| # | Critère | Exigence |
|---|---|---|
| A1 | `registered_fuel_prices` contient un relevé par vendredi depuis le 2020-01-03, sans trou | F12 |
| A2 | La moyenne d'un mois terminé égale celle de la DGEC à 0,005 €/L près | F12, F13 |
| A3 | Octobre 2026 : hors TVA 1,689 €/L pour un relevé au 2026-10-02 | F14 |
| A4 | Un classeur d'essai tronqué fait échouer `run`, et la version en service ne change pas | F22 |
| A5 | `publish --production` refuse une version qui n'est pas en service en local | F20 |
| A6 | Le jeu est au catalogue local puis au catalogue de production, avec la date du dernier relevé | F19, F28 |
| A7 | Une seconde collecte le même jour ne crée pas de version | C8 |
| A8 | `./lexicon check --static` passe sans ligne nouvelle dans `check_baseline.yml` | NF1 |
| A9 | Le parcours a été suivi deux semaines de suite, frictions relevées | F23 |

## 6. Hors périmètre du lot

- Routes de l'API, écran et outil MCP pour le prix du GNR (lot 6).
- Article GNR dans `variants` et `master_prices` (lot 5).
- Carburants routiers et fioul domestique : les tables les accueillent, on ne
  les charge pas.
- Lancement automatique de la collecte (D8).

## 7. Points à confirmer

| # | Question | Proposition |
|---|---|---|
| P1 | Nom du jeu : `fuel_prices`, ou plus large (`energy_prices`) ? | `fuel_prices` : dit ce que contient la source |
| P2 | Charger dès maintenant le gazole routier et le fioul domestique, présents dans le même classeur ? | Non, pas sans besoin exprimé |
| P3 | TVA à 20 % écrite en constante : acceptable, sachant que le champ est la métropole hors Corse ? | Oui, avec le taux nommé dans le code et dans la documentation du jeu |
| P4 | Versionner `docker-compose.server.local.yml` et documenter la pile locale dans `doc/` ? | Oui : sans elle, le parcours ne se rejoue pas ailleurs |
| P5 | `publish --production` exige-t-il aussi que `check` ait passé sur cette version ? | Pas dans ce lot : le loader local a déjà refait les contrôles de données |

## 8. Écarts à l'implémentation (2026-10-07)

| Sujet | Conçu | Fait | Pourquoi |
|---|---|---|---|
| Garde-fous | Dans `normalize` | Dans `load`, par `Datasources::FuelPrices::Readings` | Une erreur dans `normalize` laisse les tables de build à moitié écrites ; dans `load`, elles ne sont pas touchées |
| Moyennes mensuelles | Calculées en SQL | Calculées en Ruby par `Readings`, chargées telles quelles | Le contrôle contre les moyennes de la DGEC a besoin du même calcul avant tout chargement ; un seul calcul, testé sans base |
| Date de la source | « Dans le manifeste » | Dans `credits[].updated_at` du manifeste, champ existant | Un champ nouveau aurait été refusé par le loader de production tant qu'il n'est pas redéployé |
| Détection « sans changement » | Empreintes des fichiers de données | Tout le manifeste sauf version et date de construction | Un changement de crédits ou de structure doit aussi faire une version |
| Export | — | `pigz -n` : pas d'horodatage dans les fichiers | Sans cela deux exports des mêmes lignes n'ont pas la même empreinte |
| Tests | Classeur d'exemple réduit | Lignes de feuille construites dans le test | Pas de bibliothèque d'écriture de classeur dans le dépôt ; la lecture par Roo est couverte par la construction réelle |

État des critères : A1, A2, A3, A5, A7 et A8 constatés ; A4 couvert par les
tests de `Readings` ; A6 constaté en local, la production reste à faire ; A9
commence.
