# phytosanitary_purchases

Purchases of plant protection products estimated commune by commune: kilograms of active substance, by year,
product and substance. The last five years are kept (2020 to 2024 with the file of July 2026), for
metropolitan France.

Source: <https://www.data.gouv.fr/datasets/achats-de-produits-phytosanitaires-estimes-a-lechelle-de-la-commune>,
published once a year by the statistics office of the ministry of ecological transition (SDES) under the
Licence Ouverte. The figures come from the national sales database (BNV-D), which distributors feed. The
dataset is open.

## What the figures are, and are not

These are **purchases, not uses**. A distributor declares a quantity at the postal code of the buyer; the
SDES then shares it between the communes of that postal code in proportion to their farmland outside
grassland. So:

- where and when a product is bought says neither where nor when it is applied: a farm buys at its seat and
  treats its parcels wherever they are;
- the communes of one postal code get the same quantity per hectare, by construction;
- quantities are of active substance, adjuvants left out;
- a postal code with five farms or fewer is under statistical secrecy: the source then writes `secret` in
  place of the product, the substance and the quantity, keeping only the commune and the year.

Every page and tool that gives one of these figures says so (`PURCHASES_CAVEAT` in the API).

## Building it

```bash
./lexicon run phytosanitary_purchases
```

- `collect` asks data.gouv.fr for the description of the dataset (`dataset.json`) and downloads the Parquet
  file (1.4 GB) when its date changed since the last collect.
- `load` reads the file with DuckDB (`duckdb` of `requirements.txt`), keeps the last five years and the
  metropolitan communes, and writes `purchases.csv` (7 GB, 57.6 million lines) and `masked.csv`, which are
  then loaded. A commune, a product and a substance met twice in a year have their quantities added.
- `normalize` fills the four tables below. Without the download, the run takes about eleven minutes.

Left out: the commune `00000` (unknown), the overseas departments, the years before the last five.

## Tables

### `registered_phytosanitary_purchases`

One line per commune, year, product and substance.

| Column | Meaning |
|---|---|
| `insee_code` | commune (pivot `commune`) |
| `year` | year of purchase |
| `product_id` | marketing authorisation number (pivot `amm`, towards `registered_phytosanitary_products`) |
| `substance` | name of the active substance, lower case, without accents, as the source writes it |
| `cas_number` | CAS number, towards `registered_phytosanitary_substances` |
| `function` | `herbicide`, `fungicide`, `insecticide`, `other` (the four families of the SDES) |
| `danger` | hazard class of the SDES: `CMR1`, `CMR2`, `Sante-A`, `Env-A`, `Env-B`, `Autre` |
| `biocontrol` | biocontrol product |
| `organic` | usable in organic farming; empty when the usages do not say |
| `quantity` | kilograms of active substance |

### `registered_phytosanitary_purchase_summaries`

The same quantities by commune, year, function and hazard class: what a commune page reads.

### `registered_phytosanitary_purchase_communes`

One line per commune and year: `quantity`, `products_count`, `substances_count`, and

- `masked`: some purchases of that commune and year are under statistical secrecy and are not in the quantity;
- `masked_lines`: how many lines of the source they are.

A commune whose every purchase is secret has a line all the same, with an empty `quantity`.

### `registered_phytosanitary_purchase_substances`

One line per substance and year for the whole of metropolitan France: `quantity`, `communes_count`,
`products_count`, with the CAS number, function and hazard class. Also the list of the substance names.

## Per hectare

The package holds kilograms only. The API divides them by the farmland of the commune outside grassland,
read from the latest campaign of `graphic_parcels`: the parcels whose centre falls in the commune, those whose
CAP code is a `meadow` left out. That surface is the one of the latest campaign whatever the year of purchase.

## Next year

The SDES announces the next file for June 2027. `collect` sees the new date by itself; change `updated_at` in
`credits` to the date of the file.
