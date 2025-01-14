<p align="center">
<img align="center"  width="200" src="logo-pique.png">
</p>

<h1 align="center"> Pique API </h1>


**Pique API** is a FastAPI-based web service for accessing and managing `Mountain Peaks`. It uses a PostGIS-enabled PostgreSQL database for storage and querying.

## Disclaimer
**Pique API** is a small example project and has no real-world use case. As such, minimal or no support will be provided.

## Prerequisites
- Docker
- Python (for testing only)

## Installation

Clone this repository:
```shell
git clone https://github.com/vgalin/pique-api.git
```

CD into the cloned directory and run a docker-compose build:
```shell
cd pique-api
docker-compose build
```

Start the Docker containers:
```shell
docker-compose up
```
The API will then be available at `http://localhost:80`.
## Usage
### Endpoints

- `GET /`: Welcome message
- `GET /peaks/{peak_id}`: Retrieve peak with specified ID.
- `GET /peaks/`: Search for peaks within a specified box or range.
- `POST /peaks/`: Create a new peak.
- `PUT /peaks/`: Update a  peak.
- `DELETE /peaks/`: Delete a peak.

When the API is running, its full documentation is available at `http://localhost/docs` or `http://localhost/redoc`.

### `GET /peaks/` Query parameters

As `GET /peaks/` is the only non trivial endpoint, here is a quick explanation of its parameters.

The `/peaks/` endpoint supports the following query parameters for searching peaks within a box:
- `lon_min`: The minimum longitude of the box.
- `lat_min`: The minimum latitude of the box.
- `lon_max`: The maximum longitude of the box.
- `lat_max`: The maximum latitude of the box.

Alternatively, the following query parameters can be used to search for peaks within a specified range:
- `range_in_meters`: The range to search within, in meters.
- `lat`: The latitude of the center of the range.
- `lon`: The longitude of the center of the range.

## Testing
Tests are run from the local machine.

Install the Python packages required for testing:
```shell
python -m pip install -r requirements-tests.txt
```

Run the tests (while being at the root directory of this repository):
```shell
python -m pytest
```

## Going further

- Different configuration for dev/prod
- Better way to query using `GET /peaks/`
- Homogenize in/out format? (lat/long integers in input VS WKT in output)
- Github actions
- Extend existing tests

## License

This project is licensed under the MIT License.