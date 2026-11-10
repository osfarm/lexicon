# BSV Auvergne-Rhône-Alpes : inventaire (vu le 8 novembre 2026)

## 1. Hébergeurs
- **DRAAF** (`draaf.auvergne-rhone-alpes.agriculture.gouv.fr`, SPIP) : la campagne en cours (un article par bulletin) et l'année précédente (archivage 2025). C'est la source à suivre.
- **Chambre régionale** (`aura.chambres-agriculture.fr`, TYPO3) : la page principale ne montre que le premier et le dernier bulletin de chaque filière en 2026. Elle a des pages d'archives par filière et par année, de 2022 à 2025.
- Aucun hébergeur ne contient tout. Pour 2026 et 2025, prendre la DRAAF. Pour 2022 à 2024, prendre la chambre.
- Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-auvergne-rhone-alpes) ne fait que renvoyer vers ces deux sites. Seul le bilan 2025 y est hébergé.
- Les pages DRAAF « bulletin-de-sante-du-vegetal-a5280 » et « qu-est-ce-que-le-bsv-r1390 » sont des pages d'information : les bulletins sont dans la branche r51 ci-dessous.

## 2. Point d'entrée et structure
**DRAAF 2026** : https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-r51.html
→ une rubrique par filière → une rubrique par édition pour l'année → **un article par bulletin** → un PDF dans `IMG/pdf/`.
Les listes sont paginées par 8 (`?debut_listearticles=8,16,…`).

| Filière / édition | Rubrique de l'année (titrée 2026) |
|---|---|
| GC Auvergne | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-grandes-cultures-auvergne-2026-r1424.html |
| GC Rhône-Alpes | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-grandes-cultures-rhone-alpes-2026-r1425.html |
| Arboriculture Rhône-Alpes | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-arboriculture-2024-r1438.html |
| Horti-pépinières AURA / chrysanthème Auvergne | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-horticulture-pepinieres-rhone-alpes-chrysanteme-auvergne-2024-r1442.html |
| Légumes, allium, pomme de terre AURA | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-maraichage-rhone-alpes-allium-et-pomme-de-terre-aura-2026-r1706.html |
| Viticulture Auvergne | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/viticulture-auvergne-2026-r1445.html |
| Viticulture Rhône-Alpes | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/viticulture-rhone-alpes-2025-r1443.html |
| JEVI | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-jardins-et-espaces-verts-2025-r1480.html |
| Petits fruits rouges | https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-petits-fruits-rouges-r296.html (articles listés directement) |

Notes transversales : https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/les-notes-transversales-a-tous-les-bsv-r257.html

**Attention** : les rubriques d'une année sont **réutilisées et renommées** d'une campagne à l'autre. Le slug garde une année ancienne : `-2024-r1438` est titré 2026, `-2025-r1443` aussi. Il ne faut pas se fier à l'année dans l'URL.

**DRAAF 2025** : https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/archivage-2025-r1672.html
→ une rubrique par filière (r1673 à r1679 : arbo, GC, horti-pépi, JEVI, maraîchage, petits fruits, viti)
→ une rubrique par édition (ex. bsv-auvergne-r1680, bsv-rhone-alpes-r1681)
→ une **redirection meta-refresh** vers **un seul article « BSV 2025 »**, qui porte tous les PDF de l'année (environ 40 PDF).
Exemples :
- https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-2025-a6397.html (GC Auvergne)
- https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-2025-a6398.html (GC Rhône-Alpes)

La rubrique r1672 n'est pas listée dans r51, mais elle figure dans le sitemap.

**Chambre, 2022 à 2025** : https://aura.chambres-agriculture.fr/sinformer/ressources-et-documentations/bulletins-de-sante-du-vegetal-bsv
Les archives sont à `…/bulletins-de-sante-du-vegetal-bsv/bsv-archives/bsv-<filiere>-archives-<année>`. Chaque page est une liste de PDF : 43 PDF pour GC Auvergne 2025.
- https://aura.chambres-agriculture.fr/sinformer/ressources-et-documentations/bulletins-de-sante-du-vegetal-bsv/bsv-archives/bsv-grandes-cultures-auvergne-archives-2025
- Même motif pour 2024, 2023 et 2022. Slugs des filières : `grandes-cultures-auvergne`, `grandes-cultures-rhone-alpes`, `arboriculture` (2023 à 2025), `horticulture`, `viticulture-auvergne`, `viticulture-rhone-alpes`, `cultures-legumieres` (2023 à 2025), `fruits-rouges`, `lentilles` (2022 à 2024).

**Plan du site DRAAF** : https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/spip.php?page=sitemap-rub.xml liste toutes les rubriques BSV. Les articles sont dans `spip.php?page=sitemap-art.xml&annee=AAAA`, de 2015 à 2026. C'est un bon moyen de découverte.

## 3. robots.txt
- **DRAAF** : `User-agent: *` avec `Disallow: /ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`, `/*.api/` et `Crawl-delay: 1`. Les chemins `/IMG/pdf/` et les pages `-rNNN.html` / `-aNNN.html` sont **autorisés**.
- **Chambre** : `Disallow: /fileadmin/`, mais `Allow: /fileadmin/user_upload/223_chambres_dagriculture_auvergne-rhone-alpes/`. Les PDF sont dans ce dossier, donc **autorisés**.

## 4. Filières 2026 (articles DRAAF, approximatif)
| Filière / édition | Nombre en 2026 |
|---|---|
| GC Auvergne | ~36 (N°1 du 10/02 au N°35 du 04/11) |
| GC Rhône-Alpes | ~34 (jusqu'au N°31 du 04/11, avec les flashs) |
| Arboriculture Rhône-Alpes | ~30 (jusqu'au N°24 du 15/09) |
| Horti-pépi AURA | 7 |
| Légumes / allium / pomme de terre AURA | ~20 (jusqu'au N°14 du 22/10) |
| Viticulture Auvergne | 9 |
| Viticulture Rhône-Alpes | ~20 (jusqu'au N°16 du 15/07) |
| JEVI | 7 |
| Petits fruits rouges AURA | 6 sur la DRAAF ; le N°7 du 16/09 est seulement sur la chambre |

Total : environ 170 PDF.
Bilans régionaux : https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/bsv-bilans-regionaux-2025-r1387.html

## 5. Profondeur des archives
- DRAAF : 2026 et 2025 seulement.
- Chambre : 2022 à 2025 (lentilles 2022 à 2024).
- En ligne, le premier millésime est donc **2022**.

## 6. Noms des PDF
Il n'y a pas de motif unique : il varie selon la filière et même d'une année à l'autre. La date (AAAAMMJJ ou JJ-MM-AAAA) et le numéro sont presque toujours présents.
- `https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/IMG/pdf/20261104_bsv_grandes_cultures_auvergne_n_35.pdf`
- `https://draaf.auvergne-rhone-alpes.agriculture.gouv.fr/IMG/pdf/bsv-viti-ra-16_15-07-2026.pdf`
- Autres : `bsv_ra_arbo_no24du15092026.pdf` ; `bsv_jevi_aura_7_2026_v2_compressed.pdf` (sans date) ; en 2025, `…_n_01-2.pdf` (SPIP ajoute `-2` aux doublons).
- Chambre : `https://aura.chambres-agriculture.fr/fileadmin/user_upload/223_chambres_dagriculture_auvergne-rhone-alpes/Listes-affichage-FE/BSV/BSV_Grandes_cultures/BSV_Grandes_Cultures_Rhone_Alpes/2026/20261104_BSV_grandes_cultures_RA_31.pdf` (l'année est dans le chemin).

## 7. Obstacles pour un collecteur
- La structure change selon l'année : en cours, un article par bulletin ; une fois archivée, un article unique « BSV 2025 » derrière une redirection meta-refresh. Les rubriques sont recyclées et leur slug porte une année fausse.
- La rubrique d'archivage n'est pas liée depuis r51. Il faut passer par le sitemap ou par le fil d'Ariane.
- La DRAAF et la chambre ne sont pas toujours synchrones : il manque des numéros d'un côté ou de l'autre.
- Les noms de PDF sont hétérogènes : la date et le numéro doivent être lus dans le titre de l'article (« N°35 du 4 novembre 2026 »), qui est plus régulier que le nom de fichier.
- Pas de JavaScript ni de formulaire.
