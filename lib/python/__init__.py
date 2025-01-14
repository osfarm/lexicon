import os
import psycopg2


def db_connect():
    host = os.environ.get('POSTGRES_HOST')
    database = os.environ.get('POSTGRES_DB')
    user = os.environ.get('POSTGRES_USER')
    password = os.environ.get('POSTGRES_PASSWORD')

    return psycopg2.connect(host=host, database=database, user=user, password=password)
