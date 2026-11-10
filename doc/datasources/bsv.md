# `bsv` — bulletins de santé du végétal

Chaque semaine, pour une région et une filière, le bulletin de santé du végétal (BSV) dit à quel stade en sont les
cultures, quels bioagresseurs sont observés et où, et le risque pour la semaine à venir. Les 13 régions
métropolitaines les publient en PDF sur les sites de leur DRAAF ; `data/bsv/sources.yml` dit où les trouver.
Chaque bulletin autorise sa reproduction, partielle avec la mention de sa source : chaque ligne porte le bulletin
dont elle vient (`citation`, `pdf_url`).

Conception et décisions : `claudedocs/design_bsv.md` ; essai des modèles : `claudedocs/brainstorm_bsv.md`.

| Table | Grain |
|---|---|
| `registered_bsv_bulletins` | un PDF : région, filière, zone, numéro, date, territoire (départements), état |
| `registered_bsv_pages` | une page d'un bulletin : son texte, et `search` (tsvector français, accents retirés) |
| `registered_bsv_risks` | une culture × un bioagresseur d'un bulletin : stade, BBCH, niveau de risque, citation |
| `registered_bsv_risk_places` | un lieu cité pour une observation, avec sa commune quand elle est sûre ; pas servi par l'API |

## Collecte

```
sites DRAAF ─► Crawler ─► raw/bsv/archive/<sha>.pdf         le PDF, nommé par son empreinte
                           <sha>.notice.json   où il a été vu : régions, adresses, titre, section, dates
                           <sha>.pages.json    le texte de chaque page (pdftotext)
                           <sha>.haiku.json    ce qu'a lu Haiku 5.5 (lot Anthropic)
                           <sha>.opus.json     ce qu'a lu Opus 5.5, pour quelques bulletins (contrôle)
                           <sha>.fix.json      la correction d'une lecture faite sous une ancienne consigne
                raw/bsv/batches/<id>.json      un lot envoyé, pas encore relevé
                raw/bsv/controls.csv           Haiku mesuré contre Opus, bulletin par bulletin
```

L'archive n'est jamais vidée : un site retire ses bulletins (Pays de la Loire réécrit sa page à chaque campagne),
le paquet les garde. Un PDF déposé à la main dans `raw/bsv/archive/` est lu comme les autres.

`collect` :

1. parcourt les rubriques SPIP de chaque DRAAF (une requête par seconde, `robots.txt` respecté) depuis l'an
   dernier, et télécharge les PDF inconnus ; un fichier tronqué ou qui n'est pas un PDF est refusé ;
2. lit le texte des nouveaux PDF (`pdftotext`) ;
3. relève les lots envoyés avant, puis envoie les bulletins pas encore lus à l'API Anthropic en un lot
   (Message Batches, moitié prix) : tous à Haiku 5.5, cinq de sections différentes aussi à Opus 5.5 ; attend la
   fin du lot jusqu'à 90 minutes, sinon la collecte suivante le relève ; un bulletin redemandé (erreur, réponse
   coupée) n'est jamais pris pour Opus ;
4. fait corriger les lectures faites sous une ancienne consigne (ci-dessous) ;
5. compare Haiku et Opus sur les bulletins lus par les deux, l'écrit dans `controls.csv` et le dit, en rouge sous
   80 % des lignes d'Opus retrouvées ou 85 % de niveaux identiques.

Une réponse coupée par la limite de jetons (32 000) est redemandée à la collecte suivante avec 64 000.

**Correction d'une lecture** (`Correction`). Changer la consigne ne relit rien : la version gardée dans chaque
réponse dit laquelle elle a suivie. Une lecture d'une ancienne version (qui a des lignes) est corrigée une fois :
Haiku reçoit le texte des pages (pdftotext, sans le PDF) et ses lignes numérotées, avec les règles de niveau de la
consigne du jour, et ne répond que les corrections (« ligne 12 → fort », « ligne 7 à supprimer »). Environ
0,0012 $ par bulletin, dix fois moins qu'une nouvelle lecture. La réponse va dans `<sha>.fix.json` avec le lot de
la lecture qu'elle corrige (`of`) ; `load` l'applique tant que cette lecture est celle de l'archive, la lecture
elle-même restant intacte (supprimer les `.fix.json` revient en arrière). Une correction ne rend jamais un niveau
`non_precise` : le texte n'a ni curseur, ni jauge, ni couleur, et un niveau lu sur le PDF serait perdu. Une ligne
supprimée garde son numéro (les identifiants des autres risques ne bougent pas). Essai sur 30 bulletins relus à la
main : 66 % de lignes `non_precise` avant, 60 % après, sans dégrader une ligne jugée juste.

`load` contrôle chaque réponse contre le texte, sans réseau (`Extraction`). Une ligne est refusée quand sa
citation (`extrait`) ne se retrouve pas dans le texte, quand sa culture est son bioagresseur, quand un code BBCH ou
Zadoks sort de 0–99. Le modèle lit la page mise en page, pdftotext mêle colonnes, tableaux et légendes : une
citation est retrouvée aussi quand ses mots viennent dans son ordre sur un court passage du texte, un mot sur dix
au plus manquant. Il dit les lignes refusées, les cultures absentes de `data/bsv/cultures.csv` et les zones
absentes de `data/bsv/zones.csv` : on complète ces fichiers à partir de ces listes.

Un nom de culture que `cultures.csv` ne tient pas est relu sans ce qui dit comment elle est conduite (« sous
abri », « plein champ », « hors sol »), au singulier, puis découpé en les cultures qu'il énumère (« poivron /
piment ») ; une zone, sans les mots qui l'introduisent (« territoire », « édition », « secteurs ») ni les numéros de
départements, et dans une autre région quand toutes lui donnent les mêmes départements.

| Variable | Défaut | Rôle |
|---|---|---|
| `ANTHROPIC_API_KEY` | (`.env`) | sans elle, les bulletins sont collectés mais pas lus |
| `LEXICON_BSV_SINCE` | l'an dernier | `archives` : jusqu'à `archives_since` de chaque région ; ou une année |
| `LEXICON_BSV_REGIONS` | toutes | slugs séparés par des virgules |
| `LEXICON_BSV_CRAWL` | | `no` : pas de parcours des sites, seulement le texte et la lecture |
| `LEXICON_BSV_ONLY` | | empreintes séparées par des virgules : ne lire que ces bulletins |
| `LEXICON_BSV_FROM` | l'an dernier | ne lire que les bulletins dont la première page est de cette année ou après (sans année lisible : pas lus) ; `all` : tous |
| `LEXICON_BSV_MAX_NEW` | 300 | au-delà, rien n'est envoyé : le relever en connaissance de cause (environ 0,004 $ par bulletin) |
| `LEXICON_BSV_MAX_FIX` | 300 | lectures à corriger au-delà desquelles rien n'est envoyé (environ 0,0012 $ par bulletin) |
| `LEXICON_BSV_WAIT` | 90 | minutes d'attente d'un lot |

Le wrapper ne transmet pas les variables : `docker compose -f docker-compose-dev.yml exec -T -e VAR=… lexicon_runner
./lexicon-cli run bsv`.

## État d'un bulletin (`status`)

| État | Sens |
|---|---|
| `extracted` | ses risques sont publiés |
| `catalogue_only` | bilan de campagne ou note : catalogue et texte seulement |
| `pending` | pas encore lu par l'API (ou une erreur à renvoyer) |
| `refused` | refus, réponse coupée trois fois, trois erreurs, ou PDF trop gros pour l'API |
| `unreadable` | publié tronqué : pdftotext ne l'ouvre pas, il n'est pas envoyé |
| `superseded` | une version corrigée du même bulletin (même région, filière, zone, numéro, année) a été vue plus tard : `superseded_by` |

`scanned` dit un PDF sans texte : il est lu sur les images, sa citation n'est pas contrôlée.

## Risques

- `level` : `nul`, `faible`, `moyen`, `fort`, `tres_fort`, `non_precise` (le bulletin n'évalue pas le risque de
  cette ligne). Un risque qui dépend des situations prend le niveau le plus haut, `conditional` et `condition`.
  Le modèle lit parfois « très faible » comme `tres_fort` : quand `level_text` dit « très faible » et rien de haut
  (fort, élevé, important, grave, sérieux, extrême, maximal, rouge), le niveau devient `faible` (`Levels`, compté
  par `load`). Une fourchette (« faible à moyen », « moyens à forts selon les secteurs », « faible voire nul »)
  prend son niveau le plus haut : un niveau plus bas que la plus haute fourchette du texte y est relevé, sauf quand
  le texte place un curseur (« curseur sur faible ») ou décrit une jauge (« l'échelle faible à fort »). Les autres
  désaccords sont laissés au modèle : une phrase nomme souvent plusieurs niveaux.
- `pest_type` : `maladie`, `ravageur`, `adventice`, `auxiliaire`, `physiologique`, ou `stade` pour une ligne qui
  ne dit que le stade de la culture (sans bioagresseur, ou avec un intitulé comme « stade phénologique »). Ce n'est
  pas un risque : `pest` est vide et `level` en général `non_precise`.
- `bbch_min`, `bbch_max` : écrits dans le bulletin, ou ses codes Zadoks, dont l'échelle BBCH des céréales reprend
  les nombres (Z30 = BBCH 30).
- `production_names` : les productions de Lexicon (`master_productions`) que le nom de culture désigne, d'après
  `data/bsv/cultures.csv` ; vide quand il n'y est pas.
- `source_quote` : la phrase du bulletin d'où vient la ligne, retrouvée dans son texte.
- Le territoire d'un bulletin (`department_codes`) : sa région, ou sa zone quand il en a une (`zones.csv`), et les
  régions qu'il dit couvrir.

Un risque extrait n'est pas une observation officielle : il est tiré du bulletin cité, qui fait foi.

## Couverture

`data/bsv/editions.csv` liste les éditions que publie chaque région (filière, zone, sous-filière, mois de parution,
nombre attendu en 2026). `load` les rapproche des bulletins lus (`Coverage`) et dit celles qui manquent (attendues
cette année, rien depuis le début de leur saison), celles en retard (rien depuis 15 jours en saison) et les
bulletins qu'aucune édition ne prend, par région, filière, zone et sous-filière : une édition à ajouter, ou un nom à
rapprocher. Filière, zone et sous-filière peuvent lister plusieurs noms séparés par « | » (« Champagne-Ardenne|
Champagne », « olivier|oléiculture ») ; un nom vide parmi eux prend les bulletins qui n'en donnent pas. Une
sous-filière se cherche aussi dans le libellé, le titre et le nom du fichier du bulletin ; deux zones se comparent par
leurs mots ou par leurs départements.

## Reprise des archives

Fait le 2026-11-09 : 17 375 bulletins depuis 2015 selon les régions (`archives_since`), 27 Go.

```sh
docker compose -f docker-compose-dev.yml exec -T -e LEXICON_BSV_SINCE=archives lexicon_runner ./lexicon-cli run bsv
```
