# `phytosanitary_substances` — matières actives, EIQ et HRAC

Les matières actives des produits d'E-Phy, avec ce que deux listes de référence en disent : l'indicateur de
risque EIQ de l'université Cornell, et le mode d'action des herbicides du HRAC. Ce jeu se pose à côté de
`phytosanitary`, dont les tables ne changent pas.

| Table | Grain |
|---|---|
| `registered_phytosanitary_substances` | une matière active |
| `registered_phytosanitary_product_substances` | une matière active dans un produit, avec sa teneur |

`product_id` est le numéro d'AMM : il se joint à `registered_phytosanitary_products.id`.

## Sources

| Source | Ce qu'on en tire | Fichier |
|---|---|---|
| E-Phy (Anses), Licence Ouverte 2.0 | Nom, numéro CAS, état d'approbation, noms français ; composition des produits | `substance_active_utf8.csv`, `produits_utf8.csv` |
| [EIQ Pesticide Values](https://cals.cornell.edu/integrated-pest-management/risk-assessment/eiq/eiq-pesticide-values), Cornell University | EIQ et ses trois composantes | classeur partagé sur Box |
| [HRAC Global Herbicide MoA Classification](https://hracglobal.com/tools) | Groupe, ancien groupe, mode d'action, famille chimique | « Master List » de l'année |

Les deux listes ne portent pas de licence ouverte nommée : la datasource le dit (`licence_exception`) et
`./lexicon check` le rappelle en avertissement. Citer Cornell University et le HRAC à chaque réutilisation.

## L'EIQ

`eiq` est le quotient d'impact environnemental de la matière active ; `eiq_farm_worker`, `eiq_consumer` et
`eiq_ecological` en sont les trois composantes, dont il est la moyenne. `eiq_incomplete` est vrai quand
Cornell a comblé une donnée manquante par une valeur moyenne.

C'est une valeur **par matière active**. L'impact d'un traitement (« field use EIQ ») se calcule avec la
teneur du produit et la dose appliquée : Lexicon fournit les termes, pas le calcul.

## Comment une substance est rapprochée

`eiq_match` et `hrac_match` disent comment la ligne de la liste a été trouvée ; `eiq_source_name` et
`hrac_source_name` donnent le nom qu'elle porte dans la liste.

| Valeur | Sens | EIQ | HRAC |
|---|---|:---:|:---:|
| `cas` | même numéro CAS | oui | la liste n'en a pas |
| `name` | même nom, casse, ponctuation et précisions entre parenthèses mises à part | oui | oui |
| `isomer` | même nom une fois retirée la marque d'isomère (`Mecoprop-P` et `Mecoprop`) | non | oui |
| `form` | l'un nomme l'acide, l'autre un de ses sels ou esters (`Mesosulfuron` et `Mesosulfuron-methyl`) | non | oui |
| `alias` | ligne de `data/phytosanitary_substances/aliases.csv` | oui | oui |

Un mode d'action appartient à l'acide, quel que soit son sel, son ester ou son isomère : la règle s'applique
d'elle-même au HRAC. Une toxicité, non : pour l'EIQ, une autre forme n'est acceptée que si une ligne du
fichier d'alias le dit, avec sa raison. `Zinc` ne reçoit donc pas l'EIQ de `zinc phosphide`.

Pour ne garder que les rapprochements exacts : `WHERE eiq_match IN ('cas', 'name')`.

Une substance sans EIQ n'est pas une substance sans risque : la liste de Cornell ne couvre ni les
micro-organismes, ni les phéromones, ni la plupart des huiles et substances de base.

Le groupe HRAC `0` est celui des modes d'action inconnus.

## Ajouter un alias

Une ligne dans `data/phytosanitary_substances/aliases.csv` : la liste (`eiq` ou `hrac`), le nom d'E-Phy, le
nom dans la liste, et la raison. La raison est lue par celui qui relira la ligne : elle dit pourquoi les deux
noms désignent la même chose pour ce que la liste mesure.

## Collecte

```sh
./lexicon run phytosanitary_substances && ./lexicon check phytosanitary_substances \
  && ./lexicon package phytosanitary_substances && ./lexicon publish phytosanitary_substances
```

`collect` range les trois fichiers dans `raw/phytosanitary_substances/` sous la date du jour
(`ephy_<date>.zip`, `eiq_<date>.xlsx`, `hrac_<date>.xlsx`). Un fichier déjà là n'est pas retéléchargé : si
Cornell ou le HRAC changent leur site, déposer le classeur à la main sous ce nom.

`load` refuse des fichiers trop courts (moins de 1 000 substances, 10 000 produits, 500 lignes EIQ, 300 lignes
HRAC) ou un rapprochement effondré (moins de 350 substances avec EIQ, 200 avec HRAC), avant de toucher aux
tables publiées.
