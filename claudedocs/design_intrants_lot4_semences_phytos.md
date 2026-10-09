# Conception — Lot 4 : espèces et prix des semences, prix des phytos

Conception et implémentation du 2026-10-07. Besoins : `claudedocs/brainstorm_intrants.md` (F3, F5 à F7, F13 à
F18, D6, D9, D10). En service en local ; la production reste à faire.

## 0. Ce que l'étude des sources a montré

| Source | Constat |
|---|---|
| Cereapro | La page déjà collectée pour les engrais contient aussi 18 offres de phytos et 10 de semences par lieu. Les phytos y sont vendus sous les noms du groupement, avec les produits dont ils tiennent lieu et leurs matières actives, sans numéro d'AMM |
| Germineo, phytos | Liste vide sans compte professionnel : non collecté |
| Germineo, semences | Sept catégories, environ 460 produits, prix au kilo, au quintal ou à la dose ; l'espèce et la variété sont dans le nom |
| La Récolte, Agrileader | Boutiques PrestaShop, lisibles, prix affichés sans lieu |
| Semence Biologique | Boutique WooCommerce, lisible |
| Agrilisa | Site lisible, prix affichés |

## 1. Décisions

| # | Sujet | Décision |
|---|---|---|
| C1 | Découpage | Deux datasources : `seeds` et `phytosanitary_prices`, réservées aux adhérents comme `fertilizers` |
| C2 | Lecteurs | Ceux de `fertilizers`, réutilisés ; la page de Cereapro du jour est reprise, pas redemandée |
| C3 | Espèces (D6) | Table écrite à la main, `data/seeds/species.csv`, liée à la taxonomie. AGROVOC n'a pas été nécessaire |
| C4 | Espèce d'une offre | Lue au début du nom, par des motifs ordonnés du plus précis au plus général |
| C5 | Prix d'une espèce | Médiane mensuelle des prix au kilo, bio et non bio séparés ; mélanges et doses exclus |
| C6 | Lieu | Un seul pour les semences (17250) ; les cinq pour les phytos, puisque les pages sont déjà là |
| C7 | Phytos | Rattachement à l'AMM par les noms : celui de l'offre, puis ceux des produits dont elle tient lieu |
| C8 | Périmètre de ce lot | Germineo et Cereapro. Les quatre autres semenciers demandent chacun un lecteur : lot 4 bis |

### Pourquoi une médiane par espèce plutôt qu'un prix par variété (C5)

Le besoin (F6) parle de prix par variété ; l'usage (estimer un coût de semis) se fait à l'espèce. Une variété
n'est vendue que par un marchand ou deux, souvent pour une saison : sa série serait pleine de trous. Les relevés
gardent la variété ; le prix mensuel est à l'espèce.

## 2. Mesures (2026-10-07)

| Mesure | Valeur |
|---|---|
| Espèces | 53, dont 47 liées à un taxon et 45 avec une dose de semis |
| Offres de semences | 586 : 68 mélanges, 497 avec espèce, 21 sans |
| Offres avec prix au kilo | 416 ; les autres sont à la dose |
| Prix mensuels de semences | 79, pour 49 espèces |
| Relevés phytos | 85, pour 17 produits, dont 16 rattachés à un numéro d'AMM |

## 3. Écarts au besoin

| Besoin | État |
|---|---|
| F3, prix des phytos | Couvert pour 16 produits sur 1 761 autorisés : une seule source, qui vend peu de références |
| F5, espèces | Fait ; les doses de semis sont indicatives et à faire relire |
| F6, rattachement au catalogue officiel des variétés | Pas fait : la variété est lue, pas rattachée |
| F7, bio distingué | Fait |
| D10, toutes les espèces | 53 espèces ; celles qu'aucun des deux marchands ne vend manquent |
| Six marchands de semences | Deux sur six |

## 4. Suite proposée (lot 4 bis)

1. Lecteurs pour Agrileader et La Récolte (même plateforme, un lecteur commun probable), Semence Biologique,
   Agrilisa.
2. Rattachement des variétés à `registered_seed_varieties`.
3. Conversion des doses (maïs, tournesol) en prix par hectare, avec la densité de semis.
4. Une seconde source de prix phytos, sans laquelle F3 reste symbolique.

## 5. Lot 4 bis (2026-10-07)

| Marchand | Fait | Constat |
|---|---|---|
| Semence Biologique | Lecteur écrit | La boutique expose la liste de ses produits en données ; prix hors taxes au sac, ramené au kilo quand un seul sac est à la commande. 98 offres, toutes bio |
| Agrilisa | Lecteur écrit | Le prix au kilo est affiché dans les listes. 35 offres, dont 12 bio |
| Agrileader | Écarté | La plupart des semences sont « sur devis » : pas de prix à relever |
| La Récolte | Reporté | Prix au sac sans poids du sac dans les listes : 125 fiches à ouvrir chaque semaine. À décider |
| Rattachement des variétés | Bloqué | `seed_varieties` demande un fichier `gnis.csv` déposé à la main ; il n'est pas sur ce poste, et `taxonomy` ne se construit pas sans `translations` |

Après ajout : 719 offres, 606 avec espèce, 79 mélanges ; 89 prix mensuels pour 51 espèces. Le bio est maintenant
relevé chez trois marchands. Version `2026.10.07.2`, en service en local.

### Suite du 2026-10-07 : La Récolte et les variétés

| Sujet | Fait |
|---|---|
| La Récolte | Lecteur écrit : trois listes par semaine, et la fiche de chaque produit lue une seule fois pour le poids du sac. 119 offres, dont 36 mélanges. Les gazons, prestations et journées techniques de la catégorie sont écartés |
| Variétés | `gnis.csv` déposé ; `translations`, `taxonomy` et `seed_varieties` construits dans la base de build. Les offres portent `variety_id` : même nom dans l'espèce, à défaut seule variété dont le nom se termine par lui. 406 offres rattachées sur 604 |
| Schéma | `registered_seed_price_readings` gagne `variety_id` : `schema_revision 2`, `depends_on :seed_varieties`. Pas de clé étrangère : le `seed_varieties` en service en production date d'un fichier plus ancien et n'a pas toutes les variétés |

Version `2026.10.07.3` : 838 offres chez cinq marchands, 679 avec espèce, 115 mélanges ; 89 prix mensuels pour
51 espèces.

Restent ouverts : `seed_varieties` à republier avec le nouveau fichier et sa table d'espèces à compléter ; la
conversion des doses de maïs et de tournesol ; une seconde source de prix pour les phytos.

### Suite du 2026-10-07 : `seed_varieties` complété

Le fichier SEMAE déposé compte 21 605 variétés ; `seed_varieties` en écartait 1 420, faute de leur espèce dans
`data/seed_varieties/seed_varieties - seed_species.csv`.

| Sujet | Fait |
|---|---|
| Table des espèces | 37 espèces ajoutées, chacune rattachée à un taxon existant, au niveau du genre quand l'espèce n'est pas dans la taxonomie (fétuques sur `festuca`, sorghos sur `sorghum`, trèfles secondaires sur `trifolium`) |
| Résultat | 21 367 variétés pour 105 taxons, contre 20 479 pour 86 dans la version en service. Par rapport à elle : 1 660 variétés en plus, 772 en moins (radiées depuis) |
| Date de la source | Tirée des données : la dernière date d'inscription, les dates à venir (fautes de saisie du fichier, jusqu'en 2102) étant ignorées. 2026-08-23 |
| Restent écartées | 238 variétés de 15 espèces sans taxon : moutarde blanche (136) et brune (25), agrostides (44), mélanges pour gazon (11), fromental, avoine jaunâtre, vulpin, carthame, canche, koelérie, sainfoin d'Espagne, chrysanthème |
| `seeds` | Rattachement des variétés porté à 464 offres sur 604. Version `2026.10.07.4` |

Pour les 238 restantes, il faut ajouter des taxons à `taxonomy` (`sinapis_alba`, `brassica_juncea`, `agrostis`…),
ce qui touche un jeu dont beaucoup d'autres dépendent : à décider.

### Suite du 2026-10-07 : taxons ajoutés

| Jeu | Changement |
|---|---|
| `taxonomy` | 21 taxons ajoutés à `data/taxonomy/taxonomy - taxonomy.csv`, avec leurs noms français et anglais : les genres `agrostis`, `alopecurus`, `arrhenatherum`, `carthamus`, `chrysanthemum`, `deschampsia`, `hedysarum`, `koeleria`, `sinapis`, `trisetum`, et les espèces `agrostis_capillaris`, `agrostis_gigantea`, `agrostis_stolonifera`, `alopecurus_pratensis`, `arrhenatherum_elatius`, `brassica_juncea`, `carthamus_tinctorius`, `deschampsia_cespitosa`, `hedysarum_coronarium`, `sinapis_alba`, `trisetum_flavescens`. 922 taxons |
| `seed_varieties` | 13 espèces de plus dans sa table : 21 592 variétés pour 118 taxons. Restent écartées 13 lignes qui ne sont pas des espèces (« M.D. GAZON », « FOURRAGERES AUTRES ESPECES ») |
| `seeds` | La moutarde et le fromental sont liés à leur taxon : 49 espèces liées sur 53, 477 offres rattachées à une variété |

En service en local : `taxonomy` `2026.10.07.1`, `seed_varieties` `2026.10.07.2`, `seeds` `2026.10.07.6`. Le loader
signale `industry_sector`, `productions`, `rd_agri` et `variants` comme périmés : ils ont été construits contre la
taxonomie précédente. Rien ne leur est retiré, seuls des taxons s'ajoutent.

Les noms anglais et français des 21 taxons sont de ma main, à relire. Les 37 espèces rattachées au genre lors de
l'étape précédente (fétuques, sorghos, trèfles secondaires…) pourraient recevoir de même leur taxon d'espèce.
