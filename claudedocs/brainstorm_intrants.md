# Brainstorm — Références et prix des intrants (phytos, semences, engrais)

Date : 2026-10-07. Statut : besoins validés, décisions en §0. Révision 2 : réponses
de David aux questions Q1 à Q10. Deux questions restent, non bloquantes (§9).

> Document d'exigences issu de `/sc:brainstorm`. Pas de conception : le schéma
> des tables, les routes de l'API et l'architecture de l'outil de contribution
> relèvent de `/sc:design`.
> Sources étudiées : <https://app.itinera.ag/docs/referentiels> (lu le
> 2026-10-07), les datasources `phytosanitary`, `seed_varieties`, `variants` et
> `prices`, et le cadrage `claudedocs/prix/REQUIREMENTS_maj_prix_intrants.md`
> (2026-07-02), que ce document prolonge.

Demande : faire évoluer les jeux liés aux phytos, aux semences et aux engrais
pour y ajouter les références et les prix que montre Itinera (Neayi). S'en
servir pour éprouver la méthode de construction puis de publication, en local
et en production, afin d'en tirer un outil simple pour la communauté Lexicon
OSFarm. Adapter ensuite les écrans web, l'API et le serveur MCP à ces jeux.

## 0. Décisions prises

| # | Sujet | Décision |
|---|---|---|
| D1 | Provenance | Lexicon **recollecte lui-même aux sources amont** (E-Phy, EIQ, HRAC, DGEC, catalogues marchands). Rien n'est repris d'Itinera, qui sert de modèle de couverture |
| D2 | Accès | Les prix sont **ouverts à tous**, comme les références |
| D3 | Historique | **Les deux** : une série mensuelle par article, et `master_prices` tenu à jour avec la dernière valeur pour rester compatible avec Ekylibre |
| D4 | Contributeurs | **En deux temps** : d'abord le parcours développeur, validé sur ces jeux ; ensuite le dépôt de fichier par un non-développeur |
| D5 | Conditions des sources | Collecte et republication ouverte admises pour les sept sites marchands (Q1) ; réutilisation de l'EIQ et du HRAC vérifiée (Q2). Verdicts donnés par David |
| D6 | Espèces cultivées | Référentiel **reconstruit avec les données du Lexicon** (taxonomie, productions), complété si besoin par AGROVOC (FAO) (Q3) |
| D7 | Arbitrage entre sources | **Priorité fixe** : les sites marchands d'abord, puis CEGARA, puis web-agri (Q4) |
| D8 | Rythme | **Hebdomadaire**, lancé depuis le poste de build. Un runner automatique sur le serveur OSFarm viendra plus tard, hors périmètre (Q5) |
| D9 | Offres de groupement | Un prix « offre du mois » d'un groupement d'achats est un **prix négocié**, signalé comme tel (Q6) |
| D10 | Semences | **Toutes les espèces**, autant que les sources le permettent (Q7) |
| D11 | Périmètre des prix | **France métropolitaine, hors taxes** (Q8) |
| D12 | Neayi | Adhérent OSFarm, au courant de la démarche (Q9) |
| D13 | Outil du temps 2 | Emplacement non arrêté ; contrainte ferme : **un outil très simple** (Q10) |

## 1. Ce que l'on veut obtenir

1. Des référentiels d'intrants à jour et reliés entre eux : un produit phyto, une
   variété ou un engrais porte ses caractéristiques techniques **et** un prix
   daté, dont on connaît la source.
2. Une méthode éprouvée de bout en bout : construire, contrôler, empaqueter,
   publier en local, vérifier, publier en production. Ces trois jeux en sont le
   banc d'essai.
3. Un parcours de contribution assez simple pour qu'un membre de la communauté
   propose ou modifie un jeu sans connaître tout le dépôt.
4. Des écrans, une API et des outils MCP qui présentent ces jeux pour ce qu'ils
   sont : des références avec des prix dans le temps.

## 2. État des lieux

### 2.1 Ce que montre Itinera

| Référentiel | Contenu | Sources citées | Rythme |
|---|---|---|---|
| Phytos | Produits autorisés, usages, matières actives, indicateur de risque EIQ, mode d'action des herbicides (HRAC), prix | E-Phy (Anses), EIQ (Cornell), HRAC, Cereapro (offres du mois) | Hebdomadaire |
| Semences | Espèces cultivées (catégorie, nom latin, famille, saison, dose de référence, synonymes, codes PAC), variétés du commerce, prix | Table des espèces Neayi, Germineo, La Récolte, Semence Biologique, Agrileader, Agrilisa, Cereapro | Hebdomadaire |
| Engrais et amendements | Minéraux, organiques, amendements, foliaires : composition, prix mensuels, valeur du kilo de N, P, K et S tirée des engrais simples | Germineo, Cereapro, Agryco (cours quotidiens moyennés par mois depuis mi-2025) | Hebdomadaire, chaque fiche relue une fois par mois |
| GNR | Prix moyen national, relevé chaque vendredi depuis 2020, moyenné par mois (hors toutes taxes, hors TVA, TTC) | DGEC, ministère de la Transition écologique (classeur Excel) | Hebdomadaire |

Les pages de consultation (`/phytos`, `/semences`, `/engrais`) sont rendues dans
le navigateur ; aucun export ni API publique n'a été trouvé.

### 2.2 Ce que Lexicon a aujourd'hui

| Sujet | Constat |
|---|---|
| `phytosanitary` | E-Phy seul : produits, usages, risques, symboles, groupes de cultures. Ni EIQ, ni HRAC |
| `seed_varieties` | Catalogue SEMAE (20 479 variétés), relié à la taxonomie. Pas de prix, pas de dose de référence |
| Engrais | 182 articles dans `variants`. Pas de jeu dédié, pas de composition exploitable pour un calcul d'unités |
| `prices` | `master_prices` : 80 engrais, 25 semences, 32 phytos génériques ; `master_phytosanitary_prices` : 169 produits par n° AMM. Valeurs de **2019-2020**, une ligne par article, sans historique ni source |
| GNR | Absent |
| Couplage | Les itinéraires techniques (`technical_workflows`) désignent leurs articles par la clé de `prices` : tout article d'un itinéraire doit garder un prix |
| API | `/phytosanitary/{products,cropsets,symbols}`, `/seeds/varieties`, `/production/prices` |
| Méthode v2 | `./lexicon new`, `check`, `package`, `publish`, `server sync` existent. La pile de service tourne en local depuis le 2026-10-07 (`docker-compose.server.local.yml`), avec les 38 packages publics |
| Contribution | Parcours développeur outillé (J4). « Interface de dépôt de CSV pour non-développeurs » est aujourd'hui hors périmètre de la feuille de route |
| Dépôt de l'API | `lexicon-rest-api` n'est pas cloné sur le poste de développement |

## 3. Exigences fonctionnelles — données

### Phytos

- F1. Chaque matière active porte son EIQ (score global et composantes
  agriculteur, consommateur, écologique) quand Cornell en publie un.
- F2. Chaque matière active herbicide porte son groupe HRAC.
- F3. Un produit porte un prix daté quand une source en donne un, rattaché par
  son n° AMM.
- F4. Les tables actuelles de `phytosanitary` gardent leur forme : Ekylibre les
  lit.

### Semences

- F5. Un référentiel des espèces cultivées, construit à partir de la taxonomie
  et des productions du Lexicon (D6), donne au moins : nom latin, famille,
  catégorie, saison, dose de semis de référence. Il couvre toutes les espèces
  que les sources de prix proposent (D10).
- F6. Une variété du commerce porte un prix daté par conditionnement, et se
  rattache à la variété du catalogue officiel quand elle y figure.
- F7. Les semences biologiques sont distinguées des conventionnelles.

### Engrais et amendements

- F8. Un référentiel des engrais et amendements donne, par produit : type
  (minéral, organique, amendement, foliaire), teneurs (N, P, K, S et les autres
  éléments déclarés), présentation.
- F9. Un produit porte un prix daté par conditionnement.
- F10. La valeur du kilo de N, de P, de K et de S est publiée chaque mois, avec
  la méthode de calcul, pour chiffrer une formule absente du référentiel.
- F11. Les 182 articles engrais de `variants` se rattachent au nouveau
  référentiel.

### Énergie

- F12. Le prix mensuel du GNR depuis 2020 (hors toutes taxes, hors TVA, TTC) est
  publié. Source publique : c'est le jeu le plus simple, candidat au premier
  essai de la méthode.

### Prix, règles communes

- F13. Série mensuelle : un prix par article, par conditionnement et par mois,
  avec sa source et le nombre de relevés.
- F14. Les prix sont hors taxes, pour la France métropolitaine (D11). Chaque
  prix dit ce qu'il mesure : rendu exploitation ou départ, unité,
  conditionnement, et s'il s'agit d'un prix négocié par un groupement (D9).
- F15. Quand plusieurs sources donnent un prix pour le même article et le même
  mois, la priorité est fixe : sites marchands, puis CEGARA, puis web-agri
  (D7). L'ordre entre les sites marchands reste à fixer (Q11).
- F16. `master_prices` et `master_phytosanitary_prices` gardent leur forme et
  reçoivent la dernière valeur connue.
- F17. Aucun article cité par un itinéraire technique ne perd son prix.
- F18. Un article sans prix récent garde son dernier prix connu, avec sa date :
  l'ancienneté se voit, elle ne se cache pas.

## 4. Exigences fonctionnelles — méthode et contribution

### Parcours de validation (temps 1, développeur)

- F19. Un jeu nouveau ou modifié se valide par une suite de commandes
  documentée : construire, `check`, `package`, publier vers la pile locale,
  constater la mise en service et le rendu dans l'API locale, puis publier en
  production.
- F20. La publication locale et la publication en production se distinguent
  sans ambiguïté : on ne publie pas en production par mégarde.
- F21. Le parcours précise ce qui change quand un jeu est modifié plutôt
  qu'ajouté : révision de schéma, dépendances, chute de volume, jeux à publier
  ensemble.
- F22. Une collecte qui échoue (site modifié, source indisponible) ne remplace
  pas les données en service : la version précédente reste servie et l'échec
  est signalé.
- F23. Les frictions rencontrées sur ces trois jeux sont relevées : elles
  forment le cahier des charges de l'outil du temps 2.

### Outil communautaire (temps 2, non-développeur)

- F23 bis. L'outil est très simple (D13) : peu d'étapes, pas d'installation
  lourde, pas de notion à apprendre au-delà du fichier à fournir.
- F24. Un adhérent propose un jeu ou une correction à partir d'un fichier
  tabulaire, sans écrire de Ruby.
- F25. Il obtient avant tout envoi le verdict des contrôles automatiques
  (licence, données personnelles, schéma, taux de liaison, volume), dans des
  termes qu'il comprend.
- F26. Rien n'est mis en service sans validation d'un mainteneur.
- F27. La proposition garde son auteur, sa source et sa licence, repris dans les
  crédits du jeu.

## 5. Exigences fonctionnelles — écrans, API, MCP

- F28. Le catalogue présente les nouveaux jeux comme les autres : licence, date
  de la source, taux de liaison, versions.
- F29. Une fiche produit (phyto, variété, engrais) montre ses caractéristiques,
  son dernier prix et l'évolution de ce prix.
- F30. L'API sert les références, la série de prix par article et la dernière
  valeur ; les routes existantes ne changent pas de forme.
- F31. Le serveur MCP permet à un agent de trouver un intrant et son prix à une
  date donnée, et de chiffrer une dose.
- F32. Chaque prix affiché ou servi porte sa source, sa date et la mention que
  c'est un prix relevé, pas un barème.

## 6. Exigences non fonctionnelles

- NF1. **Licence** : les conditions de chaque source sont admises (D5) ; le
  verdict et sa date sont notés dans les crédits de chaque jeu ; `./lexicon check` doit passer sans nouvelle entrée dans
  `resources/check_baseline.yml`.
- NF2. **Collecte loyale** : respect des `robots.txt` et des conditions des
  sites, débit modéré, pas de contournement d'accès réservé.
- NF3. **Reproductibilité** : une collecte se rejoue ; les relevés bruts sont
  conservés pour qu'un mois passé ne dépende pas de l'état actuel d'un site.
- NF4. **Fraîcheur** : collecte hebdomadaire, lancée à la main depuis le poste
  de build (D8). Un jeu qui n'a pas été rafraîchi dans son délai apparaît
  périmé.
- NF5. **Compatibilité** : aucune table lue par Ekylibre ne change de forme sans
  révision de schéma annoncée.
- NF6. **Robustesse** : la disparition d'une source marchande dégrade la
  couverture, pas le jeu.
- NF7. **Mesure** : le taux de rattachement (prix vers AMM, variété vers
  catalogue officiel, engrais vers articles) est mesuré à chaque construction et
  publié dans le manifeste.

## 7. User stories et critères d'acceptation

- **Conseiller ou agriculteur** : je veux le prix d'un produit à la date de mon
  itinéraire, pour chiffrer mes charges.
  - CA1. Pour un n° AMM, une variété ou un engrais, l'API rend le prix du mois
    demandé, ou le dernier connu avec sa date.
  - CA2. Pour une formule NPK absente, le prix s'estime à partir des valeurs
    d'unités du mois.
- **Mainteneur** : je veux publier un jeu modifié sans casser ce qui est servi.
  - CA3. Le parcours F19 est suivi de bout en bout pour le GNR, puis pour un des
    trois jeux, en local puis en production, sans intervention manuelle sur le
    serveur.
  - CA4. Après publication, tout article des itinéraires techniques a un prix
    (0 orphelin).
- **Utilisateur d'Ekylibre** : je veux que mon installation continue de
  fonctionner.
  - CA5. `master_prices` et `master_phytosanitary_prices` ont les mêmes
    colonnes ; les dates sont de 2026.
- **Contributeur** : je veux savoir si mon jeu sera accepté avant de l'envoyer.
  - CA6. Les contrôles donnent un verdict et la raison de chaque refus.
- **Agent IA** : je veux répondre à « combien coûte un désherbage au
  glyphosate à 3 L/ha ce mois-ci ? ».
  - CA7. Deux appels d'outils MCP au plus suffisent.

## 8. Découpage proposé

| Lot | Contenu | Pourquoi dans cet ordre |
|---|---|---|
| 1 | GNR | Source publique, une table : premier passage complet de la méthode, local puis production |
| 2 | EIQ et HRAC sur les phytos | Sources publiques, modification d'un jeu existant : éprouve F21 |
| 3 | Engrais : référentiel, prix, valeur des unités | Premier jeu à prix marchands : éprouve la collecte et la licence |
| 4 | Prix des phytos, espèces et prix des semences | Même mécanique, rattachements plus difficiles (AMM, variétés) |
| 5 | Mise à jour de `master_prices`, contrôle des itinéraires | Dépend des lots 3 et 4 |
| 6 | Écrans, API, MCP | Dépend des données |
| 7 | Parcours développeur consolidé, puis outil de dépôt | Tire les leçons des lots 1 à 5 |

## 9. Questions ouvertes

Q1 à Q9 sont tranchées (D5 à D12). Restent, sans bloquer la conception des
premiers lots :

- Q10. **Emplacement de l'outil du temps 2** : interface d'administration de
  l'API, dépôt GitHub avec proposition assistée, ou autre. À décider après les
  lots 1 à 5, à la lumière des frictions relevées (F23).
- Q11. **Ordre entre les sept sites marchands** quand plusieurs donnent un prix
  pour le même article et le même mois : à fixer au lot 3, données en main.
- Q12. **Prix négocié et arbitrage** : Cereapro est à la fois site marchand
  (priorité haute, D7) et groupement d'achats (prix négocié, D9). Un prix
  négocié peut-il devenir le prix retenu d'un article, ou seulement à défaut
  d'un prix public ?

## 10. Hors périmètre

- Reprise de données depuis l'application Itinera.
- Runner automatique de collecte sur le serveur OSFarm (D8).
- Outre-mer et prix TTC (D11).
- Prix des équipements et de la main-d'œuvre (`equipment_costs`,
  `worker_contracts`).
- Mise à jour des doses dans les itinéraires techniques.
- Calcul d'indicateurs (IFT, charges par hectare) : Lexicon fournit les
  références, pas le calcul.

## 11. Prochaines étapes

1. Cloner `lexicon-rest-api` sur le poste de développement.
2. `/sc:design` sur le lot 1 (GNR) et le parcours de validation F19 à F23.
