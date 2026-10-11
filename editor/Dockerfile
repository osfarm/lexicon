# The editor of the collections of the Lexicon: geojson.io (ISC licence, Mapbox), ported to MapLibre GL
# and to free backgrounds by port.py, with the bar of overlay/ that reads and saves a collection.
# It is a static application: the API relays it under /collections/editor/.
FROM node:22-alpine AS build

# The commit port.py was written for. Changing it means reading its asserts again
ARG GEOJSON_IO_COMMIT=e62e8cb
ARG FONT="Noto Sans Bold"

RUN apk add --no-cache git python3 curl
WORKDIR /editor
RUN git clone https://github.com/mapbox/geojson.io.git . && git checkout --quiet ${GEOJSON_IO_COMMIT}

COPY port.py /port.py
COPY overlay/ /editor/
RUN python3 /port.py /editor

# The font of the labels drawn over the features, served with the application (SIL Open Font Licence).
# A range the source does not have is left out; the Latin ones must be there
RUN mkdir -p "public/fonts/${FONT}" && cd "public/fonts/${FONT}" \
 && seq 0 256 65280 | while read start; do echo "${start}-$((start + 255))"; done \
    | xargs -P 8 -I {} sh -c 'curl -sSf -m 30 --retry 2 -o "{}.pbf" "https://demotiles.maplibre.org/font/$0/{}.pbf" 2>/dev/null || rm -f "{}.pbf"' \
      "$(echo "${FONT}" | sed 's/ /%20/g')" \
 ; test -s 0-255.pbf && test -s 256-511.pbf && ls | wc -l

RUN npm install --no-audit --no-fund --ignore-scripts
RUN EDITOR_BASE=/collections/editor/ npx vite build

FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /editor/dist /srv
