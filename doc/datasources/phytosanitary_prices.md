# `phytosanitary_prices` — prix des produits phytosanitaires

Les offres de produits phytosanitaires de Cereapro, un groupement d'achats, relevées chaque semaine pour les cinq
lieux de livraison de `fertilizers`, et le prix mensuel par numéro d'AMM.

**Jeu réservé aux adhérents OSFarm** (`scope :members`). Tous les prix sont **négociés** (`negotiated`) : ce sont
ceux d'un groupement, pas des prix publics.

| Table | Grain |
|---|---|
| `registered_phytosanitary_price_readings` | une offre vue un jour pour un lieu |
| `registered_phytosanitary_monthly_prices` | un numéro d'AMM, une unité, un mois |

`product_id` est le numéro d'AMM : il se joint à `registered_phytosanitary_products.id` et à
`registered_phytosanitary_product_substances.product_id`.

## Une offre n'est pas un produit de marque

Le groupement vend sous ses propres noms et dit de quels produits connus chacun tient lieu : « Katwe » pour
LIBRAX, « Shiva » pour SULTAN. `Datasources::PhytosanitaryPrices::Products` rattache l'offre au premier de ces
noms qu'E-Phy connaît comme autorisé : d'abord le nom de l'offre, puis les produits dont elle tient lieu.

| Colonne | Sens |
|---|---|
| `label` | le nom chez le groupement |
| `stands_for` | les produits dont l'offre tient lieu, selon le groupement |
| `reference_name` | celui de ces noms qui a donné le numéro d'AMM |
| `product_id` | le numéro d'AMM ; vide quand aucun nom n'est connu d'E-Phy |

Le prix est donc celui d'une spécialité équivalente, pas forcément celui du produit de marque : à lire avec
`reference_name` sous les yeux.

Seuls les prix au litre et au kilo sont gardés ; une offre au flacon ou à la dose ne se compare à rien.

## Portée

Au 2026-10-07 : 17 produits offerts, dont 16 rattachés à un numéro d'AMM. C'est peu au regard des 1 761 produits
autorisés. Germineo ne montre pas ses produits phytosanitaires sans compte professionnel ; aucune autre source de
prix n'est branchée.

## Collecte

```sh
./lexicon run phytosanitary_prices && ./lexicon check phytosanitary_prices \
  && ./lexicon package phytosanitary_prices && ./lexicon publish phytosanitary_prices
```

Les pages de Cereapro sont reprises de la collecte de `fertilizers` du même jour quand elles existent : lancer
`fertilizers` d'abord. La liste des produits autorisés d'E-Phy est téléchargée avec chaque collecte et gardée,
pour qu'un relevé passé se relise avec les noms de son époque.
