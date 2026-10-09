# `seeds` — espèces et prix des semences

Les espèces dont on vend la semence aux exploitations françaises, les offres que des marchands affichent chaque
semaine, et le prix médian au kilo par espèce.

**Jeu réservé aux adhérents OSFarm** (`scope :members`) : les prix nomment les marchands qui les affichent.

| Table | Grain |
|---|---|
| `registered_seed_species` | une espèce : nom latin, famille, catégorie, saison de semis, dose de semis, taxon du Lexicon |
| `registered_seed_price_readings` | une offre vue un jour chez un marchand |
| `registered_seed_monthly_prices` | une espèce, en bio ou non, un mois |

`seed_varieties` (le catalogue officiel des variétés) reste un jeu à part ; `variety_id` y renvoie quand la
variété d'une offre s'y retrouve.

## Les espèces

`data/seeds/species.csv`, écrit à la main : 53 espèces. Ce n'est pas la table d'Itinera ; elle est reconstruite à
partir de ce que vendent les marchands et de la taxonomie du Lexicon (`taxon_reference_name`).

| Colonne | Sens |
|---|---|
| `category` | `cereal`, `maize`, `oilseed`, `protein`, `forage`, `cover` |
| `season` | saison de semis la plus courante : `autumn`, `spring`, `summer` |
| `sowing_rate_min`, `sowing_rate_max` | dose de semis en culture pure, en kg/ha |
| `pattern` | ce qui, au début du nom d'une offre, désigne l'espèce |

**Les doses de semis sont indicatives.** Ce sont des fourchettes usuelles, à faire relire par un agronome ; elles
sont vides quand la semence se compte en grains (maïs, tournesol) ou quand je n'avais pas de valeur sûre.

L'ordre des lignes compte : la première espèce dont le motif correspond l'emporte, donc les noms les plus précis
viennent d'abord (« blé dur » avant « blé », « avoine rude » avant « avoine »).

## Les offres

| Marchand | Lieu de livraison | Ce qui est lu |
|---|---|---|
| [Germineo](https://www.germineo.com/semences-1) | 17250 | sept catégories de semences, le conditionnement mis en avant |
| [Cereapro](https://appro-cereapro.com/catalogue) | 17250 | les offres de semences du groupement (`negotiated`) |
| [Semence Biologique](https://www.semence-biologique.fr) | prix départ | tout le catalogue, par la liste de produits que lit son propre site ; tout y est bio |
| [Agrilisa](https://www.agrilisa.com) | prix départ | vingt-quatre catégories de semences, dont neuf de semences bio ; le prix au kilo est affiché |
| [La Récolte](https://www.larecolte.fr/2293-couverts-vegetaux) | prix départ | couverts et fourragères ; prix au sac dans les listes, poids du sac dans la fiche du produit |

Un seul lieu pour les deux premiers : les semences voyagent en sacs, leur prix dépend peu de la distance. Les
trois autres affichent un prix sans lieu de livraison.

La fiche d'un produit de La Récolte n'est lue qu'une fois, la première fois qu'il apparaît, et gardée dans
`raw/seeds/la_recolte_products/` : seules les listes sont relues chaque semaine.

Semence Biologique vend au sac : le prix au kilo n'est calculé que lorsqu'un seul sac est proposé à la commande.
Agrilisa écrit ses noms en capitales : l'espèce y est lue, pas la variété.

Du nom de l'offre, `Datasources::Seeds::Label` tire :

- l'espèce (`species_id`), vide quand elle n'est pas dans la table ;
- la variété (`variety`), écrite en capitales dans le nom ;
- `organic`, quand le nom porte AB, UAB ou bio ;
- `treated`, faux quand le nom dit « non traité », vide sinon ;
- `mixture`, pour les mélanges, méteils et couverts composés : ni espèce ni variété.

`price_per_kilogram` ramène au kilo les prix au kilo, au quintal et à la tonne. Il est vide pour une semence
vendue à la dose (maïs, tournesol, colza), que rien ne permet de convertir.

## Le rattachement au catalogue officiel

`variety_id` est le numéro de la variété dans `registered_seed_varieties`, cherchée dans l'espèce de l'offre :

1. la variété qui porte exactement le nom lu ;
2. à défaut, la seule dont le nom se termine par lui : les marchands omettent la marque de l'obtenteur que le
   catalogue garde (« ABSALON » pour « LG ABSALON », « CESARIO » pour « RGT CESARIO »).

Le rattachement se fait pendant `normalize` et demande que `seed_varieties` soit construit dans la base de build
(`./lexicon run translations taxonomy seed_varieties`, avec `raw/seed_varieties/gnis.csv`). Sinon la colonne reste
vide et un message le dit.

Au 2026-10-07 : 477 offres rattachées sur 604 qui nomment une variété (86 % pour les céréales, 79 % pour les
fourragères, 75 % pour les couverts). Restent sans rattachement les maïs, vendus sous des noms commerciaux, les
moutardes brunes et d'Abyssinie rangées ici avec la moutarde blanche, et les variétés absentes du catalogue.

## Le prix mensuel

Pour une espèce, en bio ou non : la **médiane** des prix au kilo des offres du mois, toutes variétés confondues,
avec le plus bas, le plus haut et le nombre d'offres. Les mélanges et les semences vendues à la dose n'y entrent pas.

La médiane, et non la moyenne, parce qu'une offre aberrante ne doit pas déplacer le prix : au 2026-10-07, un blé
tendre est affiché 442 € le quintal quand les autres sont autour de 100.

Coût de semis indicatif d'un hectare : prix au kilo × dose de semis.

## Collecte

```sh
./lexicon run seeds && ./lexicon check seeds && ./lexicon package seeds && ./lexicon publish seeds
```

Une soixantaine de pages chez Germineo, vingt-quatre chez Agrilisa, trois appels chez Semence Biologique, trois
listes chez La Récolte (une page toutes les trois secondes, comme son `robots.txt` le demande aux robots), une
requête par seconde ailleurs. La page de Cereapro est reprise de la collecte
de `fertilizers` du même jour quand elle existe : lancer `fertilizers` d'abord. Les relevés s'additionnent comme
pour `fertilizers` (pages gardées dans `raw/seeds/`, relevés du dernier package).

Moins de 100 offres chiffrées le jour de la collecte : la construction s'arrête.

## Limites connues

- **Agrileader**, cité par Itinera, n'est pas lu : la plupart de ses semences sont « sur devis ».
- Au 2026-10-07, 44 offres sur 723 hors mélanges n'ont pas d'espèce : bourrache, chia, teff, et les inoculants
  que Semence Biologique range avec ses semences.
- Si le sac d'un produit de La Récolte change de poids, sa fiche gardée ne le sait pas : supprimer le fichier de
  `raw/seeds/la_recolte_products/` pour qu'elle soit relue.
- Les prix à la dose ne sont pas convertis.
