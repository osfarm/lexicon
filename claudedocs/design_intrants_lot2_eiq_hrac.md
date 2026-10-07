# Conception — Lot 2 : EIQ et HRAC des matières actives

Conception et implémentation du 2026-10-07. Besoins : `claudedocs/brainstorm_intrants.md` (F1, F2, F4,
NF1, NF7). En service en local ; la production reste à faire.

## 0. Décisions

| # | Sujet | Décision |
|---|---|---|
| C1 | Emplacement | Nouvelle datasource `phytosanitary_substances`, à côté de `phytosanitary` |
| C2 | Grain | La matière active, puis sa présence dans un produit avec sa teneur |
| C3 | Lien aux produits | Par le numéro d'AMM, déclaré comme pivot `amm` ; pas de clé étrangère |
| C4 | Rapprochement | Chaque ligne dit comment elle a été rapprochée. Le HRAC suit l'acide (isomères, sels, esters) ; l'EIQ ne passe à une autre forme que par une ligne d'alias motivée |
| C5 | Licence | Listes sans licence ouverte nommée : `licence_exception`, sur la foi de la vérification d'OSFarm (D5) |
| C6 | Garde-fous | Dans `load`, comme au lot 1 : fichiers trop courts ou rapprochement effondré |

### Pourquoi une datasource à part (C1)

| Option | Pour | Contre |
|---|---|---|
| Colonnes ou tables ajoutées à `phytosanitary` | Un seul jeu | Republier 16 000 produits et leurs usages pour une liste qui change une fois l'an ; `phytosanitary` se construit avec `open_nomenclature`, absent du poste ; risque sur des tables lues par Ekylibre (F4) |
| **Datasource à part** | Cycle propre ; les tables existantes ne bougent pas ; se construit seule à partir des CSV d'E-Phy | Un jeu de plus au catalogue ; le lien aux produits est un pivot, mesuré seulement quand `phytosanitary` est construit |

### Pourquoi l'EIQ ne suit pas la règle du HRAC (C4)

La première version appliquait la même règle de préfixe aux deux listes. Elle donnait à `Zinc` l'EIQ de
`zinc phosphide` et à `Bromophos-ethyl` celui de `bromophos`. Le mode d'action est celui de l'acide ; la
toxicité dépend de la forme. Seize alias écrits à la main couvrent les cas où E-Phy nomme l'acide et la
liste, la forme homologuée (`Fosetyl` et `fosetyl-aluminium`).

## 1. Mesures (2026-10-07)

| Mesure | Valeur |
|---|---|
| Substances | 1 549, dont 624 avec numéro CAS |
| Avec EIQ | 521 : 378 par CAS, 127 par nom, 16 par alias |
| Avec HRAC | 247 : 215 par nom, 27 par forme, 4 par isomère, 1 par alias |
| Liens produit-substance | 22 155, sur 14 049 produits |
| AMM retrouvés dans `registered_phytosanitary_products` (base de service) | 14 039 sur 14 049 |
| Produits autorisés dont toutes les substances ont un EIQ | 1 343 sur 1 679 (80 %) |
| Herbicides autorisés avec un groupe HRAC | 484 sur 517 (94 %) |

Les substances sans EIQ sont surtout des micro-organismes, des phéromones et des huiles, que Cornell ne
couvre pas. Les herbicides sans HRAC sont des phytoprotecteurs, des acides gras, l'acide acétique et le
sulfate de fer.

## 2. À relire par quelqu'un du métier

- Les seize alias EIQ de `data/phytosanitary_substances/aliases.csv`.
- Les rapprochements HRAC par forme et par isomère (31 lignes : `hrac_match IN ('form', 'isomer')`).
- `Mecoprop-P`, `Dichlorprop-P` : pas d'EIQ repris du racémique.

## 3. Hors périmètre

- Calcul de l'EIQ d'un traitement (teneur × dose).
- Routes de l'API et outils MCP (lot 6).
- FRAC et IRAC, les équivalents du HRAC pour les fongicides et les insecticides.
