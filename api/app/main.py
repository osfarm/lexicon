from fastapi import Depends, FastAPI, HTTPException
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session

from geoalchemy2.elements import WKBElement
from shapely import wkb

from .database import SessionLocal, engine
from . import crud, models, schemas, config


# TODO mention WGS84 somewhere? (if it is indeed the system used)

models.Base.metadata.create_all(bind=engine)
app = FastAPI(title="LexiconAPI",version="0.0.1",debug=config.DEBUG)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# WKB* objects must be encoded to be to JSON-serializable
def encode_parcel(parcel: models.Parcel):
    return jsonable_encoder(
        parcel,
        custom_encoder={WKBElement: lambda x: str(wkb.loads(str(x)))}
    )

@app.get('/')
async def read_root():
    return "Welcome to Lexicon API."


@app.get('/parcels/{parcel_id}', response_model=schemas.Parcel)
async def read_parcel(
    parcel_id: str,
    db: Session = Depends(get_db),
):
    db_parcel = crud.get_parcel(db=db, parcel_id=parcel_id)
    if not db_parcel:
        raise HTTPException(
            status_code=404,
            detail='Parcel with given id not found.'
        )
    return encode_parcel(db_parcel)