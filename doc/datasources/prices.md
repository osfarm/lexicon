# `prices` — prix de référence des articles

Le prix des articles du référentiel des variantes (engrais, semences, phytos, produits de ferme, matériels) et
les contrats de main-d'œuvre. C'est le jeu que lit Ekylibre pour chiffrer un itinéraire technique. Jeu ouvert.

| Table | Grain |
|---|---|
| `master_prices` | un prix d'un article à une date, pour un conditionnement |
| `master_phytosanitary_prices` | un prix d'un produit phytosanitaire (numéro d'AMM) à une date |
| `master_doer_contracts` | un type de contrat de travail |
| `master_price_sources` | d'où vient chaque prix des deux premières tables |

## D'où viennent les prix

Les fichiers de `data/prices/` donnent un prix de départ à chaque article. À chaque construction, le **dernier**
prix d'un article est remplacé par ce que les jeux relevés chaque semaine en disent :

| Articles | Source | Règle |
|---|---|---|
| Engrais vus chez un marchand | `fertilizers` | dernier prix mensuel, en vrac s'il existe (`observed`) |
| Autres engrais minéraux à la tonne | `fertilizers` | formule × valeur du kilo de N, P2O5, K2O et SO3 du mois (`estimated`) |
| Semences | `seeds` | dernier prix médian au kilo de l'espèce de l'article, ou des espèces de son genre (`observed`) |
| Produits phytosanitaires | `phytosanitary_prices` | dernier prix mensuel du numéro d'AMM ; un produit jamais chiffré est ajouté (`observed`) |
| Gazole non routier | `fuel_prices` | moyenne du mois hors TVA, article `non_road_diesel` (`observed`) |
| Tout le reste | `data/prices/` | inchangé (`reference`) |

Seul le prix d'un article passe ici. Qui le vend, où et à quel prix reste dans les jeux réservés aux adhérents.

Un article peut porter plusieurs prix, un par date : seul le plus récent est remplacé, les autres restent comme
son historique.

Une estimation n'est faite que pour une formule surtout composée de N, P2O5 et K2O (au moins 20 %), sans
magnésium ni calcium, vendue à la tonne : la valeur du magnésium et du calcium n'est pas connue, et une
spécialité vendue au kilo ne vaut pas que ses unités.

Si un jeu source n'est pas construit sur le poste, ses articles gardent leur prix de départ et un message le dit.

## `master_price_sources`

| Colonne | Sens |
|---|---|
| `id` | celui du prix |
| `price_table` | `master_prices` ou `master_phytosanitary_prices` |
| `method` | `observed` (relevé), `estimated` (calculé), `reference` (fichier de `data/prices/`) |
| `source` | le jeu d'où vient le prix |
| `negotiated` | vrai quand le prix relevé est celui d'un groupement d'achats |
| `previous_amount`, `previous_started_on` | le prix et la date remplacés |
| `detail` | conditionnement relevé, espèces prises en compte |

Pour ne garder que les prix relevés : joindre sur `id` et filtrer `method = 'observed'`.

## Itinéraires techniques

Les itinéraires désignent leurs articles par `reference_article_name`. Quand `technical_workflows` est construit
sur le poste, la construction de `prices` liste les articles d'itinéraire sans prix.

Au 2026-10-07, sur les 128 articles d'intrants des itinéraires en service : 6 n'ont pas de prix (les AMM 2120098,
2160818, 2171010, 9700278, 9800244 et `cow_insemination_straw`), comme avant ; 18 ont un prix de 2026 ; les
autres, surtout des produits phytosanitaires, gardent un prix de 2016 à 2021, faute de source.

## Chaque semaine

`prices` se reconstruit après les jeux qu'il lit :

```sh
./lexicon run fuel_prices fertilizers seeds phytosanitary_prices prices
./lexicon check prices && ./lexicon package prices && ./lexicon publish prices
```

Il est signalé périmé par le serveur tant qu'il n'a pas été reconstruit contre les dernières versions de ces jeux.
