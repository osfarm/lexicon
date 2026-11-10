# BSV Bretagne — inventaire (relevé du 08/11/2026)

## 1. Hébergeurs
- **Chambre régionale d'agriculture de Bretagne** (TYPO3) : **contient tout** — les 8 éditions, y compris les
  légumes de transformation absents de la DRAAF depuis 2022 —, une page par filière avec tous les PDF 2022-2026,
  et robots.txt autorise son dossier. Source recommandée.
- **DRAAF Bretagne** (SPIP) : un article par bulletin (1 PDF par article), rubrique par filière ; archives
  2016-2021 en sous-rubriques annuelles. Pas de légumes de transformation après 2021.
- Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-bretagne) renvoie aux deux, sans PDF.

## 2. Points d'entrée et structure
### Chambre
https://bretagne.chambres-agriculture.fr/mes-productions/bulletins-techniques/bsv (dernier numéro de chaque édition)
→ une page par édition, tous les PDF de 2022 à 2026 sur la même page :
- .../bsv/bsv-grandes-cultures-bretagne
- .../bsv/bsv-legumes-frais-de-bretagne
- .../bsv/bsv-legumes-de-transformation-en-bretagne
- .../bsv/bsv-pommes-de-terre
- .../bsv/bsv-arboricultures
- .../bsv/bsv-cultures-ornementales
- .../bsv/bsv-jevi-bretagne
- .../bsv/bsv-lin
(préfixe https://bretagne.chambres-agriculture.fr/mes-productions/bulletins-techniques). Pas de page par année :
l'année est dans le chemin du fichier
`/fileadmin/user_upload/303_chambre_dagriculture_de_bretagne/1-Dossiers/2_Prod/2_Agro/5_BSV/<code filière>/<AAAA>/`
avec code ∈ {1_GC, 2_LF, 3_LT, 4_PDT, 5_Cultures_Arbo, 6_Cultures_Orne, 7_JEVI, 9_Lin}.

### DRAAF
Rubrique mère : https://draaf.bretagne.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-bsv-r34.html
→ rubriques par filière (tous les bulletins depuis 2022, paginés par 8 : `?debut_listearticles=N`) :
- grandes-cultures-r689.html (~195 articles, de bsv-gc-no1-du-15-02-2022-a2652 à bsv-gc-no32-du-03-11-2026-a4050)
- legumes-frais-r691.html (~97), pommes-de-terre-r694.html (~60), cultures-ornementales-et-jevi-r693.html (~92),
  arboriculture-fruits-transformes-r696.html (~108), lin-r862.html (~11)
→ un article par bulletin (titre avec n° et date, ex. bsv-gc-no32-du-03-11-2026-a4050.html) → 1 PDF.
Archives 2016-2021 : archives-grandes-cultures-r487.html (→ grandes-cultures-2016-r35 … -2021-r634),
archives-legumes-frais-r493, archives-legumes-industrie-r494 (2016-2021), archives-pommes-de-terre-r495,
archives-cultures-ornementales-et-jevi-r496, archives-arboriculture-fruits-transformes-r497.
Pas d'URL dédiée à 2026, 2025, 2024 ou 2023 sur aucun des deux sites (l'année est dans le titre de l'article DRAAF
ou dans le dossier du PDF chez la chambre).

## 3. robots.txt
- Chambre :
  ```
  Disallow: /fileadmin/
  Allow: /fileadmin/user_upload/FAL_COMMUN/
  Allow: /fileadmin/user_upload/303_chambre_dagriculture_de_bretagne/
  ```
  → PDF BSV autorisés (ils sont sous `303_chambre_dagriculture_de_bretagne/`).
- DRAAF : SPIP standard (Disallow `/ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`,
  `/*.api/` ; `Crawl-delay: 1`) → `/IMG/pdf/` autorisé.

## 4. Éditions 2026 (PDF dans le dossier 2026 de la chambre)
| Édition | 2026 | 2025 | 2024 | 2023 | 2022 |
|---|---|---|---|---|---|
| Grandes cultures | 32 | 38 | 38 | 39 | 37 |
| Légumes frais | 19 | 19 | 17 | 20 | 21 |
| Légumes de transformation | 23 | 24 | 22 | 22 | 24 |
| Pomme de terre | 7 | — | 8 | 18 | 17 |
| Arboriculture fruits transformés (interrégional Bretagne-Normandie-PdL) | 22 | 23 | 22 | 19 | 19 |
| Cultures ornementales | 10 | 10 | 11 | 14 | 10 |
| JEVI | 9 | 11 | 9 | — | — |
| Lin | 10 | — | — | — | — |
Édition régionale unique (pas de zones). Total 2026 ≈ 132 PDF.

## 5. Archives
Chambre : 2022. DRAAF : 2016 (sous-rubriques d'archives), continu depuis 2022 dans les rubriques filières.

## 6. Noms de PDF
Chambre (motifs variables par filière, date presque toujours présente) :
- `BSV_Grandes_Cultures_n32_2026_11_03.pdf`, `BSV_pomme_de_terre_n7_2026_07_23.pdf`, `BSV_arbo_fruits_transformes__n22_2026_09_09.pdf` (AAAA_MM_JJ)
- `BSV_legumes_frais_N__19_du_09_octobre_2026-1.pdf`, `BSV_Cultures_Ornementales_N__10_du_02_novembre_2026.pdf` (mois en lettres)
- `BSV_JEVI_N__9_du_26_10_2026.pdf`, `BSV_22_1_10_2026.pdf` (légumes transfo, sans filière), `BSV_lin_Bretagne_2026_10.pdf` (n° sans date),
  2022 : `BSV_n__10_du_20-04-2022.pdf`, `BSV_Legumes_industries_2022_N__10.pdf` (sans date)
Exemples :
- https://bretagne.chambres-agriculture.fr/fileadmin/user_upload/303_chambre_dagriculture_de_bretagne/1-Dossiers/2_Prod/2_Agro/5_BSV/1_GC/2026/BSV_Grandes_Cultures_n32_2026_11_03.pdf (HEAD 200, application/pdf)
- https://bretagne.chambres-agriculture.fr/fileadmin/user_upload/303_chambre_dagriculture_de_bretagne/1-Dossiers/2_Prod/2_Agro/5_BSV/6_Cultures_Orne/2026/BSV_Cultures_Ornementales_N__10_du_02_novembre_2026.pdf
DRAAF : `IMG/pdf/bsv_grandes_cultures_n32_2026_11_03.pdf` →
https://draaf.bretagne.agriculture.gouv.fr/IMG/pdf/bsv_grandes_cultures_n32_2026_11_03.pdf (HEAD 200) ; le titre de
l'article donne toujours n° et date (`bsv-gc-no32-du-03-11-2026`, `bsv-lin-no3-du-21-avril-2026`).

## 7. Gênes pour un collecteur
- Chambre : HTML statique mais lourd (~200 Ko par page) ; date à extraire de formats variés (AAAA_MM_JJ, JJ_mois_AAAA,
  absente pour lin et certains légumes transfo → prendre l'année du dossier et le n°) ; suffixes `-1` de version.
  Une même page liste aussi des notes nationales biodiversité (à filtrer par chemin `5_BSV/<code>/<AAAA>/`).
- DRAAF : un article par bulletin, donc ~1 requête par PDF + pagination par 8 (≈ 25 pages pour GC) ; ordre de
  liste non chronologique ; pas de légumes de transformation depuis 2022.
- Arbo fruits transformés = même bulletin que les Pays de la Loire (dédoublonner).
