# quality_and_origin_signs

Quality and origin signs tied to a place: AOC/AOP, IGP and IG. For each geographical area, its products, the
communes it covers and, for wines under AOC, the zones delimited inside the communes.

Source: the INAO, on data.gouv.fr, under the Licence Ouverte. **What the INAO publishes is for information**:
the specification of a product alone says where it may be made. Label Rouge and STG are in the table of
products and have no area.

## Building it

```bash
./lexicon run postal_codes   # once: the communes of today
./lexicon run quality_and_origin_signs
```

- `collect` downloads the latest file of four datasets (products of each area, communes of the AOC/AOP areas,
  communes of the IGP and IG areas, register of products), the movements of communes of the INSEE, and the
  delimitation of the AOC (270 MB) when the INAO dated it anew.
- `load` reads the two lists of communes (Windows-1252, semicolons) and refuses them under 300 000 lines.
- `normalize` takes about forty seconds.

## Tables

| Table | One line per | Lines |
|---|---|---|
| `registered_quality_and_origin_signs` | product (unchanged; `ida` is its area) | 5 255 |
| `registered_quality_and_origin_sign_areas` | geographical area | 1 853 |
| `registered_quality_and_origin_sign_communes` | area and commune (pivot `commune`) | 364 789 |
| `registered_quality_and_origin_sign_zones` | denomination and commune, with its outline | 11 751 |

### Areas

`sign` is `AOC`, `IGP` or `IG` for an area that covers communes; `family` gathers areas the way a commune is
told about: `wine`, `spirits`, `cheese`, `meat`, `fruits_and_vegetables`, `seafood`, `other`. The family is the
one most of the products of the area belong to in the register of the INAO. A fifth of the products are not in
that register: their area is then a spirit when its sign is IG, a wine when its products are named by a colour,
`other` otherwise (Saint-Nectaire is there).

### Communes that are gone

The lists name 36 239 communes, 1 300 more than exist: they were written when the specifications were, and
communes merged since. `collect` downloads the movements of communes of the INSEE (`MOVEMENTS_URL`, the file
of 2025; a newer one dropped as `raw/quality_and_origin_signs/movements.csv` is read instead), and `normalize`
gives an area to the commune of today that absorbed a listed one. `partial` then says the commune has the area
through former communes only, named in `former_communes`: the area may cover a part of it. Twelve codes lead
nowhere and are left out.

The lists are dated October 2025 and the INAO publishes them « ponctuellement »: a specification changed since
is not there.

### Zones

The INAO draws, for wines under AOC, what is delimited inside each commune: 356 appellations in 3 658
communes, 600 MB of outlines. It says the work is not finished: a point outside every zone is not a point
outside every appellation. `complementary` tells a geographical denomination inside an appellation.

The other shapefile of the INAO, the areas themselves (one outline per denomination), is not read: it carries
no commune, and the lists say which communes an area covers.

## Left aside

- The areas and zones of immediate proximity (where a wine may be made outside its area).
- The rum of Martinique, published apart in 2020.
