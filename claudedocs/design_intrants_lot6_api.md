# Conception — Lot 6 : écrans, API et MCP pour les intrants

Conception et implémentation du 2026-10-07, dans le dépôt `lexicon-rest-api`, branche `feature/inputs`. Besoins :
`claudedocs/brainstorm_intrants.md` (F28 à F32, CA1, CA2, CA7). Essayé sur une API de développement branchée sur
la base de service locale ; ni fusionné ni déployé.

## 0. Constat de départ

`master_prices` et `master_phytosanitary_prices`, les deux tables de prix que lit Ekylibre, n'étaient servies par
aucune route de l'API. `/production/prices` sert autre chose : les prix des productions par département.

## 1. Décisions

| # | Sujet | Décision |
|---|---|---|
| C1 | Emplacement | Un espace `/inputs`, lié depuis « Explorer ». Les routes existantes ne changent pas |
| C2 | Pages | Quatorze tables, déclarées comme des données : chemin, ordre, colonnes, filtres. Une seule fonction les construit |
| C3 | Accès | Ouvert : prix de référence et leur provenance, GNR, matières actives, composition. Réservé aux adhérents : tout ce qui nomme un marchand |
| C4 | Outil MCP | `get_input_price` : le dernier prix d'un intrant cherché par nom de produit, matière active ou article, et le coût d'une quantité |
| C5 | Ce que lit l'outil | Les tables ouvertes seulement : la réponse est la même pour tous, Duke compris |
| C6 | Réponse vide | Quand rien n'a de prix, l'outil dit quels produits autorisés correspondent sans prix |
| C7 | Page d'accueil | Le tissage des jeux et des clés, écrit à la main, n'est pas modifié |

### Pourquoi déclarer les pages comme des données (C2)

Les autres espaces écrivent chaque page à la main, une cinquantaine de lignes par table. Pour quatorze tables qui
se ressemblent, cela faisait sept cents lignes ; la déclaration en fait trois cents, et une table de plus est une
entrée de plus. C'est aussi ce dont l'outil de contribution aura besoin : servir un jeu neuf sans écrire de code.

## 2. Routes

| Route | Table | Accès |
|---|---|---|
| `/inputs/article-prices` | `master_prices` | ouvert |
| `/inputs/phytosanitary-prices` | `master_phytosanitary_prices` | ouvert |
| `/inputs/price-sources` | `master_price_sources` | ouvert |
| `/inputs/fuel-prices` | `registered_fuel_monthly_prices` | ouvert |
| `/inputs/phytosanitary-substances` | `registered_phytosanitary_substances` | ouvert |
| `/inputs/phytosanitary-product-substances` | `registered_phytosanitary_product_substances` | ouvert |
| `/inputs/fertilizers` | `registered_fertilizers` | adhérents |
| `/inputs/fertilizer-prices` | `registered_fertilizer_monthly_prices` | adhérents |
| `/inputs/fertilizer-unit-values` | `registered_fertilizer_unit_values` | adhérents |
| `/inputs/fertilizer-price-readings` | `registered_fertilizer_price_readings` | adhérents |
| `/inputs/seed-species` | `registered_seed_species` | adhérents |
| `/inputs/seed-prices` | `registered_seed_monthly_prices` | adhérents |
| `/inputs/seed-price-readings` | `registered_seed_price_readings` | adhérents |
| `/inputs/phytosanitary-price-readings` | `registered_phytosanitary_price_readings` | adhérents |

Chacune existe en HTML, `.json` et `.csv`, avec ses filtres et les crédits de son jeu.

## 3. Essais (2026-10-07)

| Essai | Résultat |
|---|---|
| Les six pages ouvertes, sans clé | 200 |
| Les huit pages réservées, sans clé | 401 |
| Les huit pages réservées, avec une clé d'adhérent créée en local | 200 |
| `get_input_price` « ammonitrate » | trois prix, deux relevés et un estimé, datés d'octobre 2026 |
| `get_input_price` « blé tendre », quantité 150 | semence à 0,95 €/kg, coût 142,98 € |
| `get_input_price` « gazole » | 1,6889 €/L |
| `get_input_price` « metazachlor », quantité 2 | neuf produits, dont deux à prix de 2026 |
| `get_input_price` « glyphosate », quantité 3 | aucun prix ; dix produits autorisés signalés sans prix |
| Tests | 136, dont 9 nouveaux |

## 4. Écarts au besoin

| Besoin | État |
|---|---|
| CA7, chiffrer un désherbage au glyphosate en deux appels | L'outil répond en un appel, mais qu'aucun prix n'existe : sur 727 produits au glyphosate, aucun n'a de prix dans le Lexicon |
| F29, fiche d'un produit avec l'évolution de son prix | Pas de fiche : l'historique se lit en filtrant la table par article. Pas de graphique |
| F31, prix à une date donnée | L'outil rend le dernier prix ; les séries mensuelles sont dans les tables réservées |
| CA2, prix d'une formule absente | Les valeurs d'unités sont servies (adhérents) ; le calcul reste à faire par l'appelant |
| Routes et outil pour les données réservées par MCP | `read_resource` les lit déjà avec la clé de l'appelant |

## 5. Pour mettre en service

1. Relire et fusionner `feature/inputs` dans `main` de `lexicon-rest-api`.
2. Publier une version (`bun run ./bin/tag.ts`, qui pousse sur `origin/main` et crée l'étiquette).
3. Redéployer la pile dans Dokploy : l'image de l'API y est tirée à chaque déploiement.
