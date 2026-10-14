# Bundles : reprise, avec Cultia comme premier destinataire

Exigences, relevé du 2026-10-13. Ce document ne décide ni de l'architecture ni
du code : il dit ce qui doit être vrai à la fin. Suite : `/sc:design`.

## 1. But

Cultia charge encore `6.1.0-cultia`, un package de l'ancien format, déposé à la
main dans son dépôt. Il doit charger le bundle `cultia` servi par le Lexicon
v2, le recevoir à jour sans intervention, et y trouver les prix d'intrants
(`fertilizers`, `fuel_prices`) qui n'existent pas dans l'ancien format.

## 2. Ce qui existe

| Maillon | État |
|---|---|
| `./lexicon bundle <flavor>`, flavors paramétrés | fait, testé |
| `./lexicon publish --bundle`, zone privée `_bundles/<flavor>/` | fait, testé |
| `./lexicon fetch <url>` (sha256, attente au quota) | fait, testé |
| Route `/bundles/<flavor>/` de l'API, portée `bundle:<flavor>` | en service : 401 sans clé. Contenu servi avec une clé : non vérifié |
| Clé d'API avec portée supplémentaire | interface d'administration et `bin/key.ts` |
| `out/bundles/cultia` | du 4 octobre, 31 packages, 214 Mo, périmé |
| `cultia_back/scripts/load_lexicon.py` | ne lit que l'ancien format (`lexicon.json`) |

## 3. Ce qui ne va pas

1. `resources/flavors/cultia.yml` est une liste d'exclusions, identique à
   `light.yml`. Toute datasource ajoutée depuis y entre par défaut :
   `hve_farms` (qui nomme des personnes), `alim_confiance`, `canteens`,
   `phytosanitary_purchases`, `pat`…
2. Le flavor coupe des dépendances : `quality_and_origin_signs`,
   `agricultural_schools`, `canteens` dépendent de `postal_codes`, exclu ;
   `commune_links` et `enterprise_links` de `cadastre` et `enterprises`, exclus.
3. Un bundle est réexporté depuis la base de build et reçoit sa propre version
   (`2026.10.04.1` dans le bundle, `2026.10.03.1` en service pour
   `administrative_areas`). On ne sait pas dire si Cultia a les mêmes données
   que l'API.
4. Chaque `bundle` réexporte toutes les datasources du flavor.
5. Rien ne rafraîchit un bundle : `ship` les ignore.
6. Rien ne dit quels bundles sont publiés, ni de quand ils datent.

## 4. Décisions prises

| # | Sujet | Décision |
|---|---|---|
| D1 | Périmètre | De bout en bout : flavor, bundle, publication, clé, chargeur dans `cultia_back`, chargement réel en base Cultia |
| D2 | Contenu | Liste blanche (`only`, que le format de flavor connaît déjà) |
| D3 | Jeux réservés | La portée `bundle:cultia` vaut accord pour tout ce que le flavor nomme, jeux `scope :members` compris |
| D4 | Mise à jour | Avec `ship` : une datasource mise en production est rafraîchie dans les bundles qui la contiennent |
| D5 | Jeux du bundle | Tout ce que `cultia_back` peut lire : voir B2 |
| D6 | Sources de `prices` | Dans le bundle : Cultia compare les prix |
| D7 | Version d'un jeu filtré | Un bundle suivi par `ship` ne filtre pas ; un bundle filtré garde sa propre version (§ 5, Versions) |
| D8 | `rd_agri` | Hors du bundle |
| D9 | Autres flavors | `ekyagri`, `ekyviti`, `natais`, `sydec`, `pv`, `innovation` retirés pour le moment. Restent `cultia`, `around`, `full`, `light`, `test` |

## 5. Exigences fonctionnelles

### Contenu du bundle

- **B1** — Le flavor `cultia` nomme ses datasources. Une datasource nouvelle
  n'entre dans le bundle que si on l'y ajoute.
- **B2** — Le bundle contient : `productions`, `rica`,
  `enterprise_classifications`, `technical_workflows`,
  `technical_workflow_sequences`, `intervention_models`,
  `agricultural_pictures`, `taxonomy`, `open_nomenclature`, `variants`,
  `units`, `budgets`, `chart_of_accounts`, `phytosanitary`, `prices`,
  `fertilizers`, `seeds`, `phytosanitary_prices`, `fuel_prices`, et les
  traductions de chacune. S'y ajoute ce que B3 impose (`seed_varieties` pour
  `seeds`, par exemple). Pas `rd_agri`.
- **B3** — Construire un bundle échoue, en nommant ce qui manque, quand une
  datasource retenue a une clé étrangère vers une datasource absente.
- **B4** — Un jeu `scope :members` entre dans un bundle parce que le flavor le
  nomme, jamais par défaut. Son manifest garde sa portée.
- **B5** — `master_translations` du bundle ne porte que les traductions des
  datasources retenues.

### Versions

- **B6** — Un flavor suivi par `ship` (B11) ne porte aucun filtre : il choisit
  des datasources, entières. Ses packages sont ceux qui sont publiés, même
  version et mêmes `sha256`. `index.json` du bundle dit donc, jeu par jeu,
  quelle version de production Cultia a chargée.
- **B7** — Un flavor qui filtre (`around`) reste construit à la demande depuis
  la base de build et garde une version à lui, comme aujourd'hui : ce qu'il
  contient n'est le package publié d'aucune version. Son manifest nomme le
  flavor et, pour information, la version locale dont il est tiré.
- **B7 bis** — Déclarer un flavor à la fois suivi et filtré est refusé au
  chargement du flavor.
- **B8** — Reconstruire un bundle ne refait que ce qui a changé.

### Mise à jour

- **B9** — `./lexicon ship <noms> --production` rafraîchit et republie, après
  la mise en service, chaque bundle dont le flavor contient l'un des noms.
  Sans `--production`, rien ne part.
- **B10** — Un bundle qui échoue ne défait pas la mise en production de la
  datasource : `ship` le dit et sort en erreur.
- **B11** — Un flavor déclare s'il est suivi par `ship`. Les flavors
  paramétrés (`around`) et ceux d'essai ne le sont pas.
- **B12** — `index.json` du bundle est envoyé en dernier : qui télécharge
  pendant une publication voit l'ancien bundle entier ou le nouveau entier.

### Suivi

- **B13** — `./lexicon status` montre, pour chaque bundle suivi, la version
  publiée de chaque jeu et celle en service, et signale les écarts.
- **B14** — Les versions qu'un bundle ne désigne plus sont retirées de la zone
  privée selon `resources/retention.yml`.

### Côté Cultia (`cultia_back`, spec § 14.4.1)

- **C1** — `scripts/load_lexicon.py` lit le format 3 : `index.json`, un
  `manifest.json` par jeu, `structure.sql`, `indexes.sql`, `data/*.csv.gz`.
- **C2** — Il télécharge le bundle depuis `LEXICON_BUNDLE_URL` avec
  `LEXICON_API_KEY`, et vérifie chaque `sha256`.
- **C3** — `lexicon/index.json`, commité, fige les versions chargées ; staging
  et production chargent le même. Il remplace `LEXICON_VERSION`.
- **C4** — Il ne recharge que les jeux dont la version diffère de celle en
  base. Un jeu qui échoue laisse le précédent en service ; plus de
  `DROP SCHEMA lexicon CASCADE`.
- **C5** — Il contrôle le nombre de lignes contre le manifest, pose les clés
  étrangères, recrée la vue `master_translations`, rejoue les droits Supabase.
- **C6** — La phase RICA (contrôle des tranches, `rica_group_stats`) ne tourne
  que si `rica` a changé, et le script rappelle alors de redémarrer l'API.
- **C7** — Les noms de tables et de colonnes que Cultia lit ne changent pas.
  Un écart entre `6.1.0-cultia` et le bundle est relevé avant la bascule.
- **C8** — Les dossiers `lexicon/6.*-cultia` sortent du dépôt une fois le
  format 3 chargé en production.

## 6. Exigences non fonctionnelles

- **N1** — La clé de Cultia ne vit que côté serveur de `cultia_back`.
- **N2** — La zone privée garde ses permissions (`D700,F600`) : le serveur de
  fichiers public ne sert jamais un bundle.
- **N3** — Rafraîchir un bundle après `ship` d'une datasource légère prend
  moins d'une minute.
- **N4** — Un bundle de quelques centaines de Mo se télécharge sans épuiser le
  quota d'une clé `standard` (à mesurer, Q2).
- **N5** — Tests : construction avec liste blanche, refus sur dépendance
  manquante, égalité des versions, `ship` qui suit un bundle ; côté Cultia,
  chargement d'un bundle d'essai sur une base jetable.

## 7. Recette

1. `./lexicon bundle cultia` ne produit que les jeux nommés, aux versions en
   service.
2. `./lexicon publish --bundle cultia --production`, puis
   `LEXICON_API_KEY=… ./lexicon fetch https://lexicon.osfarm.org/bundles/cultia`
   depuis une autre machine : tous les `sha256` concordent.
3. `./lexicon server sync` de ce bundle sur une base vide : aucun refus.
4. `python -m scripts.load_lexicon` sur la base de staging de Cultia : les
   tests de `cultia_back` passent, `registered_rica_holdings` a ses colonnes
   de tranche.
5. `./lexicon ship fuel_prices --production` : `index.json` du bundle désigne
   la nouvelle version ; un second `load_lexicon` ne recharge que `fuel_prices`.
6. Sans clé : 401. Avec une clé sans `bundle:cultia` : 403.

## 8. Questions ouvertes

- **Q1** — Le bundle en zone privée de production : y en a-t-il un, et de
  quand ? À lire avec la clé de Cultia une fois créée ; il sera remplacé de
  toute façon.
- **Q2** — Plan et quota de la clé de Cultia (N4), une clé ou deux (staging,
  production). La clé reste à créer.
- **Q3** — `fertilizers`, `seeds` et `phytosanitary_prices` portent les
  relevés par marchand. D3 les ouvre à Cultia ; ce que Cultia en montre à ses
  propres utilisateurs relève de `cultia_back`.
