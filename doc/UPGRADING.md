# Update/Upgrade process
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [To v2 (per-datasource packages)](#to-v2-per-datasource-packages)
- [To 4.0.0](#to-400)
    - [Docker image rebuild](#docker-image-rebuild)
    - [Configuration needed](#configuration-needed)
- [TO 3.0.0 (docker version)](#to-300-docker-version)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## To v2 (per-datasource packages)
The branch `v2` replaces the single versioned package by one package per datasource, published to a server that puts each of them in service on its own.

### Docker image rebuild
The image moved from Debian 11 to Debian 12, whose package repositories still work, and now includes `rsync`. The `lexicon-common` gem is part of the repository (`lib/lexicon/common/`) and no longer downloaded. The `./lexicon` wrapper rebuilds the image by itself at the next call.

### Configuration needed
- `LEXICON_PUBLISH_TARGET` in `.env`, to publish (see [INSTALL.md](INSTALL.md)).
- The `MINIO_*` variables are no longer used.

### What changes in practice
- `./lexicon dump all` then `remote upload` becomes `./lexicon package` then `./lexicon publish` (see [PUBLICATION.md](PUBLICATION.md)).
- `./lexicon validate` now reports correctly; a datasource it marks invalid is refused by `package`.
- On the serving side, `master_translations` and `datasource_credits` are views, and the schema keeps the stable name `lexicon` instead of `lexicon__<version>`.

## To 4.0.0
The version 4 is a major upgrade of the code architecture.

### Docker image rebuild
Rebuilds are now done automatically wehen needed but the process needs to be initialized manually first by building the image with:
 ```bash
touch .env # The .env file is needed

docker-compose build --pull
docker-compose up -d
```

### Configuration needed
See [The __Bonus__ section of INSTALL.md](INSTALL.md)

## TO 3.0.0 (docker version)
- The `Dockerfile` file should be edited to have the environment variables `UID` and `GID` set to the ones of the current user. (use the `id` command to know them).
- The `out` and `raw` folders should be present and owned by your user.
