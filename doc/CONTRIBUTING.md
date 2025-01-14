# How to contribute

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Helpers](#helpers)
- [Do we store data on repository?](#do-we-store-data-on-repository)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

To add a new datasource, you'll need to create a code file in `lib/datasources/`.
For example, if we want to create a datasource to get all models of equipment of
the firm Agropowa, we'll create a file `lib/datasources/agropowa.rb`

```ruby
module Datasources
  class Agropowa < Base
    def self.description
      'Equipment catalog of Agropowa'
    end

    # This method permit to execute the collect action. No data treatment here
    # Only download or retrieving.
    def collect
      execute "curl 'http://agropowa.com/equipment/catalog.xls' > #{dir}/catalog.xls"
    end

    # This method permit to define how to load the raw data into the database
    # Helpers exists:
    #  - load_xls, load_xlsx can import spreadsheet as a set of tables directly
    def load
      load_xls "#{dir}/catalog.xls"
    end

    # Create the data in the target schema from the previously imported data
    def normalize
      query 'CREATE TABLE IF NOT EXISTS equipment (vendor VARCHAR NOT NULL, name VARCHAR NOT NULL)'
      query "INSERT INTO equipment (vendor, name) SELECT 'Agropowa', nom_equipement FROM tracteurs"
      # Add here more cleaning code if necessary
    end
  end
end
```

When the file is written, you can test it:
```sh
./lexicon run agropowa
```
This command will run all the process for Agropowa datasource only. Each step
can be run separately:
```sh
./lexicon collect agropowa
./lexicon load agropowa
./lexicon normalize agropowa
```

### Helpers
List of available helpers:
- `execute(command)` Execute a command for a shell
- `load_csv(file)` Load CSV file in DB
- `load_xls(file)` Load XLS file in DB
- `load_xlsx(file)` Load XLSX file in DB
- `query(sql)` Execute an SQL query in working DB by default
- `unzip(source, destination)` Extract a zip file into given destination

### Do we store data on repository?
Data storage strategy must defined depending on the format and the size of the
datasources. Textual format should always be storable by default if not all
change at each update.