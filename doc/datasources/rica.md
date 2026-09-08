# `rica` — RICA micro-data (Fichier Micro-Données)

Annual accounting micro-data for French holdings, published by SSP / Agreste under
[Licence Ouverte 2.0](https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf).
Nine vintages, 2016 → 2024, loaded from files dropped by hand into `raw/rica/` (the SSP portal
has no open download endpoint).

Three tables land in the `lexicon` schema:

| Table | Grain |
|---|---|
| `registered_rica_holdings` | one row per holding × vintage |
| `registered_rica_variables` | the yearly data dictionary — one row per variable × vintage |
| `registered_rica_modalities` | the yearly value lists — one row per variable × modality × vintage |

## Read this before using a number from this datasource

**The FMD is an anonymised publication. Most of its magnitudes are band codes, not
measurements.** A holding's SAU is not published as `84.3 ha`; it is published as the code
`17`, meaning "somewhere in [170, 180) hectares". 123 of the ~985 variables of the 2024
vintage are like this, including every per-crop area (the 47 `SUT3*`) and every per-category
livestock count (the 35 `EFM6*`).

The dictionary is what tells the two apart:

* `data_type` is `char` (2016–2022) or `caractères` (2023+) → **ordinal band code**;
* `data_type` is `num` / `numérique` → real value.

Money (`PBV*`, `VAV*`, `ACV*`, `CHR*`, `PBRTO`, `EBEXP`, `RESEX`) and quantities (`PRQ*`,
`PBQ*`, `VAQ*`, `ACQ*`) are real. Two traps run the other way: `SUI3*` (irrigated area) and
`SUD4*` (developed horticultural area) are in **real hectares** even though their `SUT3*`
neighbours are bands.

### The rule for consumers

> **A magnitude whose denominator is a band is exposed as an interval, never as a point
> value.**

A yield computed as `PRQ3BLET / band midpoint`, then displayed as a single number, is the
same bug in another shape: it looks like a measurement and it is not one. Carry
`lower_bound` and `upper_bound` all the way to the reader, or say "170–180 ha".

## Band columns on `registered_rica_holdings`

Two variables are promoted to native columns:

| Column | Variable | Meaning |
|---|---|---|
| `sau_band integer` | `SAUTI` | band code for total UAA, `0`…`30` |
| `total_area_band integer` | `SUTOT` | band code for total area (UAA and non-UAA) |

They are `integer` and carry the `_band` suffix on purpose. A name like `sau_ha` reads as
hectares, and consumers believed it: the column held codes 0–30 and every national average
computed from it came out around 13 "hectares".

Resolve a band to its bounds by joining the modality table:

```sql
SELECT h.idnum, h.year, m.lower_bound, m.upper_bound, m.bound_unit, m.label
FROM registered_rica_holdings h
JOIN registered_rica_modalities m
  ON m.year = h.year
 AND m.variable_code = 'SAUTI'
 AND m.modality_code = h.sau_band::text
WHERE h.year = 2024;
```

`modality_code` is `character varying` because the FMD codes are not all numeric — `SEXEP`
and `STATU` use the literal code `blanc` for an unknown value — hence the cast.

The other promoted columns are real values: `gross_product` (`PBRTO`),
`gross_operating_surplus` (`EBEXP`), `operating_result` (`RESEX`) and
`extrapolation_coefficient` (`EXTR2`) are all declared numeric by the dictionary. Every
variable that has no native column stays in the `data` JSONB payload, uncast.

## Bounds on `registered_rica_modalities`

`lower_bound`, `upper_bound` and `bound_unit` are derived at normalize time from the French
modality label, so that no consumer has to write a regex over
`"Surface égale ou supérieure à 15 ha et inférieure à 20 ha"`.

Conventions, uniform across every family:

* `lower_bound` is **inclusive**, `upper_bound` is **exclusive**;
* an open-ended top band ("Surface égale ou supérieure 400 ha") has `upper_bound IS NULL`;
* a zero band ("Surface nulle", and the absence forms such as "Pas de DPU") is `[0, 0]`;
* a "non nul" band starts at `0` — the zero itself is a separate modality of the same
  variable, so in practice the two do not overlap;
* age bands are counted in complete years, so "21 à 25 ans" is `[21, 26)` and "Plus de
  80 ans" starts at `81`;
* a modality that is not quantitative keeps `NULL` bounds. That covers the 18 nomenclatures
  of 2024 (`FJURI`, `ZALTI`, `ZDEFA`, `ZENVI`, `REGIO`, `OTEXE`, `OTE64F`, `OTEFDA`,
  `OTEFDD`, `IRMODE`, `IRORIGI`, `RIMPO`, `SEXEP`, `STATU`, `VDETAIL`, `FOAGR`, `FOGEN`,
  `DJAXP`) and the "Sans objet" modality, which means *not applicable*, not *zero*.

`bound_unit` vocabulary — `hectare`, `head`, `hour` and `liter` are
`master_units.reference_name`; the rest are RICA-specific:

| Unit | Label family | Example variables |
|---|---|---|
| `hectare` | `Surface …` | `SAUTI`, `SUTOT`, `SUT3*` |
| `head` | `Effectif …`, `Effectif moyen …`, `Effectif primé …` | `EFM6*`, `EFF10` |
| `livestock_unit` | `Nombre d'UGB …` | `UGBTO`, `UGBBO` |
| `annual_work_unit` | `Nombre d'UTA …` | `TOUTA`, `TVUTA` |
| `human_work_unit` | `Nombre d'UTH …` | — (no variable currently declares UTH) |
| `hour` | `Nombre d'heures …` | `TVL11` |
| `payment_entitlement` | `Nombre de DPU …` | `SBVDPUS` / `SBVDPS` |
| `liter` | `Quota laitier …` | `QUOLA` (2016–2018) |
| `euro` | `PBS de … à moins de … euros` | `CDEXE` |
| `year` | `21 à 25 ans` | `TRA05` |

When the variable's own dictionary label names a unit in parentheses, that label wins over
the modality wording. From 2020 the SSP reworded the work-time bands without saying what
they measure — `TOUTA`'s modalities became "Effectif …" and `TVUTA`'s "Nombre d'UTH …" —
while both variable labels kept `(UTA)`. Reading the unit off the modality alone would have
published work time as head counts, which is the original bug in miniature: the dictionary
is the authority.

Known source quirks that survive into the data, on purpose:

* `TOUTA` 2016–2019 has a genuine hole in its series — no modality covers `[4, 5)` UTA;
* `CDEXE` has no zero band: its lowest published class starts at 25 000 € (2016–2021) then
  15 000 € (2022+), because the smallest holdings are outside the RICA field.

If SSP rewords a label, normalize logs a warning naming the variable, the modality and the
label it could not parse — that is the signal to extend `BandBounds` in
`lib/datasources/rica.rb`.

## The promotion guard

`check_promotions!` runs before any holding is inserted. It compares every entry of
`PROMOTED_COLUMNS` against the vintage's own dictionary and **refuses to load** when a
variable declared `char` / `caractères` is promoted to a numeric column that is not named
`*_band`. Both dictionary vocabularies are accepted, and a vintage shipped without a
dictionary falls back on the nearest one rather than skipping the check.

This is the only part of the fix that stops the bug coming back: renaming a column repairs
today's data, the guard is what rejects the next `char` variable promoted to a numeric
column named after a unit.

## Adding a vintage

1. Drop the SSP folder under `raw/rica/` and add an entry to `SOURCES` (data path,
   dictionary path, and the column-name mapping matching that year's header spelling).
2. Extend `YEARS`.
3. Run `./lexicon run rica` and read the warnings: unparsed band labels and missing
   dictionary entries are both reported by name.

The 2016–2018 `.txt` files are not clean CSV — quoted lines, a stray trailing separator, a
blank final line. `clean_legacy_file` normalises them in `collect`; without it the `COPY`
fails and the vintage loads **empty, with no visible error**.
