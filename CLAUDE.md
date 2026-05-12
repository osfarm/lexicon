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
./lexicon dump all                # Create versioned package in out/
./lexicon version bump [major|minor|patch]  # Bump version
./lexicon remote upload <version> # Upload package to MinIO/S3
./lexicon remote download <version>
./lexicon production load <version> # Deploy to Ekylibre instance
./lexicon console                 # Interactive Ruby REPL
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

### Python Integration

Some datasources delegate heavy data processing to Python scripts (NumPy/Pandas). The `Python` DSL module in datasources wraps Python script execution.

## Configuration

- `.env` — Runtime credentials (PostgreSQL, MinIO, N8N, Ollama). Copy from `.env.dist`
- `config/production.yml` — Production database connection. Copy from `config/production.yml.sample`
- The `./lexicon` wrapper script checks build-hash consistency between host and container, rebuilding if dependencies changed

## Adding a New Datasource

See `doc/CONTRIBUTING.md` for the full guide. The minimum is: create `lib/datasources/my_datasource.rb` inheriting `Datasources::Base`, implement `collect`/`load`/`normalize`, and define `table_definitions`.
