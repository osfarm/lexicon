# BSV Hauts-de-France — inventaire (vérifié le 08/11/2026)

## 1. Hébergeur
DRAAF Hauts-de-France (SPIP, thème DSFR) : https://draaf.hauts-de-france.agriculture.gouv.fr/
Contient tout : chaque BSV est un article de la DRAAF avec son PDF dans `/IMG/pdf/`. Pas de renvoi vers la chambre.
(L'ancienne URL `bulletins-de-sante-du-vegetal-bsv-a37.html` redirige en HTTP vers la rubrique r37.)

## 2. Point d'entrée et structure
Racine : https://draaf.hauts-de-france.agriculture.gouv.fr/les-bulletins-de-sante-du-vegetal-bsv-r37.html

Structure : rubrique filière → rubrique année (`2026-rNNN.html`) → liste paginée d'articles, **un article par
bulletin** (8 par page, pagination SPIP `?debut_listearticles=8,16,…`) → 1 PDF par article.

| Filière | Rubrique | 2026 | 2025 | 2024 | 2023 |
|---|---|---|---|---|---|
| Grandes cultures | grandes-cultures-r38.html | 2026-r736 | 2025-r716 | 2024-r673 | 2023-r553 |
| Arboriculture fruitière | arboriculture-fruitiere-r46.html | 2026-r737 | 2025-r717 | 2024-r672 | 2023-r552 |
| Pomme de terre | pomme-de-terre-r45.html | 2026-r735 | 2025-r715 | 2024-r679 | 2023-r555 |
| Cultures légumières | cultures-legumieres-r225.html | 2026-r739 | 2025-r714 | 2024-r701 | 2023-r551 |
| Lin fibre | lin-fibre-r227.html | 2026-r738 | 2025-r719 | 2024-r674 | 2023-r554 |
| Fruits rouges | fruits-rouges-r47.html | 2026-r741 | 2025-r724 | (aucune 2024) | 2023-r556 |
| JEVI | jardins-espaces-vegetalises-et-infrastructures-r48.html | 2026-r744 | 2025-r718 | 2024-r699 | (rien 2019-2023) |

URL complète : `https://draaf.hauts-de-france.agriculture.gouv.fr/2026-r736.html`, page suivante
`https://draaf.hauts-de-france.agriculture.gouv.fr/2026-r736.html?debut_listearticles=8`.

## 3. robots.txt
https://draaf.hauts-de-france.agriculture.gouv.fr/robots.txt :
```
User-agent: *
Disallow: /ecrire/
Disallow: /lib/
Disallow: /prive/
Disallow: /spip.php?action=*
Disallow: /spip.php?page=login*
Disallow: /*.api/
Crawl-delay: 1
```
`/IMG/pdf/`, les rubriques et la pagination `?debut_listearticles=` sont autorisés.

## 4. Filières 2026 (édition unique Hauts-de-France, pas de zones)
Nombre d'articles (= PDF) au 08/11/2026 :
- Grandes cultures : 43 (n°01 du 03/02 au n°43 du 03/11 ; deux par semaine au printemps)
- Pomme de terre : 29
- Cultures légumières : 27
- Arboriculture fruitière : 26
- Lin fibre : 17 (le n°17 est un bilan sanitaire)
- Fruits rouges (fraise) : 13
- JEVI : 6
Total ≈ 160. Pas de viticulture (le vignoble champenois de l'Aisne est dans le BSV Champagne du Grand Est),
pas d'horticulture.
Il existe aussi des articles hors série (bilans sanitaires par culture, « Messages campagnols » en 2019) rangés
dans les mêmes listes.

## 5. Profondeur des archives
Depuis 2016 (année de fusion : éditions Nord-Pas-de-Calais `edition-nord-pas-de-calais-r52.html`, Picardie
`edition-picardie-r53.html` et Hauts-de-France `editions-hauts-de-france-r201.html` sous grandes-cultures 2016).
Lin depuis 2020, fruits rouges depuis 2017 (rien en 2022 : rubrique « 2022 - Aucun bulletin publié en 2022 »).

## 6. Noms de PDF
Aucun motif commun : chaque filière (et parfois chaque année) a le sien. Date et numéro souvent présents mais sous
des formes différentes ; le **titre de l'article** (« BSV Grandes cultures n°43 du 03 novembre 2026 ») et son slug
sont, eux, réguliers : `bsv-<filiere>-no<N>-du-<J>-<mois>-<AAAA>-a<id>.html`.
- GC : `bsv_gc_n43_031126.pdf` (n + JJMMAA)
- Arbo : `bsv_af_no26_16_septembre_2026.pdf`
- PdT : `bsvpommedeterre29du8septembre2026.pdf`
- Légumes : `bsv_legumes_272026.pdf` (numéro + année, pas de date)
- Lin : `bsv_lin_no17_du_30_sept_2026_bilan_sanitaire_2025-2026.pdf`
- Fruits rouges : `bsv_13_fraises_290926.pdf`
- JEVI : `06_bulletinjevihdf2026.pdf` (pas de date)

Exemples complets :
- https://draaf.hauts-de-france.agriculture.gouv.fr/IMG/pdf/bsv_gc_n43_031126.pdf (vérifié : PDF 1.4, 8 pages, 2,3 Mo)
- https://draaf.hauts-de-france.agriculture.gouv.fr/IMG/pdf/bsv_af_no26_16_septembre_2026.pdf

## 7. Gênes pour un collecteur
- Un article par bulletin : une requête par BSV en plus de la liste (≈ 160 pages + 20 pages de liste pour 2026).
- Noms de PDF hétérogènes, parfois sans date : prendre la date et le numéro dans le titre de l'article
  (mois en toutes lettres, « 1er », fautes de frappe occasionnelles « Arboricuture »).
- Le numéro dans le slug ne correspond pas toujours au titre (ex. 2025 : slug `no18-du-9-juillet` pour le titre
  « n°19 du 2 juillet »).
- Ids de rubriques par année non prévisibles : partir de r37 → filière → année.
- HTML statique, pas de JavaScript ni formulaire.
