# BSV Bourgogne-Franche-Comté : inventaire (vu le 8 novembre 2026)

## 1. Hébergeurs
- **DRAAF** (`draaf.bourgogne-franche-comte.agriculture.gouv.fr`, SPIP) : elle **contient tout**, la campagne en cours comme les archives. C'est la source à suivre.
- **Chambre régionale** (`bfc.chambres-agriculture.fr/innover-rechercher-developper/strategie-ecophyto-2030/bulletin-de-sante-du-vegetal/bsv-<filiere>`) : elle a des copies, par exemple 15 PDF vigne 2026 sous `/fileadmin/user_upload/227_chambre_regionale_dagriculture_de_bourgogne-franche-comte/_COLLECTIONS_DE_FICHIERS/BSV/Viticulture/Campagne_2026/`. Mais son robots.txt **interdit** ces fichiers (voir §3) : il ne faut pas l'utiliser.
- Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-bourgogne-franche-comte) renvoie vers la DRAAF r32.

## 2. Point d'entrée et structure
Racine : https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-bsv-r345.html. Elle a trois branches.

**Campagne en cours** : https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bsv-bourgogne-franche-comte-campagne-en-cours-r32.html
→ une rubrique par filière, qui **redirige par meta-refresh** vers **un article unique par filière et par campagne**. Cet article liste tous les PDF de la campagne.

| Filière | Rubrique | Article 2026 (cible de la redirection) |
|---|---|---|
| Grandes cultures | r706 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-grandes-cultures-bourgogne-franche-comte-saison-a3801.html (saison 2026-2027) |
| Viticulture | r707 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-viticulture-bourgogne-franche-comte-2026-a3707.html |
| Cassis | r709 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bsvc-01-a3709.html |
| Légumes | r710 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-legumes-bourgogne-franche-comte-2026-a3756.html |
| Prairies | r711 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-prairies-bourgogne-franche-comte-2026-a3678.html |
| Horticulture et paysage (horti + JEVI) | r712 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-horticulture-et-paysage-bourgogne-franche-comte-a3693.html |
| Myrtilles (BSV **national** hébergé ici) | r862 | https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-grandes-cultures-bourgogne-franche-comte-2025-a3717.html (le slug est trompeur) |

Les rubriques ont la forme `https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/<slug>-rNNN.html`, par exemple `bsv-grandes-cultures-r706.html`.

**Campagnes antérieures** : https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bsv-bourgogne-franche-comte-campagnes-anterieures-r708.html
→ `archivage-bsv-grandes-cultures-r713`, `archivage-bsv-viticulture-r714`, `archivage-bsv-cassis-r715`, `archivage-bsv-legumes-r716`, `archivage-prairies-r717`, `archivage-horticulture-paysage-r718`
→ un article par campagne. URLs de 2025, 2024 et 2023 :

| Filière | 2025 | 2024 | 2023 |
|---|---|---|---|
| GC (campagnes à cheval) | …-2025-a3568 (2025-2026) | …-2024-a3284 | …-2023-a3004 |
| Viticulture | …-2025-a3467 | …-2024-a3169 | …-2023-a2883 |
| Cassis | …-2025-a3459 | …-2024-a3158 | …-2023-a2867 |
| Légumes | …-2025-a3488 | …-2024-a3192 | …-2023-a2899 |
| Prairies | …-2025-a3436 | …-2024-a3104 | …-2023-a2866 |
| Horticulture et paysage | a3450 | a3152 | a2861 |

Préfixe des articles : `https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-<filiere>-bourgogne-franche-comte-`. Pour l'horticulture : `…-horticulture-et-paysage-bourgogne-franche-comte-aNNNN.html`.

**Bilans** : https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bsv-bourgogne-franche-comte-bilans-de-campagne-r721.html (articles a3123 à a3127).

## 3. robots.txt
- **DRAAF** : `User-agent: *` avec `Disallow: /ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`, `/*.api/` et `Crawl-delay: 1`. Les chemins `/IMG/pdf/` sont **autorisés**.
- **Chambre** : `User-agent: *` avec `crawl-delay: 10` et `Disallow: /fileadmin/`. Seul `Allow: /fileadmin/user_upload/FAL_COMMUN/` est ouvert, ce qui **interdit** le dossier `227_…` des BSV.

## 4. Filières 2026 (PDF sur la DRAAF)
| Filière | PDF 2026 |
|---|---|
| Grandes cultures | ~37 : 24 dans l'article 2025-2026 (a3568, jusqu'au N°35 du 21/07/2026) et 13 dans l'article 2026-2027 (a3801, N°1 du 04/08 au N°13 du 03/11) |
| Viticulture | 15 (N°1 du 31/03 au N°15 du 07/07) |
| Cassis | 8 |
| Légumes | 9 |
| Prairies | 4 |
| Horticulture et paysage | 16 (jusqu'au N°16 du 30/10) |
| Myrtilles (national) | 11 |

Total : environ 100 PDF. Il n'y a pas d'édition infrarégionale : l'ancienne séparation Bourgogne / Franche-Comté a disparu après 2016.

## 5. Profondeur des archives
- Par les rubriques d'archivage : GC depuis la campagne 2018-2019 (a1391), les autres filières depuis 2019.
- Des articles **2016** des anciennes régions restent en ligne mais ne sont pas liés depuis les rubriques. On les trouve par la recherche SPIP (`spip.php?page=recherche&recherche=bulletin+sante+vegetal+2016`), par exemple https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-grandes-cultures-2016-bourgogne-a330.html.
- Ces articles couvrent aussi la betterave Bourgogne 2016 (a527). 2017 est probablement aussi en ligne (non vérifié).
- Premier millésime : **2016**.

## 6. Noms des PDF
Tous dans `/IMG/pdf/`, en général avec le numéro et la date (JJ_MM_AAAA ou JJ_MM_AA). Le format varie :
- `https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/IMG/pdf/bsv_gc_n_13_du_03_11_2026.pdf`
- `https://draaf.bourgogne-franche-comte.agriculture.gouv.fr/IMG/pdf/bsv2026-vigne_15_du_07-07-2026.pdf`
- Autres : `bsv_legumes_n_9_du_26_08_26.pdf` (année sur 2 chiffres), `bsv_35_du_21_juillet_2026.pdf` (mois en lettres, sans filière), `bsv_prairie_4-2026.pdf` (sans date), `bsv_myrtilles_national_11_20260826.pdf`, `bsv_gc_n_10_du_13_10_2026_1_.pdf`.

## 7. Obstacles pour un collecteur
- Les rubriques de filière redirigent par `<meta http-equiv="refresh">` et non en HTTP. Il faut suivre la redirection soi-même.
- Il y a un article par campagne, qui grossit en place : il faut relire chaque article et comparer les listes de PDF.
- Les GC sont rangées par saison à cheval (« saison 2026-2027 ») : les bulletins d'une année civile sont répartis sur deux articles.
- Les noms de PDF sont hétérogènes. Certains n'ont pas de date (prairies), d'autres n'ont pas de filière (`bsv_35_du_…`). Le texte du lien vaut le nom de fichier. Il faut donc tirer la filière de l'article et la date du nom ou du PDF.
- Le BSV myrtilles est national et non régional, et le slug de son article est trompeur.
- Pas de JavaScript ni de formulaire.
