# Usage
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Short commands](#short-commands)
- [Datasources commands](#datasources-commands)
- [Version management commands](#version-management-commands)
- [Release commands](#release-commands)
- [Remote repository commands](#remote-repository-commands)
- [Production related commands](#production-related-commands)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

The script `lexicon` is used to manipulate data. Run it with `./lexicon [command [args]]`

## Short commands
- `./lexicon list` Lists all the datasources
- `./lexicon clean` Empties the database (loaded and normalized data)
- `./lexicon validate` Checks all datasources and make sure that all normalized table they declare are present and have at least 1 record and generates a report of what was found.
- `./lexicon console` Starts a ruby console allowing to interact directly with all features of the lexicon. For experimented users only!

## Datasources commands
- `./lexicon run|collect|load|normalize [datasource, ...]` run/collect/load/normalize the listed datasources. By default all datasources are selected.
    - With the `-P` option, all datasources are collected, loaded and normalized in parallel.

    - All datasources are dumped in parallel and compressed. This is a CPU-intensive operation.

To build a version, you have to take care at the order.

- `./lexicon collect`

- `./lexicon load`

- `./lexicon normalize`

## Version management commands
- `./lexicon version` Gives the version of the lexicon
- `./lexicon version bump [major|minor|patch]` increments the given part of the version number and updates the `VERSION` file
    - The default part is patch.

## Release commands
To release a version, you have to specify a flavor if needed. Otherwise, all dataset will be release.

- `./lexicon dump all [datasource, ...] [--flavor <flavor>] [--no-validate] [--force]`

Generates a Lexicon Package in the out/<version> folder if it does not already exist

[datasource, ...]

A list of datasources can be given to extract only a subset of the lexicon. The structure for all datasources is always exported.

[--flavor <flavor>]

Filter the datasources with the flavor file specified in resources/flavors/

Example for a version 4.1.5

```
# resources/flavors/light.yml
---
name: light
without:
  - graphic_parcels
  - cadastre
  - hydrography
```

Release a version with all datasources and produce a folder in out/5.0.0

- `./lexicon dump all`

Release a version with light (without graphic_parcels, cadastre and hydrography) in folder/5.0.0-light

- `./lexicon dump all --flavor light --no-validate`

## Remote repository commands
To use these commands, credentials for a S3 compatible server needs to be added in the `.env` file at the root of the project.

- `./lexicon remote upload <VERSION>` Uploads the package of the given version to the S3 storage if it does not already exists.
    - Note that the package has to be created with the `dump` command before.
- `./lexicon remote download <VERSION>` Download the given version from the S3 storage if it exists and you don't have it locally.
    - Files are downloaded in the `out` directory. Downloading a package is like `run` + `dump all`
- `./lexicon remote delete <VERSION>` Deletes the given version from the remote storage. There is no going back!

For open source version, you have to add a specific open source policy on minio serveur throught mc s3 client (see doc on Ekylibre Drive for that in Tech/Applicatifs plateforme/Minio)

## Production related commands

### setup

To use these commands, configuration for the production database to connect to have to be put in the `config/production.yml` file. See the sample file for an example.

You to copy on the server `config/production.yml` and `.env`

`scp .env eky-lhotse:/home/ubuntu/lexicon/`

`scp config/production.yml eky-lhotse:/home/ubuntu/lexicon/config/`

then you can use `docker compose up -d`

### load and activate a version from S3

`docker compose exec lexicon_runner ./lexicon-cli remote download <VERSION>`

### usage

example from the host server, you can use `docker compose exec lexicon_runner ./lexicon-cli remote download <VERSION>` instead of `./lexicon remote download <VERSION>` in local dev.

- `./lexicon config` Prints some config related to the configuration of the production commands
- `./lexicon production loadable` Checks the `out directory`, list all packages that can be loaded and displays information about them.
- `./lexicon production versions` Checks the production database and prints information about the packages loaded. It also displays, if possible which version is enabled.
- `./lexicon production disable` Disables the current enabled version if any.
- `./lexicon production enable [version]` enables the provided version or the latest one if none is provided. If a version is already enabled, it is disabled first.
- `./lexicon production load <VERSION> [--no-validate] [--datasources datasource ...]` Loads the package of version `<version>`.
    - All datasources are loaded in parallel.
    - By default, the integrity of the package is checked first. As it reads a lot of data, this can be a long operation. The `--no-validate` option disables this check.
- `./lexicon production delete <VERSION>` Deletes the provided version from the production server.

### troubleshooting

#### when downloading a version from S3

#<Errno::EACCES: Permission denied @ dir_s_mkdir - /lexicon/out/xxxxxxxxxxx>
> Change permissions on `out` folder
`sudo chmod -R 775 out`


