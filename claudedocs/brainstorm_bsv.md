# Bulletins de santé du végétal (BSV) dans Lexicon — cadrage

Brainstorm du 2026-11-08. Sources proposées : la page BSV de la chambre régionale de Nouvelle-Aquitaine, celle
d'Arvalis, la présentation du ministère, la base BSV d'Ecophytopic. Exigences seulement : la conception viendra
ensuite (`/sc:design`).

## Pourquoi

Le BSV est le bulletin hebdomadaire de l'épidémiosurveillance (plan Ecophyto, financé par l'OFB) : pour une région
et une filière, il dit à quel stade sont les cultures, quels bioagresseurs sont observés, où, et quel est le risque
pour la semaine. C'est la seule information publique, régulière et couvrant tout le pays sur l'état sanitaire des
cultures. Lexicon a déjà ce qu'il faut pour la relier : les stades BBCH (`phenological_stages`), les cibles des
produits phytosanitaires (`phytosanitary`), les communes (`postal_codes`, `administrative_areas`). Un client
d'Ekylibre ou de l'API pourrait savoir, pour sa culture et sa région, ce que le réseau observe cette semaine.

## Ce qu'on sait des sources (2026-11-08)

### Les bulletins

- Environ **3 500 bulletins par an** (ministère), publiés par les réseaux régionaux : un par région (ou ancienne
  région), filière et semaine, plus des bilans de campagne et des notes nationales. Nouvelle-Aquitaine seule :
  26 éditions en 6 filières (grandes cultures, viticulture, arboriculture, légumes et petits fruits, horticulture et
  pépinière, JEVI).
- **PDF seulement.** Ni API, ni flux, ni jeu de données ouvert. Un bulletin fait 4 pages (kiwi) à 17 pages (grandes
  cultures Aquitaine).
- **Le texte s'extrait** (`pdftotext`) sur les bulletins récents : ce ne sont pas des images. Les graphiques
  (piégeages, modèles) et certains tableaux sont des images.
- Structure d'un bulletin grandes cultures (N°31 Aquitaine du 2026-11-05, lu) : une page « Ce qu'il faut retenir »
  par culture et bioagresseur avec un niveau de risque (« risque fort dans les parcelles n'ayant pas dépassé le stade
  4-5 feuilles »), puis par culture : stades et avancement des semis (« 75 % des semis réalisés », « BBCH 0-13 »),
  et par bioagresseur des rubriques à peu près stables : **Observations** (avec des lieux : « Asques 33 »,
  « Issigeac 24 »), **Période de risque** (en stades BBCH), **Seuil indicatif de risque**, **Évaluation du risque**,
  méthodes alternatives. Les animateurs et la supervision DRAAF sont nommés en première page.
- **Conditions de reprise**, imprimées sur le bulletin : « Reproduction intégrale de ce bulletin autorisée.
  Reproduction partielle autorisée avec la mention « extrait du bulletin de santé du végétal Nouvelle-Aquitaine
  Grandes cultures N°X du JJ/MM/AA » ». Les sites DRAAF sont sous Licence Ouverte (etalab-2.0) sauf mention
  contraire. À vérifier région par région.

### Où les prendre

| Source | Ce qu'elle offre | Pour une collecte |
|---|---|---|
| Sites des **DRAAF** (`draaf.<région>.agriculture.gouv.fr`) | Une rubrique BSV par année, un article par édition, les PDF dans `IMG/pdf/` (42 PDF sur l'article grandes cultures Aquitaine 2026). Archives en ligne au moins depuis 2023 | **Meilleure entrée** : même moteur (SPIP) d'une région à l'autre, `robots.txt` ne l'interdit pas |
| Sites des **chambres régionales** | Les mêmes PDF, avec des noms prévisibles (`BSV_NA_<filière>_<n°>_<AAAAMMJJ>.pdf`) | **`robots.txt` interdit `/fileadmin/`**, où sont les PDF (Nouvelle-Aquitaine) : à éviter |
| **Ecophytopic**, base BSV | Index national : 149 fiches (une par région et filière), facettes région et filière, renvoi vers la source | Liste de contrôle de ce qui existe ; pas de PDF ni d'API |
| **Arvalis** | Renvoi vers des pages régionales (anciennes régions) | Inutile pour collecter |
| **Ministère** | Présentation (2016), liste des sites par région périmée | Inutile pour collecter |

### Les observations brutes

Les relevés parcelle par parcelle sont dans **Epiphyt**, système d'information de la DGAL, alimenté par les bases
régionales. L'export (Epiphyt-Extract) est réservé aux acteurs autorisés ; toute autre structure fait une demande
écrite à la DGAL (SDQSPV), qui décide après avis du comité national d'épidémiosurveillance (note de service de 2017,
état actuel non vérifié). Ce serait la meilleure donnée, mais pas une donnée ouverte.

### L'historique : PestObserver

Sur data.gouv.fr, « Archive en agro-écologie de BSV » (projet PestObserver, CC-BY, 2016) : **40 829 fichiers**,
457 Mo de texte. 23 542 fichiers texte (BSV des années 2009 à 2015, issus des sites DRAAF de l'époque) et 17 286
fichiers TEI XML (« Avertissements agricoles » des services régionaux de la protection des végétaux, depuis les
années 1960, découpés en parties et sections). OCR de qualité moyenne avant 2000 ; colonnes mal remises en ordre dans
les textes de BSV. La description annonce des métadonnées par fichier (région, cultures, maladies, insectes, risque,
communes, date, pesticides) qui ne sont pas dans l'archive téléchargée : à chercher (échantillon `EcologySample.rar`,
site `pestobserver.eu`). Les PDF d'origine (32 Go) sont annoncés sur `pestobserver.eu`.

### Contrainte technique connue

`phytosanitary` lit déjà des PDF avec Mistral OCR, mais l'annotation de document de Mistral s'arrête à **8 pages**
(`doc/datasources/phytosanitary.md`). Beaucoup de BSV dépassent : l'extraction ne pourra pas reprendre telle quelle
celle des dérogations.

## Décisions prises

| Sujet | Décision |
|---|---|
| Ce qu'on en tire | **Les risques extraits** : par bulletin, une ligne par culture et bioagresseur (risque, stade, période à risque, seuil, lieux), plus le catalogue des bulletins et leur texte |
| Périmètre | **France métropolitaine, toutes filières**, dès la première version (outre-mer exclu, voir plus bas) |
| Historique | **Avec PestObserver** : 1960–2016 en plus des bulletins en ligne, au **catalogue et en recherche plein texte seulement**, sans extraction des risques (2026-11-08) |
| Accès | **Ouvert**, servi par l'API et un outil MCP, chaque ligne renvoyant à son bulletin |
| Epiphyt | **On fait sans.** Une demande d'accès peut être adressée à la DGAL (SDQSPV) en parallèle ; rien n'en dépend (2026-11-08) |
| Reprise | **Les autres régions autorisent la même reprise** que la Nouvelle-Aquitaine : extrait cité avec la mention du bulletin (2026-11-08) |
| Extraction | **API Anthropic, Batches, PDF envoyé tel quel** (Claude voit les pages : curseurs, jauges, tableaux en couleurs). **Claude Haiku 5.5** extrait tous les bulletins, avec une consigne resserrée (exhaustivité, pas de niveau tiré d'une observation) ; **Claude Opus 5.5** extrait un échantillon chaque semaine pour mesurer l'écart. Le modèle local a été essayé et abandonné le même jour (voir « Essai du 2026-11-08 ») (2026-11-08) |
| Bulletins 2016–2022 | **Tant pis pour le moment** (2026-11-08) |
| Échelle de risque | **5 niveaux** : nul, faible, moyen, fort, très fort, le texte d'origine toujours gardé (2026-11-08) |
| Outre-mer | **Non** pour la première version : métropole seulement (2026-11-08) |
| Relecture | **David JOULIN** relit un échantillon avant la première publication (2026-11-08) |
| Codes Zadoks | **Convertis en BBCH** (les codes Z et BBCH des céréales coïncident) ; le code d'origine reste dans le texte du stade (2026-11-08) |
| Risque conditionnel | **Niveau le plus haut, avec un drapeau `conditionnel`** et le texte de la condition (2026-11-08) |
| Territoire d'un bulletin | **Liste de départements**, déduite de la zone et des régions nommées ; un bulletin commun à plusieurs régions les couvre toutes (2026-11-08) |
| Date | **Celle de l'en-tête**, plus la date à laquelle Lexicon a vu le bulletin la première fois ; un écart de plus de 10 jours est signalé (2026-11-08) |
| Contrôle Opus | **5 bulletins par semaine**, tirés dans des filières différentes (environ 0,60 $ par semaine) (2026-11-08) |
| Lieux cités | **Gardés avec leur code INSEE, pas exposés** par l'API ni le MCP pour le moment (2026-11-08) |
| Bilans et notes | **Catalogue et texte seulement**, sans lignes de risque (2026-11-08) |
| Noms de cultures | **Nom du bulletin gardé, rattaché à la construction** à une ou plusieurs productions de Lexicon par une table de `data/bsv/` ; les noms inconnus sont listés (2026-11-08) |
| Absence, observation, tendance | **Pas de niveau** (`non_precise`) : seule l'évaluation du risque par le bulletin donne un niveau, « nul » seulement si le risque est dit nul (consigne resserrée, 2026-11-08) |

## Exigences fonctionnelles

### Collecte

- **F1 — Catalogue.** Tous les bulletins publiés, région par région : région émettrice et zone (édition Aquitaine,
  Limousin…), départements couverts, filière, sous-filière (kiwi, fruits à noyau…), numéro, date de publication
  (celle de l'en-tête), date de première collecte, nature (bulletin, bilan de campagne, note), URL d'origine,
  empreinte du PDF. Les bilans et les notes n'ont que leur entrée au catalogue et leur texte.
- **F2 — Accumulation.** Les PDF s'accumulent dans `raw/` et ne sont jamais effacés ; un bulletin retiré du site
  reste. Un bulletin déjà lu n'est pas relu : un build rejoué sans réseau redonne le même paquet.
- **F3 — Couverture contrôlée.** Le build compare ce qu'il a collecté à l'index d'Ecophytopic (149 fiches, dont
  outre-mer, hors périmètre) et dit
  quelles régions et filières n'ont rien donné, ou rien depuis plus de deux semaines en saison.
- **F4 — Rythme.** Chaque semaine, avec la routine des intrants.

### Extraction

- **F5 — Texte.** Le texte intégral de chaque bulletin, page par page, pour la recherche (accents retirés, comme
  `rd_agri`).
- **F6 — Risques.** Pour chaque bulletin, une ligne par culture × bioagresseur (ou par culture seule pour les stades) :
  culture, bioagresseur (nom tel qu'écrit) et son type, stade observé (texte, et BBCH min–max quand il est donné,
  codes Zadoks convertis), niveau de risque (nul, faible, moyen, fort, très fort, ou non précisé, plus le texte
  d'origine et un drapeau `conditionnel` quand le niveau dépend d'une condition), période à risque, seuil
  indicatif, observations (texte court), lieux cités, page du bulletin, phrase source.
- **F7 — Lieux.** Les lieux cités (« Asques 33 ») rattachés à un code INSEE quand c'est possible ; la zone du
  bulletin rattachée à ses départements.
- **F8 — Rattachements.** Culture vers la production de Lexicon, bioagresseur vers les cibles de `phytosanitary`,
  stade vers `phenological_stages`, quand ils existent ; le nom d'origine est toujours gardé.
- **F9 — Contrôle.** Une extraction est refusée, et le build le dit, quand elle ne retrouve pas la date ou le numéro
  du bulletin, ou cite un bioagresseur ou une culture absents du texte, ou un stade BBCH hors de 0 à 99. Comme pour
  les dérogations, un refus n'empêche pas les autres bulletins d'entrer.

### Historique

- **F10 — PestObserver.** Les 40 829 fichiers entrent au catalogue avec leur texte (recherche plein texte), leur
  région (ancienne région), leur date et leur filière quand elles se déduisent. Pas d'extraction de risques pour eux.
  Les métadonnées annoncées par PestObserver (cultures, maladies, insectes), si on les retrouve, s'ajoutent au
  catalogue telles quelles.
- **F11 — Anciennes régions.** Une table de passage ancienne région → région actuelle et départements, pour qu'une
  question posée sur une commune trouve aussi les bulletins anciens.

### Service

- **F12 — API.** Les risques en cours pour une région ou une commune, une culture et une semaine ; l'historique d'un
  bioagresseur sur une région ; la recherche plein texte ; le lien vers chaque PDF.
- **F13 — MCP.** Un outil qui répond à « quels risques sur mon colza à Agen cette semaine ? » : les lignes du
  dernier bulletin de la zone, avec la mention de source exigée et le lien.
- **F14 — Mention.** Chaque ligne extraite porte la référence du bulletin dans la forme imposée par le bulletin
  (« extrait du bulletin de santé du végétal <région> <filière> N°X du JJ/MM/AA ») ; l'API et le MCP la rendent.

## Exigences non fonctionnelles

- **N1 — Politesse.** Une requête par seconde au plus par site, un `User-Agent` qui dit qui collecte, respect de
  `robots.txt` (donc pas les chambres quand elles l'interdisent).
- **N2 — Coût et durée.** L'extraction passe par l'API Batches (moitié prix, rendu en moins d'une heure en
  pratique) : environ 0,004 $ par bulletin avec Haiku 5.5, 0,12 $ avec Opus 5.5 (essai du 2026-11-08). Haiku sur
  les 3 500 bulletins d'une année : une quinzaine de dollars ; le contrôle par Opus, quelques dollars par semaine
  selon la taille de l'échantillon.
- **N7 — Contrôle.** Chaque semaine, un échantillon de bulletins (de filières différentes) est extrait aussi par
  Opus 5.5 ; le build dit, pour cet échantillon, la part de lignes manquantes et de niveaux différents entre les
  deux, et le signale au-delà d'un seuil. Celle d'un bulletin est
  gardée par empreinte et jamais refaite, sauf changement du modèle ou des consignes, qui se décide.
- **N3 — Exactitude affichée.** Ce qui est extrait par un modèle est dit tel quel : chaque ligne garde le texte
  d'origine dont elle est tirée, et l'API ne présente jamais un risque extrait comme une observation officielle.
- **N4 — Données personnelles.** Les animateurs nommés et leurs adresses électroniques ne sont pas repris dans les
  tables (le PDF reste lié).
- **N5 — Volume.** Le paquet hebdomadaire ne change que si un bulletin est nouveau (`source_date`, pas de version
  sans changement).
- **N6 — Robustesse.** Le changement de gabarit d'un site régional n'arrête pas la collecte des autres ; il est
  signalé par F3.

## User stories et critères d'acceptation

1. **Conseiller ou agriculteur, par le MCP** : « Quels risques sur mon colza à Agen cette semaine ? »
   - L'outil situe Agen (47) dans l'édition Aquitaine, prend le dernier bulletin grandes cultures, rend grosse
     altise (risque fort avant 4-5 feuilles), charançon du bourgeon terminal, limaces, pucerons cendrés, avec la
     mention et le lien du N°31 du 2026-11-05.
2. **Ekylibre** : afficher, en face d'une culture de l'exploitation, les alertes de la zone de la semaine.
   - Une requête par région, culture et date rend les lignes du dernier bulletin, rattachées à la production
     d'Ekylibre quand le rattachement existe.
3. **Chercheur ou technicien** : suivre la pyrale du maïs en Alsace depuis 1990.
   - La recherche plein texte rend les bulletins d'Alsace qui la citent, PestObserver compris, triés par date ;
     les lignes extraites s'y ajoutent pour les bulletins récents.
4. **Mainteneur** : savoir chaque lundi ce qui manque.
   - Le build liste les régions et filières sans bulletin nouveau et les bulletins refusés, avec leurs raisons.

## Essai du 2026-11-08

19 bulletins de pleine saison (Nouvelle-Aquitaine 9, Occitanie 3, Pays de la Loire 7 ; toutes filières, 4 à 25
pages), une même consigne d'extraction et un même schéma JSON.

| Méthode | Lignes | Sans niveau | Remarques |
|---|---:|---:|---|
| Qwen3 8B en local (Ollama, RTX 4070 SUPER), texte `pdftotext` | — | — | Arrêté à 9 bulletins : niveaux inventés (« fort » pour la PSA du kiwi, que le bulletin ne note pas), un bulletin parti en boucle (312 lignes en 15 min) |
| Claude dans la session, texte `pdftotext` (référence) | 408 | 74 % | Fidèle au texte, toutes les citations retrouvées ; mais les niveaux dessinés sont perdus |
| Claude Opus 5.5, API Batches, PDF | 421 | 58 % | Lit les curseurs et les jauges et le dit (« curseur Mouches à 3 ») ; même niveau que la référence sur 275 des 312 lignes appariées, 32 niveaux en plus tirés des images, 2 désaccords |
| Claude Sonnet 5.5, API Batches, PDF | 373 | 43 % | Déduit des niveaux absents du bulletin (« à surveiller » → moyen) : écarté |
| Claude Haiku 5.5, API Batches, PDF | 377 | 62 % | Lit aussi les curseurs ; même niveau qu'Opus sur 227 des 248 lignes appariées ; tend à prendre une intensité observée pour un risque (« populations faibles » → faible) ; moins complet (JEVI Nouvelle-Aquitaine 11 lignes contre 23, pépinière 9 contre 26). Coût : environ 0,08 $ pour les 19 bulletins |
| Claude Haiku 5.5, consigne resserrée | 454 | 65 % | Plus complet qu'Opus (JEVI Nouvelle-Aquitaine 27 lignes, pépinière 29) ; aucun niveau qu'Opus n'a pas ; 14 niveaux en moins, dont la moitié sont des « non présent » qu'Opus (consigne de départ) notait nul et que la consigne resserrée laisse sans niveau, et quelques jauges ou « risque élevé » manqués. Coût : environ 0,09 $ |

- **Le texte seul ne suffit pas** : beaucoup de bulletins donnent leur évaluation en curseurs, jauges ou tableaux
  en couleurs (maraîchage et grandes cultures des Pays de la Loire, fraise-framboise, pépinière).
- **Beaucoup de bulletins ne donnent pas de niveau** du tout (« période à risque », « à surveiller », tendances) :
  même bien lus, plus de la moitié des lignes restent `non_precise`. C'est la donnée, pas un défaut d'extraction.
- **Coût mesuré** (Batches, moitié prix) : Opus 5.5 590 000 tokens en entrée et 116 000 en sortie pour 19 bulletins,
  environ 2,40 $ ; Sonnet 5.5 environ 1 $ ; Haiku 5.5 environ 0,08 $ (191 000 tokens en sortie).
- **Défauts des bulletins eux-mêmes**, relevés à l'essai : paragraphes restés d'un bulletin précédent, titres de
  rubrique faux, dates contradictoires (en-tête, mention de reproduction, nom de fichier), bulletins communs à
  plusieurs régions.
- Fichiers de l'essai gardés dans `claudedocs/bsv_essai/` : la consigne resserrée, le script d'extraction par
  l'API Batches, le tableau de relecture (voir son `README.md`).

## Questions ouvertes

- ~~Q1 — Epiphyt~~ : tranchée le 2026-11-08, on fait sans ; une demande à la DGAL peut partir en parallèle.
- ~~Q2 — Licence région par région~~ : tranchée le 2026-11-08, les autres régions autorisent la même reprise.
- ~~Q3 — Extraction~~ : tranchée le 2026-11-08 après essai : API Anthropic (Batches), PDF entier, Claude Opus 5.5.
- ~~Q4 — Coût de l'historique~~ : tranchée le 2026-11-08, catalogue et recherche plein texte seulement. Reste à
  retrouver les métadonnées annoncées par PestObserver (`EcologySample.rar`, `pestobserver.eu`).
- ~~Q5 — Bulletins 2016–2022~~ : tant pis pour le moment (2026-11-08). Pour mémoire : PestObserver s'arrête en 2016 et les sites DRAAF semblent remonter à 2023 :
  les années entre les deux sont-elles quelque part (archives des chambres, Ecophytopic, demande aux DRAAF) ?
- ~~Q6 — Échelle de risque~~ : 5 niveaux (2026-11-08). Pour mémoire : Les bulletins écrivent leurs risques en texte libre (« faible à modéré », « fort dans
  les parcelles… ») : faut-il une échelle commune à 5 niveaux, ou garder le texte et une échelle seulement quand
  elle est sans ambiguïté ?
- ~~Q7 — Lieux~~ : tranchée le 2026-11-08, gardés avec leur code INSEE, pas exposés.
- ~~Q8 — Outre-mer~~ : non pour la première version (2026-11-08). Pour mémoire : Les bulletins des Antilles, de la Réunion et de Mayotte (cultures tropicales, publication
  mensuelle à Mayotte) entrent-ils dès la première version ?
- ~~Q9 — Revue métier~~ : David JOULIN (2026-11-08).

## Hors périmètre

- Produire un conseil ou un risque propre à Lexicon : on reprend ce que disent les bulletins.
- Les modèles de prévision (Aphibox, outils Terres Inovia) cités par les bulletins.
- Les graphiques et courbes de piégeage des bulletins (images).
- Les notes nationales et guides de l'observateur au-delà de leur entrée au catalogue.

## Prochaines étapes

1. ~~Trancher Q1, Q2 et Q4~~ : fait le 2026-11-08.
2. ~~Essai d'extraction~~ : fait le 2026-11-08 (voir « Essai du 2026-11-08 »). Reste la relecture par David
   (`relecture_bsv.csv`). Les règles de consigne sont tranchées (2026-11-08, tableau des décisions).
3. Inventaire des sites DRAAF : une ligne par région, rubrique BSV, profondeur des archives, gabarit (F1, F3, Q5).
4. Conception (`/sc:design`) : découpage en jeux (catalogue et texte, risques, historique), schéma, rattachements.
