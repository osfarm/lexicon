<div align="center">
  <!-- You are encouraged to replace this logo with your own! Otherwise you can also remove it. -->
  <img src="lexicon-icon.svg" alt="logo" width="140"  height="auto" />
  <br/>

  <h3><b>Lexicon</b></h3>

</div>

**Lexicon** is the repo where we gather and normalize all reference data to
feed `lexicon` schema of Ekylibre and Lexicon API project.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Installation](#installation)
- [Upgrade](#upgrade)
- [Usage](#usage)
- [Data sources](#data-sources)
- [How to contribute](#how-to-contribute)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

Lexicon work under Docker with Python 3 / Ruby and Postgresql / Postgis stack.

**Beware of disk space before running it (need at least 8 cores CPU > 3Ghz, 32Go RAM and 1To disk SSD free space)**

See [doc/INSTALL.md](doc/INSTALL.md) for more informations

## Upgrade
See [doc/UPGRADING.md](doc/UPGRADING.md) for more informations

## Usage

### 1.Run dataset (aka collect, load and normalize)

On the host, you could use `./lexicon <COMMAND> <OPTIONS>`

To build a dataset (collect, load, normalize) in one time, you can use 'run' command.

**example for phyto dataset**

`./lexicon run phytosanitary`

### 2.Dump lexicon

You can dump all datasets or use flavors to filter dataset. A package `<VERSION>` is produce in out folder with `<VERSION_NUMBER>-<FLAVOR>` name

**example for all datasets**

`./lexicon dump all --no-validate`

**example for dataset only in SAINT-PORCHAIRE(17250) zone**


`./lexicon dump all --flavor saint-porchaire --no-validate`

with flavor file `saint-porchaire.yml`

```yml
---
name: saint-porchaire
without:
  - pesticide_frequency_indicator
  - enterprises
datasources:
  cadastre: # name of the datasource, corresponding to a file in lib/datasources
    registered_cadastral_parcels: # name of the table to filter in the datasource
      filter: WHERE postgis.ST_DWithin(centroid , postgis.ST_PointFromText('POINT(-0.78 45.81)',4326) , 0.10)
  cadastral_prices:
    registered_cadastral_prices:
      filter: WHERE postal_code = '17250' ORDER BY id
  graphic_parcels:
    registered_graphic_parcels:
      filter: WHERE postgis.ST_DWithin(centroid , postgis.ST_PointFromText('POINT(-0.78 45.81)',4326) , 0.10) ORDER BY id
  hydrography:
    registered_hydrographic_items:
      filter: WHERE postgis.ST_DWithin(centroid , postgis.ST_PointFromText('POINT(-0.78 45.81)',4326) , 0.10)
    registered_area_items:
      filter: WHERE postgis.ST_DWithin(centroid , postgis.ST_PointFromText('POINT(-0.78 45.81)',4326) , 0.10)
    registered_cadastral_buildings:
      filter: WHERE postgis.ST_DWithin(centroid , postgis.ST_PointFromText('POINT(-0.78 45.81)',4326) , 0.10)
  postal_codes:
    registered_postal_codes:
      filter: WHERE postal_code = '17250'
  weather:
    registered_weather_stations:
      filter: WHERE country = 'FR' AND country_zone = '17'
    registered_hourly_weathers:
      filter: WHERE station_id LIKE 'FR17%'

```

### 3.Upload lexicon in MiniO/S3 like system

set credentials in your `.env`

```ỳml
MINIO_HOST=<YOUR-HOST> # https://api.opensourcefarm.org/
MINIO_ACCESS_KEY=<YOUR-ACCESS-KEY>
MINIO_SECRET_KEY=<YOUR-SECRET-KEY>
```

then you could launch remote upload command

`./lexicon remote upload <VERSION>`

See [doc/USAGE.md](doc/USAGE.md) for more informations

## Data sources

**Datasources**             | Spatial | Items number | Last updated |   Provider     |
----------------------------|:-------:|:------------:|:------------:|:--------------:|
Agricultural interventions  |   ⨯     |     779      |     2023     |     Ekylibre   |
Agricultural productions    |   ⨯     |     322      |     2023     |     Ekylibre   |
Area shapes                 |   ✔     |     27M      |     2023     |     IGN        |
Budgets                     |   ⨯     |     34       |     2023     |     Ekylibre   |
Cadastral prices            |   ⨯     |     ----     |     2023     |     IGN        |
Cadastral owners            |   ⨯     |     ----     |     2023     |     IGN        |
Cadastral shapes            |   ✔     |     ----     |     2023     |     IGN        |
Charts of accounts          |   ⨯     |     1600     |     2023     |     Ekylibre   |
EU market prices            |   ⨯     |     153k     |     2023     |     EU         |
FR Enterprises              |   ⨯     |     1.2M     |     2023     |     INSEE      |
FR legal positions          |   ⨯     |     23       |     2023     |     INSEE      |
FR postal codes             |   ✔     |     39k      |     2023     |     La Poste   |
FR RPG shapes               |   ✔     |     6.5M     |     2022     |     IGN        |
Historical Weather          |   ✔     |     7.9M     |     2024     |   Meteo France |
Hydrography shapes          |   ✔     |     3.4M     |     2023     |     IGN        |
Onoma nomenclatures         |   ⨯     |     5500     |     2024     |     Ekylibre   |
Phenological states         |   ⨯     |     54       |     2023     |     INRAE      |
Phytosanitary products      |   ⨯     |     16k      |     2023     |     ANSES      |
Protected zones             |   ✔     |     1760     |     2023     |     IGN        |
Soil informations           |   ✔     |     1700     |     2023     |     INRAE      |
Units & Articles            |   ⨯     |     1350     |     2023     |     Ekylibre   |


See [doc/DATASOURCES.md](doc/DATASOURCES.md) for more informations

## How to contribute
See [doc/CONTRIBUTING.md](doc/CONTRIBUTING.md) for more informations