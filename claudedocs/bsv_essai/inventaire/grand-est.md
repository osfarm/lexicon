# BSV Grand Est — inventaire (vérifié le 08/11/2026)

## 1. Hébergeur
DRAAF Grand Est (SPIP + thème DSFR « agrispip_dsfr ») : https://draaf.grand-est.agriculture.gouv.fr/
Tous les PDF de 2026 sont hébergés sur ce site, sous `/IMG/pdf/`. L'article « Bulletins de la santé du végétal 2026 »
(`bulletins-de-la-sante-du-vegetal-2026-a4909.html`) n'est qu'un renvoi (lien « Les BSV 2026 ») vers la rubrique
r1751 du même site : aucun lien vers la chambre n'est nécessaire.

## 2. Point d'entrée et structure
Racine BSV : https://draaf.grand-est.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-bsv-r75.html
→ année en cours (rubrique) + rubrique « Archives » :
https://draaf.grand-est.agriculture.gouv.fr/bulletin-de-sante-du-vegetal-archives-r162.html

Structure : rubrique année → sous-rubrique par filière → un article par territoire (Alsace / Champagne-Ardenne /
Lorraine) avec la liste des PDF de l'année. Quand une filière n'a qu'un article, la rubrique répond par une page
vide avec `<meta http-equiv="refresh" content="0; url=...-aNNNN.html">` (à suivre). Pas de pagination observée.

| Année | Rubrique |
|---|---|
| 2026 | https://draaf.grand-est.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-2026-r1751.html |
| 2025 | https://draaf.grand-est.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-2025-r1646.html |
| 2024 | https://draaf.grand-est.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-2024-r1037.html |
| 2023 | https://draaf.grand-est.agriculture.gouv.fr/bulletins-de-sante-du-vegetal-2023-r945.html |
| 2022…2017 | r862, r748, r572, r515, r420, r319 |
| 2016 | bulletin-de-sante-du-vegetal-2016-r143.html, bulletin-de-sante-du-vegetal-lorraine-2016-r80.html |
| 2015 | bsv-alsace-2015-r164.html, bsv-champagne-ardenne-2015-r163.html (un article par filière, pas de sous-rubrique) |

2026, détail :
- Grandes cultures `grandes-cultures-r1752.html` → `territoire-alsacien-a4843.html`, `territoire-champardennais-a4841.html`, `territoire-lorrain-a4842.html`
- Viticulture `viticulture-r1753.html` → `territoire-alsacien-a4846.html`, `territoire-champardennais-a4844.html`, `territoire-lorrain-a4845.html`
- Arboriculture `arboriculture-r1755.html` → `territoire-alsacien-a4848.html`, `territoire-lorrain-a4847.html`
- Légumes-maraîchage `cultures-legumieres-maraichage-r1754.html` → redirige vers `cultures-legumieres-maraichage-a4849.html`
- Horticulture-pépinières `horticulture-pepinieres-r1756.html` → `bsv-horticulture-pepinieres-2026-a4850.html`
- Houblon `houblon-r1757.html` → `bsv-houblon-2026-a4851.html`
- JEVI `jevi-jardins-espaces-vegetalises-et-infrastructures-r1758.html` → `bsv-jevi-jardins-espaces-vegetalises-et-infrastructures-2026-a4852.html`

Les pages 2025, 2023 ont la même forme (filières : GC, viti, légumes, arbo, horti, houblon, JEVI, **tabac** — tabac absent en 2026).

## 3. robots.txt
https://draaf.grand-est.agriculture.gouv.fr/robots.txt (servi par `spip.php?page=robots.txt`) :
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
`/IMG/pdf/` et les pages `*-rNNN.html` / `*-aNNNN.html` sont autorisés. Respecter `Crawl-delay: 1`.

## 4. Filières 2026 (nb de PDF liés au 08/11/2026)
- Grandes cultures : Alsace 35, Champagne-Ardenne 38, Lorraine 33 (≈ 34 numéros chacun, hebdo de février à novembre)
- Viticulture : Alsace 15, Champagne 17, Lorraine 14
- Arboriculture : Alsace 24, Lorraine 24
- Légumes-maraîchage (édition Grand Est) : 22
- Horticulture-pépinières (GE) : 15
- Houblon (GE) : 10
- JEVI (GE) : 9
Total ≈ 270 PDF. Quelques doublons (même numéro republié avec suffixe `-2`, lien listé deux fois).

## 5. Profondeur des archives
Depuis 2015 (Alsace et Champagne-Ardenne), Lorraine depuis 2016 ; Grand Est unifié depuis 2016/2017.

## 6. Noms de PDF
Motif : `IMG/pdf/<zone>_<filiere>_no<N>_du_<JJ-MM-AA>[-2].pdf`, zone ∈ `alsace`, `char`, `lorraine`, `ge` ;
filière ∈ `gdes_cultures`, `viticulture`, `arboriculture`, `legumes`, `horticulture`, `houblon`, `jevi`.
Date et numéro présents dans le nom (date en JJ-MM-AA, parfois J sans zéro : `du_9-04-26`, parfois différente de la
date de l'intitulé d'un jour). Le texte du lien redonne « BSV Grandes Cultures n°34 du 4 novembre 2026 ( pdf - 972.4 kio) ».
- https://draaf.grand-est.agriculture.gouv.fr/IMG/pdf/alsace_gdes_cultures_no34_du_04-11-26-2.pdf
- https://draaf.grand-est.agriculture.gouv.fr/IMG/pdf/ge_jevi_no9_du_21-10-26.pdf (vérifié : PDF 1.7, 1,8 Mo)

## 7. Gênes pour un collecteur
- Rubriques à un seul article : redirection par `meta refresh` (pas HTTP), à suivre à la main.
- Articles d'une année : identifiants non prévisibles, il faut parcourir l'arbre depuis r75 / r162.
- Doublons `-2` et un lien sans intitulé propre pour le même fichier ; une erreur de rangement observée (un PDF
  `alsace_arboriculture_no10…` dans l'article Lorraine) : se fier au nom de fichier pour la zone.
- Dates du nom au format JJ-MM-AA, jour parfois sans zéro.
- Pas de JavaScript ni de formulaire ; tout est en HTML statique.
