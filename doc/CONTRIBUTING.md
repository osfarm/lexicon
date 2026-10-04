# How to contribute

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Declaring what a datasource publishes](#declaring-what-a-datasource-publishes)
- [Tests](#tests)
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

### Declaring what a datasource publishes
A datasource declares its output tables in `self.table_definitions(builder)`, and a few facts used when it is packaged (see [PUBLICATION.md](PUBLICATION.md)):

```ruby
class Agropowa < Base
  description 'Equipment catalog of Agropowa'
  credits name: '...', url: '...', provider: '...', licence: '...', licence_url: '...', updated_at: '2026-10-04'

  schema_revision 2              # bump it when a published table changes shape
  depends_on :open_nomenclature  # datasources read during normalize, without a foreign key
  translations :equipments       # prefixes of the ids written in master_translations
  scope :members                 # only for data reserved to API key holders
  pivot :commune, table: :agropowa_dealers, column: :postal_code   # a key shared with other datasets
  personal_data 'Legal entities only'   # why columns that look personal can be published
end
```

`./lexicon new agropowa > lib/datasources/agropowa.rb` prints a skeleton with these declarations.

Foreign keys declared with `.references(...)` already give the dependencies between datasources; `depends_on` is only for the others. A table belongs to one datasource only.

### Checking a contribution
```sh
./lexicon check --static     # every datasource, from its declarations
./lexicon check agropowa     # one datasource: declarations, then the data it built
```
An error blocks the contribution: missing description, credits, licence or source date; a licence that is not open on a datasource that is not reserved with `scope :members`; a column that looks like personal data without a `personal_data` reason; an empty table; a link rate under the declared `minimum`; less than 70 % of the rows of the previous version. Data about natural persons is not accepted.

The static check, RuboCop and the unit tests run on every pull request (`.github/workflows/ci.yml`). The checks on built data are run by the maintainers. See [PUBLICATION.md](PUBLICATION.md) §12.

### Tests
Unit tests live in `test/` and run in the container:
```sh
docker compose -f docker-compose-dev.yml run --rm -T -v "$PWD/test:/lexicon/test:ro" lexicon_runner \
  sh -c 'for f in test/lexicon/*/*_test.rb; do bundle exec ruby -Itest $f || exit 1; done'
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