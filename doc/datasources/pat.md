# pat

Territorial food projects (projets alimentaires territoriaux, PAT): what a territory undertakes to bring food
production and consumption closer, recognised by the ministry of agriculture at level 1 or 2. The dataset
says, for each project, who leads it, what it works on, which communes it covers, and gives figures about
the farming of its territory.

Source: the observatory France PAT (<https://france-pat.fr/>), which publishes on data.gouv.fr under the
Licence Ouverte, about twice a year:
<https://www.data.gouv.fr/datasets/pat-projets-alimentaires-territoriaux-description>. The dataset is open.

## Building it

```bash
./lexicon run pat
```

- `collect` asks data.gouv.fr for the files of the dataset and downloads the latest `pats-<date>.csv` (the
  UTF-8 one) into `raw/pat/` when it is not there. A file dropped by hand under that name is read as well.
- `load` reads the sheets with Ruby, refuses a file that lacks a column it reads or holds fewer than a hundred
  projects, and writes `projects.csv` and `communes.csv`.
- `normalize` fills the two tables. The whole run takes a few seconds.

The file has 256 columns, most of them repeated groups (partners, objectives, documents) and free text. The
columns kept are listed in `COLUMNS`.

## Tables

### `registered_territorial_food_projects`

One line per project (471 in October 2026).

| Column | Meaning |
|---|---|
| `id` | identifier of France PAT |
| `name`, `usual_name` | administrative name, and the one in use when there is one |
| `sheet_url` | the sheet of the project on france-pat.fr |
| `website` | the site of the project |
| `regions`, `departments` | names, separated by commas when the project spans several |
| `holder`, `holder_kind` | who leads it: Intercommunalité, Communauté de communes, Département… |
| `co_holders` | those who lead it beside the holder |
| `label` | « Labellisation Niveau 1 », « Labellisation Niveau 2 », « Labellisation en attente » |
| `label_level` | 1 or 2; empty while the recognition is pending |
| `labelled_in` | year of the latest recognition |
| `validated_on` | when the observatory validated the sheet |
| `themes` | what the project works on, as keys (see below) |
| `communes_count` | communes covered |
| `inhabitants`, `area_km2` | permanent inhabitants and area of the territory |
| `farms_count`, `organic_farms_count` | farms, and those certified organic |
| `farmland_ha`, `organic_farmland_ha` | farmland (SAU) and its organic part, in hectares |
| `farmland_share`, `organic_farmland_share` | farmland in the territory, organic farmland in the farmland, in percent |
| `permanent_grassland_share`, `legumes_share` | percent of permanent grassland and of legume crops |
| `hedge_metres_per_ha` | metres of hedge per hectare of farmland |
| `irrigation_m3` | water used for irrigation |
| `nitrates_mg_per_l`, `pesticides_ug_per_l` | nitrates and plant protection products in water |

These figures describe the whole territory of a project, not one of its communes.

Themes: `food_economy`, `culture_and_gastronomy`, `food_education`, `nutrition_and_health`,
`social_justice`, `environment`, `collective_catering`, `town_planning`, `governance`, `other`.

### `registered_territorial_food_project_communes`

One line per project and commune covered (`project_id`, `insee_code`, pivot `commune`): 34 566 lines for
27 455 communes. A commune is often in two projects, the one of its intercommunality and the one of its
department, and at most in three.

### Communes that come by a co-holder

The list of communes of a sheet is not always whole. The « PAT du Pays de Saintonge Romane » says it covers
70 communes and three intercommunalities, and lists 36 codes, those of one of the three. So `load` adds, for
each co-holder that is an intercommunality, the member communes the sheet does not list, and writes the name of
that co-holder in `through` (empty for a commune the sheet lists).

Members come from the layer `epci` of the ADMIN EXPRESS file `postal_codes` collects
(`raw/postal_codes/archive`); without that file nothing is added and a warning says so. A co-holder is matched
to an intercommunality by its name, capitals, accents and words such as « Communauté de communes » or « CC »
left out; a name that matches none, or two, adds nothing.

In October 2026, 19 of the 26 intercommunal co-holders are recognised. All but those of Saintonge Romane
were already listed whole by their sheet: the rule adds 34 communes, to that one project. The seven not
recognised name several intercommunalities at once or something else (« Les 4 EPCI du territoire »).

`co_holders` of the project table lists every co-holder, whatever its kind.

## Left aside

- The nine datasets « PAT - axe … » (the actions of each project, theme by theme) and the dataset of
  perimeters: the list of communes says where a project applies, no geometry is needed.
- Contacts (service, address, telephone), partners, objectives and free descriptions of the sheet.
