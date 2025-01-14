# Update/Upgrade process
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [To 4.0.0](#to-400)
    - [Docker image rebuild](#docker-image-rebuild)
    - [Configuration needed](#configuration-needed)
- [TO 3.0.0 (docker version)](#to-300-docker-version)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

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
