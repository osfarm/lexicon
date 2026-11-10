# BSV Corse : inventaire (vu le 8 novembre 2026)

## 1. Hébergeurs
- **DRAAF** (`draaf.corse.agriculture.gouv.fr`, SPIP) : toutes les filières, y compris le JEVI, un article par bulletin, de 2021 à 2026. C'est la source principale.
- **Chambre d'agriculture de Corse** (`corse.chambres-agriculture.fr/agroambiente/ecophyto-bsv/bsv-<filiere>`, TYPO3) : une page par filière, avec une liste de PDF rangés par année (2023 à 2026). Elle n'a pas de page JEVI.
  - Elle est parfois **plus complète** que la DRAAF : en viticulture 2026, elle a 9 PDF (N°1 à 10, sauf le 9) contre 4 sur la DRAAF (N°5, 7, 8, 10).
  - Mais son robots.txt n'autorise pas son dossier de fichiers (voir §3).
- Aucun site ne contient tout.
- Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-corse) renvoie vers les deux sites.

## 2. Point d'entrée et structure
**DRAAF** : https://draaf.corse.agriculture.gouv.fr/les-bulletins-de-sante-du-vegetal-bsv-r53.html
→ une rubrique par filière → une rubrique par année → **un article par bulletin** → un PDF dans `IMG/pdf/`.
Les listes sont paginées par 8 (`?debut_listearticles=8`).

| Filière | Rubrique | 2026 | 2025 | 2024 | 2023 |
|---|---|---|---|---|---|
| Oléiculture | bsv-oleiculture-corse-r54 | 2026-bsv-oleiculture-corse-r458 | bvs-2025-oleiculture-corse-r426 | bsv-oleiculture-corse-2024-r399 | bsv-2023-oleiculture-corse-r353 |
| Arboriculture (noyau, coque) | bsv-arboriculture-corse-fruits-a-noyau-et-a-coque-r62 | — | bsv-2025-arboriculture-corse-r421 | bsv-2024-aboriculture-corse-r361 | bsv-2023-arboriculture-corse-r354 |
| Grandes cultures et fourrage | bsv-grandes-cultures-et-fourrage-corse-r138 | bsv-2026-grandes-cultures-et-fourrage-corse-r462 | …-2025-…-r440 | …-2024-…-r400 | …-2023-…-r352 |
| Agrumes et kiwi | bsv-agrumes-kiwi-corse-r65 | bsv-2026-agrumes-kiwi-corse-r459 | bsv-2025-agrumes-kiwi-corse-r433 | bsv-2024-agrumes-kiwi-corse-r387 | bsv-2023-agrumes-kiwi-corse-r357 |
| Viticulture | bsv-viticulture-corse-r61 | bsv-2026-viticulture-corse-r463 | bsv-2025-viticulture-corse-r432 | bsv-2024-viticulture-corse-r385 | bsv-2023-viticulture-corse-r358 |
| Maraîchage | bsv-maraichage-corse-r63 | bsv-2026-maraichage-corse-r460 | bsv-2025-maraichage-corse-r434 | bsv-maraichage-corse-2024-r388 | bvs-2023-maraichage-corse-r356 |
| JEVI | bsv-jevi-r64 | bsv-jevi-2026-r472 | bsv-jevi-2025-r430 | bsv-jevi-2024-r379 | (pas de 2022 ni de 2023 ; 2021 = r303) |

Toutes ces pages sont de la forme `https://draaf.corse.agriculture.gouv.fr/<slug>.html`, par exemple https://draaf.corse.agriculture.gouv.fr/bsv-2026-viticulture-corse-r463.html.

**Chambre** :
- Racine : https://corse.chambres-agriculture.fr/agroambiente/ecophyto-bsv
- Pages par filière : `…/bsv-agrumes-kiwis`, `…/bsv-arboriculture`, `…/bsv-fourrage-et-grandes-cultures`, `…/bsv-maraichage`, `…/bsv-oleiculture`, `…/bsv-viticulture`. Chaque page est une liste unique de PDF, avec l'année dans le chemin du fichier (chaque lien apparaît deux fois).

## 3. robots.txt
- **DRAAF** : `Disallow: /ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`, `/*.api/` et `Crawl-delay: 1`. `/IMG/pdf/` est **autorisé**.
- **Chambre** : `Disallow: /fileadmin/` et `Allow: /fileadmin/user_upload/244_chambres_d'agriculture_corse/`, **avec une apostrophe**. Or les PDF sont sous `/fileadmin/user_upload/244_chambres_dagriculture_corse/`, sans apostrophe. Lu à la lettre, le robots.txt **interdit donc ces PDF**. C'est probablement une coquille : demander à la chambre avant de s'en servir. Le `Sitemap:` déclaré pointe aussi vers un autre domaine (rd.agriculture-paca.fr).

## 4. Filières 2026
| Filière | DRAAF | Chambre |
|---|---|---|
| Oléiculture | ~12 (N°12 du 30/10) | 12 |
| Agrumes et kiwi | 8 (N°8 du 30/10) | 8 |
| Grandes cultures et fourrage | 6 (N°5 du 25/09) | 6 |
| Maraîchage | ~11 (N°11 du 15/09) | 10 |
| Viticulture | **4** (N°10 du 25/08) | 9 |
| JEVI | 7 (N°7 du 21/10) | pas de page |
| Arboriculture | **aucun BSV 2026** sur l'un ou l'autre site (dernier millésime : 2025) | |

Total : environ 48 PDF sur la DRAAF, et environ 53 bulletins distincts en réunissant les deux sites. Il n'y a pas d'édition infrarégionale.

## 5. Profondeur des archives
- DRAAF : **2021** pour toutes les filières (pas d'article BSV dans les sitemaps de 2020 et 2018).
- Chambre : 2023 (2024 pour GC et fourrage).

## 6. Noms des PDF
Sur la DRAAF, le motif est assez régulier : `bsv_<filiere>_<n>_<jour>_<mois en lettres>_<aaaa>.pdf`.
- `https://draaf.corse.agriculture.gouv.fr/IMG/pdf/bsv_viticulture_10_24_aout_2026.pdf`. Le titre de l'article dit 25 août et le fichier 24 août.
- `https://draaf.corse.agriculture.gouv.fr/IMG/pdf/bsv_oleiculture_12_30_octobre_2026.pdf`

Sur la chambre :
- `https://corse.chambres-agriculture.fr/fileadmin/user_upload/244_chambres_dagriculture_corse/BSV/Viticulture/2026/BSV_viticulture_10_24_aout_2026.pdf`
- Variantes : `BSV_viticuture_6_1_juillet_2026.pdf` (coquille), `BSV_GC-Fourrage_28_AOUT_2026.pdf` (sans numéro), `BSV_Agrumes_kiwis_1_17_avril_2026-PORT-MVRISTORI.pdf`.

## 7. Obstacles pour un collecteur
- La couverture est incomplète d'un côté comme de l'autre (viticulture DRAAF lacunaire, pas de JEVI sur la chambre). Il faudrait les deux sources et un dédoublonnage par filière, numéro et date, mais le robots.txt de la chambre bloque les PDF à la lettre.
- Les mois sont en lettres dans les noms de fichiers, parfois en majuscules.
- La date du nom peut différer d'un jour de celle du titre.
- Il y a des coquilles dans les slugs (`bvs-2025`, `aboriculture`) : il ne faut pas deviner les URL, il faut suivre les liens.
- Pas de JavaScript ni de formulaire.
