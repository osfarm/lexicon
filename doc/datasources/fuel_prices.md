# `fuel_prices` — prix du gazole non routier (GNR)

Prix moyens nationaux relevés chaque vendredi par la DGEC (ministère de la Transition écologique) et
publiés chaque lundi, sous [Licence Ouverte 2.0](https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf).
Source : classeur « Prix HTT et TTC depuis janvier 2020 » de la page
<https://www.ecologie.gouv.fr/politiques-publiques/prix-produits-petroliers>, feuille « Carburants non
routiers ». Champ : France métropolitaine hors Corse, livraisons de moins de 5 000 litres.

| Table | Grain |
|---|---|
| `registered_fuel_prices` | un relevé par produit et par vendredi, depuis le 2020-01-03 |
| `registered_fuel_monthly_prices` | la moyenne des relevés par produit et par mois |

Seul le produit `non_road_diesel` est chargé. Le classeur contient aussi les carburants routiers et le
fioul domestique : la colonne `product` permet de les ajouter sans changer les tables.

## Les trois prix

| Colonne | Ce que c'est | D'où il vient |
|---|---|---|
| `price_excluding_taxes` | hors toutes taxes | source |
| `price_including_taxes` | toutes taxes comprises | source |
| `price_excluding_vat` | hors TVA, TICPE comprise | calculé : TTC / 1,20 |

Pour chiffrer une intervention agricole, c'est le prix hors TVA qui compte : la TVA est récupérée, la
TICPE ne l'est pas. Le taux de 20 % est celui de la métropole (`Readings::VAT_RATE`).

Prix en euros par litre.

## Le mois en cours

Il figure dans `registered_fuel_monthly_prices` avec les relevés déjà parus : `observations` et
`last_observed_on` disent qu'il est partiel. Sa moyenne change jusqu'au dernier vendredi du mois.

## Collecte

Chaque semaine, le lundi après-midi :

```sh
./lexicon run fuel_prices && ./lexicon check fuel_prices \
  && ./lexicon package fuel_prices && ./lexicon publish fuel_prices
./lexicon status                          # attendre « in service »
./lexicon publish fuel_prices --production
```

`collect` lit dans la page du ministère l'adresse du classeur, dont le nom change, et le garde dans
`raw/fuel_prices/prices_<date>.xlsx`. Si rien n'a changé depuis le dernier package, `package` n'écrit pas
de version.

## Ce qui arrête la construction

`load` vérifie la feuille avant de charger quoi que ce soit ; les tables publiées ne sont pas touchées
quand il refuse.

| Contrôle | Seuil |
|---|---|
| En-têtes | les libellés attendus en lignes 1 et 2 |
| Nombre de relevés | au moins 350 |
| Ordre et jour | dates croissantes, toutes des vendredis |
| Fraîcheur | dernier relevé de moins de 21 jours |
| Prix | hors toutes taxes entre 0,20 et 3,00 €/L, TTC supérieur |
| Moyennes | à 0,005 €/L de celles que la DGEC publie dans la même feuille, pour les mois terminés |

Le message nomme chaque contrôle en défaut. Le classeur fautif reste dans `raw/fuel_prices/`.
