# Essai d'extraction des BSV (2026-11-08)

Ce qui reste de l'essai décrit dans `../brainstorm_bsv.md` (« Essai du 2026-11-08 »), gardé comme base de la
conception.

| Fichier | Contenu |
|---|---|
| `consigne_extraction.md` | La consigne resserrée donnée au modèle (prompt système) : forme du JSON, échelle de niveau, ce qui donne ou non un niveau, exhaustivité |
| `extract_claude.py` | Le script de l'essai : envoie les PDF à l'API Batches d'Anthropic avec la consigne en cache et un schéma JSON strict, puis relève les réponses et contrôle que chaque phrase source se retrouve dans le texte du PDF |
| `relecture_bsv.csv` | Les 421 lignes extraites par Claude Opus 5.5 sur 19 bulletins, avec en regard le niveau de la référence (extraction dans la session, sur le texte), de Sonnet 5.5 et de Haiku 5.5 (première consigne) ; colonnes « juste ? » et « correction » à remplir |

La consigne ne reprend pas encore les décisions prises après l'essai : conversion des codes Zadoks, drapeau
`conditionnel`, départements couverts, date de première collecte (tableau des décisions du cadrage).

Le script tourne dans un conteneur, la clé lue dans le `.env` :

```sh
docker run --rm -u 1000:1000 -e HOME=/tmp -e ANTHROPIC_API_KEY="$(grep '^ANTHROPIC_API_KEY=' .env | cut -d= -f2-)" \
  -v <dossier>:/w -w /w python:3.12-slim sh -c \
  'python -m venv /w/venv && /w/venv/bin/pip install -q anthropic &&
   /w/venv/bin/python extract_claude.py submit bsv bsv/out claude-haiku-5-5 &&
   /w/venv/bin/python extract_claude.py collect bsv bsv/out'
```

`<dossier>/bsv/` contient `consigne_extraction.md`, `sample/*.pdf` et `txt/*.txt` (sortie de `pdftotext`). Les
19 PDF de l'essai ne sont pas gardés : ils sont listés dans `relecture_bsv.csv` et se retrouvent sur les sites des
DRAAF de Nouvelle-Aquitaine, d'Occitanie et des Pays de la Loire.
