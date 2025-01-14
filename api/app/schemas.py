from typing import List

from pydantic import BaseModel, computed_field

from geoalchemy2.types import WKBElement

from typing_extensions import Annotated

class Parcel(BaseModel):
    id: str
    cap_crop_code: str
    city_name: str
    shape: str
    centroid: str
  
    class Config:
        orm_mode = True

# as-is, the following should not be the current file
class BoxSearch(BaseModel):
    lon_min: float  # xmin
    lat_min: float  # ymin
    lon_max: float  # merry xmax
    lat_max: float  # ymax


class RangeSearch(BaseModel):
    range_in_meters: int
    lat: float
    lon: float
