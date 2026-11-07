# Dérogations 120 jours dans `phytosanitary` — cadrage

Brainstorm du 2026-11-07. Modèle : la fonction « dérogations 120 j » de `cropivia_backend`
(`docs/amm_120j.md`, `app/integrations/agri_gouv.py`, `app/services/phyto/derogations/`,
`app/jobs/sync_derogations.py`), en service depuis le 2026-07-24.

## Pourquoi

E-Phy ne publie pas les autorisations de mise sur le marché d'une durée maximale de 120 jours (article 53 du
règlement CE 1107/2009). Le ministère les publie une à une, en PDF, sur
`https://agriculture.gouv.fr/produits-phytopharmaceutiques-autorisations-de-mise-sur-le-marche-dune-duree-maximale-de-120-jours`.
Un agriculteur qui traite sous dérogation ne trouve donc ni le produit ni l'usage dans Lexicon, et Ekylibre ne
peut pas l'enregistrer comme un traitement autorisé.

## Ce qu'on sait de la source (2026-11-07)

- 37 décisions sur la page, 32 numéros d'AMM distincts, toutes cultures : bananier, olivier, canne à sucre, kiwi,
  porte-graines, tomate, pépinières forestières, voies ferrées… Une seule vise le fraisier.
- 22 de ces AMM existent déjà dans E-Phy (DECIS PROTECH, AMISTAR, MOVENTO retiré, DESOGERME retiré…) : la
  dérogation leur **ajoute un usage**. 10 n'y sont pas (2140084, 2219993, 2220766, 2229997, 2249996, 2249997,
  2260141, 2260251, 2260410, 2260551).
- Structure de la page (relevée par cropivia, toujours vraie) : chaque décision est une carte DSFR,
  `<a href="/telecharger/{id}">n°{AMM} - {NOM}</a>` sans extension `.pdf` ; « Culture(s) concernée(s) : … »
  est dans le texte qui **précède** l'ancre.
- La page ne garde que les décisions récentes : une décision échue finit par en disparaître.
- Une décision fait environ 4 pages : produit, titulaire, substances, classes de danger, conditions d'emploi
  (SP1, SPe, EPI), dates de début et de fin, et un tableau d'usages (code, libellé, culture, plein champ ou
  sous abri, cible, dose maximale et unité, nombre d'applications, stades BBCH, délai avant récolte).

## Décisions prises

| Sujet | Décision |
|---|---|
| Périmètre | **Toutes les cultures** (cropivia filtre le fraisier ; Lexicon sert tous les clients) |
| Rangement | **Dans les tables E-Phy** : usages ajoutés à `registered_phytosanitary_usages`, produits absents ajoutés à `registered_phytosanitary_products` |
| État d'un usage dérogatoire | `authorized` entre le début et la fin de la dérogation, `withdrawn` ensuite, calculé au build |
| Produit déjà dans E-Phy | Ligne **inchangée** (garde l'état E-Phy, même retiré) ; seuls les usages s'ajoutent |
| Produit absent d'E-Phy | Créé, `product_type` `DEROGATION`, avec ses dates |
| Lecture des PDF | **Mistral OCR** avec un schéma JSON strict (comme cropivia), extraction **mise en cache** par empreinte du PDF |
| Dérogations échues | **Gardées**, avec leurs dates : un traitement fait pendant la dérogation reste justifiable |
| Rythme | **Chaque semaine**, avec la routine des intrants sur le poste fixe du bureau |

## Exigences fonctionnelles

- **F1 — Collecte.** `collect` lit la page, relève pour chaque décision l'AMM, le nom, les cultures annoncées et
  l'URL du PDF, et télécharge les PDF qu'il n'a pas encore. Les PDF s'accumulent dans
  `raw/phytosanitary/derogations/`, nommés par leur empreinte ; un PDF retiré de la page n'est jamais effacé.
- **F2 — Extraction.** Chaque PDF est lu une fois par Mistral OCR ; le JSON obtenu est gardé à côté du PDF. Un
  build rejoué sans réseau et sans clé redonne le même résultat à partir de ce cache.
- **F3 — Contrôle.** Une extraction est refusée (et le dit) quand il lui manque l'AMM, les dates, ou tout usage ;
  quand l'AMM lue diffère de celle de la page ; quand une dose ou un stade sort des bornes. Une décision refusée
  n'empêche pas les autres d'entrer, mais le build dit lesquelles manquent.
- **F4 — Usages.** Chaque usage d'une décision devient une ligne de `registered_phytosanitary_usages`, d'id
  stable `DEROG:{amm}:{code usage}:{milieu}` (le code seul n'est pas unique : une décision peut porter le même
  code en plein champ et sous abri). Colonnes remplies comme pour E-Phy : `ephy_usage_phrase`, culture, cible,
  dose et unité, `applications_count`, stades min et max, délai avant récolte, conditions d'emploi.
- **F5 — Marquage.** Trois colonnes nouvelles sur les usages : `is_derogation`, `derogation_started_on`,
  `derogation_stopped_on`. Les produits créés portent les mêmes dates.
- **F6 — État.** `state` d'un usage dérogatoire : `authorized` si la date du build est entre le début et la fin,
  `withdrawn` sinon. Un produit E-Phy n'est jamais modifié.
- **F7 — Espèces.** La culture d'une dérogation est en texte libre (« Tomate - aubergine (sous abris) »,
  « kiwi, kiwaï ») : elle passe par les mêmes rapprochements que les usages E-Phy (cropsets, nomenclature,
  `exceptions`) ; ce qui ne se rapproche de rien est listé par le build.
- **F8 — Historique.** Une décision vue une fois reste dans le paquet après sa disparition de la page.
- **F9 — Remplacement.** Une décision publiée à nouveau (prolongation, correction) remplace les usages de la
  même AMM et du même code ; l'ancienne reste dans `raw/` mais n'est plus construite.
- **F10 — Source.** Le paquet garde, pour chaque décision, l'URL de son PDF sur agriculture.gouv.fr ; les PDF
  eux-mêmes ne sont pas dans le paquet.

## Exigences non fonctionnelles

- **NF1** — Sans `MISTRAL_API_KEY`, le build passe : il prend ce qui est en cache et dit combien de PDF n'ont pas
  été lus.
- **NF2** — La page change de structure : `collect` le dit et le build continue avec le cache, sans effacer de
  dérogation.
- **NF3** — `phytosanitary` déclare `schema_revision 2` (colonnes ajoutées) ; `credits` cite la source du ministère
  à côté de celle de l'ANSES.
- **NF4** — Un build hebdomadaire sans décision nouvelle ni changement d'E-Phy ne produit pas de nouvelle version
  du paquet (`source_date`).
- **NF5** — La logique de lecture et de contrôle d'une extraction est testable sans réseau ni base (comme
  `Datasources::FuelPrices::Readings`).

## Critères d'acceptation

1. Sur la page du 2026-11-07, le build produit les usages des 37 décisions ; les 10 AMM absentes d'E-Phy
   deviennent des produits `DEROGATION`.
2. SANTHAL GOLD (AMM 2230002) n'est plus sur la page : son PDF, gardé dans
   `cropivia_backend/docs/2026-124-DECISION-SANTHAL Gold-fraisier_VSignée.pdf`, déposé dans le cache, donne les
   mêmes 4 usages que cropivia, avec ses dates du 02/07 au 30/10/2026, et l'état `withdrawn` au 2026-11-07.
3. DECIS PROTECH garde sa ligne produit et ses usages E-Phy intacts ; ses usages dérogatoires s'y ajoutent.
4. Un second build sans réseau donne le même paquet.
5. Une décision retirée de la page reste dans le paquet suivant.
6. Ekylibre, sans changement, voit les usages en cours et ne propose pas les usages échus.

## Questions ouvertes (pour la conception)

- **Q1 — Lecture du PDF par Mistral.** cropivia envoie une URL publique (bucket Supabase public). Ici :
  l'URL `/telecharger/{id}` d'agriculture.gouv.fr directement, ou le PDF en base64 ? À essayer.
- **Q2 — Volume et coût.** 37 PDF au premier passage, puis quelques-uns par semaine. Modèle `mistral-ocr-latest`,
  limite de 8 pages pour `document_annotation`.
- **Q3 — Rapprochement des cultures.** Faut-il un fichier `data/phytosanitary/derogation_crops.csv` relu par le
  métier, à côté de `exceptions` ?
- **Q4 — Rythme sans reconstruire E-Phy.** Reconstruire `phytosanitary` entier chaque semaine retélécharge E-Phy.
  Accepté, ou une collecte des dérogations seule ?
- **Q5 — Consommateurs.** Vérifier dans Ekylibre et `lexicon-rest-api` qu'aucun ne suppose qu'un id d'usage a la
  forme E-Phy, ni qu'un `product_type` vaut `PPP`, `ADJUVANT`, `PRODUIT-MIXTE` ou `PCP`.
- **Q6 — Conditions d'emploi.** Elles vont dans `usage_conditions` en texte, ou dans les mentions du produit créé ?

## Suite

`/sc:design` sur ce cadrage, puis un plan. Rien n'est implémenté.
