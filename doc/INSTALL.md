# Lexicon installation and configuration
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents** 

- [Requirements](#requirements)
- [Additional configuration for Docker](#additional-configuration-for-docker)
- [Finally](#finally)
- [Bonus](#bonus)
    - [S3 Storage](#s3-storage)
    - [Ekylibre database (_production_ commands)](#ekylibre-database-_production_-commands)
        - [Allow access to the database server from the container](#allow-access-to-the-database-server-from-the-container)
        - [For production servers](#for-production-servers)
        - [For development](#for-development)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Requirements
* Docker
* docker-compose
* Internet connection :)

Instructions:
```bash
# For ubuntu 24.04

# Update the system
sudo apt update && sudo apt -y upgrade
# Clean old docker versions, if any
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
# Docker repo dependencies
sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

# Add Docker's official GPG key:
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# update sources and install docker + python3
sudo apt update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin python3-pip python3-setuptools

# You need to give your user the rights to call Docker
sudo adduser $(whoami) docker
# And you'll need to reboot the computer
```

## Additional configuration for Docker
In order to have programs executed in a docker container write files that belong to you, some more configuration may be needed.
If your user id and main group id are 1000, nothing to do, the defaults will work.
To know that, use the `id` command.

If the ids are not 1000, you need to edit the `Dockerfile` file accordingly.

## Finally
```bash
touch .env

docker compose build --pull
docker compose up
```

## Bonus
### S3 Storage
To use the `remote` commands, credentials also need to be added to `.env`.   
See `.env.dev` for keys.

### Ekylibre database (_production_ commands)
In order to be able to load Packages in a production server configuration needs to be added in `.env`. See comments in `.env.dist` for keys and default values. 

Note that the postgresql installation needs to allow connections from the network as the access to the server is done from the inside of a Docker container.

#### Allow access to the database server from the container
Connections from the subnet `172.16.0.0/12` need be allowed in `pg_hba.conf` by adding:
```
host    all             all             172.16.0.0/12            md5
```

The server should also listen to the docker interface (usually `172.17.0.1`. You can check the IP address of the `docker0` network adapter to make sure).

In `postgresql.conf`:
```
listen_addresses = 'localhost, 172.17.0.1'
```

#### For production servers
It is advised to have an unprivilegied user handle all the lexicon changes to avoid possible data loss in case of an error.

```sql
CREATE ROLE lexicon PASSWORD 'lexicon' LOGIN;
REVOKE ALL PRIVILEGES ON DATABASE ekylibre_development FROM lexicon CASCADE;
GRANT CREATE ON DATABASE ekylibre_development TO LEXICON;
GRANT USAGE ON SCHEMA postgis TO lexicon;
```

If a lexicon is already enabled on the production server, and to be compatible with the `production enable/disable` commands, the lexicon schema needs to be renamed THEN enabled as it adds metadata to a table in the schema:

```sql
ALTER SCHEMA lexicon OWNER TO lexicon;
ALTER SCHEMA lexicon RENAME TO lexicon__3_99_99;
```

#### For development
No need to create a specific user to handle lexicon operations, just rename the lexicon schema (if any):
```sql
ALTER SCHEMA lexicon RENAME TO lexicon__3_99_99;
```
