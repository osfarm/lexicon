# Lexicon REST API Tycho Recipe

This Tycho recipe deploys the **OSFarm Lexicon REST API** service paired with a secure PostgreSQL/PostGIS database instance behind a Traefik reverse proxy.

## Features

- **Standardized DB + API Integration**: Deploys both services as a unified ecosystem in rootless Podman mode.
- **SELinux Compatible Volume Mounts**: Uses the `:z` flag for volume persistence safely in rootless environments.
- **Automatic HTTPS Routing**: Traefik-ready labels out of the box.

## Configuration Parameters

| Variable | Description | Default |
|----------|-------------|---------|
| `LEXICON_SUBDOMAIN` | Subdomain used to access the REST API | `lexicon` |
| `LEXICON_DB_DATA_LOCATION` | Host directory to store persistent PostgreSQL data | `/data/lexicon/db` |
| `DB_NAME` | PostgreSQL Database name | `lexicon` |
| `DB_USER` | PostgreSQL Username | `lexicon` |
| `DB_PASSWORD` | PostgreSQL User Password | `osfarm` |
| `DB_SCHEMA` | Active Lexicon normalization schema to expose | `lexicon__6_0_0-ekyviti` |

## Installation

Run the following command to deploy using your local or registered Tycho environment:

```bash
tycho install lexicon-api
```
