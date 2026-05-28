# n8n Workflow Automation Tycho Recipe

This Tycho recipe deploys the **n8n Workflow Automation** platform for the Lexicon project, configured behind a Traefik reverse proxy.

## Features

- **Pipeline Orchestration Ready**: Easily trigger and monitor ETL run pipelines of the Lexicon service.
- **SELinux Compatible Volume Mounts**: Employs the `:z` flag to write state securely to the host filesystem.
- **Dynamic Traefik Auto-routing**: HTTPS enabled out of the box using configured global domain settings.

## Configuration Parameters

| Variable | Description | Default |
|----------|-------------|---------|
| `N8N_SUBDOMAIN` | Subdomain used to access the n8n UI | `n8n` |
| `N8N_DATA_LOCATION` | Host directory to store persistent n8n database and configurations | `/data/lexicon/n8n` |
| `N8N_GENERIC_TIMEZONE` | Timezone to configure workflow executors (e.g. cron triggers) | `Europe/Paris` |

## Installation

Run the following command to deploy using Tycho:

```bash
tycho install lexicon-n8n
```
