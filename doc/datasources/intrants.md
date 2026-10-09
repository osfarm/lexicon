# Intrants : vue d'ensemble

Sept jeux décrivent les intrants agricoles et leurs prix. Cette page dit ce que chacun contient, qui peut le
lire, dans quel ordre ils se construisent et ce qu'il faut relancer chaque semaine. Le détail de chacun est dans
sa fiche.

## Les jeux

| Jeu | Contenu | Accès | Source | Rythme | Fiche |
|---|---|---|---|---|---|
| `fuel_prices` | Prix du gazole non routier, par vendredi et par mois | ouvert | DGEC | hebdomadaire | [fuel_prices.md](fuel_prices.md) |
| `phytosanitary_substances` | Matières actives, EIQ, groupe HRAC, composition des produits | ouvert | E-Phy, Cornell, HRAC | à chaque mise à jour des listes | [phytosanitary_substances.md](phytosanitary_substances.md) |
| `fertilizers` | Engrais, relevés de prix, prix mensuel, valeur des unités N, P2O5, K2O, SO3 | adhérents | Cereapro, Germineo | hebdomadaire | [fertilizers.md](fertilizers.md) |
| `seeds` | Espèces, offres de semences, prix médian par espèce | adhérents | Germineo, Cereapro, Semence Biologique, Agrilisa, La Récolte | hebdomadaire | [seeds.md](seeds.md) |
| `phytosanitary_prices` | Offres de produits phytosanitaires rattachées à un numéro d'AMM | adhérents | Cereapro | hebdomadaire | [phytosanitary_prices.md](phytosanitary_prices.md) |
| `prices` | Prix de référence des articles, lus par Ekylibre, et leur provenance | ouvert | les quatre jeux de prix ci-dessus et `data/prices/` | hebdomadaire | [prices.md](prices.md) |
| `seed_varieties` | Catalogue officiel des variétés | ouvert | SEMAE, fichier déposé à la main | à chaque nouveau fichier | [../DATASOURCES.md](../DATASOURCES.md) |

Les jeux réservés le sont parce qu'ils nomment les marchands. `prices`, ouvert, ne reçoit que le prix d'un
article, jamais qui le vend.

## Ce qui dépend de quoi

```
taxonomy ──► seed_varieties ──► seeds ─────────────┐
         └─► variants ─────────────────────────────┤
fuel_prices ───────────────────────────────────────┤
fertilizers ───────────────────────────────────────┼──► prices ──► (Ekylibre, /inputs, get_input_price)
phytosanitary ──► phytosanitary_prices ────────────┘
              └─► phytosanitary_substances
```

- `seeds` et `phytosanitary_prices` reprennent la page de Cereapro collectée le même jour par `fertilizers` :
  lancer `fertilizers` d'abord.
- `seeds` rattache ses variétés à `seed_varieties` pendant `normalize` : il faut que `seed_varieties` soit construit
  sur le poste (`./lexicon run translations taxonomy seed_varieties`).
- `prices` lit les quatre jeux de prix : il se construit en dernier.

## Chaque semaine

Le lundi après-midi, après la publication de la DGEC :

```sh
./lexicon ship fuel_prices fertilizers seeds phytosanitary_prices
./lexicon ship prices
```

puis, une fois vérifié en local :

```sh
./lexicon publish fuel_prices fertilizers seeds phytosanitary_prices prices --production
./lexicon status --production
```

Environ 170 pages sont demandées aux marchands, à une requête par seconde. Les pages sont gardées dans `raw/` :
c'est, avec les packages, la mémoire des relevés.

## Dans l'API

`/inputs` sert ces tables (les réservées, avec une clé d'adhérent), et l'outil MCP `get_input_price` donne le
dernier prix d'un intrant et le coût d'une dose. Voir `ADMINISTRATION.md`, §2.1 bis.

## Limites connues

- Prix des produits phytosanitaires : une seule source, seize produits. Aucun produit au glyphosate n'a de prix.
- Semences vendues à la dose (maïs, tournesol, colza, betterave) : pas de prix au kilo.
- Doses de semis, alias EIQ, noms des taxons ajoutés : renseignés sans relecture d'un agronome.
- La collecte est lancée à la main depuis le poste de build.
