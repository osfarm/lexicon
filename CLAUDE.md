# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lexicon is a reference data aggregation and normalization platform that collects, transforms, and packages agricultural and geographic reference datasets (phytosanitary products, cadastral data, crop varieties, weather data, etc.) for use by the Ekylibre agricultural ERP system.

## Development Commands

### Docker Environment

```bash
docker compose -f docker-compose-dev.yml up -d   # Start dev environment (DB + runner)
docker compose -f docker-compose-dev.yml down     # Stop dev containers
```

### CLI (runs inside Docker container via wrapper script)

```bash
./lexicon list                    # List all available datasources
./lexicon run [names]             # Run full pipeline (collect + load + normalize)
./lexicon collect [names]         # Download raw data only
./lexicon load [names]            # Load raw data into raw schema tables
./lexicon normalize [names]       # Normalize into lexicon schema
./lexicon run -P                  # Run all datasources in parallel (4 workers)
./lexicon run --jobs 8            # Custom parallel job count
./lexicon validate                # Validate schema against definitions
./lexicon clean                   # Clear all database content
./lexicon package [names]         # v2: one versioned package per datasource in out/packages/<name>/<version>/
./lexicon publish [names]         # v2: send packages to the serving side (LEXICON_PUBLISH_TARGET, the local stack) and designate them
./lexicon publish [names] --production  # v2: send to LEXICON_PRODUCTION_TARGET what is in service locally (--force to skip that)
./lexicon status [--production]   # v2: version of each package: local, published, in service (status.json of the loader)
./lexicon publish --bundle <flavor>  # v2: send a bundle to the private area of the serving side
./lexicon status --bundles [--production]  # v2: what each tracked bundle designates, beside what is in service
./lexicon fetch <url>             # v2: download a bundle served by the API (key in LEXICON_API_KEY)
./lexicon bundle <flavor> [names] # v2: repository of packages filtered by a flavor, in out/bundles/<flavor>/
./lexicon bundle around --as my-farm --set longitude:-0.78 latitude:45.81 radius:0.10  # v2: parameterized flavor
./lexicon check [names] [--static] # v2: can the datasources be accepted? declarations, then built data (resources/check_baseline.yml = known issues)
./lexicon new <name>              # v2: print the skeleton of a new datasource
./lexicon new <name> --tabular    # v2: print the sheet of a tabular contribution (data/contributions/<name>/dataset.yml)
./lexicon contribute <name>       # v2: review a tabular contribution and say, in French, what to correct (no database needed)
./lexicon contribute --web        # v2: the same review in a local web page (http://localhost:8787), read again as the files change
./lexicon contribute --proposed [--production]  # v2: datasets proposed with the tool served online
./lexicon contribute --fetch <workspace>/<name> [--production]  # v2: bring one into data/contributions/<name>
./lexicon ship [names] [--production] [--no-build]  # v2: check, run, check, package, publish locally, wait for the loader; then production
./lexicon server sync [names]     # v2: put packages in service in the serving database (name or name@version)
./lexicon server sync a b --together  # v2: swap several packages in one transaction (all or none)
./lexicon server status           # v2: versions in service, stale packages, last loads
./lexicon server watch            # v2: loop run by the loader container on the server
./lexicon server rollback <name>  # v2: put back the version a package replaced
./lexicon server bundles          # v2: make the tracked bundles of the repository out of the packages in service
./lexicon server prune [--apply]  # v2: old versions (resources/retention.yml) and packages gone from the repository
./lexicon dump all                # Create versioned package in out/
./lexicon version bump [major|minor|patch]  # Bump version
./lexicon remote upload <version> # Upload package to MinIO/S3
./lexicon remote download <version>
./lexicon production load <version> # Deploy to Ekylibre instance
./lexicon console                 # Interactive Ruby REPL
```

### Tests

Unit tests live in `test/` (Minitest). The directory is not mounted in the runner container:

```bash
docker compose -f docker-compose-dev.yml run --rm -T -v "$PWD/test:/lexicon/test:ro" lexicon_runner \
  sh -c 'for f in test/lexicon/*/*_test.rb; do bundle exec ruby -Itest $f || exit 1; done'
```

To try the serving side by hand, the wrapper does not forward environment variables:

```bash
docker compose -f docker-compose-dev.yml exec lexicon_runner sh -c \
  'LEXICON_SERVER_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:5432/lexicon_server_dev" ./lexicon-cli server status'
```

### Linting

```bash
./bin/rubocop    # RuboCop (config in .rubocop.yml; datasources/ is excluded)
```

## Architecture

### Three-Phase Data Pipeline

Each datasource runs through three phases:

1. **Collect** — Downloads raw files from external APIs/sources into `/raw/<datasource>/`
2. **Load** — Parses CSV/XLS/SHP files and imports into raw PostgreSQL schema tables
3. **Normalize** — Transforms raw data into final `lexicon` schema tables

### Datasource Pattern

All datasources live in `lib/datasources/` and inherit from `Datasources::Base`. Each defines:

```ruby
module Datasources
  class MyDatasource < Base
    description "..."
    credits name: "...", url: "...", provider: "...", licence: "..."

    def collect   # Download phase
    def load      # Import phase
    def normalize # Transform phase

    def self.table_definitions(builder)  # Declares expected output tables
  end
end
```

Datasources are **auto-discovered** via Zeitwerk — just add a file under `lib/datasources/` and it registers automatically.

### Key Directories

- `lib/datasources/` — ~40 datasource implementations
- `lib/lexicon/datasource/` — Executor/runner logic (SimpleRunner, NameRunner, Parallel/SequentialExecutor)
- `lib/lexicon/database/` — Schema management, data dumper, table lifecycle
- `lib/lexicon/loader/` — File loaders: CSV (via psql COPY), XLS (via Roo), SHP (via ogr2ogr)
- `data/` — Static reference files (CSVs, shapefiles bundled in the repo)
- `raw/` — Downloaded data (gitignored, populated by collect phase)
- `out/` — Generated versioned packages (gitignored)
- `resources/` — Schemas, flavor definitions, supporting files

### Dependency Injection

Services are wired via `Dry::Container` in `Lexicon::Application#register_services`. The container provides database, loaders, executors, validators, etc. Datasources receive services via injection rather than direct instantiation.

### Database Schema

- **Raw schema** — Per-datasource temporary tables, short-lived during normalization
- **Lexicon schema** — Final normalized tables, versioned as `lexicon__<version>-<flavor>`
- PostGIS is required for spatial datasources (shapefiles loaded via `ogr2ogr`)

### Packaging & Distribution

- `./lexicon dump all` → compressed archive in `out/<version>/`
- **Flavors** (`--flavor light`, etc.) apply conditional filters defined in `resources/flavors/`
- Packages are distributed via MinIO/S3 and deployed to production Ekylibre instances
- Version is stored in `VERSION` file

### Packages v2 (in progress, branch `v2`)

Design: `claudedocs/design_lexicon_v2_j1.md`. `Lexicon::Packaging` builds one package per datasource
(`manifest.json`, `structure.sql`, `indexes.sql`, `data/*.csv.gz`), versioned `YYYY.MM.DD.N`. A datasource
declares `schema_revision N` when its tables change shape, and `depends_on :other` for datasources it reads
during normalize without a foreign key.

Translations: on the build side `master_translations` stays one table written by several datasources. A
datasource declares `translations :prefix, ...` (the prefixes of the ids it writes) and its package ships those
rows in a table `<name>__translations`; on the serving side `master_translations` is a view over these tables,
rebuilt at each swap, and `datasource_credits` is a view over the manifests. The `translations` datasource is
`packaged false`. A bundle is a repository like `out/packages`, loadable with
`LEXICON_PACKAGES_ROOT=out/bundles/<flavor> ./lexicon server sync`.

Access: a datasource declares `scope :members` when it is reserved to API key holders (`cadastre_owners`,
`enterprise_links`, `agroedi`, `vine_varieties`, `fertilizers`, `seeds`, `phytosanitary_prices`). `rd_agri` is open although under CC BY-NC-SA: it says why
with `licence_exception`, and carries a `search` tsvector column (accents removed) the API searches. Its package is published readable by its owner only (`D700,F600`): the loader, which runs
as that owner, puts it in service, while the public file server, which runs as an unprivileged user, cannot
serve it. Bundles go to `_bundles/<flavor>/` with the same permissions and are handed out by the API under
`/bundles/<flavor>/` to the keys carrying `bundle:<flavor>`.

Two kinds of bundles. A flavor `tracked: true` (`cultia`) names whole datasources under `only`, with no filter: its
bundle is made of the packages in service themselves, by the serving side. `publish --bundle` only sends its
definition (`Packaging::BundleDefinition`, refused when a foreign key leaves the list), `Server::Bundles` hard-links
the packages in service into `_bundles/<flavor>/` at each turn of `server watch` (`Packaging::BundleAssembler`, index
written last, `state.json` for what is missing), and `ship` checks the bundles naming a datasource designate the
version it put in service. Any other flavor (`around`, `test`) filters: its bundle is exported from the build
database and sent whole, as before.

`Server::ApiRole` creates, when `LEXICON_API_PASSWORD` is set, the role the API connects with: it reads
`lexicon` and `lexicon_meta` (default privileges cover the tables each swap brings in), owns `lexicon_access`,
and can change nothing else.

Members manage their own API keys under `/account` of the API (accounts opened by an administrator, invitation by mail, keys narrowed to IPv4 addresses or domains): the stack passes `LEXICON_SMTP_URL`, `LEXICON_MAIL_FROM` and `LEXICON_PUBLIC_URL` to the API (`doc/PUBLICATION.md` §18). Members also gather parcels into collections there, reworked in a map editor: `editor/` builds geojson.io on MapLibre GL and the backgrounds of the IGN (`port.py`, pinned to a commit of geojson.io), as the `editor` service the API relays under `/collections/editor/` (§19).

Deployment: `docker-compose.server.yml` is the serving stack (db, loader, packages file server, API), deployed
by Dokploy on the `osfarm_lexicon` server. `./lexicon publish` needs `rsync` in the runner image.

`Lexicon::Server` puts a package in service in another database (`LEXICON_SERVER_DATABASE_URL`, refused if it
is the build database): `Stager` loads it in `lexicon_staging`, `Checker` refuses it before or after staging,
`Swapper` replaces the tables of `lexicon` in one transaction and recreates the foreign keys pointing to them,
`Meta` keeps versions and the load journal in `lexicon_meta`. A failed load leaves the previous version in
service. `test/lexicon/server/loader_test.rb` runs against a scratch database it creates and drops. The legacy `dump` / `remote` / `production` commands still exist but
their MinIO remote is gone.

Local serving stack: `docker-compose.server.local.yml` on top of `docker-compose.server.yml` (project
`lexicon-server`: API on 8888, packages on 8889, database on 5556, repository `out/published`). A package goes
there first; `publish --production` refuses a version that is not in service there (`doc/PUBLICATION.md` §3, §16).
`docker-compose.server.api-dev.yml`, added as a third file, runs the local API on the sources of the working copy of
`../lexicon-rest-api` instead of the released image.

`enterprises` keeps every establishment of the SIRENE stock, whatever its activity (44 million lines; it used to keep
agricultural APE codes only), so that `siren` and `siret` pivots match any company. What is derived from it was renamed
with its meaning: `registered_cadastral_parcels.has_enterprise_pm_owner` and `link_communes.enterprise_owner_parcels_count`
(a parcel one of whose owners is a company SIRENE knows). A query that joins `registered_enterprises` on `siren` must ask
whether the SIREN exists, never join its establishments: a large owner has thousands of them. `PivotMeter` does the same
when it measures a pivot. `postal_codes` reads the communes and the municipal arrondissements of ADMIN EXPRESS from its
GeoPackage (`ogr2ogr`), and adds Paris, Lyon and Marseille as whole communes (75056, 69123, 13055) under each postal
code of their arrondissements, which are all La Poste lists (`commune_links` adds to their record what their
arrondissements count, the cadastre and SIRENE knowing only those); `cadastre` downloads with `curl -L`, the site answering with a redirection.

Collected again and again: a datasource declares `source_date 'SELECT ...'` so that its package carries the date
its data gives instead of the `updated_at` of `credits`, and `package` writes no new version when nothing
changed. `fuel_prices` (weekly non-road diesel prices of the DGEC, `doc/datasources/fuel_prices.md`) is the
first: its sheet is checked in `load` by `Datasources::FuelPrices::Readings`, before any published table is touched.

`phytosanitary_substances` stands beside `phytosanitary` without changing its tables: active substances of
E-Phy with the EIQ of Cornell and the HRAC mode of action, linked to products by the `amm` pivot.
`Datasources::PhytosanitarySubstances::Matcher` says how each line was matched (`cas`, `name`, `isomer`, `form`,
`alias`); a toxicity is never carried to another salt or ester unless `data/phytosanitary_substances/aliases.csv`
says so (`doc/datasources/phytosanitary_substances.md`).

`fertilizers` collects delivered prices every week from two merchants (Cereapro, Germineo) for the five places of
`data/fertilizers/delivery_places.csv`. Readings add up: each build reads again the pages kept in
`raw/fertilizers/<date>/` and the readings of the latest local package. `Catalog` tells which product an offer is
about (by name for simple fertilisers, by formula otherwise), `Pricing` draws the monthly price (public price
before a negotiated one) and the value of N, P2O5, K2O and SO3 (`doc/datasources/fertilizers.md`).

`seeds` and `phytosanitary_prices` read the same merchants with the readers of `fertilizers`
(`Datasources::Fertilizers::Cereapro` and `::Germineo`; `seeds` has three more of its own: Semence Biologique, Agrilisa and La Récolte, whose product pages are read once
and kept in `raw/seeds/la_recolte_products/`). `seeds` links its offers to `registered_seed_varieties` during normalize
when that table is built (`./lexicon run translations taxonomy seed_varieties`, with `raw/seed_varieties/gnis.csv`) and take the page of Cereapro `fertilizers` fetched the same
day: run `fertilizers` first. `seeds` names the species of an offer from `data/seeds/species.csv` (order matters,
sowing rates are indicative); `phytosanitary_prices` ties an offer to an authorisation number through the product
names it stands for (`doc/datasources/seeds.md`, `doc/datasources/phytosanitary_prices.md`).

`prices` stays open: during normalize it replaces the latest price of an article with what `fertilizers`, `seeds`,
`phytosanitary_prices` and `fuel_prices` say (aggregated, never the merchant), prices other mineral fertilisers from
the value of their nutrients, and records where each price comes from in `master_price_sources`. Rebuild it after
those four every week (`doc/datasources/prices.md`).

Tabular contributions: a directory `data/contributions/<name>/` holding a `dataset.yml` (description, author,
source and licence, columns with their types, key, pivots) and CSV files is a datasource, with no Ruby.
`Contribution::Sheet` reads it, `Contribution::Review` says in French what a contributor must correct,
`Contribution::TabularDatasource.define_all` makes `Datasources::<Name>` at start (`doc/CONTRIBUER_UN_TABLEAU.md`).
`./lexicon contribute --web` serves that review locally (`Contribution::Web`: `App` answers a request and knows
nothing of sockets, `Pages` writes the HTML, `Server` is a small HTTP server on the standard library). The wrapper
runs it in a container of its own, which publishes port 8787 on 127.0.0.1 and mounts `data/contributions` writable;
every change asks for the token of the page, and a host name other than localhost is refused.
The same tool is served online under `/contribute/outil` of the API (`doc/PUBLICATION.md` §17): the `contribute` service
of the serving stack runs `./lexicon-cli contribute --web --hosted` (`Contribution::Web::Hosted`), which answers the API
only (shared secret `LEXICON_CONTRIBUTE_SECRET`), keeps one directory per API key prefix and lets a contributor mark a
dataset as proposed; `Contribution::Inbox` lists and fetches those from a maintainer's machine. Nothing proposed online
is built by the server. No request waits for a large table: the page sends it in parts of 4 MB
(`?morceau=<i>&sur=<n>`), and a table over 2 MB is read in a thread once the request is answered (`App#background`, one
at a time), the page asking for the state until `pending` is false.
A table dropped there goes through `Contribution::Import`: it reads CSV of any separator and encoding, Excel and
LibreOffice (Roo), names the columns, guesses their types, rewrites the values the way those types are read, picks
the key and the pivots, and says in French what it did; a column of codes stays text, a mixed column too.
The page of a dataset never reloads: each action answers the parts of the page to replace as JSON (`Pages#parts`),
every change of the form is saved and reviewed at once, and `Review` takes a `memo` so that a large table is only
read again when its file or its description changes.
A table without INSEE codes designates two columns under `pivots`, `commune_postal_code` and `commune_name`
(`Sheet::PLACE_PARTS`): `TabularDatasource` then adds an `insee_code` column during normalize, found in
`registered_postal_codes` by postal code and name (capitals, accents, punctuation and SAINT/ST ignored; the name of
the commune first, the names mail is delivered by otherwise; no code when no commune or several match), declares it as a `commune` pivot and depends on `postal_codes`.
A normalize that fails puts the previous tables back and leaves the half-written ones in `<name>__error`.
A table too large for the repository is kept in `raw/<name>/` under the same file name, the sheet alone being committed
(`alim_confiance`): `Sheet#path` looks beside the sheet first, in `raw/` otherwise.

`phytosanitary_purchases` reads the yearly Parquet file of the SDES (purchases of plant protection products estimated commune by commune, from the BNV-D) with DuckDB, which `requirements.txt` brings into the runner image. It keeps the last five years of metropolitan France, one line per commune, year, product and substance, with three tables drawn from it (by commune, by commune and function, by substance for the country). Lines under statistical secrecy are counted per commune and year, never dropped silently. These are purchases, not uses (`doc/datasources/phytosanitary_purchases.md`).

`pat` reads the sheets of the territorial food projects (projets alimentaires territoriaux) the observatory France PAT publishes on data.gouv.fr: one table of projects (holder, recognition level, themes, farming figures of the territory) and one of the communes each covers, which is how a project is tied to a place (`doc/datasources/pat.md`).

Farming and food of a commune, five datasources the API gathers on the sheet of a commune (`doc/datasources/<name>.md` each). `quality_and_origin_signs` reads the lists of communes of the INAO (areas of AOC/AOP, IGP, IG), brings communes that merged back to those of today with the movements of the INSEE (`partial`, `former_communes`), and loads the zones delimited for wines under AOC. `hve_farms` is the directory of farms certified HVE, reserved to members because it names people, placed by SIRET. `organic_farming` reads the Agence Bio by commune and by intercommunality: a figure of fewer than three farms is secret (`masked`), and parcels are counted at the seat of the farm. `canteens` reads the register of « ma cantine » and its yearly declarations (shares of organic purchases), summed up by commune without an average. `agricultural_schools` reads RefEA from the portal of agricultural education: schools and what they prepare for.

Inputs (fuel, fertilisers, seeds, plant protection products and their prices): overview and weekly routine in
`doc/datasources/intrants.md`; state of the work and what remains in `claudedocs/etat_intrants.md`.

History: `graphic_parcels` keeps the RPG campaign by campaign. `registered_graphic_parcels` holds the latest
campaign (with a `campaign` column), `registered_graphic_parcels_history` the earlier ones; parcel ids are not
stable across campaigns, the place is the link. One GeoPackage per campaign is dropped by hand in
`raw/graphic_parcels/` (see `doc/datasources/graphic_parcels.md`). The legacy loader of
packages over SSH is `./lexicon load_package remote <version>`, so that `./lexicon load <name>` stays the load
phase of a datasource.

`lib/lexicon/common/` is the former `lexicon-common` gem, brought into the repository (database wrapper, psql,
shell executor, mixins, legacy package classes). It is no longer a Gemfile dependency.

### Python Integration

Some datasources delegate heavy data processing to Python scripts (NumPy/Pandas). The `Python` DSL module in datasources wraps Python script execution.

## Configuration

- `.env` — Runtime credentials (PostgreSQL, MinIO, N8N, Ollama). Copy from `.env.dist`
- `config/production.yml` — Production database connection. Copy from `config/production.yml.sample`
- The `./lexicon` wrapper script checks build-hash consistency between host and container, rebuilding if dependencies changed

## Adding a New Datasource

See `doc/CONTRIBUTING.md` for the full guide. The minimum is: create `lib/datasources/my_datasource.rb` inheriting `Datasources::Base`, implement `collect`/`load`/`normalize`, and define `table_definitions`.
