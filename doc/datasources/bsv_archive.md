# `bsv_archive` — archive des bulletins de santé du végétal (PestObserver)

Les textes de l'« Archive en agro-écologie de BSV » publiée sur data.gouv.fr par le projet PestObserver (CC-BY,
2016) : 40 829 fichiers, catalogue et texte intégral. Aucun risque n'en est extrait ; les bulletins d'aujourd'hui
sont dans [`bsv`](bsv.md).

| Table | Contenu |
|---|---|
| `registered_bsv_archive_documents` | un fichier : nature, régions, départements, filières, date, titre, texte, `search` |

## Ce que contient le corpus

- **Avertissements agricoles** (TEI XML, 17 286 fichiers, 1955–2010) des services régionaux de la protection des
  végétaux, découpés en parties et sections. OCR de qualité moyenne avant 2000.
- **BSV de 2009 à 2016** (texte, 23 542 fichiers), tels que les sites des DRAAF et des chambres les publiaient.
  Les colonnes sont parfois mal remises en ordre, les titres parfois espacés lettre à lettre.

Les PDF d'origine (37 Go) et les métadonnées annoncées par le projet (cultures, maladies, insectes, communes) ne
sont pas dans l'archive téléchargeable.

## Ce qui est déduit (`Documents`)

| Colonne | Avertissements (XML) | BSV (texte) |
|---|---|---|
| `kind` | `avertissement` (AA), `bulletin_technique` (BT), `bulletin_departemental` (BP) | `bsv`, `note` |
| `sectors` | code du nom : GC grandes cultures, TC toutes cultures, AF arboriculture, VG viticulture, CL cultures légumières, PDT pomme de terre | mots du nom de fichier, à défaut des premières lignes |
| `old_regions` | anciennes régions, département ou vignoble du nom (`Pays_de_la_Loire_Poitou_Charentes`, `Bas-Vivarais`) | domaine du site dans le nom, région du nom ou de l'en-tête, à défaut site de DRAAF, de chambre ou de FREDON le plus cité |
| `regions`, `department_codes` | par `data/bsv/old_regions.csv` (ancienne région → région d'aujourd'hui et départements) | idem |
| `published_on` | date du titre (« Le 16 Octobre 1984 »), à un an près de celle du nom | date du nom (`09_03_2010`, `20140707`, `2013.07.03`), à défaut des premières lignes |
| `year` | année du nom | année de la date, du nom ou de l'en-tête |

Ce qui ne se déduit pas reste vide. Au premier chargement : 16 % des BSV sans région, 7 % sans date ; 31 % des
avertissements sans date exacte (titres mal reconnus), tous avec leur année.

`search` : titre en poids A, texte en B, en français, accents retirés comme dans `rd_agri` et `bsv`.

## Construction

```bash
docker compose -f docker-compose-dev.yml exec -T lexicon_runner ./lexicon-cli run bsv_archive
```

`collect` télécharge `reportsOCR.zip` (173 Mo) une fois, dans `raw/bsv_archive/` ; `load` le lit sans le décompresser.
Le corpus ne change plus : on ne le reconstruit que si `old_regions.csv` ou la lecture changent.

## Côté API

Cherché avec les bulletins d'aujourd'hui par `/bsv/search` et l'outil MCP `search_plant_health_bulletins`, toujours
après eux ; un document se lit sous `/bsv/archive/<id>` (`lexicon-rest-api` 1.7.0, 2026-11-15). Il n'est pas sur la
page d'accueil : il ne partage aucune clé avec les autres jeux.
