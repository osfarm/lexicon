# `cadastre_owners` : propriétaires personnes morales

Les locaux et les parcelles non bâties dont un propriétaire est une personne morale (société, commune,
association…), d'après les fichiers MAJIC que la DGFiP publie une fois par an. Réservé aux adhérents
(`scope :members`). Situation en service : **2026**, publiée le 2026-11-03.

| | |
|---|---|
| Source | DGFiP, [Fichiers des locaux et des parcelles des personnes morales](https://www.data.gouv.fr/fr/datasets/fichiers-des-locaux-et-des-parcelles-des-personnes-morales/) (Licence Ouverte 2.0) |
| Rythme | une situation par an, publiée à l'automne |
| Collecte | à la main : `collect` ne télécharge rien, il vérifie que les CSV sont là |
| Descriptif des champs | `Fichier des locaux … - 2026.odt` et `Fichier des parcelles … - 2026 .odt`, à côté de cette fiche |

## Tables

| Table | Contenu | Lignes (situation 2026) |
|---|---|---:|
| `registered_cadastral_owners` | un propriétaire par numéro MAJIC et département : SIREN, dénomination, forme juridique, groupe de personne | 3 050 737 |
| `registered_cadastral_premises` | les locaux, avec leur adresse et leur propriétaire | 22 840 518 |
| `registered_cadastral_parcel_owners` | le lien entre une parcelle du cadastre et chacun de ses propriétaires | 21 412 220 |

`normalize` écrit aussi deux colonnes de `registered_cadastral_parcels`, la table de `cadastre` :
`pm_owners_count` (nombre de propriétaires personnes morales) et `has_enterprise_pm_owner` (un des propriétaires a
un SIREN que `registered_enterprises` connaît). Il les remet d'abord à zéro, pour qu'une parcelle vendue depuis la
situation précédente perde sa marque. En situation 2026 : 17 476 207 parcelles ont un propriétaire personne morale,
15 448 554 un propriétaire connu de SIRENE.

## Changer de situation

1. Télécharger les archives de la nouvelle situation depuis la page data.gouv.fr (un zip de locaux, deux ou trois de
   parcelles, découpés par département), et les descriptifs `.odt` à mettre ici à la place des anciens.
2. Les extraire à plat dans `raw/cadastre_owners/locaux_<année>/` et `raw/cadastre_owners/parcelles_<année>/` :

   ```sh
   unzip -q -j <zip des locaux> -d raw/cadastre_owners/locaux_2026
   for z in <zips des parcelles>; do unzip -q -j "$z" -d raw/cadastre_owners/parcelles_2026; done
   ```

3. Comparer la liste des fichiers avec celle de l'année précédente (un fichier par département,
   `PM_<aa>_B_<dep>0.csv` pour les locaux, `PM_<aa>_NB_<dep>0.csv` pour les parcelles), et l'en-tête d'un fichier
   (`head -1`) : `load` lit les colonnes dans l'ordre, séparées par `;`, en UTF-8.
4. Changer `LOCAUX_DIR`, `PARCELLES_DIR`, `description` et `updated_at` des `credits` dans
   `lib/datasources/cadastre_owners.rb`.
5. Reconstruire, puis ce qui en dépend :

   ```sh
   ./lexicon run cadastre_owners          # 1 h 15 environ, dont 50 min pour les colonnes du cadastre
   ./lexicon run enterprise_links commune_links
   ./lexicon ship cadastre_owners cadastre enterprise_links commune_links --no-build
   ./lexicon publish cadastre cadastre_owners enterprise_links commune_links --production
   ```

   `cadastre` n'est pas reconstruit mais réempaqueté : ses deux colonnes ont changé. Son paquet fait l'essentiel des
   quelque 2 Go envoyés ; la mise en service en production prend un quart d'heure.

## Situation 2026 : l'Orne

La DGFiP a oublié les parcelles de l'Orne : aucune des trois archives de 2026 ne contient `PM_26_NB_610.csv` (les
locaux de l'Orne y sont). `raw/cadastre_owners/parcelles_2026/` contient à sa place `PM_25_NB_610.csv`, de la
situation 2025 (112 952 liens parcelle–propriétaire). Quand la DGFiP publiera le fichier, le mettre à la place et
reconstruire comme ci-dessus.

## Limites

- `has_enterprise_pm_owner` marque toute parcelle dont un propriétaire est une société connue de SIRENE, quelle que
  soit son activité : il ne distingue pas les exploitations agricoles (il faudrait filtrer les codes APE 01 à 03).
- Les propriétaires personnes physiques ne sont pas dans ces fichiers.
- Paris n'a pas de parcelles dans `cadastre` (département 75 absent de `DEPTS`) : ses locaux sont là, ses parcelles
  non.
