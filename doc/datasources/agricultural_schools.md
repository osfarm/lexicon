# agricultural_schools

Where farming is taught: schools, apprentice training centres and adult training centres of agricultural
education, what each prepares for, and the farms and workshops schools teach on.

Source: RefEA, on the open data portal of agricultural education
(<https://enseignement-agricole.opendatasoft.com/explore/>). The page of the list on data.gouv.fr was archived
in May 2026 and its links are dead: the portal is read directly.

The list of establishments is under the Licence Ouverte. **The portal names no licence for the training
offer** (`offre-formation-globale`); it is published beside the list by the same ministry, and read on that
ground. Ask the ministry before publishing it further than Lexicon does.

## Building it

```bash
./lexicon run postal_codes   # once
./lexicon run agricultural_schools
```

`collect` finds the list by its name, which carries the school year, and downloads it without the outline of
the commune each line comes with.

## Tables

### `registered_agricultural_schools`

One line per place: 1 539 schools (`kind` = `school`) and 244 farms and workshops they teach on
(`teaching_support`). Groupings and administrative services of the list are left out.

`id` is the code of the ministry (DGER). `nature` (MFREO, LEAP, CFPC, LEGTA…), `sector` (public, privé),
`affiliation`, `siret`, `national_education_code`, address, `insee_code`, `phone`, `email`, `website`,
`pupils`, `students`, `adults`, `apprentices`, `boarding`, `half_board`, `parent_id` and `parent_name` (the
establishment it belongs to), `trainings_count`.

**A school is placed in its commune, not at its address**: the source gives the centre of the commune. The
telephone and the mailbox are those of the school; no person is named.

### `registered_agricultural_trainings`

One line per school, training and route (8 831 for 1 249 schools): `name`, `diploma` (Bac Pro, CAPA, BTSA…),
`speciality` when the source gives one, `route`: `school`, `apprenticeship`, `continuing` or
`higher_education`.

## Left aside

Open days, optional subjects, languages, numbers of pupils and examination results, which the portal publishes
as other datasets.
