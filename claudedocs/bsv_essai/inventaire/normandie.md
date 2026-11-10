# BSV Normandie — inventaire (vérifié le 08/11/2026)

## 1. Hébergeur
DRAAF Normandie (SPIP, thème DSFR) : https://draaf.normandie.agriculture.gouv.fr/
Contient tout : un article par bulletin, PDF dans `/IMG/pdf/`.

## 2. Point d'entrée et structure
Racine : https://draaf.normandie.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-r114.html
(Alimentation › Santé et protection des végétaux › Surveillance du territoire › Bulletin de santé du végétal)

Structure : rubrique filière → rubrique « Campagne AAAA » (ou « AAAA-AA » pour céréales et colza, campagne
d'automne à été) → liste paginée (≈ 5 par page, `?debut_listearticles=`) → **un article par bulletin** → 1 PDF.
Les rubriques à un seul article redirigent par `meta refresh`.

| Filière (rubrique) | 2026 | 2025 | 2024 | 2023 |
|---|---|---|---|---|
| Arboriculture et fruits transformés (r186) | campagne-2026-r1599 | campagne-2025-r1359 | campagne-2024-r1094 | campagne-2023-r617 |
| Betteraves (r187) | campagne-2026-r1606 | campagne-2025-r1461 | campagne-2024-r1090 | campagne-2023-r625 |
| Céréales (r188) | campagne-2025-26-r1565, campagne-2026-2027-r1811 | campagne-2025-r1357 | campagne-2024-r1093 | campagne-2023-r611 |
| Colza (r192) | campagne-2025-26-r1495, campagne-2026-27-r1797 | campagne-2025-r1355 | campagne-2024-r1089 | campagne-2023-r610 |
| Horticulture et pépinière (r189) | campagne-2026-r1602 | campagne-2025-r1387 | campagne-2024-r1107 | (pas de 2023) |
| Légumes (r190) | campagne-2026-r1583 | campagne-2025-r1353 | campagne-2024-r1016 | campagne-2023-r609 |
| Lin et plantes à fibres (r191) | campagne-2026-r1598 | campagne-2025-r1369 | campagne-2024-r1095 | campagne-2023-r622 |
| Pommes de terre (r193) | campagne-2026-r1600 | campagne-2025-r1449 | campagne-2024-r1098 | campagne-2023-r618 |
| Protéagineux (r204) | campagne-2026-r1601 | campagne-2025-r1360 | campagne-2024-r1096 | campagne-2023-r615 |
| JEVI (r195) | campagne-2026-r1611 | campagne-2025-r1477 | campagne-2024-r1101 | (rien 2019-2023) |
| Bilans annuels (r242) | parutions-2026-r1584 | parutions-2025-r1349 | parutions-2024-r1013 | parutions-2023-r604 |

Préfixe de toutes ces pages : `https://draaf.normandie.agriculture.gouv.fr/<slug>.html`
(ex. https://draaf.normandie.agriculture.gouv.fr/campagne-2026-r1583.html).

## 3. robots.txt
https://draaf.normandie.agriculture.gouv.fr/robots.txt :
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
`/IMG/pdf/` et les rubriques autorisés.

## 4. Filières 2026 (édition Normandie ; arboriculture « fruits transformés » commune Bretagne-Normandie-Pays de la Loire)
Articles au 08/11/2026 :
- Légumes : 30 (n°31 le 5 novembre)
- Céréales : ≈ 22 sur 2025-26 dont ≈ 16 en 2026 + 2 sur 2026-27 (numérotation « n°<n>-<semaine> », ex. 2-44)
- Colza : 25 sur 2025-26 (≈ 13 en 2026) + 10 sur 2026-27
- Betteraves : ≈ 23
- Arboriculture (fruits à cidre/transformés) : 21
- Pommes de terre : 16
- Lin fibre : 16
- Horticulture-pépinière : 15
- Protéagineux : 13
- JEVI : 4-6
Total ≈ 170 en 2026. Quelques articles rangés dans la mauvaise filière (un BSV céréales listé sous betteraves 2026),
et des articles sans PDF au moment du passage (BSV Colza n°26-26 du 4 novembre 2026, a5232).

## 5. Profondeur des archives
Depuis 2015 (arbo, betteraves, céréales, horticulture, légumes, protéagineux, JEVI), 2016 PdT, 2017 lin et colza.

## 6. Noms de PDF
Hétérogènes, date pas toujours présente ni au même format :
- Légumes : `bsv_legumesnormandie_<N>_<AAAA>_<MM>_<JJ>.pdf`
- Arbo : `bsv_arbo_fruits_transformes__n<N>_<AAAA>_<MM>_<JJ>.pdf`
- Céréales : `bsv_<n>-<sem>_cereales_normandie_<AAAA-campagne>.pdf` (pas de date ; « 2027 » = campagne 2026-27)
- Colza : `bsv_colza_no22-28oct26.pdf`
- Horti / PdT : `20261023-bsv2026_hortipepinormandie16.pdf`, `20261023-bsv_pomme_de_terre_no16_2026-1.pdf`
  (préfixe AAAAMMJJ = date de dépôt, pas de parution)
Exemples complets :
- https://draaf.normandie.agriculture.gouv.fr/IMG/pdf/bsv_legumesnormandie_31_2026_11_05.pdf (vérifié : PDF 1.7, 1,1 Mo)
- https://draaf.normandie.agriculture.gouv.fr/IMG/pdf/bsv_arbo_fruits_transformes__n22_2026_09_09.pdf
Slug d'article plus régulier : `bsv-<filiere>-no<N>-du-<J>-<mois>-<AAAA>-a<id>.html`, avec variantes
(`du-22-10-2026`, `le-22-octobre`, `bulletin-de-sante-du-vegetal-bsv-cereales-de-a5218.html` tronqué).

## 7. Gênes pour un collecteur
- Une requête par bulletin (articles), pagination courte (≈ 5 par page) : beaucoup de pages de liste.
- Campagnes à cheval sur deux années (céréales, colza) : une année civile = deux rubriques.
- Dates : à prendre dans le titre (« du 4 novembre 2026 », « du 22/10/2026 ») ; les noms de PDF mélangent formats.
- Articles mal classés et articles publiés avant leur PDF : prévoir un repassage.
- HTML statique, pas de JavaScript ni formulaire.
