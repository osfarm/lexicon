# Datasource `rd_agri` — Plateforme R&D Agricole

Documents publiés sur [rd-agri.fr](https://rd-agri.fr) (ACTA, APCA, DGER), reliés
aux référentiels Lexicon. Conception détaillée : `claudedocs/design_rd_agri.md`.

Licence des contenus : **CC BY-NC-SA 4.0**, sauf mention contraire dans la
notice. Toute réutilisation doit citer rd-agri comme auteur principal.

## Tables produites

| Table | Contenu |
|---|---|
| `registered_rd_agri_documents` | Un document : titre, description, année, dates, publicateur canonique, langue, mots-clés, projet, URL |
| `registered_rd_agri_document_productions` | Document → `master_productions` |
| `registered_rd_agri_document_taxa` | Document → `master_taxonomy` (lien précis, avant élargissement aux productions) |
| `registered_rd_agri_document_areas` | Document → `registered_administrative_areas` (région, département) |
| `registered_rd_agri_document_production_systems` | Document → `master_nomenclatures` (`production_systems`) |
| `registered_rd_agri_document_pests` | Document → cible E-phy ou `master_nomenclatures` (`issue_natures`) |

Chaque lien porte `channels`, qui indique d'où il vient :
- `keyword` : mots-clés des auteurs ;
- `label` : labels d'enrichissement retrouvés dans le titre ou la description ;
- `title` : titre ;
- `project_code` : préfixe GIEE du code projet ;
- `organism` : nom d'un organisme ;
- `override` : ajout manuel.

La colonne **Auteurs** de l'export n'est jamais chargée : ce sont des données
nominatives.

## Prérequis

`rd_agri` lit des tables produites par d'autres datasources et échoue si elles
sont vides :

```sh
./lexicon run taxonomy productions open_nomenclature administrative_areas phytosanitary
./lexicon run industry_sector rd_agri
```

## Mettre à jour les données

1. Sur https://rd-agri.fr, lancer une recherche **sans filtre**, puis exporter
   les résultats en CSV (bouton d'export des résultats).
2. Déposer le fichier dans `raw/rd_agri/`, sous n'importe quel nom. `collect`
   retient l'export « Documents » d'après ses en-têtes. Si plusieurs exports
   sont présents, il prend le plus récent. Les exports « Projets » et « Jeux de
   données » sont ignorés.
3. Mettre à jour `updated_at` dans les `credits` de `lib/datasources/rd_agri.rb`.
4. `./lexicon run rd_agri`, après les prérequis.
5. Relire les statistiques du journal : part des documents liés par table et
   par canal.

## Ajuster les liens (`data/rd_agri/`)

| Fichier | Rôle |
|---|---|
| `keyword_mappings.csv` | Mot-clé auteur → filière `industry_sector`, production, ou `ignore`. S'applique aussi aux titres. |
| `publishers.csv` | Libellé de publicateur → libellé canonique (comparaison insensible à la casse et à la ponctuation) |
| `languages.csv` | Langue saisie → code ISO 639-2 |
| `giee_regions.csv` | Préfixe de code projet GIEE → code région |
| `pest_exclusions.csv` | Termes génériques exclus des ravageurs et maladies (pluriel toléré) |
| `area_exclusions.csv` | Noms de zones ambigus ignorés dans les titres (« Rhône », « Nord »…) |
| `taxon_expansion_exclusions.csv` | Couples taxon → production à ne pas relier (« Colza » ≠ rutabaga) |
| `overrides.csv` | Corrections manuelles, voir ci-dessous |

`overrides.csv` : `document_id,target_kind,target,action`.
- `action` vaut `add` ou `remove`.
- Format de `target` selon `target_kind` :

| `target_kind` | `target` | Exemple |
|---|---|---|
| `production` | `reference_name` | `milk_cow` |
| `taxon` | `reference_name` | `bos` |
| `production_system` | `name` | `organic_farming` |
| `area` | `kind:code` | `region:53` |
| `pest` | `source:référence` | `issue_nature:mammite`, `ephy_target:Pucerons` |

Une cible inconnue fait échouer `normalize`.

## Revue de précision

```sql
SELECT channel, d.title, dp.production
  FROM (SELECT document_id, production, unnest(channels) AS channel
          FROM registered_rd_agri_document_productions) dp
  JOIN registered_rd_agri_documents d ON d.id = dp.document_id
 WHERE channel = 'label'
 ORDER BY random() LIMIT 50;
```
