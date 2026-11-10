# BSV Pays de la Loire — inventaire (relevé du 08/11/2026)

## 1. Hébergeurs
- **DRAAF Pays de la Loire** (SPIP) : une page unique avec toutes les filières de la campagne en cours (y compris
  viticulture et JEVI). Contient tout pour 2026, mais **pas d'archives**.
- **Chambre régionale d'agriculture** (TYPO3) : six filières (pas de JEVI), avec des pages d'archives par filière
  et par année depuis 2024. Mais robots.txt n'autorise pas son dossier de fichiers (voir §3).
- **Polleniz** (FREDON Pays de la Loire, WordPress) : https://polleniz.fr/bsv/ — 112 PDF : arboriculture,
  arbo-fruits transformés, grandes cultures, ornement 2026 (+ quelques bilans 2025) ; pas de viticulture,
  maraîchage ni JEVI. Fichiers sous `/wp-content/uploads/<AAAA>/<MM>/`, robots.txt sans restriction utile.

## 2. Point d'entrée et structure
### DRAAF (recommandée pour la campagne en cours)
https://draaf.pays-de-la-loire.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-a162.html
Une page, sections titrées « > Grandes cultures : », « > Viticulture : », etc. ; chaque PDF est un lien dont le texte
donne la date (« du 27 octobre 2026 »). La page est réécrite à chaque campagne (« Publié le 09/08/2021, mis à jour le
02/11/2026 ») : les PDF de l'an passé en disparaissent (sauf bilans). Pas d'URL 2025/2024/2023.
Recherche SPIP : https://draaf.pays-de-la-loire.agriculture.gouv.fr/spip.php?page=recherche&recherche=bulletin+sante+vegetal
→ seulement a162 et une page de présentation (le-bulletin-de-sante-du-vegetal-a2033.html).

### Chambre (archives)
https://pays-de-la-loire.chambres-agriculture.fr/sinformer/ressources-et-documentation/bulletins-techniques-et-de-preconisation/bulletins-vegetal/bsvpdl
(dernier numéro par filière) → pages d'archives `.../bsvpdl/bsv-<filière>-archives-<AAAA>` pour
filière ∈ {grandes-cultures, viticulture, maraichage, arboriculture, arbo-fruits-transformes, ornement} et
AAAA ∈ {2024, 2025, 2026}, ex. :
- https://pays-de-la-loire.chambres-agriculture.fr/sinformer/ressources-et-documentation/bulletins-techniques-et-de-preconisation/bulletins-vegetal/bsvpdl/bsv-grandes-cultures-archives-2026
- .../bsvpdl/bsv-grandes-cultures-archives-2025
- .../bsvpdl/bsv-grandes-cultures-archives-2024 (42 PDF)
Pas de 2023.

## 3. robots.txt
- DRAAF : SPIP standard (Disallow `/ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`,
  `/*.api/` ; `Crawl-delay: 1`) → `/IMG/pdf/` autorisé.
- Chambre :
  ```
  Disallow: /fileadmin/
  Allow: /fileadmin/user_upload/FAL_COMMUN/
  Allow: /fileadmin/user_upload/226_chambre_d'agriculture_pays_de_la_loire/
  ```
  L'`Allow` porte une apostrophe (`d'agriculture`) alors que le dossier réel est `226_chambre_dagriculture_pays_de_la_loire`
  (ex. `/fileadmin/user_upload/226_chambre_dagriculture_pays_de_la_loire/Listes-affichage-FE/Vegetal/BSV/Grandes-cultures/2026/...`) :
  à la lettre, **les PDF de la chambre sont interdits** (erreur probable de leur part ; à signaler ou à demander).
- Polleniz : seules des URL `/calendar/action~...` sont interdites → `/wp-content/uploads/` autorisé.

## 4. Éditions 2026 (page DRAAF a162, nb de PDF par section, bilans et notes compris)
| Section | PDF | Remarque |
|---|---|---|
| Grandes cultures | 38 | ~32 bulletins 2026 + bilans, notes résistance |
| Viticulture | 21 | |
| Arboriculture fruitière | 23 | |
| Fruits transformés (interrégional Bretagne-Normandie-PdL) | 23 | même fichier qu'en Bretagne |
| Cultures légumières (maraîchage) | 32 | ~30 bulletins 2026 |
| Cultures ornementales | 13 | |
| JEVI | 11 | |
| Notes/biodiversité (avant les sections) | 5 | |
Total : 166 PDF, dont 135 avec « 2026 »/« 26 » dans le nom. Édition régionale unique (pas de zones infra-régionales).

## 5. Archives
DRAAF : aucune (campagne en cours seulement). Chambre : 2024. Polleniz : 2025-2026 (bilans 2025).

## 6. Noms de PDF (DRAAF, `IMG/pdf/`) — un motif par filière
- GC : `bsv_grandescultures_<AAAAMMJJ>.pdf` → https://draaf.pays-de-la-loire.agriculture.gouv.fr/IMG/pdf/bsv_grandescultures_20261027.pdf
- Maraîchage : `<AAAAMMJJ>_bsv_maraichage_no<N>.pdf` → https://draaf.pays-de-la-loire.agriculture.gouv.fr/IMG/pdf/20261029_bsv_maraichage_no30.pdf
- Viticulture : `bsv<N>_<JJMMAAAA>.pdf` (sans filière : `bsv17_23072026.pdf`, `bsv_20260519_v2.pdf`)
- Arbo : `bsv_arboriculture_<AAAAMMJJ>.pdf` ; fruits transformés : `bsv_arbo_fruits_transformes__n<N>_<AAAA_MM_JJ>.pdf`
- Ornement : `bsv_ornt_<N>_<AAMMJJ>.pdf` (date sur 6 chiffres, numéro parfois absent : `bsv_ornt_260522.pdf`)
- JEVI : `<N>_bsv_jevi_<AAAAMMJJ>.pdf`
Chambre : `bsv_arboriculture_no_22_20261022.pdf`, `20260723_bsv_viticulture_no_17.pdf`, `BSV_Grandes_cultures_no_40_20241210.pdf`.

## 7. Gênes pour un collecteur
- Page DRAAF écrasée à chaque campagne : il faut collecter pendant la campagne, l'historique ne reste pas en ligne.
- Viticulture : nom de fichier sans filière ; la filière vient de la section de la page (parser les titres « > X : »).
- Sept motifs de nom différents, dates sur 8 ou 6 chiffres, AAAAMMJJ ou JJMMAAAA ; versions `-2`, `_v2`.
- Chambre : robots.txt interdit, à la lettre, le dossier des PDF ; liens parfois avec `//` (`/fileadmin//user_upload/...`) ;
  pas de JEVI.
- Arbo fruits transformés : édition interrégionale, la même que celle de Bretagne (dédoublonner).
