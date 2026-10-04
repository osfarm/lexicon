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
./lexicon publish [names]         # v2: send packages to the serving side (LEXICON_PUBLISH_TARGET) and designate them
./lexicon status                  # v2: version of each package: local, published, in service (status.json of the loader)
./lexicon publish --bundle <flavor>  # v2: send a bundle to the private area of the serving side
./lexicon fetch <url>             # v2: download a bundle served by the API (key in LEXICON_API_KEY)
./lexicon bundle <flavor> [names] # v2: repository of packages filtered by a flavor, in out/bundles/<flavor>/
./lexicon bundle around --as my-farm --set longitude:-0.78 latitude:45.81 radius:0.10  # v2: parameterized flavor
./lexicon check [names] [--static] # v2: can the datasources be accepted? declarations, then built data (resources/check_baseline.yml = known issues)
./lexicon new <name>              # v2: print the skeleton of a new datasource
./lexicon server sync [names]     # v2: put packages in service in the serving database (name or name@version)
./lexicon server sync a b --together  # v2: swap several packages in one transaction (all or none)
./lexicon server status           # v2: versions in service, stale packages, last loads
./lexicon server watch            # v2: loop run by the loader container on the server
./lexicon server rollback <name>  # v2: put back the version a package replaced
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
`enterprise_links`, `agroedi`, `vine_varieties`). `rd_agri` is open although under CC BY-NC-SA: it says why
with `licence_exception`, and carries a `search` tsvector column (accents removed) the API searches. Its package is published readable by its owner only (`D700,F600`): the loader, which runs
as that owner, puts it in service, while the public file server, which runs as an unprivileged user, cannot
serve it. Bundles go to `_bundles/<flavor>/` with the same permissions and are handed out by the API under
`/bundles/<flavor>/` to the keys carrying `bundle:<flavor>`.

`Server::ApiRole` creates, when `LEXICON_API_PASSWORD` is set, the role the API connects with: it reads
`lexicon` and `lexicon_meta` (default privileges cover the tables each swap brings in), owns `lexicon_access`,
and can change nothing else.

Deployment: `docker-compose.server.yml` is the serving stack (db, loader, packages file server, API), deployed
by Dokploy on the `osfarm_lexicon` server. `./lexicon publish` needs `rsync` in the runner image.

`Lexicon::Server` puts a package in service in another database (`LEXICON_SERVER_DATABASE_URL`, refused if it
is the build database): `Stager` loads it in `lexicon_staging`, `Checker` refuses it before or after staging,
`Swapper` replaces the tables of `lexicon` in one transaction and recreates the foreign keys pointing to them,
`Meta` keeps versions and the load journal in `lexicon_meta`. A failed load leaves the previous version in
service. `test/lexicon/server/loader_test.rb` runs against a scratch database it creates and drops. The legacy `dump` / `remote` / `production` commands still exist but
their MinIO remote is gone.

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
