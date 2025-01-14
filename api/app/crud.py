"""
This file contains functions for working with peak data in a database.

The functions allow for getting, creating, and searching for peaks.
"""

from sqlalchemy.orm import Session
from sqlalchemy import func

from . import models, schemas


def get_parcel(db: Session, parcel_id: str) -> schemas.Parcel | None:
    """
    Retrieve a parcel from the database by ID.

    :param db: SQLAlchemy session object
    :param parcel_id: ID of the parcel to retrieve
    :return: The parcel object
    """
    return db.query(models.Parcel).filter(models.Parcel.id == parcel_id).first()