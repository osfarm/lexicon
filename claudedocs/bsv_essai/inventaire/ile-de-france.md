# BSV Île-de-France — inventaire (vérifié le 08/11/2026)

## 1. Hébergeur
DRIAAF Île-de-France (SPIP, thème DSFR) : https://driaaf.ile-de-france.agriculture.gouv.fr/
Contient tout : un article par bulletin, PDF dans `/IMG/pdf/`. La fiche Ecophytopic
(https://ecophytopic.fr/bsv/piloter/bsv-ile-de-france) ne fait que décrire les filières.

## 2. Point d'entrée et structure
Rubrique mère : https://driaaf.ile-de-france.agriculture.gouv.fr/epidemiosurveillance-et-bulletin-de-sante-du-vegetal-bsv-r189.html
(sous-rubriques : BSV en cours r195, Bilans sanitaires annuels r196, Notes techniques r427, Seuils r431, Archives r197).

Année en cours : https://driaaf.ile-de-france.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-bsv-r195.html
(les anciens articles `bulletin-de-sante-du-vegetal-a513.html` et `le-dernier-bulletin-de-sante-du-vegetal-a441.html`
redirigent en HTTP vers r195).

Structure : rubrique « en cours » → une rubrique par filière et par année → liste paginée (8 par page,
`?debut_listearticles=8,16…`) → **un article par bulletin** → 1 PDF. Chaque fin d'année, les rubriques de l'année
passent sous Archives (r197).

| Filière | 2026 | 2025 | 2024 | 2023 |
|---|---|---|---|---|
| Grandes cultures (+ PdT, légumes industriels) | 01-grandes-cultures-2026-r845.html | grandes-cultures-2025-r731.html | grandes-cultures-pomme-de-terre-legumes-industriels-2024-r697.html | grandes-cultures-pomme-de-terre-et-legumes-industriels-2023-r616.html |
| Arboriculture | nouvelle-rubrique-no-847-r847.html | arboriculture-2025-r728.html | arboriculture-2024-r696.html | arboriculture-2023-r615.html |
| Maraîchage | maraichage-2026-r846.html | maraichage-2025-r730.html | maraichage-2024-r698.html | maraichage-2023-r617.html |
| Pépinière / horticulture | pepiniere-horticulture-2026-r848.html | horticulture-pepiniere-2025-r740.html | horticulture-pepiniere-2024-r699.html | horticulture-pepiniere-2023-r618.html |

Archives : https://driaaf.ile-de-france.agriculture.gouv.fr/archives-bsv-r197.html
(toutes les URLs ci-dessus sont relatives à https://driaaf.ile-de-france.agriculture.gouv.fr/).

## 3. robots.txt
https://driaaf.ile-de-france.agriculture.gouv.fr/robots.txt :
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
`/IMG/pdf/` et les rubriques autorisés. (Ecophytopic, lui, interdit `/search/`, donc sa base BSV
`/search/base-bsv`.)

## 4. Filières 2026 (édition régionale unique)
Au 08/11/2026 :
- Grandes cultures : 39 (n°39 du 3 novembre)
- Maraîchage : 26
- Arboriculture : 24 (dernier le 10 septembre)
- Pépinière + horticulture (même rubrique, deux séries numérotées à part) : ≈ 30 (pépinière ≈ 15, horticulture 15)
Total ≈ 120. Pas de JEVI, viticulture ni petits fruits.

## 5. Profondeur des archives
En ligne depuis 2023 seulement (rubriques 2023 dans Archives). Les années plus anciennes ne sont plus rangées
dans l'arborescence (d'anciens PDF comme `IMG/pdf/bsv_grandes_cultures_n34-3.pdf` peuvent subsister sans page).
Bilans sanitaires annuels à part dans r196.

## 6. Noms de PDF
Pas de date dans le nom, seulement un numéro, motif variable selon la filière :
- GC : `bsv_grandes_cultures_n_<N>.pdf` (pas d'année non plus → collisions d'une année à l'autre, SPIP ajoute `-2`, `-3`)
- Arbo : `bsv_arbo_<AAAA>_<N>.pdf`
- Maraîchage : `bsv_maraichage<AAAA>-<N>.pdf`
- Pépinière : `bsvpepi_n<N>[-2].pdf` ; horticulture : `bsv_horti_n<N>.pdf`
La date est dans le titre/slug de l'article : `bsv-<filiere>-no<N>-du-<J>-<mois>-<AAAA>-a<id>.html`.
- https://driaaf.ile-de-france.agriculture.gouv.fr/IMG/pdf/bsv_grandes_cultures_n_39.pdf (vérifié : PDF 1.7, 1,1 Mo)
- https://driaaf.ile-de-france.agriculture.gouv.fr/IMG/pdf/bsv_arbo_2026_24.pdf

## 7. Gênes pour un collecteur
- PDF sans date (et souvent sans année) : la date doit venir de l'article ; suffixes `-2`, `-3` de SPIP.
- Un article par bulletin : une requête par BSV.
- Slugs de rubriques irréguliers (« nouvelle-rubrique-no-847 », préfixes « 01- », « 21- ») et ids non prévisibles :
  partir de r195 / r197.
- Pépinière et horticulture mêlées dans une rubrique : distinguer par le titre.
- Les rubriques changent de parent en fin d'année (r195 → r197) ; archives courtes (2023+).
- HTML statique, pas de JavaScript.
