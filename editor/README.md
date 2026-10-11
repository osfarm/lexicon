# Éditeur des collectes

L'éditeur cartographique dans lequel un adhérent retravaille ses collectes :
[geojson.io](https://github.com/mapbox/geojson.io) (licence ISC, Mapbox), que
l'on construit ici sans rien demander à Mapbox.

- `Dockerfile` récupère geojson.io au commit épinglé (`GEOJSON_IO_COMMIT`),
  applique `port.py`, ajoute `overlay/`, télécharge la police des étiquettes et
  construit l'application. L'image finale ne contient que des fichiers
  statiques, servis par Caddy.
- `port.py` remplace Mapbox GL par MapLibre GL (un alias à la construction),
  les fonds Mapbox par ceux de l'IGN (plan, photographies aériennes, cadastre)
  et OpenStreetMap, la recherche Mapbox par le géocodeur de l'IGN, et retire
  les scripts de mesure d'audience. Chaque remplacement vérifie que le texte
  attendu est là : avec un autre commit de geojson.io, la construction s'arrête.
- `overlay/` ajoute la barre du Lexicon : elle lit la collecte désignée par
  `?collecte=<chemin>` (un chemin du site même, jamais une autre adresse),
  l'enregistre et ramène à sa fiche.

L'API relaie l'application sous `/collections/editor/` (`EDITOR_URL`), pour
qu'elle soit sur le même site que les données qu'elle lit et écrit.

## Changer de version de geojson.io

Changer `GEOJSON_IO_COMMIT`, reconstruire (`docker compose build editor`) et
corriger `port.py` là où un `assert` échoue. Puis ouvrir une collecte et
vérifier la carte, les fonds, la recherche et l'enregistrement.

## Ce que l'éditeur appelle à l'extérieur

Les tuiles de `data.geopf.fr` (IGN) et de `tile.openstreetmap.org`, et le
géocodeur de `data.geopf.fr` quand on cherche un lieu. Rien d'autre.
