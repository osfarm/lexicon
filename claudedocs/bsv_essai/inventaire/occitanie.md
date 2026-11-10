# BSV Occitanie — inventaire (relevé du 08/11/2026)

## 1. Hébergeurs
Deux sources complètes à peu près équivalentes, les mêmes fichiers (même taille vérifiée sur un GC) :
- **Chambre régionale d'agriculture d'Occitanie** (TYPO3) : la plus complète et la plus à jour (archives depuis
  2023-2024, éditions Tabac, olivier jusqu'au n°19 d'octobre quand la DRAAF s'arrête au n°9 de juin).
- **DRAAF Occitanie** (SPIP) : une rubrique par filière → une sous-rubrique par année → un seul article cumulatif.
  Archives limitées à 2025-2026.
- https://bsv.occitanie.chambagri.fr/ n'est qu'un formulaire d'abonnement (POST avec jeton), sans PDF ; il donne
  en revanche la liste officielle des éditions. Pas de robots.txt (404).
- JEVI : la DRAAF n'a qu'un PDF 2026 (article « lien vers le list historique ») ; non trouvé chez la chambre (FREDON Occitanie non explorée).

## 2. Points d'entrée et structure
### Chambre (recommandée)
https://occitanie.chambres-agriculture.fr/sinformer/lagriculture-les-essentiels/bsv (dernier numéro de chaque édition)
→ deux pages d'ancien découpage régional :
- https://occitanie.chambres-agriculture.fr/sinformer/lagriculture-les-essentiels/bsv/bsv-languedoc-roussillon-par-filieres
- https://occitanie.chambres-agriculture.fr/sinformer/lagriculture-les-essentiels/bsv/bsv-midi-pyrenees-par-filieres
  (+ `/bilans` sous chacune)
→ une page par filière, ex. `.../bsv-midi-pyrenees-par-filieres/grandes-cultures`, `/ail`, `/arboriculture`,
`/chataigne`, `/horticulture-pepinieres`, `/maraichage`, `/melon`, `/noix-noisette`, `/raisin-de-table`, `/tabac`,
`/viticulture` ; `.../bsv-languedoc-roussillon-par-filieres/viticulture`, etc.
→ PDF de toutes les années sur la même page, rangés par dossier
`/fileadmin/user_upload/265_chambre_dagriculture_-_occitanie/BSV/<Ancienne région>/<Filière>/<année ou campagne>/`.
Ex. GC Midi-Pyrénées : 48 PDF `2023-2024/`, 26 `2025/`, 46 `2025-2026/` ; Viti LR : 41 `2023-2024/`, 20 `2025/`, 20 `2026/`.
Pas d'URL par année : une seule page par filière.

### DRAAF
Rubrique mère : https://draaf.occitanie.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-r103.html
→ rubrique filière (ex. grandes-cultures-r162.html) → sous-rubrique année/édition → **un article unique** cumulant les PDF.
Rubriques 2026 → article :
- GC Ouest Occitanie : 2026-grandes-cultures-ouest-occitanie-r1912.html → bulletin-sante-du-vegetal-grandes-cultures-a9676.html (35 PDF, dont fin 2025 : campagne 2025-2026)
- GC Ouest Occitanie campagne 2027 : 2027-grandes-cultures-ouest-occitanie-r2030.html → ...-grandes-cultures-a10114.html (8 PDF, depuis sept. 2026)
- GC Arc méditerranéen : 2026-grandes-cultures-arc-mediteraneen-r1940.html → ...-grandes-cultures-a9829.html (8)
- Arbo Languedoc-Roussillon : 2026-arboriculture-languedoc-roussillon-r1933.html → ...-arboriculture-a9812.html (18)
- Arbo Midi-Pyrénées : 2026-arboriculture-midi-pyrenees-r1934.html → ...-arboriculture-a9816.html (26)
- Maraîchage LR : 2026-languedoc-roussillon-r1932.html → ...-languedoc-roussillon-maraichage-a9811.html (22)
- Maraîchage MP : 2026-midi-pyrenees-r1941.html → ...-maraichage-a9830.html (16)
- Melon : 2026-r1942.html → ...-melon-a9832.html (13)
- Ail : 2026-r1937.html → ...-ail-a9818.html (11)
- Châtaigne : 2026-chataigne-r1935.html → ...-chataigne-a9817.html (8)
- Noix/noisette : 2026-r1986.html → ...-noix-a9910.html (10)
- Horticulture-pépinières : 2026-r1938.html → ...-horticulture-pepiniere-a9820.html (4)
- Olivier : 2026-r1994.html → bulletin-de-sante-du-vegetal-olivier-a9920.html (14)
- JEVI : 2026-r2016.html → lien-vers-le-list-historique-a10017.html (1)
- Vigne Languedoc-Roussillon : 2026-r1983.html → ...-viticulture-a9906.html (21)
- Raisin de table : 2026-r1982.html → ...-raisin-de-table-2026-a9905.html (19)
- Vigne Gascogne : 2026-r1984.html → vigne-gascogne-st-mont-madiran-a9909.html (17)
- Vigne Cahors : 2026-r1992.html → ...-vigne-cahors-a9917.html (18)
- Vigne Gaillac : 2026-r1993.html → ...-vigne-gaillac-a9918.html (16)
- Vigne Fronton/Tarn-et-Garonne : 2026-r2004.html → ...-fronton-tarn-et-garonne-a9931.html (16)
- Vigne Aveyron : 2026-r2005.html → ...-vigne-aveyron-a9937.html (16)
- Bilans : consultez-bsv-bilan-r181.html → 2026-r2028.html, 2025-r1917.html, 2024-r1703.html, 2023-r1558.html
(toutes sous https://draaf.occitanie.agriculture.gouv.fr/). Total ≈ 319 PDF dans les articles 2026.
Rubriques 2025 : 2025-r1844 (ail), 2025-arboriculture-languedoc-roussillon-r1845, 2025-arboriculture-midi-pyrenees-r1846,
2025-r1848 (châtaigne), 2025-r1850 (horti), 2025-r1851 (JEVI), 2025-languedoc-roussillon-r1852 / 2025-midi-pyrenees-r1853
(maraîchage), 2025-r1873 (melon), 2025-r1862 (noix), 2025-languedoc-roussillon-r1876 (olivier), 2025-r1878 (Aveyron),
2025-midi-pyrenees-r1872 (Cahors), 2025-vigne-r1871 (Fronton), 2025-midi-pyrenees-r1875 (Gaillac),
2025-vigne-gascogne-r1863, 2025-languedoc-roussillon-r1864 (vigne LR), 2025-raisin-de-table-r1870. Pas de 2025 GC
(couvert par la campagne 2025-2026 dans r1912). Pas de rubrique 2024 ni 2023 (hors bilans).

## 3. robots.txt
- DRAAF : SPIP standard (Disallow `/ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`,
  `/*.api/` ; `Crawl-delay: 1`) → `/IMG/pdf/` autorisé.
- Chambre :
  ```
  Disallow: /fileadmin/
  Allow: /fileadmin/user_upload/FAL_COMMUN/
  Allow: /fileadmin/user_upload/265_chambre_dagriculture_-_occitanie/
  ```
  → les PDF BSV (sous `265_chambre_dagriculture_-_occitanie/BSV/`) sont autorisés.

## 4. Éditions 2026
Viticulture : Languedoc-Roussillon, Aveyron, Cahors-Lot, Fronton-Tarn-et-Garonne, Gaillac, Gascogne (St Mont/Madiran) ;
raisin de table. Grandes cultures : Ouest-Occitanie, Arc méditerranéen. Arboriculture : LR, MP. Maraîchage : LR, MP.
Ail, olivier (Arc méditerranéen/LR), JEVI. Éditions Sud-Ouest partagées avec la Nouvelle-Aquitaine : châtaigne, melon,
noix, horticulture-pépinière (les PDF de la chambre portent alors `BSV_NA_...`). Tabac : dernier dossier `2023-2024`.
Nombres : voir la liste DRAAF ci-dessus (8 à 35 PDF par édition, ~320 au total).

## 5. Archives
DRAAF : 2025 (bilans depuis 2023). Chambre : 2023-2024 (dossiers `2023-2024/`).

## 6. Noms de PDF
- DRAAF : titre slugifié, date en toutes lettres, numéro souvent présent :
  `bulletin_sante_du_vegetal_<filière>_no<N>_du_<JJ>_<mois>_<AAAA>.pdf` ; variantes `n_9`, `n08`, `no_` sans numéro
  (`..._raisin_no_du_8_avril_2026.pdf`), date sans jour (`..._chataignier_no8_du_septembre_2026.pdf`),
  « sante_des_vegetaux », suffixes `-2`.
  - https://draaf.occitanie.agriculture.gouv.fr/IMG/pdf/bulletin_sante_du_vegetal_grandes_cultures_n08_du_05_novembre_2026.pdf
  - https://draaf.occitanie.agriculture.gouv.fr/IMG/pdf/bulletin_sante_du_vegetal_maraichage_n22_du_05_novembre_2026.pdf
- Chambre : `BSV_<FILIÈRE>_<ZONE>_N<NN>_<JJMMAAAA>.pdf`, plus régulier :
  - https://occitanie.chambres-agriculture.fr/fileadmin/user_upload/265_chambre_dagriculture_-_occitanie/BSV/Midi-Pyrenees/Grandes_cultures/2025-2026/BSV_GC_MP_N08_05112026.pdf
  - https://occitanie.chambres-agriculture.fr/fileadmin/user_upload/265_chambre_dagriculture_-_occitanie/BSV/Languedoc-Roussillon/Viticulture/2026/BSV_VITI_LR_N21_11082026.pdf
  (exceptions : `bsv_olivier_20261030_n19.pdf`, `BSV_AIL_HS_JUIN_2026_Fiche_sechage.pdf`).

## 7. Gênes pour un collecteur
- DRAAF : noms de mois en français à parser, numéros parfois absents, erreurs de rangement (l'article Cahors contient
  un PDF Gaillac), DRAAF en retard sur la chambre pour certaines éditions (olivier). Ids de rubriques/articles neufs
  chaque année ; GC organisé par campagne (2025-2026, 2027), pas par année civile.
- Chambre : pages TYPO3 lourdes (~110-190 Ko) mais HTML statique ; dossiers d'année irréguliers (`2025`, `2025-2026`,
  `2023-2024`, PDF 2026 rangés dans `2025/` pour noix et pépinière).
- Éditions Sud-Ouest communes avec la Nouvelle-Aquitaine : à dédoublonner (même bulletin chez les deux régions).
- bsv.occitanie.chambagri.fr : formulaire uniquement, inutile au collecteur.
