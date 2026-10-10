# Proposer un jeu de données à partir d'un tableau

Pour ajouter au Lexicon un jeu de données qui tient dans un ou plusieurs tableaux, il n'y a pas de code à
écrire : un dossier, une fiche, et les tableaux en CSV.

Le guide du contributeur, avec ce que répond `./lexicon contribute` et ce qu'il faut faire à chaque réponse, est
aussi sur le site : <https://lexicon.osfarm.org/contribute> (page écrite dans `lexicon-rest-api`,
`src/contribute/Guide.ts` ; la tenir à jour quand un message de `Contribution::Review` change).

## 1. Le dossier

Un dossier par jeu, dans `data/contributions/`, nommé en minuscules sans accent ni espace :

```
data/contributions/releves_sol/
├── dataset.yml      la fiche
└── releves.csv      le tableau
```

Un tableau trop gros pour le dépôt (plusieurs dizaines de Mo) se range dans `raw/releves_sol/`, sous le même nom de
fichier : `raw/` n'est pas versionné, seule la fiche est commitée. Lexicon lit le tableau à côté de la fiche d'abord,
dans `raw/` sinon.

## 2. Le tableau

Depuis un tableur, « Enregistrer sous » au format CSV, encodage UTF-8, séparateur virgule.

- La première ligne donne le nom des colonnes, en minuscules, sans accent ni espace : `insee_code`, pas « Code INSEE ».
- Une colonne identifie chaque ligne : jamais vide, jamais deux fois la même valeur.
- Les dates s'écrivent `2026-09-30`, les nombres avec un point (`12.5`), les oui/non `true` ou `false`.
- Une date avec son heure s'écrit `2025-12-04T17:00:53+01:00` ; sans décalage
  horaire (`+01:00`), l'heure est prise pour du temps universel.
- Un point géographique tient dans une case, latitude d'abord : `48.811873,2.211849`.
- Une case vide veut dire « pas de valeur ».

## 3. La fiche

`./lexicon new releves_sol --tabular` en écrit le modèle. Elle dit ce qu'est le jeu, d'où il vient, sous quelle
licence, et ce que contient chaque colonne :

```yaml
description: Relevés d'humidité des sols par commune
author: Camille Martin, GAEC des Prés
source:
  name: Relevés de sondes capacitives
  url: https://exemple.org/sondes
  provider: GAEC des Prés
  licence: Licence Ouverte 2.0
  licence_url: https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf
  date: 2026-09-30
tables:
  - file: releves.csv
    key: id
    columns:
      id: text
      insee_code: text
      measured_on: date
      value: number
    pivots:
      insee_code: commune
```

| Rubrique | Sens |
|---|---|
| `author` | qui propose le jeu ; son nom figure dans les crédits |
| `source.licence` | une licence ouverte (Licence Ouverte, CC-BY, ODbL…). Sinon, ajouter `scope: members` : le jeu est alors réservé aux adhérents |
| `source.date` | la date des données, pas celle du dépôt |
| `key` | la colonne qui identifie chaque ligne |
| `columns` | chaque colonne du fichier et son type : `text`, `integer`, `number`, `date`, `boolean`, `datetime` (date et heure), `point` (latitude,longitude) |
| `pivots` | les colonnes qui portent un identifiant connu du Lexicon : `commune` (code INSEE), `department`, `siren`, `siret` (établissement), `cadastral_parcel`, `cap_crop_code`, `taxon`, `production`, `weather_station`, `amm`, `variant`. C'est ce qui relie le jeu aux autres |
| `personal_data` | à remplir seulement si une colonne ressemble à une donnée personnelle (nom, courriel, téléphone) : dire pourquoi elle peut être publiée |

Une commune sans code INSEE : quand le tableau ne porte que le code postal et le nom de la commune, désigner les
deux colonnes sous `pivots`, l'une `commune_postal_code`, l'autre `commune_name`. À la construction, le Lexicon
ajoute une colonne `insee_code` : le code de la commune de ce code postal qui porte ce nom (sans tenir compte des
majuscules, des accents, des traits d'union ni de « Saint » abrégé). Une ligne dont le nom n'est celui d'aucune
commune de son code postal reste sans code ; un code postal seul ne suffit pas, il couvre plusieurs communes. Le
jeu `postal_codes` doit être construit avant.

Plusieurs tableaux : une entrée par fichier sous `tables`. Chacun devient une table `registered_<jeu>_<fichier>` ;
`table:` permet de choisir un autre nom, qui commence par `registered_`.

## 4. Vérifier

```sh
./lexicon contribute releves_sol
```

La commande relit le dossier comme le fera un mainteneur et dit, ligne à l'appui, ce qui est à corriger :

```
  à corriger : « releves.csv », colonne « value » : 2 valeurs ne sont pas un nombre, avec un point pour les
               décimales (ligne 2 « 12,5 », ligne 5 « abc »).
  à corriger : « releves.csv » : 1 valeur de « id » revient plusieurs fois (r2).
[ NOK ] releves_sol : 2 points à corriger avant de proposer le jeu.
```

Elle n'a besoin d'aucune base de données et ne publie rien.

### Dans un navigateur

```sh
./lexicon contribute --web
```

Sur un poste qui n'a jamais servi au Lexicon, il suffit de Docker et du dépôt : voir
[INSTALL.md](INSTALL.md), « Contribution tool only ».

Dans une page, <http://localhost:8787>, sans écrire la fiche à la main :

1. donner un nom au jeu ;
2. déposer le tableau tel qu'il est : CSV (virgule, point-virgule ou tabulation, UTF-8 ou non), Excel (`.xlsx`,
   `.xls`) ou LibreOffice (`.ods`). Ses colonnes sont reconnues et renommées en minuscules sans accent, leur type
   est deviné (texte, nombre entier, nombre, date, oui/non), les valeurs sont remises en forme (`12,5` devient
   `12.5`, `01/09/2026` devient `2026-09-01`, `oui` devient `true`), la colonne qui identifie chaque ligne est
   choisie (ou ajoutée s'il n'y en a pas) et les codes de commune, de département, SIREN et AMM sont reconnus
   comme des liens. La page dit tout ce qu'elle a fait ;
3. vérifier ce qui a été reconnu et le corriger dans le tableau des colonnes ;
4. remplir « D'où vient le jeu » : la relecture dit au fur et à mesure ce qui reste.

Il n'y a rien à enregistrer ni à recharger : chaque changement est écrit dans la fiche et relu aussitôt. Un
fichier enregistré directement dans le dossier est proposé à la reconnaissance, et la page suit ce qui change sur
le disque. La fiche reste modifiable en YAML, en bas de page. `Ctrl-C` arrête l'interface.

Une colonne de codes (`code_postal`, `siret`, `id`…) reste du texte, pour garder ses zéros ; une colonne où une
seule valeur ne suit pas la règle reste du texte, et rien n'y est changé.

L'interface ne répond que sur le poste (`127.0.0.1`) et n'écrit que dans `data/contributions/`. Un autre port :
`LEXICON_CONTRIBUTE_PORT=8800 ./lexicon contribute --web`.

### En ligne, sans rien installer

Le même outil est servi sur <https://lexicon.osfarm.org/contribute/outil> aux détenteurs d'une clé d'API du Lexicon.
On y entre avec sa clé ; chaque clé a son espace, où l'on ne voit que ses propres jeux, gardés sur le serveur. Un
tableau déposé y pèse au plus 50 Mo, et une clé garde au plus 20 jeux. Un gros tableau part par morceaux et se lit
en quelques dizaines de secondes : la page affiche l'avancement et se met à jour toute seule. Au-delà de 50 Mo,
installer l'outil sur son poste, où le tableau se range dans `raw/<nom>/`. Quand la relecture ne trouve plus rien à
corriger, le bouton « Proposer ce jeu » le signale aux mainteneurs ; « Retirer la proposition » revient en arrière.

## 5. Proposer

Quand la commande répond `[ OK ]`, envoyer le dossier : par une demande de fusion sur le dépôt, ou à un
mainteneur d'OSFarm. En ligne, le bouton « Proposer ce jeu » suffit. Rien n'est mis en service sans la relecture
d'un mainteneur.

## Côté mainteneur

Le dossier suffit : au démarrage, Lexicon en fait une datasource comme les autres (`./lexicon list` la montre).

Un jeu proposé en ligne se rapatrie d'abord sur le poste, d'où il suit le même chemin :

```sh
./lexicon contribute --proposed --production               # ce qui est proposé : <espace>/<nom>, auteur, description
./lexicon contribute --fetch ab12cd34/releves_sol --production   # le dossier arrive dans data/contributions/releves_sol/
```

Sans `--production`, les deux commandes regardent la pile de service locale (`out/contributions`).

```sh
./lexicon contribute releves_sol            # la relecture
./lexicon ship releves_sol                  # construit, contrôle, empaquette, publie en local, attend le loader
./lexicon ship releves_sol --production     # la même chose, puis la production
```

Ce qu'un tableau ne sait pas faire : télécharger sa source, transformer les données, porter une autre géométrie qu'un point, se
lier à un autre jeu par une clé étrangère. Pour cela, écrire une datasource Ruby (`./lexicon new <nom>`,
[CONTRIBUTING.md](CONTRIBUTING.md)).
