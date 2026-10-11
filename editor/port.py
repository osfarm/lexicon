"""Ports geojson.io to a free background, for the editor of collections the Lexicon serves.

Run by the Dockerfile on a checkout of https://github.com/mapbox/geojson.io at the commit it pins:

    python3 port.py <checkout>

MapLibre GL stands for Mapbox GL (an alias of the build: the code keeps its imports), the backgrounds are
the maps of the IGN and OpenStreetMap, places are searched with the geocoder of the IGN, and nothing is
asked to Mapbox, Google or an audience measurement any more. Every change asserts that the text it
replaces is there: with another commit of geojson.io, the build stops instead of shipping half a port.
"""
import re, json, sys, os
root = sys.argv[1]
def rd(p): return open(os.path.join(root,p)).read()
def wr(p,s): open(os.path.join(root,p),"w").write(s)
def sub(p, old, new, n=1):
    s=rd(p); assert old in s, (p, old[:70]); wr(p, s.replace(old,new,n))
def rsub(p, pat, new, flags=0, least=1):
    s=rd(p); s2,k=re.subn(pat,new,s,flags=flags); assert k>=least,(p,pat,k); wr(p,s2)

# --- build: MapLibre stands for Mapbox GL, and the application lives under a path of the Lexicon
pkg=json.loads(rd("package.json"))
pkg["dependencies"]["maplibre-gl"]="5.9.0"
pkg["name"]="lexicon-collections-editor"
wr("package.json", json.dumps(pkg, indent=2)+"\n")
sub("vite.config.ts", "  base: env.mode === 'staging' ? '/geojson-io-staging/' : '/',", """  base: process.env.EDITOR_BASE ?? '/collections/editor/',
  resolve: {
    alias: [
      {
        find: 'mapbox-gl/dist/mapbox-gl.css',
        replacement: 'maplibre-gl/dist/maplibre-gl.css'
      },
      { find: /^mapbox-gl$/, replacement: 'maplibre-gl' }
    ]
  },""")

wr("index.html", """<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <meta name="referrer" content="no-referrer" />
    <link rel="icon" href="/public/images/lexicon-mark.svg" />
    <title>Collectes — Lexicon</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="./pages/index.tsx"></script>
  </body>
</html>
""")

rsub("pages/index.tsx", r"// initialize mapbox analytics\n.*?\}\);\n\n", "", flags=re.S)
sub("pages/index.tsx", "<title>geojson.io | Powered by Mapbox</title>", "<title>Collectes — Lexicon</title>")

# --- backgrounds: IGN and OpenStreetMap, no key needed
wr("app/lib/default_styles.ts", """// Backgrounds of the editor served by the Lexicon: the maps of the IGN
// (Géoplateforme, open without a key) and OpenStreetMap. No Mapbox style is used.

export type StyleConfigTemplate = {
  name: string;
  url?: string;
  json?: mapboxgl.Style;
  supports3dFeatures?: boolean;
};

const defaults = { type: 'MAPBOX', token: '' } as const;

// Fonts of the labels drawn over the features, served with the application
export const GLYPHS = `${window.location.origin}${import.meta.env.BASE_URL}fonts/{fontstack}/{range}.pbf`;

const IGN = '© IGN';
const ign = (layer: string, format: string, style = 'normal') =>
  `https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=${layer}&STYLE=${encodeURIComponent(
    style
  )}&FORMAT=${format}&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}`;

type Raster = { id: string; tiles: string; attribution: string; maxzoom: number };

function rasters(name: string, layers: Raster[]): any {
  return {
    version: 8,
    name,
    glyphs: GLYPHS,
    sources: Object.fromEntries(
      layers.map((layer) => [
        layer.id,
        {
          type: 'raster',
          tiles: [layer.tiles],
          tileSize: 256,
          maxzoom: layer.maxzoom,
          attribution: layer.attribution
        }
      ])
    ),
    layers: layers.map((layer) => ({ id: layer.id, type: 'raster', source: layer.id }))
  };
}

const PLAN: Raster = {
  id: 'ign-plan',
  tiles: ign('GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2', 'image/png'),
  attribution: IGN,
  maxzoom: 19
};
const PHOTOS: Raster = {
  id: 'ign-photos',
  tiles: ign('ORTHOIMAGERY.ORTHOPHOTOS', 'image/jpeg'),
  attribution: IGN,
  maxzoom: 19
};
const CADASTRE: Raster = {
  id: 'ign-cadastre',
  tiles: ign('CADASTRALPARCELS.PARCELLAIRE_EXPRESS', 'image/png', 'PCI vector'),
  attribution: IGN,
  maxzoom: 19
};

const STYLES: Record<string, StyleConfigTemplate> = {
  LIGHT: { name: 'Plan IGN', json: rasters('Plan IGN', [PLAN]), ...defaults },
  STANDARD_SATELLITE: {
    name: 'Photos IGN',
    json: rasters('Photographies aériennes', [PHOTOS]),
    ...defaults
  },
  OUTDOORS: {
    name: 'Photos et cadastre',
    json: rasters('Photographies aériennes et cadastre', [PHOTOS, CADASTRE]),
    ...defaults
  },
  STANDARD: {
    name: 'Plan et cadastre',
    json: rasters('Plan IGN et cadastre', [PLAN, CADASTRE]),
    ...defaults
  },
  OSM: {
    name: 'OpenStreetMap',
    json: rasters('OpenStreetMap', [
      {
        id: 'osm-tiles',
        tiles: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        attribution: '© les contributeurs d’OpenStreetMap',
        maxzoom: 19
      }
    ]),
    ...defaults
  }
};

export default STYLES;
""")

# glyphs and sprites of Mapbox are gone everywhere
for p in ["app/lib/style_config_adapters.ts","app/lib/load_and_augment_style.ts"]:
    s=rd(p)
    s=re.sub(r"\n\s*sprite: 'mapbox://sprites/mapbox/streets-v8',", "", s)
    s=s.replace("glyphs: 'mapbox://fonts/mapbox/{fontstack}/{range}.pbf',","glyphs: GLYPHS,")
    s=re.sub(r"\n\s*'[a-z]+-emissive-strength': 1,?", "", s)
    s="import { GLYPHS } from 'app/lib/default_styles';\n"+s
    wr(p,s)
sub("app/lib/load_and_augment_style.ts", "'text-font': ['DIN Offc Pro Bold', 'Arial Unicode MS Bold'],", "'text-font': ['Noto Sans Bold'],")
# no fog, a property MapLibre does not know
rsub("app/lib/style_config_adapters.ts", r"  if \(!style\.imports\) \{\n    result\.fog = STANDARD_FOG;\n  \}\n", "")
sub("app/lib/style_config_adapters.ts", "import STANDARD_FOG from 'app/lib/standard_fog';\n", "")
# a style given by its address was a Mapbox one: only the styles above exist
rsub("app/lib/style_config_adapters.ts", r"    const url = getMapboxLayerURL\(layer\);\n    style = await fetch\(url\)", "    style = await fetch(layer.url)")
sub("app/lib/style_config_adapters.ts", "import { getMapboxLayerURL } from 'app/lib/utils';\n", "")

# --- the map: no token, no plugin fetched from Mapbox, a flat projection
rsub("app/components/map_component.tsx", r"mapboxgl\.accessToken = env\.MAPBOX_TOKEN;\n\nmapboxgl\.setRTLTextPlugin\(.*?\n\);\n", "", flags=re.S)
sub("app/components/map_component.tsx", "import { env } from 'app/lib/env_client';\n", "")
s=rd("app/lib/pmap/index.ts")
s,k=re.subn(r"(this\.map|map)\.setProjection\([^;]*\);", r"flatten(\1);", s); assert k>=3,k
s=s.replace("const MAP_OPTIONS:", """// MapLibre takes a projection as an object, and the globe of Mapbox GL, which the
// overlay of deck.gl was corrected for, is not the one of MapLibre: the map stays flat
function flatten(map: any) {
  try {
    map.setProjection({ type: 'mercator' });
  } catch {
    // an older MapLibre is flat already
  }
}

const MAP_OPTIONS:""",1)
wr("app/lib/pmap/index.ts", s)
sub("state/jotai.ts", "mapProjection: 'globe'", "mapProjection: 'mercator'")
sub("app/components/styles/popover.tsx", "const iconSrc = `/layer-icons/${id}.png`;", "const iconSrc = `${import.meta.env.BASE_URL}layer-icons/${id}.png`;")
sub("app/components/styles/popover.tsx", "src={`/layer-icons/projection-${id}.png`}", "src={`${import.meta.env.BASE_URL}layer-icons/projection-${id}.png`}")
wr("app/lib/mapbox_static_url.ts", """import type { PartialLayer } from 'state/jotai';

/**
 * A picture standing for a background: the first tile of a tiled layer, nothing for the others.
 */
export function mapboxStaticURL(
  mapboxLayer: Pick<PartialLayer, 'type' | 'url' | 'token'>
) {
  return mapboxLayer.type === 'MAPBOX'
    ? ''
    : String(mapboxLayer.url)
        .replace('{x}', '0')
        .replace('{y}', '0')
        .replace('{z}', '0');
}
""")

# --- search: the geocoder of the IGN instead of Mapbox Search
s=rd("app/lib/geocode.ts")
s=s.replace("import { env } from 'app/lib/env_client';\n","")
s=re.sub(r"import \{ SearchSession, SearchBoxCore \} from '@mapbox/search-js-core';\nimport type \{.*?\} from '@mapbox/search-js-core';\n", """// A place found by the geocoder of the IGN (Géoplateforme): what Mapbox Search
// called a suggestion, with its coordinates already in it
type SearchBoxSuggestion = {
  name: string;
  mapbox_id: string;
  coordinates: [number, number];
};
type SearchBoxFeatureSuggestion = {
  geometry: { type: 'Point'; coordinates: [number, number] };
  properties: { mapbox_id: string; bbox?: [number, number, number, number] };
};
""", s, flags=re.S)
s=re.sub(r"type SearchBoxSession = SearchSession<.*?>;\n\n", "", s, flags=re.S)
s=re.sub(r"export async function retrieveFeature\(.*?\n\}\n", """export async function retrieveFeature(
  suggestion: SearchBoxSuggestion
): Promise<SearchBoxFeatureSuggestion> {
  return Promise.resolve({
    geometry: { type: 'Point', coordinates: suggestion.coordinates },
    properties: { mapbox_id: suggestion.mapbox_id }
  });
}
""", s, flags=re.S)
s=re.sub(r"// Create a singleton search session instance\n.*?\n\}\n\n/\*\*\n \* Search using Mapbox Search JS Core", "/**\n * Search with the geocoder of the IGN", s, flags=re.S)
start=s.index("  const search = new SearchBoxCore({ accessToken: env.MAPBOX_TOKEN });\n\n  const session = getSearchSession(search);\n\n  try {")
end=s.index("    return {\n      literal: getLiteralItems(query),\n      features: getFeatureItems(query, searchIndex),\n      geocoder: geocoderItems")
s=s[:start]+"""  try {
    const params = new URLSearchParams({ q: query, limit: '5' });
    if (center && (zoom ?? 0) > 8) {
      params.set('lon', String(center.lng));
      params.set('lat', String(center.lat));
    }
    const response = await fetch(
      `https://data.geopf.fr/geocodage/search?${params.toString()}`,
      { signal, referrerPolicy: 'no-referrer' }
    );
    const found = response.ok ? await response.json() : { features: [] };
    const geocoderItems: SearchBoxSuggestionItem[] = (found.features ?? [])
      .filter((feature: any) => feature?.geometry?.type === 'Point')
      .map((feature: any) => ({
        type: 'geocoder',
        suggestion: {
          name: String(feature.properties?.label ?? ''),
          mapbox_id: String(feature.properties?.id ?? feature.properties?.label ?? ''),
          coordinates: feature.geometry.coordinates
        },
        properties: { label: String(feature.properties?.label ?? 'Lieu') }
      }));

"""+s[end:]
s=s.replace("  center: LngLat | undefined;\n  zoom: number | undefined;\n  signal: AbortSignal | undefined;\n  searchIndex: SearchIndex;\n}): Promise<GeocoderResults> {","  center: LngLat | undefined;\n  zoom: number | undefined;\n  signal: AbortSignal | undefined;\n  searchIndex: SearchIndex;\n}): Promise<GeocoderResults> {",1)
s=s.replace("export async function mapboxSearch({\n  query,\n  center,\n  zoom,\n  searchIndex\n}","export async function mapboxSearch({\n  query,\n  center,\n  zoom,\n  signal,\n  searchIndex\n}")
s=s.replace("console.error('Mapbox search error:', error);","console.error('Search error:', error);")
assert "SearchBoxCore" not in s and "getSearchSession" not in s, "geocode leftovers"
wr("app/lib/geocode.ts", s)

# --- two places read the inside of Mapbox GL, which MapLibre does not share
sub("app/components/legend.tsx", "const y = (map as any)._containerHeight / 2;", "const y = map.getContainer().clientHeight / 2;")
sub("app/components/legend.tsx", "const x = (map as any)._containerWidth / 2 - maxWidth / 2;", "const x = map.getContainer().clientWidth / 2 - maxWidth / 2;")
# an icon that finishes loading after the map is gone has nowhere to go
sub("app/lib/maki.ts", """          if (!map.hasImage(mapId)) {
            map.addImage(mapId, img, { sdf: true });
          }
          resolve();""", """          try {
            if (!map.hasImage(mapId)) {
              map.addImage(mapId, img, { sdf: true });
            }
          } catch {
            // the map was removed meanwhile
          }
          resolve();""")
