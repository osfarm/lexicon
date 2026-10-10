# hydrography

Despite its name, this datasource carries most of what Lexicon takes from the BD TOPO of the IGN: water,
buildings, hedges, vegetation, sensitive sites, protected areas and power lines. It keeps the name its
package and the flavors know it by.

Source: <https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BD-TOPO>, Open Licence. The IGN
publishes an edition every quarter (15 March, June, September, December).

## Getting the files

Nothing is downloaded by `collect`: it only checks that the files are there.

1. Download `BDTOPO_3-5_TOUSTHEMES_GPKG_LAMB93_FXX_<date>.7z.001` and the following parts (about 25 GB)
   into `raw/hydrography/`. `FXX` is metropolitan France; overseas departments are not loaded.
2. Extract the layers the datasource reads (67 GB out of 144), flat, with the `7z` of the runner:

```bash
docker compose -f docker-compose-dev.yml exec -T -u "$(id -u):$(id -g)" lexicon_runner sh -c '
  cd raw/hydrography && 7z e -y BDTOPO_3-5_TOUSTHEMES_GPKG_LAMB93_FXX_<date>.7z.001 \
    -ir!surface_hydrographique.gpkg -ir!detail_hydrographique.gpkg -ir!troncon_hydrographique.gpkg \
    -ir!cours_d_eau.gpkg -ir!plan_d_eau.gpkg -ir!batiment.gpkg -ir!pylone.gpkg -ir!haie.gpkg \
    -ir!zone_de_vegetation.gpkg -ir!zone_d_activite_ou_d_interet.gpkg -ir!parc_ou_reserve.gpkg \
    -ir!foret_publique.gpkg -ir!ligne_electrique.gpkg'
```

3. Set `LAST_UPDATED` in `lib/datasources/hydrography.rb` to the date of the edition, then
   `./lexicon run hydrography`.

The archive holds one GeoPackage per layer, in one directory per theme. `LAYERS` names the layers and, for
each, the columns that are loaded: the others are left in the file.

## What is kept

### `registered_hydrographic_items`

Stretches of watercourse (`lines`), water surfaces (`shape`) and details such as springs (`point`), with the
`nature` the IGN gives. Only objects in service are kept.

| Column | From | Meaning |
|---|---|---|
| `permanent` | `persistance`, `caractere_permanent` | true when water is there all year, false when intermittent, dry or ephemeral, empty when unknown |
| `persistence` | `persistance` | the value of the IGN: Permanent, Intermittent, Sec, Ephémère, Inconnue |
| `ditch` | `fosse` | a ditch, not a watercourse (not legally binding, says the IGN) |
| `width_class` | `classe_de_largeur` | width at bankfull: « Entre 0 et 5 m », « Entre 5 et 15 m »… |
| `water_police` | `inventaire_police_de_l_eau` | « Inscrit », « Non inscrit », « Expertise en cours », empty when the inventory says nothing (two stretches out of three) |
| `underground` | `position_par_rapport_au_sol` | true below ground level |

`water_police = 'Inscrit'` is the closest thing to a legal answer the data gives: the stretch is a
watercourse for the water police. An empty value does not mean it is not one.

### `registered_cadastral_buildings`

The name is historical: these are the buildings of the BD TOPO, not of the cadastre.

| Column | From | Meaning |
|---|---|---|
| `nature` | `usage_1` | main use: Résidentiel, Agricole, Annexe, Indifférencié… |
| `secondary_nature` | `usage_2` | second use of a mixed building |
| `kind` | `nature` | architecture: Serre, Silo, Industriel, agricole ou commercial… |
| `dwellings_count` | `nombre_de_logements` | from the land files; a dwelling whatever the use says |
| `height` | `hauteur` | metres |
| `light` | `construction_legere` | light structure without foundations |
| `state` | `etat_de_l_objet` | En service, En construction, En ruine, En projet |

### `registered_area_items`

| `nature` | Layer | Geometry | `kind` |
|---|---|---|---|
| `edge` | `haie` | lines, with `height` and `width` in metres | |
| `green_zone` | `zone_de_vegetation` | areas | Bois, Vigne, Verger, Haie… (also in `name`) |
| `electric_pole` | `pylone` | points | |
| `sensitive_site` | `zone_d_activite_ou_d_interet` | areas | Ecole maternelle, Collège, Maison de retraite… |
| `protected_area` | `parc_ou_reserve` | areas | Réserve naturelle, Parc naturel régional… |
| `public_forest` | `foret_publique` | areas | Forêt domaniale, Autre forêt publique |
| `power_line` | `ligne_electrique` | lines | the voltage: 63 kV, 225 kV, 400 kV… |

Sensitive sites are the natures listed in `SENSITIVE_NATURES`: places where vulnerable people stay, near
which plant protection treatments are restricted. Day nurseries are barely there (about 200), and playgrounds
not at all. Half of these areas are « fictive »: a small shape around a point, not the real grounds.

Natura 2000 sites of `parc_ou_reserve` are left out: `protected_natural_zones` has them.

The layer `erp` (establishments open to the public) was looked at and left aside: its activities are free
text and almost none is validated by the IGN.

## Geometry

Each object keeps its whole geometry. Until the edition of September 2026 the parts of a geometry were
dumped under one id and only the first was kept.
