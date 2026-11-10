# BSV Centre-Val de Loire — inventaire (vérifié le 08/11/2026)

## 1. Hébergeur
DRAAF Centre-Val de Loire (SPIP, thème DSFR) : https://draaf.centre-val-de-loire.agriculture.gouv.fr/
Contient tout : PDF dans `/IMG/pdf/`, aucun lien vers un autre domaine dans les pages 2026.

## 2. Point d'entrée et structure
Racine : https://draaf.centre-val-de-loire.agriculture.gouv.fr/acces-au-bsv-r37.html
(Alimentation › Santé et protection des végétaux › Santé des végétaux › Bulletin de santé du végétal › Accès au BSV)
→ une rubrique par année + « Archives BSV » (r314).

Structure **variable selon l'année** :
- 2026, 2023 (et archives 2015-2020) : rubrique année → **un article par filière** (liste paginée,
  `?debut_listearticles=`) → tous les PDF de l'année dans l'article.
- 2025, 2024 : rubrique année → **sous-rubrique par filière** dont le texte liste les PDF (pagination possible ;
  la rubrique contient aussi des articles sans rapport, à ignorer).

| Année | URL |
|---|---|
| 2026 | https://draaf.centre-val-de-loire.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-2026-r367.html |
| 2025 | https://draaf.centre-val-de-loire.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-2025-r342.html (filières r343…r353) |
| 2024 | https://draaf.centre-val-de-loire.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-2024-r319.html (filières r320…r330) |
| 2023 | https://draaf.centre-val-de-loire.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-2023-r301.html |
| 2022, 2021 | bulletin-de-sante-du-vegetal-2022-r289.html, bulletin-de-sante-du-vegetal-2021-r267.html |
| 2020…2015 | https://draaf.centre-val-de-loire.agriculture.gouv.fr/archives-bsv-r314.html → archives-bsv-2020-r228 … archives-bsv-2015-r166 |

2026, articles : `arboriculture-a1967.html`, `nouvel-article-no-1969-a1969.html` (céréales à paille),
`oleagineux-a1962.html`, `legumes-a1958.html`, `proteagineux-a1971.html`, `horticulture-pepiniere-a1977.html`,
`viticulture-a1979.html`, `betterave-a1980.html`, `pommes-de-terre-a1981.html`,
`sante-des-jardins-amateurs-a1985.html` (JEVI), `mais-a1987.html`.

## 3. robots.txt
https://draaf.centre-val-de-loire.agriculture.gouv.fr/robots.txt :
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
`/IMG/pdf/` et les pages autorisés.

## 4. Filières 2026 (édition régionale unique ; nb de PDF au 08/11/2026)
Arboriculture 34 · Oléagineux 25 (inclut la fin de la campagne 2025-26 et le début de 2026-27) · Betterave 24 ·
Légumes 22 · Pommes de terre 17 · Horticulture-pépinière 16 (dont bilan) · Céréales à paille 16 (fin de campagne
2025-26 + début 2026-27) · Viticulture 15 · Protéagineux 15 (dont bilan 2025-2026) · Maïs 13 (dont bilan) ·
JEVI / jardins amateurs 8. Total ≈ 205.

## 5. Profondeur des archives
Depuis 2015 (archives-bsv-2015-r166 : articles par filière, dont « Zones non agricoles », « Adventices »).

## 6. Noms de PDF
Motif dominant : `bsv_<filiere>_<NN>_du_<JJ-MM-AA>[-][-2].pdf` (numéro et date présents), avec des variantes :
- `bsv_arboriculture_34_du_29_10_26.pdf` (séparateur `_` dans la date)
- `bsv_viti_15_du_30-06-26-.pdf` (tiret final)
- bilans : `bsv_bilan_mais_2026.pdf`, `bsv_horti_pepi_bilan_du_05-11-26.pdf`, `bsv_proteagineux_bilan_2025_2026.pdf`
- sans date : `bsv_proteagineux_cvdl_14.pdf` ; ancien format : `bsv_grandes_cultures_oleagineux_no15_jc_20260203.pdf`
- JEVI : `bulletin_<N>_jevi_cvl-<AAAAMMJJ>.pdf` (parfois `-202609`, date incomplète)
Exemples :
- https://draaf.centre-val-de-loire.agriculture.gouv.fr/IMG/pdf/bsv_viti_15_du_30-06-26-.pdf (vérifié : PDF 1.7, 11 pages, 1,9 Mo)
- https://draaf.centre-val-de-loire.agriculture.gouv.fr/IMG/pdf/bsv_legumes_18_du_28-10-26.pdf

## 7. Gênes pour un collecteur
- Structure qui change d'une année à l'autre (article par filière vs sous-rubrique par filière) : le collecteur doit
  ramasser les PDF où qu'ils soient sous la rubrique de l'année.
- Slugs non parlants (`nouvel-article-no-1969` = céréales à paille) : identifier la filière par le titre.
- Campagnes à cheval (céréales, oléagineux) : la numérotation repart en cours d'année ; un même article mêle deux
  campagnes.
- Noms de PDF presque réguliers mais avec exceptions (date au format JJ_MM_AA, absente, ou AAAAMMJJ) : prendre aussi
  l'intitulé du lien.
- Les rubriques 2024/2025 contiennent des articles hors BSV (actualités) dans leur liste.
- HTML statique, pas de JavaScript ni formulaire.
