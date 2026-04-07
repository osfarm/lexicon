# CONVENTIONS.md

Conventions pour créer un jeu de données (datasource) dans Lexicon.

## Fichier et classe

- Créer `lib/datasources/mon_datasource.rb` (snake_case)
- La classe est CamelCase et hérite de `Datasources::Base`
- Le nom du datasource est dérivé automatiquement (underscore du nom de classe)

```ruby
module Datasources
  class MonDatasource < Base
    # ...
  end
end
```

## DSL de classe (obligatoire)

```ruby
description 'Description lisible du datasource'

credits(
  name: 'Nom de la source',
  url: 'https://url.source',
  provider: 'Fournisseur',
  licence: 'CC-BY-SA 4.0',
  licence_url: 'https://url.licence',
  updated_at: '2025-01-26'
)
```

Plusieurs appels à `credits` sont possibles si la donnée vient de plusieurs sources.

## Méthodes du cycle de vie

Toutes les méthodes doivent être définies (peuvent être vides) :

### `collect`

Télécharger ou copier les fichiers bruts dans `dir` (répertoire de travail).

```ruby
def collect
  # Téléchargement HTTP
  downloader.curl 'https://exemple.com/data.csv', out: 'data.csv'

  # Copie depuis data/
  FileUtils.cp Dir.glob('data/mon_datasource/*.csv'), dir

  # Extraction d'archive
  execute("7z x #{dir}/archive.7z -o#{dir}/extract -aoa")
  unzip(dir.join('archive.zip'), dir.join('extract'))
end
```

### `load`

Charger les fichiers bruts dans des tables temporaires du schéma `<datasource_name>`.

```ruby
def load
  load_csv(dir.join('data.csv'), 'nom_table')
  load_csv(dir.join('data.csv'), 'nom_table', col_sep: ';', encoding: 'ISO-8859-15')
  load_xls(dir.join('data.xls'))
  load_xlsx(dir.join('data.xlsx'))
  load_roo(dir.join('data.ods'), extension: 'ods')
  load_shp(dir.join('data.shp'), table_name: 'parcelles', srid: 2154)
end
```

### `normalize`

Transformer les tables temporaires en tables finales dans le schéma `lexicon`.

```ruby
def normalize
  query <<~SQL
    INSERT INTO ma_table (col1, col2)
      SELECT col1, col2::NUMERIC
      FROM #{name}.table_temporaire
  SQL
end
```

`#{name}` désigne le schéma temporaire du datasource — **toujours utiliser cette variable** pour référencer les tables de `load`.

## Déclaration des tables (`table_definitions`)

Obligatoire. Déclare le schéma final des tables produites dans `lexicon`.

```ruby
def self.table_definitions(builder)
  builder.table :registered_ma_table, sql: <<~SQL
    CREATE TABLE registered_ma_table (
      id character varying PRIMARY KEY NOT NULL,
      label character varying NOT NULL
    );
    CREATE INDEX registered_ma_table_id ON registered_ma_table (id);
  SQL
end
```

### Nommage des tables

| Préfixe | Usage |
|---|---|
| `master_*` | Données de référence interne (unités, traductions, variantes...) |
| `registered_*` | Données collectées depuis une source externe |

### Clés étrangères

```ruby
builder.table(:ma_table, sql: <<~SQL).references(
  colonne_fk: [:table_cible, :colonne_cible]
)
  CREATE TABLE ma_table (
    colonne_fk character varying NOT NULL,
    ...
  );
SQL
```

Les clés étrangères sont créées après `normalize` et référencent des tables du schéma `lexicon`.

### Types de colonnes courants

```sql
id character varying PRIMARY KEY NOT NULL
reference_name character varying PRIMARY KEY NOT NULL
label character varying NOT NULL
translation_id character varying NOT NULL     -- référence master_translations
value numeric(19,4)
shape postgis.geometry(Polygon, 4326) NOT NULL
centroid postgis.geometry(Point, 4326)
started_at timestamp
crop_names text[]                             -- tableau de valeurs
```

### Index

```sql
-- Colonne standard
CREATE INDEX ma_table_col ON ma_table (colonne);

-- Colonne géométrique (obligatoire pour PostGIS)
CREATE INDEX ma_table_shape ON ma_table USING GIST (shape);
```

## Traductions

Le pattern pour alimenter `master_translations` :

```ruby
def normalize
  query "DELETE FROM master_translations WHERE id LIKE 'ma_table%'"

  query <<~SQL
    INSERT INTO master_translations (id, fra, eng)
      SELECT CONCAT('ma_table_', reference_name), fra, eng
      FROM #{name}.table_source
  SQL
end
```

Format de l'identifiant : `<nom_table>_<reference_name>`.

## Données géographiques

- Toujours stocker en **SRID 4326** (WGS84) dans la table finale
- Transformer si la source utilise un autre SRID (ex : 2154 pour Lambert-93 France)
- Préfixer les fonctions PostGIS avec `postgis.`

```ruby
def normalize
  query <<~SQL
    INSERT INTO registered_parcelles (id, shape, centroid)
      SELECT id,
             postgis.ST_Transform(geom, 4326),
             postgis.ST_Centroid(postgis.ST_Transform(geom, 4326))
      FROM #{name}.parcelles
  SQL
end
```

## Données statiques (fichiers dans le dépôt)

Les fichiers de référence fournis avec le dépôt se placent dans `data/<datasource_name>/`.

```ruby
def collect
  FileUtils.cp Dir.glob('data/mon_datasource/*.csv'), dir
end
```

## Déclaration de ressources (alternative à `collect`)

Si les fichiers sont stables, les déclarer comme `resource` plutôt que d'écrire `collect` à la main.

```ruby
# Fichier local (copié depuis data/)
resource 'mon_fichier'
resource 'mon_fichier', source: 'chemin/relatif'

# Ressource distante (téléchargée et mise en cache)
resource 'ma_donnee', url: 'https://exemple.com/data.csv'
```

Quand des `resource` sont déclarées, le resource collector remplace `collect`.

## Intégration Python

Certains datasources délèguent à Python pour le traitement de données volumineuses.

```ruby
python :collect, :normalize  # ces méthodes sont implémentées en Python
```

Le code Python est dans `lib/datasources/<datasource_name>/__init__.py`.

## Chargement de données en masse (`COPY`)

Pour les gros volumes, utiliser `COPY` au lieu d'`INSERT` :

```ruby
def load
  database.copy_data "COPY ma_table (col1, col2) FROM STDIN" do |c|
    data.each { |row| c.call "#{row[0]}\t#{row[1]}\n" }
  end
end
```

## Tester un datasource

```sh
./lexicon run mon_datasource          # Pipeline complet
./lexicon collect mon_datasource      # Collecte uniquement
./lexicon load mon_datasource         # Chargement uniquement
./lexicon normalize mon_datasource    # Normalisation uniquement
./lexicon validate                    # Vérifier la conformité des schémas
```
