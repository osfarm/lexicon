# `fertilizers` — engrais, prix et valeur des unités

Les engrais et amendements proposés aux exploitations françaises, les prix livrés que deux marchands affichent
chaque semaine pour cinq lieux, le prix mensuel qu'on en tire, et la valeur du kilo d'azote, de phosphore, de
potasse et de soufre.

**Jeu réservé aux adhérents OSFarm** (`scope :members`) : les prix nomment les marchands qui les affichent. Le
package n'est pas téléchargeable sur le dépôt public, et l'API ne sert ses données qu'aux porteurs d'une clé.

| Table | Grain |
|---|---|
| `registered_fertilizers` | un produit : type, teneurs, article Ekylibre correspondant, marchands qui le proposent |
| `registered_fertilizer_price_readings` | une offre vue un jour, chez un marchand, pour un lieu de livraison |
| `registered_fertilizer_monthly_prices` | un produit, un conditionnement, un mois |
| `registered_fertilizer_unit_values` | un élément fertilisant, un mois |

## Sources

| Marchand | Ce que c'est | Prix |
|---|---|---|
| [Cereapro](https://appro-cereapro.com/catalogue) | Groupement d'achats | Prix **négociés** (`negotiated`), rendus ferme, par période de livraison |
| [Germineo](https://www.germineo.com/fertilisants-2) | Boutique en ligne | Prix publics, transport inclus, pour le conditionnement mis en avant |

Ni l'un ni l'autre n'affiche de prix sans lieu de livraison. Agryco, qu'utilise Itinera, refuse les collectes
automatiques : il n'est pas collecté.

Tous les prix sont **hors taxes**, en euros par tonne (`ton`), par litre ou par kilo selon `unit`.

## Lieux de livraison

Un prix marchand est un prix livré quelque part. Cinq lieux, les mêmes chaque semaine
(`data/fertilizers/delivery_places.csv`) :

| Code postal | Commune | Zone |
|---|---|---|
| 17250 | Saint-Porchaire | Sud-Ouest |
| 28000 | Chartres | Centre |
| 35000 | Rennes | Ouest |
| 51000 | Châlons-en-Champagne | Nord-Est |
| 26000 | Valence | Sud-Est |

Changer un lieu rompt la série : le dire dans le message de commit et dans cette page.

## Qu'est-ce qu'un produit

Le même engrais porte des noms différents d'un marchand à l'autre. `Datasources::Fertilizers::Catalog` le
ramène à un produit, dans cet ordre :

1. **Engrais simple connu par son nom** : `data/fertilizers/simple_fertilizers.csv` (ammonitrate 33,5, urée 46,
   chlorure de potasse 60…). Un grade soufré n'est pas l'engrais dont il porte le nom : « Ammonitrate soufré 27 »
   n'est pas l'ammonitrate 27.
2. **Engrais minéral connu par sa formule** : `npk-15-15-15-s16` pour 15-15-15 + 16 SO3. La formule vient des
   teneurs données par le marchand, ou du nom quand il en est une (« 00.18.18+16so3 »).
3. **Le reste** (organiques, amendements, foliaires, spécialités) reste un produit de son marchand :
   `germineo-3569`, `cereapro-magnesia-kainit`. Il a ses prix, mais n'est pas rapproché d'un autre marchand.

`variant_reference_name` désigne l'article de `variants` qui a la même formule.

Les teneurs sont celles de l'étiquette : N, P2O5, K2O, SO3, MgO, CaO, en pourcentage.

## Prix mensuel

Pour un produit, un conditionnement et un mois (`Datasources::Fertilizers::Pricing`) :

1. Les offres à livrer dans plus de 90 jours sont écartées : ce sont les prix d'une autre saison.
2. Le marchand retenu est le premier de la priorité : Germineo, puis Cereapro. Un prix négocié n'est donc retenu
   qu'en l'absence de prix public, et `negotiated` le dit.
3. Le prix est la moyenne des relevés de ce marchand dans le mois, tous lieux confondus. `observations` en donne
   le nombre, `last_observed_on` la date du dernier.

Un mois sans relevé n'a pas de ligne : le dernier prix connu est celui du dernier mois présent.

Pour un prix par lieu, ou une autre règle, repartir de `registered_fertilizer_price_readings`.

## Valeur des unités

| Élément | Tiré de | Calcul |
|---|---|---|
| `N` | Ammonitrate 33,5 | prix de la tonne / 335 |
| `P2O5` | Superphosphate triple 45 | prix de la tonne / 450 |
| `K2O` | Chlorure de potasse 60 | prix de la tonne / 600 |
| `SO3` | Sulfate d'ammoniaque (21 N, 60 SO3) | (prix de la tonne − 210 × valeur de N) / 600 |

En euros par kilo d'élément, sur le prix en vrac, à défaut en big-bag de 600 kg. La ligne nomme le produit, le
conditionnement, le prix et le marchand utilisés.

Prix estimé d'une formule : 10 × (N × valeur de N + P2O5 × valeur de P2O5 + K2O × valeur de K2O + SO3 × valeur
de SO3) euros par tonne. Au 2026-10-07, sur les treize formules binaires et ternaires relevées en vrac,
l'estimation est à moins de 13 % du prix relevé.

L'azote de l'ammonitrate est plus cher que celui de l'urée : la valeur de N dépend de l'engrais de référence.

## Collecte

Chaque semaine :

```sh
./lexicon run fertilizers && ./lexicon check fertilizers \
  && ./lexicon package fertilizers && ./lexicon publish fertilizers
./lexicon status                          # attendre « in service »
./lexicon publish fertilizers --production
```

- Une requête par seconde au plus, environ 70 pages, sous l'identité `Lexicon OSFarm`.
- Les pages sont gardées dans `raw/fertilizers/<date>/` (une trentaine de Mo par semaine).
- **Les relevés s'additionnent** : chaque construction relit les pages gardées et les relevés du dernier package
  local (`out/packages/fertilizers/`). Tant que l'un des deux existe, l'historique est conservé.
- Un marchand qui donne moins de 100 offres chiffrées est écarté pour la semaine, avec un message ; si les deux
  le sont, la construction s'arrête et les tables publiées ne changent pas.
- Un prix nul, égal à 999,99 (le prix affiché sans lieu de livraison) ou hors de 20 à 5 000 € la tonne est écarté.

## Limites connues

- Germineo : seul le conditionnement mis en avant dans la liste est relevé, pas les autres.
- Les organiques, amendements et foliaires ne sont pas rapprochés entre marchands.
- Pas d'alerte quand un prix varie fortement d'une semaine à l'autre.
