# organic_farming

Organic farming year by year since 2008: operators, farms, areas and livestock, by commune and by
intercommunality (EPCI). From the yearly inspections of the certification bodies.

Source: the Agence Bio, every year, under the Licence Ouverte 2.0:
<https://www.data.gouv.fr/datasets/historique-detaille-des-surfaces-cheptels-et-nombre-doperateurs-par-commune>
and the same « par EPCI ».

## Two things to know before reading a figure

1. **Statistical secrecy.** Areas and livestock of fewer than three farms are kept secret: the number of farms
   is given, the figure is not, and `masked` is true. In 2025 that is 62 % of the communes with a farm (those
   that can be read hold 1.83 million hectares) and 95 % of the lines of livestock. The intercommunality gives
   the order of magnitude: 4 % of its areas are secret, and it holds 2.61 million hectares.
2. **The seat, not the land.** Every parcel of a farm is counted in the commune of its seat, wherever it lies.
   The table says what the farms seated in a commune farm organic, not what is organic on its land.

Operators are never secret.

## Building it

```bash
./lexicon run organic_farming
```

`collect` downloads five files (280 MB) when the source dated them anew. The whole run takes fifteen seconds.

## Tables

| Table | One line per | Lines |
|---|---|---|
| `registered_organic_operators` | commune, year, kind, main production and activities | 742 835 |
| `registered_organic_areas` | commune and year | 252 746 |
| `registered_organic_livestock` | commune, year and production | 244 035 |
| `registered_organic_epci_areas` | intercommunality and year | 21 996 |
| `registered_organic_epci_livestock` | intercommunality, year and production | 101 429 |
| `registered_organic_communes` | commune: its intercommunality, first and last year | 25 352 |

- `kind` of an operator: `P` producer, `T` processor or restaurant, `D` distributor, `I` importer.
- Areas in hectares: `certified_area`, `first_year_conversion_area`, `second_…`, `third_…`, `conversion_area`,
  `organic_area` (certified and in conversion).
- Livestock in heads, or hives: `certified_heads`, `conversion_heads`, `organic_heads`.
- A place written twice in a year, under two names, is one line: its farms are added, its figures too unless
  one is secret.

### Livestock of intercommunalities

The source masks the livestock of fewer than three farms in a commune, and publishes it whole for an
intercommunality, down to the herd of one farm. It is served as published: no line of
`registered_organic_epci_livestock` is masked.

## Left aside

- Areas by crop in the commune (500 MB): 89 % of its lines are secret in 2025. The same file by
  intercommunality (145 MB) is readable and is not loaded yet.
- Lines the source cannot place (`00000`, 75 000 ha a year), departments and regions.
- The parcels declared organic to the CAP and those of CartoBio, which say where the land is.
