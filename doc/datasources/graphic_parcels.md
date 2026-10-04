# Datasource `graphic_parcels` — Registre parcellaire graphique (RPG)

Les parcelles déclarées à la PAC en France métropolitaine, avec leur culture,
campagne par campagne. Source : IGN / ASP / MASA, Licence Ouverte 2.0.

## Tables produites

| Table | Contenu |
|---|---|
| `registered_graphic_parcels` | La dernière campagne (2025) : identifiant, `campaign`, code culture PAC, commune, forme, centroïde |
| `registered_graphic_parcels_history` | Les campagnes précédentes (2022 à 2024) : `campaign`, identifiant, code culture PAC, forme, centroïde |

La table courante garde la forme qu'elle avait avant l'historique, plus la
colonne `campaign` : qui la lisait déjà n'a rien à changer.

Deux choses à savoir sur l'historique :

- **Une parcelle n'a pas d'identité d'une campagne à l'autre.** Les
  identifiants (`id`) sont redistribués chaque année : `19` en 2022 et `19` en
  2023 ne sont pas la même parcelle. Le lien entre campagnes se fait par le
  lieu : « qu'est-ce qui était déclaré en ce point ? ».
- Une parcelle faite de plusieurs morceaux donne autant de lignes, avec le
  même identifiant.

Le libellé d'un code culture change avec les années : il se lit dans
`master_crop_production_cap_codes` pour l'année de la campagne.

## Fichiers attendus

Les GeoPackages sont déposés à la main dans `raw/graphic_parcels/`, un par
campagne, sous le nom `RPG_Parcelles_<campagne>.gpkg`. Ils viennent de
<https://geoservices.ign.fr/rpg> (France métropolitaine, Lambert-93). Seule
la couche des parcelles sert ; les autres fichiers de la livraison (îlots,
SNA, ZDH…) ne sont pas lus.

| Campagne | Version du RPG | Fichier dans l'archive | Couche | Colonne géométrique |
|---|---|---|---|---|
| 2022 | 2.0 | `PARCELLES_GRAPHIQUES.gpkg` | `parcelles_graphiques` | `the_geom` |
| 2023 | 2.2 | `PARCELLES_GRAPHIQUES.gpkg` | `PARCELLES_GRAPHIQUES` | `geom` |
| 2024 | 3.0 | `RPG_Parcelles.gpkg` | `RPG_Parcelles` | `geom` |
| 2025 | 4.0 | `RPG_Parcelles.gpkg` | `RPG_Parcelles` | `geom` |

Extraire un seul fichier d'une archive, sans tout décompresser :

```sh
7z e -oraw/graphic_parcels RPG_4-0__GPKG_LAMB93_FXX_2025-01-01.7z.001 '*/RPG_Parcelles.gpkg' -r
mv raw/graphic_parcels/RPG_Parcelles.gpkg raw/graphic_parcels/RPG_Parcelles_2025.gpkg
```

## Ajouter une campagne

1. Déposer `RPG_Parcelles_<campagne>.gpkg` dans `raw/graphic_parcels/`.
2. Regarder le nom de la couche et de sa colonne géométrique
   (`ogrinfo -so -al <fichier>`) : ils ont changé à chaque version du RPG.
3. Ajouter la campagne à `CAMPAIGNS` dans `lib/datasources/graphic_parcels.rb`.
   La plus récente devient la campagne courante ; les autres vont dans
   l'historique.
4. Vérifier que `master_crop_production_cap_codes` connaît l'année.
5. `./lexicon run graphic_parcels`, puis `package` et `publish`.

## Volumes et durées

Environ 9,7 millions de parcelles par campagne ; en base, 12 Go pour la
campagne courante et 17 Go pour les trois de l'historique. Mesuré sur le
poste de build pour quatre campagnes : chargement 13 minutes, normalisation
21 minutes, `VACUUM` 1 minute.

## Dans l'API

- `/geographical-references/cap-parcels` : la dernière campagne.
- `/geographical-references/cap-parcels/history?longitude=…&latitude=…` : ce
  qui a été déclaré en un point, campagne par campagne.
- L'identificateur de parcelle (`/tools/parcel-identifier`) montre les
  cultures des campagnes précédentes.
- Outil MCP `get_crop_history`.

Les flavors qui filtrent `registered_graphic_parcels` par un lieu filtrent
l'historique de la même façon.
