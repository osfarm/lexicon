#!/usr/bin/python3
import os
import sys
import glob
import requests
import json
import gzip

from jsonslicer import JsonSlicer
from psycopg2.extras import execute_values
from lib.python import db_connect

DATABASE = 'lexicon'
URL = "https://cadastre.data.gouv.fr/data/etalab-cadastre/latest/geojson/departements/"
FILE = "cadastre-{dep}-{layer}.json.gz"
PATH = 'raw/cadastre'
LIB = 'lib/datasources/cadastre'
FILE_PATH = os.path.join(PATH, FILE)
FILE_URL = os.path.join(URL, '{dep}', FILE)
DEPTS = ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "21", "22", "23", "24", "25", "26", "27", "28", "29", "2A", "2B", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "50", "51", "52", "53", "54", "55", "56", "57", "58", "59", "60", "61", "62", "63", "64", "65", "66", "67", "68", "69", "70", "71", "72", "73", "74", "76", "77", "78", "79", "80", "81", "82", "83", "84", "85", "86", "87", "88", "89", "90", "91", "92", "93", "94", "95"]  # "971", "972", "973", "974", "976", "02", "08", "10", "51", "52", "55"


def download(file_url, file_path):
    """
    Download the stream
    """
    os.system('curl --retry 5 {} > {}'.format(file_url, file_path))


def sysexit(message):
    sys.stderr.write('\n' + message + '\n')
    sys.exit(0)


def collect():
    try:
        for dep in DEPTS:
            for layer in ['parcelles']:  # 'communes', 'feuilles', 'sections'

                file_url = FILE_URL.format(dep=dep, layer=layer)
                file_path = FILE_PATH.format(dep=dep, layer=layer)

                sys.stderr.write("\nTrying with dep {dep}\n".format(dep=dep))
                r = requests.get(file_url, stream=True)
                remote_size = int(r.headers['Content-length'])

                if r.status_code == 200:
                    if not os.path.exists(file_path):
                        sys.stderr.write('Dep {} will be downloaded...\n'.format(dep))
                        download(file_url, file_path)

                    elif os.path.getsize(file_path) != remote_size:
                        sys.stderr.write('Corrupted dep {}. New download...\n'.format(dep))
                        download(file_url, file_path)

                    else:
                        sys.stderr.write("File already exists\n")

                elif r.status_code == 404:
                    sys.stderr.write("URL does not exists\n")

                else:
                    sys.stderr.write("Connection error\n")

    except requests.exceptions.RequestException as e:
        sysexit(e)


def iter_features(pattern):
    for dep in glob.glob(os.path.join(PATH, pattern)):
        with gzip.open(dep, 'rb') as f:
            yield from JsonSlicer(f, ('features', None))

def iter_parcelles_tuples():
    for feature in iter_features('cadastre-*-parcelles.json.gz'):
        feat_id = str(feature['properties'].get('id', '0'))
        geometry = json.dumps(feature['geometry'])
        town_insee_code = str(feature['properties'].get('commune', '0'))
        section_prefix = str(feature['properties'].get('prefixe', '0'))
        section = str(feature['properties'].get('section', '0'))
        work_number = str(feature['properties'].get('numero', '0'))
        net_surface_area = json.dumps(feature['properties'].get('contenance', 0))

        yield (feat_id, town_insee_code, section_prefix, section, work_number, float(net_surface_area), geometry)


def normalize():
    sql_parcelles = """
        INSERT INTO lexicon.registered_cadastral_parcels (id, town_insee_code, section_prefix, section, work_number, net_surface_area, shape)
        VALUES %s
        ON CONFLICT DO NOTHING;
    """
    sys.stderr.write("Start normalize\n")
    with db_connect() as connection:
        with connection.cursor() as cursor:
            sys.stderr.write("Load Cadastral Parcels...\n")
            execute_values(cursor, sql_parcelles, iter_parcelles_tuples(),
                           template="(%s, %s, %s, %s, %s, %s, postgis.ST_SetSRID(postgis.ST_Multi(postgis.ST_GeomFromGeoJSON(%s)), 4326))",
                           page_size=10000)
        connection.commit()

        with connection.cursor() as cursor:
            sys.stderr.write("Make valid shape on Cadastral Parcels...\n")
            cursor.execute("""
                DELETE FROM lexicon.registered_cadastral_parcels
                WHERE postgis.ST_IsValid(shape) = false
            """)
            sys.stderr.write("Compute centroid on Cadastral Parcels...\n")
            cursor.execute("""
                UPDATE lexicon.registered_cadastral_parcels
                SET centroid = postgis.ST_Centroid(shape)
            """)

        connection.commit()
