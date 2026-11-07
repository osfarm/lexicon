# `phytosanitary` — produits phytopharmaceutiques et leurs usages

Ouvert. Construit chaque semaine avec les intrants (`intrants.md`, « Chaque semaine »).

## Sources

| Source | Ce qu'elle apporte | Lecture |
|---|---|---|
| E-Phy (ANSES), data.gouv.fr | produits, usages, mentions de danger, permis de commerce parallèle | XML par `__init__.py`, CSV des usages |
| Ministère de l'Agriculture, [AMM de 120 jours au plus](https://agriculture.gouv.fr/produits-phytopharmaceutiques-autorisations-de-mise-sur-le-marche-dune-duree-maximale-de-120-jours) | dérogations de l'article 53 du règlement (CE) 1107/2009 : usages qu'E-Phy ne publie pas, et produits qu'il ne connaît pas | page et PDF, lus par Mistral OCR (`Derogations`) |
| `data/phytosanitary/*.csv` | cropsets, exceptions de cultures, symboles, cibles PFI | fichiers du dépôt |

Tables : `registered_phytosanitary_products`, `_usages`, `_risks`, `_cropsets`, `_symbols`,
`_target_name_to_pfi_targets`.

## Dérogations de 120 jours

Le ministère publie une décision par PDF, et seulement pendant sa validité. Le 2026-11-07, 37 décisions, toutes
cultures (canne à sucre, bananier, olivier, kiwi, porte-graines, tomate…) ; 22 de leurs AMM sont dans E-Phy (la
dérogation y ajoute un usage), 10 n'y sont pas.

### Ce que fait chaque phase

- **collect** : lit la page (gardée en `raw/phytosanitary/derogations/page_<date>.html`), télécharge les PDF qu'il
  n'a pas, et fait lire par Mistral OCR ceux qui n'ont pas encore de lecture. Un échec (page changée, PDF absent,
  Mistral indisponible) est affiché et n'arrête pas la collecte d'E-Phy.
- **load** : contrôle chaque lecture et écrit les tables brutes `derogation_products`, `derogation_usages`,
  `derogation_risks` et `derogations_refused`, sans réseau.
- **normalize** : ajoute les produits absents d'E-Phy, puis les usages, avant le rapprochement des espèces.

### L'archive

`raw/phytosanitary/derogations/` n'est jamais vidé : c'est elle qui garde une décision une fois retirée de la page.
Chaque PDF y est nommé par son empreinte (24 premiers caractères du SHA-256), avec :

- `<sha>.notice.json` : ce que la page en disait (cultures, organisme, substance, délivrance, échéance), le premier
  et le dernier jour où elle l'a listé ;
- `<sha>.ocr.json` : la réponse de Mistral, champs (`document_annotation`) et texte des pages. Elle n'est demandée
  qu'une fois : un build rejoué sans réseau ni clé redonne le même paquet.

Une décision qui n'est plus sur la page s'ajoute en déposant son PDF dans le répertoire ; la collecte suivante la lit.

### Lecture et contrôles

Mistral OCR reçoit le PDF en base64 avec un schéma JSON strict (`Derogations::SCHEMA`) ; la clé est
`MISTRAL_API_KEY` du `.env`. Une décision est **refusée**, et listée par `load` avec ses raisons, quand :

- l'AMM lue n'a pas 7 chiffres, ou diffère de celle de la page ou de celle du texte (« Numéro d'AMM ») ;
- les dates lues diffèrent de celles du texte (« délivrée en France du … au … »), finissent avant de commencer, ou
  couvrent plus de 130 jours ;
- elle n'a pas d'usage, ou un usage a un code qui n'est pas un nombre, une phrase sans `*`, une dose négative, un
  stade BBCH hors de 0 à 99 ;
- elle a plus de 8 pages (limite de Mistral).

Deux PDF d'une même décision (même AMM, même début : une décision corrigée) : celui que la page a listé en dernier
l'emporte. Une même AMM à une autre date est une autre décision ; les deux restent.

### Dans les tables

Usage dérogatoire, dans `registered_phytosanitary_usages` :

- `id` : `DEROG:{amm}:{code}:{milieu}:{AAAAMMJJ du début}`, milieu `plein_champ`, `sous_abri` ou `na` ;
- `lib_court` : le code de l'usage, celui du catalogue E-Phy. La phrase, la culture, la cible et le traitement sont
  ceux d'un usage E-Phy de même code quand il y en a un, sinon tirés de la phrase comme le fait `__init__.py` ;
  l'espèce passe ensuite par les cropsets, la nomenclature et `exceptions`, comme pour E-Phy ;
- `usage_conditions` : la culture à laquelle l'usage est restreint et son milieu, le nombre d'applications tel
  qu'écrit, les dates, puis les conditions d'emploi de la décision ;
- `pre_harvest_delay` : 3 jours quand la décision n'en donne pas, comme pour E-Phy ;
- `state` : `authorized` si le jour du build est dans la dérogation, `withdrawn` sinon ;
- `is_derogation`, `derogation_started_on`, `derogation_stopped_on`, `derogation_url` (le PDF sur le site du
  ministère).

Produit absent d'E-Phy, dans `registered_phytosanitary_products` : `product_type` `DEROGATION`, `is_derogation`,
`state` `authorized` tant qu'une de ses décisions court, `started_on` et `stopped_on` de la première et de la dernière,
mentions de danger dans `registered_phytosanitary_risks`. Un produit E-Phy n'est jamais modifié, même retiré : une
AMM dérogatoire qui entre dans E-Phy y prend sa ligne E-Phy.

### Limites

- L'état est celui du jour du build : une dérogation qui finit un mercredi reste `authorized` jusqu'au lundi. La date
  exacte est dans `derogation_stopped_on`.
- Un produit retiré d'E-Phy dont une dérogation court (MOVENTO, DESOGERME le 2026-11-07) garde `state` `withdrawn` :
  un client qui exige un produit et un usage `authorized` ne voit pas cet usage.
- Les décisions publiées avant la première collecte ne sont pas dans l'archive, sauf PDF déposé à la main.
- Première collecte, le 2026-11-07 (paquet 2026.11.07.1, en production le même jour) : 37 décisions sur la page,
  toutes lues ; 30 gardées (51 usages), 7 refusées. MOVENTO : AMM lue 2110086, 2249997 sur la page. AMISTAR et
  ESSEN'CIEL : stades BBCH mal lus (5010 et 9005 ; fin à 9 pour un début à 89 ou 91). AVADEX FACTOR, MERLIN FLEXX,
  REVYONA, VINAIGRE D'ALCOOL : phrase d'usage sans `*` (« Bananier », « Orge désherbage »), que le contrôle refuse.
- La clé Mistral est `MISTRAL_API_KEY` du `.env` du poste de build ; le conteneur `lexicon_runner` ne la lit qu'à sa
  création : `docker compose -f docker-compose-dev.yml up -d --force-recreate lexicon_runner` après l'avoir changée.
