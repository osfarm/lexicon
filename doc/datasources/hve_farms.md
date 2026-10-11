# hve_farms

Farms certified « Haute Valeur Environnementale » (HVE), the third and highest level of the environmental
certification of farms.

Source: the ministry of agriculture, twice a year, under the Licence Ouverte 2.0:
<https://www.data.gouv.fr/datasets/annuaire-des-exploitations-certifiees-haute-valeur-environnementale>.

**Only the farms that agreed to be listed are there.** The number of farms of a commune is a minimum, never a
count. And many farms bear the name of a person: the dataset is reserved to API key holders
(`scope :members`); the API gives the count of a commune to anyone and the names to members.

## Building it

```bash
./lexicon run postal_codes enterprises   # once
./lexicon run hve_farms
```

`collect` downloads the latest CSV of the dataset (20 942 farms on 1 July 2026). `load` refuses a file that
lacks a column or lists fewer than 5 000 farms.

## Table

`registered_hve_farms`, one line per farm: `name`, `siret`, `siren`, `cvi` (wine growers), `address`,
`postal_code`, `city`, `department`, `region`, `website`, `animal_activity`, `plant_activity`, `direct_sales`,
`certified_on`.

- `insee_code` is the commune SIRENE gives the establishment (20 748 farms); failing that, the one of the
  postal code that bears the name the directory writes (184). `located_by` says which: `sirene` or
  `postal_code`. Ten farms are placed nowhere.
- `siret_checked` says SIRENE knows the SIRET (20 769). A SIRET that is not fourteen digits, or that SIRENE
  does not know, is kept as written.
- A postal code of four digits gets back the zero a spreadsheet took from it.

Pivots: `commune`, `siret`, `siren`. Main activities are those of the directory: wine growing for two farms
out of three.

## Left aside

The earlier directories: only the latest is kept, so a farm that left the certification disappears.
