#!/usr/bin/python3
import sys
import zipfile
from pathlib import Path

import pandas
from numpy import nan
from psycopg2.extras import execute_values

from lib.python import db_connect

BASE_NAME = Path('eta_utf8.zip')
BASE_DIR = Path(__file__).resolve().parent.parent.parent.parent
LOCAL_PATH = BASE_DIR.joinpath('raw', 'enterprises')
ZIP_PATH = LOCAL_PATH.joinpath(BASE_NAME)

COLS = [
    'siret',  # Numéro SIRET
    'activitePrincipaleEtablissement',  # Code APE
    'enseigne1Etablissement',  # Libellé établissement
    'numeroVoieEtablissement',  # Numéro de la voie
    'typeVoieEtablissement',  # Type de voie
    'libelleVoieEtablissement',  # Nom de la voie
    'libelleCommuneEtablissement',  # Commune
    'codePostalEtablissement',  # Code postal
    'etatAdministratifEtablissement',  # Statut de l'établissement (A actif
]

DTYPES = {
    'siret': str,  # int
    'activitePrincipaleEtablissement': str,
    'enseigne1Etablissement': str,
    'numeroVoieEtablissement': str,  # Int64 pour gérer le NaN
    'typeVoieEtablissement': str,
    'libelleVoieEtablissement': str,
    'libelleCommuneEtablissement': str,
    'codePostalEtablissement': str,  # Int64 pour gérer le NaN
    'etatAdministratifEtablissement': str,
}

CODES_APE = ('01.11Z', '01.12Z', '01.13Z', '01.14Z', '01.15Z', '01.16Z', '01.19Z', '01.21Z', '01.22Z', '01.23Z',
             '01.24Z', '01.5Z', '01.26Z', '01.27Z', '01.28Z', '01.29Z', '01.30Z', '01.41Z', '01.42Z', '01.43Z',
             '01.44Z', '01.45Z', '01.46Z', '01.47Z', '01.49Z', '01.50Z', '01.61Z', '01.62Z', '01.63Z', '01.64Z',
             '01.70Z', '02.10Z', '02.20Z', '02.30Z', '02.40Z', '03.11Z', '03.12Z', '03.21Z', '03.22Z')


def do_normalization(coll):
    for chunk in coll:
        for row in chunk.itertuples():
            if row.activitePrincipaleEtablissement in CODES_APE:
                establishment_number = row.siret
                french_main_activity_code = row.activitePrincipaleEtablissement

                name = row.enseigne1Etablissement \
                    if row.enseigne1Etablissement is not nan and row.enseigne1Etablissement != '' else None

                a = (row.numeroVoieEtablissement, row.typeVoieEtablissement, row.libelleVoieEtablissement)
                b = []

                for i in a:
                    if str(i) not in ('nan', '', '-'):
                        b.append(str(i))

                address = " ".join(b) if len(b) > 0 else None
                postal_code = row.codePostalEtablissement
                city = row.libelleCommuneEtablissement if row.libelleCommuneEtablissement is not nan else None

                yield (establishment_number, french_main_activity_code, name, address, postal_code, city, 'France')


def normalize_file(file, connection):
    data = pandas.read_csv(file, chunksize=100000, usecols=COLS, dtype=DTYPES, na_values=['-'])
    iterator = do_normalization(data)

    with connection.cursor() as cursor:
        # it = tqdm(iterator, total=csvlen(CSV_PATH), ascii=True, unit_scale=True)
        execute_values(cursor, "INSERT INTO lexicon.registered_enterprises VALUES %s", iterator, page_size=10000)
    connection.commit()


def handle_file(file):
    with db_connect() as connection:
        normalize_file(file, connection)


def normalize():
    try:
        zfile = zipfile.ZipFile(ZIP_PATH)
        for finfo in zfile.infolist():
            if finfo.filename == 'StockEtablissement_utf8.csv':
                handle_file(zfile.open(finfo))

        sys.exit(0)
    except Exception as e:
        sys.stderr.write(str(e))
        sys.exit(1)
