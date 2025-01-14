from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

import time

from . import config


def wait_for_db(db_uri):
    """checks if database connection is established"""
    # this function is the only piece of code that has been found and
    # reused almost "as-is"
    # source: https://stackoverflow.com/a/69383016/12182226

    _local_engine = create_engine(db_uri)
    _LocalSessionLocal = sessionmaker(
        autocommit=False, autoflush=False, bind=_local_engine
    )

    MAX_ATTEMPTS = 10
    for i in range(MAX_ATTEMPTS):
        try:
            # try to create session to check if DB is awake
            db_session = _LocalSessionLocal()
            # try some basic query
            db_session.execute('SELECT 1')
            db_session.commit()
        except Exception:
            print(f'Waiting for DB, {i+1}/{MAX_ATTEMPTS}')
        else:
            break
        time.sleep(2)


SQLALCHEMY_DATABASE_URL = config.DATABASE_URI
wait_for_db(SQLALCHEMY_DATABASE_URL)

lexicon_schema = 'postgis,lexicon'

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"options": '-csearch_path={}'.format(lexicon_schema)}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
