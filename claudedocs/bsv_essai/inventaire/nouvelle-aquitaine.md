# BSV Nouvelle-Aquitaine — inventaire (relevé du 08/11/2026)

## 1. Hébergeur
DRAAF Nouvelle-Aquitaine (SPIP) : contient toutes les éditions, y compris les éditions interrégionales
pilotées par la Nouvelle-Aquitaine (« Grand Sud-Ouest ») et celles reprises d'autres régions (melon Occitanie,
myrtille national). Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-nouvelle-aquitaine) ne donne que des
fiches par édition, sans PDF. La chambre régionale n'est pas nécessaire.

## 2. Point d'entrée et structure
Rubrique mère : https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-r71.html
→ une sous-rubrique par année → un article par édition (filière × zone) → liste de PDF dans le corps de l'article
(liens `IMG/pdf/...`, tantôt relatifs, tantôt absolus).
Pagination SPIP de la rubrique : `?debut_listearticles=0,8,16,24` (8 articles par page).

- 2026 : https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/bsv-nouvelle-aquitaine-2026-r1216.html (25 articles, 4 pages)
- 2025 : https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/bsv-nouvelle-aquitaine-2025-r1141.html (~28 articles)
- 2024 : https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/bsv-nouvelle-aquitaine-2024-r1002.html
- 2023 : https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/bsv-nouvelle-aquitaine-2023-r912.html (~27 articles)

Les ids d'articles changent chaque année (ex. grandes-cultures-aquitaine-a2662 en 2023, -a3965 en 2026) :
il faut repartir de la rubrique de l'année, pas d'une liste d'URL fixe.

## 3. robots.txt (DRAAF, SPIP standard, identique sur les 4 DRAAF)
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
`/IMG/pdf/` et les pages `*-rNNN.html` / `*-aNNN.html` sont autorisés. Respecter `Crawl-delay: 1`.
Chambre régionale (nouvelle-aquitaine.chambres-agriculture.fr) : `Disallow: /fileadmin/` mais
`Allow: /fileadmin/user_upload/251_chambre_regionale_dagriculture_nouvelle-aquitaine/` — son propre dossier
est donc autorisé (à nuancer par rapport à ce qui était connu), mais elle n'est pas utile ici.

## 4. Éditions 2026 (article → nb de PDF liés, bilans 2025 inclus)
| Édition | Article | PDF |
|---|---|---|
| Grandes cultures Aquitaine | grandes-cultures-aquitaine-a3965.html | 42 |
| Grandes cultures Limousin | grandes-cultures-limousin-a3970.html | 36 |
| Grandes cultures Poitou-Charentes | grandes-cultures-poitou-charentes-a3956.html | 40 |
| Vigne Nord Aquitaine | vigne-nord-aquitaine-a4053.html | 22 |
| Vigne Sud Aquitaine | vigne-sud-aquitaine-a4054.html | 18 |
| Vigne Charentes | vigne-charentes-a4052.html | 21 |
| Vigne Haut-Poitou | vigne-haut-poitou-a4072.html | 11 |
| Vigne Limousin | vigne-limousin-a3961.html | 18 |
| Pommier Nord N-A | pommier-nord-nouvelle-aquitaine-a3980.html | 20 |
| Pommier-poirier Centre et Sud N-A | pommier-poirier-centre-et-sud-n-a-a3949.html | 24 |
| Fruits à noyau | fruits-a-noyau-a3951.html | 23 |
| Kiwi | kiwi-a3950.html | 22 |
| Noix Grand Sud-Ouest | noix-grand-sud-ouest-a4022.html | 11 |
| Châtaignier Grand Sud-Ouest | chataignier-grand-sud-ouest-a4084.html | 10 |
| Fraise-framboise (petits fruits) | fraise-framboise-a3948.html | 14 |
| Myrtille (national) | myrtille-national-a3979.html | 11 |
| Maraîchage Nord N-A (16-17-79-86-87) | maraichage-nord-nouvelle-aquitaine-dpt-16-17-79-86-87-a4190.html | 20 |
| Maraîchage Sud N-A (19-24-33-40-47-64) | maraichage-sud-nouvelle-aquitaine-dpt-19-24-33-40-47-64-a3971.html | 14 |
| Melon-pastèque Nord N-A | melon-pasteque-nord-nouvelle-aquitaine-a4229.html | 20 |
| Melon Occitanie (repris) | melon-occitanie-a4063.html | 11 |
| Légumes de plein champ N-A | legumes-de-plein-champ-nouvelle-aquitaine-a4257.html | 0 (article vide) |
| Pomme de terre | pomme-de-terre-a4013.html | 20 |
| Horticulture-pépinière Grand Sud-Ouest | horticulture-pepiniere-grand-sud-ouest-a4284.html | 6 |
| JEVI N-A | jardins-espaces-vegetalises-et-infrastructures-jevi-n-a-a3994.html et ...-a4289.html | 4 + 2 |

Total : ~438 PDF distincts sur la rubrique 2026 (dont hors-séries, flashs prairies, bilans 2025).
Toutes les URL de PDF sont sur le même domaine (aucun lien externe).

## 5. Archives
2023 (première année en ligne dans la rubrique r71 ; rien d'antérieur listé).

## 6. Noms de PDF
Motif dominant : `bsv_<filière>_<zone>_<n°>_<AAAAMMJJ>.pdf`, mais très irrégulier :
- date AAAAMMJJ : `bsv_gc_na_aqui_31_20261105.pdf`, `bsv_na_kiwi_21_20261008.pdf`
- date JJMMAAAA en Limousin : `bsv_gc_na_limousin_1_17022026.pdf` (parfois tronquée : `..._27_6102026.pdf`, `..._3_030326_1_.pdf`)
- date en tête : `20260330_bsv_na_hs_confusion_sexuelle_arbo...`
- sans date : horticulture/pépinière (`bsv_horticulture_gso_n__1-2026.pdf`), hors-séries vigne
  (`bsv_na_vigne_charentes_hors-serie_lancement_campagne_2026.pdf`), bilans (`bsv_na_jevi_bilan_2025.pdf`)
- doublons suffixés `-2` (versions corrigées) : `bsv_gc_na_limousin_10_21042026-2.pdf`

Exemples (vérifiés, HEAD 200 application/pdf) :
- https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/IMG/pdf/bsv_gc_na_aqui_31_20261105.pdf
- https://draaf.nouvelle-aquitaine.agriculture.gouv.fr/IMG/pdf/bsv_na_kiwi_21_20261008.pdf

## 7. Gênes pour un collecteur
- Pas de JavaScript ni formulaire : HTML statique, liens directs.
- Ids d'articles et de rubriques non prévisibles d'une année à l'autre ; nouvelle rubrique chaque année.
- L'article 2026 contient aussi les bilans de la campagne précédente (datés 2025) : dater par le nom ou le texte du lien
  (« BSV Kiwi N°21 »), pas par la rubrique.
- Formats de date hétérogènes (AAAAMMJJ, JJMMAAAA, absente) ; versions `-2` à dédoublonner.
- Un article peut être vide (légumes de plein champ) ou dédoublé (deux articles JEVI).
- Éditions interrégionales (Grand Sud-Ouest, melon Occitanie, myrtille national) : risque de doublon avec les
  collectes d'Occitanie (châtaigne, noix, horticulture-pépinière sont aussi publiées chez la chambre d'Occitanie).
