# BSV Provence-Alpes-Côte d'Azur : inventaire (vu le 8 novembre 2026)

## 1. Hébergeurs
- **DRAAF** (`draaf.paca.agriculture.gouv.fr`, SPIP) : elle **contient tout**, de 2015 à 2026, un article par bulletin. C'est la source à suivre.
- `https://www.bsv-paca.fr/` (chambre régionale, application Symfony avec Turnstile) sert seulement à l'**abonnement par mail**. Son bouton « Consulter les BSV en ligne » renvoie vers la DRAAF r267. Son robots.txt renvoie 404.
- Ecophytopic (https://ecophytopic.fr/bsv/piloter/bsv-provence-alpes-cote-dazur ; le slug `-paca` donne 404) renvoie vers bsv-paca.fr et la DRAAF.
- La rubrique `bulletin-de-sante-du-vegetal-r329` ne contient que des articles d'information : présentation, abonnement, ENI. Les PDF de 2016 vus auparavant viennent de la rubrique `archives-r324` (arboriculture 2016).

## 2. Point d'entrée et structure
Racine : https://draaf.paca.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-bsv-r267.html
→ une rubrique par filière → une rubrique par année (« Année 2026 »…) → **un article par bulletin** (bulletin de santé, bulletin d'alerte, numéro bis) → un PDF dans `IMG/pdf/`.
Les listes sont paginées par 8 (`?debut_listearticles=8`).

| Filière | Rubrique | 2026 | 2025 | 2024 | 2023 |
|---|---|---|---|---|---|
| Oléiculture | oleiculture-r271 | annee-2026-r855 | annee-2025-r784 | annee-2024-r755 | annee-2023-r699 |
| Arboriculture | arboriculture-r272 | annee-2026-r851 | annee-2025-r785 | annee-2024-r746 | annee-2023-r700 |
| Viticulture | viticulture-r279 | annee-2026-r858 | annee-2025-r786 | annee-2024-r754 | annee-2023-r701 |
| Cultures maraîchères | cultures-maraicheres-r273 | annee-2026-r849 | annee-2025-r787 | annee-2024-r744 | annee-2023-r697 |
| PPAM | plantes-a-parfum-et-aromatiques-r275 | annee-2026-r852 | annee-2025-r788 | annee-2024-r747 | annee-2023-r702 |
| Productions horticoles | productions-horticoles-r277 | annee-2026-r850 | annee-2025-r790 | annee-2024-r743 | annee-2023-r698 |
| Grandes cultures (édition « Arc méditerranéen ») | grandes-cultures-r274 | annee-2026-r861 | annee-2025-r791 | annee-2024-r762 | annee-2023-r704 |
| Tomate d'industrie | tomate-d-industrie-r280 | annee-2026-r863 | annee-2025-r792 | annee-2024-r763 | annee-2023-r705 |
| Amandier | bulletin-amandier-r708 | annee-2026-r856 | annee-2025-r783 | annee-2024-r749 | annee-2023-r709 |
| JEVI et pépinières ornementales | jardins-espaces-vegetalises-infrastructures-et-pepinieres-ornementales-r276 | annee-2026-r862 | annee-2025-r789 | annee-2024-r756 | annee-2023-r703 |

Toutes ces pages sont de la forme `https://draaf.paca.agriculture.gouv.fr/<slug>.html`, par exemple https://draaf.paca.agriculture.gouv.fr/annee-2026-r858.html.
Les années 2015 à 2022 existent pour toutes les filières sauf l'amandier (depuis 2023) et le JEVI (depuis 2016). Les rubriques « Année 2015 » à un seul article redirigent par meta-refresh vers cet article.

## 3. robots.txt (https://draaf.paca.agriculture.gouv.fr/robots.txt)
`Disallow: /ecrire/`, `/lib/`, `/prive/`, `/spip.php?action=*`, `/spip.php?page=login*`, `/*.api/` et `Crawl-delay: 1`.
`/IMG/pdf/` et les pages `-rNNN` / `-aNNN` sont **autorisés**. Un HEAD sur un PDF répond 200 en `application/pdf`.

## 4. Filières 2026 (articles, donc PDF, approximatif)
| Filière | Nombre en 2026 |
|---|---|
| Oléiculture | ~22 (N°19 du 30/10, avec des alertes mouche) |
| Arboriculture | ~25 (N°22 du 09/09) |
| Viticulture | ~20 (N°19 du 28/07) |
| Maraîchage | ~22 (N°21 du 06/11) |
| PPAM | 5 |
| Horticulture | ~14 (bulletins et alertes botrytis) |
| Grandes cultures | 8 |
| Tomate d'industrie | 4 |
| Amandier | 6 |
| JEVI / ZNA | ~13 (N°9 du 27/10, alerte *Popillia japonica*) |

Total : environ 140 PDF. Il n'y a pas d'édition infrarégionale.

## 5. Profondeur des archives
Les archives remontent à **2015** (rubriques « Année 2015 »), avec en plus `archives-r324` (arboriculture 2016).

## 6. Noms des PDF
Il n'y a pas de motif commun aux filières. La date (AAAAMMJJ, JJMMAAAA ou « 06_novembre_2026 ») et le numéro sont présents dans les exemples de 2026.
- `https://draaf.paca.agriculture.gouv.fr/IMG/pdf/bsvviti_20260728_n19.pdf`
- `https://draaf.paca.agriculture.gouv.fr/IMG/pdf/bsv_maraichage_no21_du_06_novembre_2026.pdf`
- Autres : `bsv_olivier_20261030_n19.pdf`, `bsw_paca_arbo_20260909_n22.pdf` (coquille « bsw »), `bsv_gc_arcmed_n08_25062026.pdf`, `bsv_zna-po_20261027_n9.pdf`, `bsvhorti_20261102_no6_alerte.pdf`.

## 7. Obstacles pour un collecteur
- Les slugs et les titres des articles sont peu fiables. Par exemple, `bulletin-de-sante-no3-07-juillet-2026` est titré N°17, et `bulletin-no03-du-27-mai-2026` est titré « du 23 avril ». Il faut lire la date dans le nom du PDF ou dans le PDF lui-même.
- Le classement « Année N » mélange bulletins ordinaires, bulletins d'alerte et numéros bis : il faut repérer le type (alerte, bis, hors-série).
- Les GC sont une édition « Arc méditerranéen », probablement commune avec l'Occitanie : risque de doublon avec cette région.
- bsv-paca.fr (abonnement, Turnstile) ne sert pas à la collecte.
- Pas de JavaScript ni de formulaire sur la DRAAF.
