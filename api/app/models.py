import uuid
from datetime import datetime
from sqlalchemy import Column, Integer, String

from geoalchemy2 import Geometry, WKBElement
from geoalchemy2.functions import ST_Area, ST_Perimeter, ST_AsGeoJSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import (
    Computed,
    Column,
    String,
    DateTime,
    Boolean,
    Float,
    ForeignKey,
    select,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column
from .database import Base


class Parcel(Base):
    __tablename__ = 'registered_graphic_parcels'
    __table_args__ = {"schema": "lexicon"}
    id = Column(String, primary_key=True, index=True)
    cap_crop_code = Column(String)
    city_name = Column(String)
    shape = Column(Geometry('MULTIPOLYGON', srid=4326))
    centroid = Column(Geometry('POINT', srid=4326))
