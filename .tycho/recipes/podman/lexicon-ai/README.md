# Lexicon AI Tycho Recipe

This Tycho recipe deploys a local self-hosted artificial intelligence stack, consisting of the **Ollama** LLM model engine and **Open WebUI** interface.

## Features

- **Self-hosted LLMs**: Run highly capable language models locally inside rootless containers.
- **Unified Interface**: Clean chat interface powered by Open WebUI, pre-connected to your Ollama runtime.
- **SELinux Compatibility**: Safely persists SQLite user data and model stores on the host system via `:z` volume flags.

## Configuration Parameters

| Variable | Description | Default |
|----------|-------------|---------|
| `AI_SUBDOMAIN` | Subdomain used to access the chat interface (e.g. `ia.yourdomain.com`) | `ia` |
| `OLLAMA_DATA_LOCATION` | Host directory to store downloaded models (e.g. Llama 3) | `/data/lexicon/ollama` |
| `OPENWEBUI_DATA_LOCATION` | Host directory to store persistent user, chat logs, and configurations | `/data/lexicon/openwebui` |

## Installation

Run the following command to deploy using Tycho:

```bash
tycho install lexicon-ai
```
