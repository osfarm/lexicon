# Conception — Lot 3 : engrais, prix et valeur des unités

Conception du 2026-10-07. Besoins : `claudedocs/brainstorm_intrants.md` (F8 à F11, F13 à F18, NF1 à NF7,
décisions D1 à D13, questions Q11 et Q12). Points B1 à B4 tranchés le 2026-10-07 : sans Agryco, cinq lieux dont
17250, prix négocié retenu à défaut de prix public, Germineo avant Cereapro. Implémenté le même jour : voir §10.

C'est le premier lot à collecter des prix chez des marchands. L'étude des trois sites change deux
hypothèses du cadrage : les prix ne sont pas affichés sans code postal, et l'un des sites refuse les
collectes automatiques.

## 0. Ce que l'étude des sources a montré (2026-10-07)

| Site | Ce qui est public sans rien saisir | Les prix | Accès automatique |
|---|---|---|---|
| Cereapro (`appro-cereapro.com`) | Le catalogue des offres : 86 offres d'engrais et d'amendements, avec produit, catégorie, origine, forme, période de livraison, conditionnement, teneurs. `robots.txt` autorise tout | Remplacés par « 999,99 » tant qu'un **code postal** de livraison n'est pas saisi : ce sont des prix rendus ferme | Pages lisibles ; la saisie du code postal passe par l'application du site |
| Germineo (`germineo.com`) | Les fiches produits (2 093 dans le plan du site, dont les fertilisants), avec nom, référence, catégorie, conditionnement, période de livraison. `robots.txt` n'interdit que le compte et le panier | À zéro dans la fiche tant qu'un **pays et un code postal** ne sont pas saisis : prix livrés | Pages lisibles ; la saisie du code postal passe par l'application du site |
| Agryco (`agryco.com`) | Rien : le site répond **406** à tout client qui n'est pas un navigateur, `robots.txt` compris | Non vus | Refusé. C'est un blocage voulu |

Trois conséquences :

1. **Un prix marchand est un prix livré quelque part.** Il n'y a pas de « prix Germineo de l'ammonitrate »,
   il y a son prix livré à Chartres ou à Auch. Le jeu doit dire où (§3).
2. **Obtenir un prix demande de saisir un code postal dans l'application du site**, donc de rejouer ses
   échanges ou de piloter un navigateur. C'est plus qu'une lecture de page, et plus fragile.
3. **Agryco ne peut pas être collecté** sans contourner un refus explicite, ce que NF2 exclut. Il faut un
   flux fourni par Agryco, ou s'en passer (§7, B1).

## 1. Décisions de conception

| # | Sujet | Décision |
|---|---|---|
| C1 | Découpage | Deux datasources : `fertilizers` (le référentiel, stable) et `fertilizer_prices` (les relevés, hebdomadaires) |
| C2 | Référentiel | Construit à partir des 182 articles de `variants`, complété par les produits vus chez les marchands. Chaque produit a un type, une présentation et ses teneurs |
| C3 | Identité d'un produit | Sa formule normalisée (teneurs et forme), pas son nom commercial : « Ammonitrate 33.5 » et « AMMONITRATE 33,5 - Engrais Granulé » sont le même produit |
| C4 | Relevés | Chaque offre vue est gardée telle quelle : marchand, produit, conditionnement, période de livraison, lieu de livraison, prix, date du relevé |
| C5 | Prix mensuel | Un prix par produit, conditionnement et mois, tiré des relevés selon la règle de priorité (D7) |
| C6 | Valeur des unités | Calculée chaque mois à partir des prix des engrais simples, avec les produits utilisés publiés à côté |
| C7 | Lieu de référence | Un petit nombre de codes postaux fixés, les mêmes chaque semaine (§3) |
| C8 | Collecte | Un collecteur par marchand, derrière une même interface ; les pages brutes sont conservées |
| C9 | Garde-fous | Comme aux lots 1 et 2 : dans `load`, avant de toucher aux tables publiées |
| C10 | `master_prices` | Pas touché ici : lot 5 |

### Pourquoi deux datasources (C1)

Le référentiel change quand un produit apparaît ; les prix changent chaque semaine. Séparés, la collecte
hebdomadaire ne republie que les prix, et une panne de collecte ne touche pas au référentiel. Les prix
portent une clé étrangère vers le référentiel : les deux se publient ensemble la première fois
(`server sync fertilizers fertilizer_prices --together`).

### Pourquoi garder les relevés bruts en plus du prix mensuel (C4, C5)

| Option | Pour | Contre |
|---|---|---|
| Publier seulement le prix mensuel retenu | Une table simple | La règle d'arbitrage devient invérifiable ; changer la règle demande de recollecter le passé, ce qui est impossible |
| **Publier les relevés et le prix mensuel** | La règle se rejoue sur l'historique ; chacun peut refaire son propre calcul ; la source de chaque prix est visible (F32) | Deux tables ; les relevés nomment les marchands |

## 2. Modèle de données

Schéma indicatif, à figer à l'implémentation.

```
master_variants (existant)
      ▲ variant_reference_name (nullable)
      │
registered_fertilizers ◄──────────────── registered_fertilizer_price_readings
  id                     fertilizer_id     id
  name                                     merchant            germineo | cereapro | …
  kind                                     observed_on         date du relevé
  form                                     delivery_place      code postal de référence
  nitrogen … sulfur                        packaging           bulk | big_bag_600 | …
  organic                                  delivery_from/to    période de livraison
  variant_reference_name                   price               € HT par tonne ou par litre
  ▲                                        unit                ton | liter
  │                                        negotiated          prix de groupement (D9)
  │                                        source_label        nom chez le marchand
  │                                        source_url
  │
  ├──── registered_fertilizer_monthly_prices
  │       fertilizer_id, packaging, month, price, unit,
  │       merchant (celui retenu), observations, last_observed_on, negotiated
  │
  └──── registered_fertilizer_unit_values
          month, nutrient (N | P2O5 | K2O | SO3), value (€ par kg d'élément),
          fertilizer_id (le produit de référence), price, observations
```

| Table | Datasource | Grain | Volume attendu |
|---|---|---|---|
| `registered_fertilizers` | `fertilizers` | un produit | 250 à 400 |
| `registered_fertilizer_price_readings` | `fertilizer_prices` | une offre, un lieu, un jour de relevé | 200 à 600 par semaine |
| `registered_fertilizer_monthly_prices` | `fertilizer_prices` | un produit, un conditionnement, un mois | 100 à 300 par mois |
| `registered_fertilizer_unit_values` | `fertilizer_prices` | un élément, un mois | 4 par mois |

`kind` : `mineral`, `organic`, `amendment`, `foliar` (F8). Teneurs en pourcentage : N, P2O5, K2O, SO3, MgO,
CaO, et les oligo-éléments quand ils sont déclarés. Les teneurs sont dans les conventions de l'étiquette
(oxydes), comme dans `variants`.

Rattachement aux 182 articles (F11) : `variant_reference_name`, rempli quand la formule normalisée
coïncide. Le taux de rattachement est mesuré à chaque construction (NF7).

## 3. Lieu de référence (C7)

Un prix rendu ferme dépend de la distance au port ou à l'usine. Trois façons de faire :

| Option | Pour | Contre |
|---|---|---|
| Un seul code postal | Simple ; une série propre | Représente une région, pas la France |
| **Trois à cinq codes postaux répartis** (par exemple Beauce, Bretagne, Sud-Ouest, Nord-Est, Rhône-Alpes) | Montre l'écart régional ; le prix mensuel « France » est leur moyenne, et chaque lieu reste lisible | Trois à cinq fois plus de requêtes chez chaque marchand |
| Tous les départements | Fin | Une centaine de requêtes par produit et par semaine : disproportionné, et lourd pour les sites |

Proposition : cinq lieux, fixés dans un fichier `data/fertilizer_prices/delivery_places.csv`, jamais
changés sans le dire (la série en dépend). À confirmer (§7, B2).

## 4. Calcul

### 4.1 Prix mensuel d'un produit (C5, F13, F15)

1. Ne garder que les relevés du mois dont la période de livraison commence dans les 90 jours : une offre
   « morte-saison » pour dans six mois n'est pas le prix du mois.
2. Par marchand : moyenne des relevés du mois, tous lieux confondus.
3. Entre marchands : celui que la priorité désigne (D7, Q11). Un prix de groupement est marqué
   `negotiated` ; qu'il puisse être le prix retenu est la question Q12 (§7, B3).
4. Un mois sans relevé reprend le dernier prix connu, avec sa date (F18).

### 4.2 Valeur des unités (C6, F10)

| Élément | Engrais simple de référence | Calcul |
|---|---|---|
| N | Ammonitrate 33,5 | prix de la tonne / 335 kg |
| P2O5 | Super triple 45 | prix de la tonne / 450 kg |
| K2O | Chlorure de potasse 60 | prix de la tonne / 600 kg |
| SO3 | Sulfate d'ammoniaque 21 N 60 SO3 | (prix de la tonne − 210 kg × valeur de N) / 600 kg |

En vrac ou en big-bag de 600 kg, selon ce qui est relevé, la table disant lequel. Un mois où un engrais de
référence manque reprend la dernière valeur connue. Le prix d'une formule absente (CA2) :
somme des teneurs × valeurs, que l'API ou l'utilisateur calcule ; la table ne publie que les valeurs.

Le choix des engrais de référence se discute : l'urée donne un azote moins cher que l'ammonitrate. La
table nomme le produit utilisé pour que le lecteur sache ce qu'il lit.

## 5. Collecte (C8, NF2, NF3)

```
Collecteur (un par marchand)
  catalogue()            → liste des produits : nom, catégorie, teneurs, conditionnements, adresse
  offres(lieu)           → liste des offres avec prix, pour un code postal
```

- Les pages et réponses brutes sont rangées dans `raw/fertilizer_prices/<marchand>/<date>/` : un relevé
  passé se relit sans retourner sur le site.
- Débit : une requête par seconde au plus, un seul passage par semaine, identification du collecteur dans
  l'en-tête (`Lexicon OSFarm`, adresse du projet).
- Un marchand en panne n'arrête pas la collecte : ses relevés manquent cette semaine-là, le prix mensuel
  se calcule sur les autres (NF6). Tous en panne : la construction s'arrête (C9).
- Garde-fous par marchand : nombre d'offres dans une fourchette, prix dans une plage par type de produit,
  aucun « 999,99 » ni zéro (le code postal n'a pas été pris en compte), variation de plus de 40 % d'une
  semaine à l'autre signalée.

Le référentiel `fertilizers` se construit sans prix : catalogue public de Cereapro, fiches de Germineo,
articles de `variants`. Il peut être fait et publié avant que la question des prix soit réglée.

## 6. Découpage du lot

| Étape | Contenu | Dépend de |
|---|---|---|
| 3a | `fertilizers` : référentiel, normalisation des formules, rattachement aux articles | rien |
| 3b | Collecteur Cereapro avec code postal, table des relevés | B2 |
| 3c | Collecteur Germineo | B2 |
| 3d | Prix mensuels et valeur des unités | 3b ou 3c, B3 |
| 3e | Agryco | B1 |

3a peut commencer tout de suite.

## 7. Points bloquants

| # | Question | Ce que je propose |
|---|---|---|
| B1 | **Agryco refuse les collectes automatiques** (réponse 406 à tout ce qui n'est pas un navigateur). Tu as noté leurs conditions comme acceptables (D5) : avez-vous un accord, et peuvent-ils fournir un flux ou un export ? | Ne pas contourner. Leur demander un export ; à défaut, faire le lot sans eux : Itinera ne s'en sert que pour les cours des grands engrais simples, que Cereapro couvre aussi |
| B2 | **Les prix sont livrés à un code postal.** Combien de lieux, et lesquels ? Saisir un code postal passe par l'application de chaque site : c'est une collecte plus intrusive qu'une lecture de page. Est-ce couvert par ce que tu as vérifié auprès de Cereapro et de Germineo ? | Cinq lieux fixes ; confirmer avec les deux marchands que cet usage leur convient, ou leur demander un export hebdomadaire, plus simple pour tout le monde |
| B3 | **Q12** : un prix de groupement (Cereapro) peut-il être le prix retenu d'un produit ? | Oui à défaut d'un prix public, toujours marqué `negotiated` ; non quand un prix public existe le même mois |
| B4 | **Q11** : ordre entre marchands | Germineo (prix public), puis Cereapro (prix de groupement), puis Agryco si un flux existe |

## 8. Critères d'acceptation

| # | Critère | Exigence |
|---|---|---|
| A1 | Chaque engrais de `variants` est rattaché au référentiel, ou la raison de l'absence est connue | F11 |
| A2 | Chaque produit a un type et au moins une teneur | F8 |
| A3 | Un relevé porte marchand, lieu, date, conditionnement, période de livraison et adresse de la source | F13, F14, F32 |
| A4 | Aucun prix « 999,99 » ou nul n'entre dans les tables | NF6 |
| A5 | La valeur de N, P2O5, K2O et SO3 est publiée pour le mois courant, avec le produit de référence | F10 |
| A6 | Le prix d'une formule ternaire calculé par les unités est à moins de 15 % de son prix relevé, sur les formules qui ont les deux | CA2 |
| A7 | Un marchand coupé pendant la collecte ne vide pas les tables | F22, NF6 |
| A8 | Le parcours en onze étapes est suivi pour les deux jeux, publiés ensemble la première fois | F19, F21 |

## 9. Hors périmètre

- Mise à jour de `master_prices` (lot 5).
- Routes de l'API, écrans, outils MCP (lot 6).
- Engrais de ferme (fumiers, lisiers) : pas de prix de marché.
- Estimation du coût de transport entre deux lieux.

## 10. Écarts à l'implémentation (2026-10-07)

| Sujet | Conçu | Fait | Pourquoi |
|---|---|---|---|
| Découpage (C1) | Deux datasources | Une seule, `fertilizers`, quatre tables | Les deux lisent les mêmes pages : deux collectes auraient doublé les requêtes chez les marchands. Les tables font un millier de lignes : tout republier chaque semaine ne coûte rien, et il n'y a plus de publication groupée à faire |
| Accès aux prix | « Rejouer les échanges de l'application ou piloter un navigateur » | Cereapro : une page par lieu, avec un témoin de session nommant la commune. Germineo : le formulaire de code postal, puis les pages de catégories | Les deux sites se lisent par de simples requêtes |
| Historique | Non traité | Relecture des pages gardées et des relevés du dernier package | Les tables de build sont recréées à chaque construction |
| Référentiel (C2) | 182 articles de `variants` complétés | Les produits vus chez les marchands, rattachés aux articles par leur formule | Importer des articles jamais vus en vente aurait donné des produits sans prix ni teneurs vérifiées |
| Germineo | Tous les conditionnements | Le conditionnement mis en avant dans la liste | Les autres demandent une page par produit : cinq fois plus de requêtes |
| Garde-fou de variation | Signalement au-delà de 40 % d'une semaine à l'autre | Pas fait | À faire quand il y aura deux semaines à comparer |
| Agryco (3e) | Selon B1 | Abandonné | Décision B1 |

Mesures du 2026-10-07 : 161 produits (84 minéraux, 41 organiques, 20 foliaires, 16 amendements), 914 relevés,
181 prix mensuels, 4 valeurs d'unités ; 11 produits vus chez les deux marchands, 18 rattachés à un article de
`variants`. Critères A2 à A5, A7 (par les tests) constatés ; A6 : écart de 1 à 13 % sur treize formules ; A1 :
18 articles rattachés sur 182, les autres n'étant pas en vente chez ces deux marchands ou étant des engrais de
ferme ; A8 : en service en local, production à faire.

Accès, décidé après relecture des prix en base locale : le jeu est **réservé aux adhérents** (`scope :members`),
ce qui révise D2. La version `2026.10.07.1`, construite ouverte, n'a jamais quitté le poste ; elle est remplacée
par `2026.10.07.2`.
