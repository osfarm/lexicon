# canteens

Collective catering as the platform « ma cantine » knows it: the national register of canteens, and what each
declares every year of its food purchases under the EGalim law.

Source: Direction générale de l'alimentation, under the Licence Ouverte 2.0. The register changes every week
(<https://www.data.gouv.fr/datasets/registre-national-des-cantines>), a campaign is published once
(<https://www.data.gouv.fr/datasets/resultats-de-campagnes-de-teledeclaration-des-cantines>).

## What the figures do not say

- **Only the canteens that declared.** 3 089 for 2021, 21 592 for 2024: a commune without a declaration is not
  a commune without a canteen, and a change from one year to the next first tells who declared.
- **A central kitchen declares where it cooks**, for the restaurants it delivers elsewhere (`central`).
- Shares are those of the food purchases, in value, as declared.

## Building it

```bash
./lexicon run postal_codes   # once
./lexicon run canteens
```

`collect` downloads the register and every campaign the dataset lists (`campagne_td_<year>.csv`): a new
campaign is read without touching the code.

## Tables

### `registered_canteens`

One line per canteen of the register (66 315 in 15 769 communes): `name`, `siret`, `siren`, `insee_code`,
`sectors` (school, nursery, hospital…), `economic_model` (public, private), `management_type` (direct,
conceded), `production_type`, `central_kitchen_siret`, `daily_meals`, `yearly_meals`, `declared_years`,
`project_ids` (the territorial food projects covering it: identifiers of the `pat` package).

### `registered_canteen_declarations`

One line per canteen and year, with what the canteen was that year: `organic_share` and `quality_share`
(bought under another quality sign than organic), as ratios; `meets_targets` when the canteen buys at least
20 % organic and 50 % under a quality sign, organic included; `yearly_meals` from the register of today.

### `registered_canteen_communes`

The declarations of a commune, year by year: `declarations_count`, `central_declarations_count`,
`meeting_targets_count`, lowest, median and highest `organic_share`, `median_quality_share`, and the two shares
weighted by the meals of the canteens whose meals the register knows (`weighted_declarations` of them). There
is no average: a nursery of twenty meals would weigh as much as a hospital.

## Left aside

The detailed declarations (purchases family by family) the platform does not publish.
