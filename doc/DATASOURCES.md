# Datasources
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Summary](#summary)
- [GNIS](#gnis)
    - [How to get file](#how-to-get-file)
- [ITIS](#itis)
- [Vulnerable zones](#vulnerable-zones)
- [French departments](#french-departments)
- [AgroEDI](#agroedi)
- [EPHY](#ephy)
- [Legal Legal positions](#legal-legal-positions)
- [PFI](#pfi)
- [Water rivers & lakes](#water-rivers-&-lakes)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Summary
|      Datasources    | Producer | Responsible | Primary key |     Ekylibre model     | Update frequency |
|:-------------------:|:--------:|:-----------:|:-----------:|:----------------------:|:----------------:|
|        sirene       |          |     Rémi    |  siren+nic  |         entity         |       daily      |
|         rpg         |   IGN    |     Rémi    |      id     |     cultivable_zone    |      yearly      |
|       cadastre      |   IGN    |     Rémi    |      id     |            ?           |      yearly      |
|     commodities     |          |     Anne    |      id     |         variant        |       daily      |
|       weather       |          |     Rémi    |      id     |      intervention      |       daily      |
|      phyto_data     |          |     Rémi    |      id     |         variant        |       daily      |
|      ephy_data     |          |     David    |      id     |         variant        |       daily      |
|      seed_data      |   GNIS   |     Rémi    |      id     |    variant / product   |      yearly      |
|      tool_cost      |          |   Pauline   |      id     |   variant / equipment  |      yearly      |
|      equipments     |          |     Emma    |      id     |   variant / equipment  |      yearly      |
|     productions     |          |     Emma    |      id     | activity / production |      yearly      |
| mandatory_documents |          |   Pauline   |      id     |    document_template   |      monthly     |
|       analyses      |          |     Emma    |      id     |   activity / variant   |      yearly      |
|       agroedi       |     AgroEDI Europe     |     David   |      reference_code     |   activity / production / intervention   |      yearly      |
|       PFI		        |     Agricultural French Ministry     |     David   |      pfi_crop_code     |   activity / production / intervention   |      yearly      |
| water_rivers |     Sandre     |   David   |      name     |       |      yearly     |
| legal_positions | INSEE | David | id | entity | yearly |

## GNIS

### How to get file
- Go to http://cat.geves.info/wd170awp/wd170awp.exe/connect/cat
- Click on _Variétés_ > _Catalogue Officiel_
- Click on _Actualiser_
- Click on _Exporter_

## ITIS
See: https://itis.gov/downloads/index.html

## Vulnerable zones
Shapefiles: http://services.sandre.eaufrance.fr/telechargement/geo/ZON/ZoneVuln/FXX/ZoneVuln-shp.zip

## French departments
- Shapefiles from IGN: https://wxs-telechargement.ign.fr/oikr5jryiph0iwhw36053ptm/telechargement/inspire/GEOFLA_THEME-DEPARTEMENTS_2015_2$GEOFLA_2-1_DEPARTEMENT_SHP_LAMB93_FXX_2015-12-01/file/GEOFLA_2-1_DEPARTEMENT_SHP_LAMB93_FXX_2015-12-01.7z
- Shapefiles from OSM: http://osm13.openstreetmap.fr/~cquest/openfla/export/departements-20140306-5m-shp.zip

## AgroEDI
See : http://agroedieurope.fr/

## EPHY
See : https://ephy.anses.fr/
Datasource on : https://www.data.gouv.fr/fr/datasets/donnees-ouvertes-du-catalogue-e-phy-des-produits-phytopharmaceutiques-matieres-fertilisantes-et-supports-de-culture-adjuvants-produits-mixtes-et-melanges/

## Legal Legal positions
See reference insee code on https://www.insee.fr/fr/statistiques/fichier/2028129/cj_juillet_2018.xls

## PFI
Pesticide Frequency Indicator
See : http://agriculture.gouv.fr/indicateur-de-frequence-de-traitements-phytosanitaires-ift
Datasource on : https://alim.agriculture.gouv.fr/ift/

## Water rivers & lakes
Shapefiles: http://services.sandre.eaufrance.fr/geo/MasseDEau_VRAP2016?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&typename=MasseDEauRiviere&SRSNAME=EPSG:4326&OUTPUTFORMAT=SHAPEZIP

http://services.sandre.eaufrance.fr/geo/MasseDEau_VRAP2016?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&typename=MasseDEauPlanDEau&SRSNAME=EPSG:4326&OUTPUTFORMAT=SHAPEZIP
