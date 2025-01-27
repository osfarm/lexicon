**Module `GraphicParcels` Documentation**

The `GraphicParcels` module is a part of the larger `Datasources` namespace, designed to handle the collection, loading, and normalization of graphic parcel data from various zones and regions. This documentation provides an overview of its main components, methods, and usage.

#### Class Variables
- **LAST_UPDATED**: A string representing the last update date for the graphic parcel data.
- **description**: A brief description of the module's purpose.
- **credits**: Metadata about the data source, including name, URL, provider, license information, and the last updated timestamp.
- **ZONES**: A hash containing the zone names as keys and their corresponding projection codes as values.
- **REGIONS**: A hash containing the zone names as keys and an array of region identifiers as values.

#### Methods
- **collect**: This method downloads and extracts graphic parcel data from IGN's website based on the defined zones and regions. Manual file download may be needed if automatic download fails.
- **create_table_command(file, proj: nil, table:, search_path: []):** Generates a shell command to create a PostgreSQL table using `shp2pgsql` based on the provided parameters.
- **import_shp_command(file, proj: nil, table:, search_path: [])**: Generates a shell command to import shapefile data into a PostgreSQL table using `shp2pgsql` with the provided parameters.
- **load**: This method loads graphic parcel data into a PostgreSQL database. It first loads city data from a local shapefile, then iterates through the defined zones and regions to load the corresponding parcel data into temporary tables using multiple threads for efficiency. Finally, it waits for all threads to finish executing before exiting the load task.
- **table_definitions(builder)**: A class method that defines SQL commands for creating the `registered_graphic_parcels` table in the database.
- **normalize**: This method normalizes graphic parcel data by inserting it into the `registered_graphic_parcels` table, updating city names based on barycenter locations, and handling conflicts during insertion to avoid duplicates.

#### Usage
To use the `GraphicParcels` module, follow these steps:
1. Define your zones and regions in the `ZONES` and `REGIONS` class variables.
2. Implement the necessary setup and configuration for your data processing framework.
3. Call the `collect` method to download and extract graphic parcel data from IGN's website. If automatic download fails, manually download the required files.
4. Call the `load` method to load the extracted data into a PostgreSQL database.
5. Call the `normalize` method to normalize the loaded data and insert it into the final table (`registered_graphic_parcels`).