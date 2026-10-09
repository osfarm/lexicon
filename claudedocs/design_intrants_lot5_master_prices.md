# Conception — Lot 5 : `master_prices` à jour et itinéraires techniques

Conception et implémentation du 2026-10-07. Besoins : `claudedocs/brainstorm_intrants.md` (F16 à F18, CA4, CA5,
D3). En service en local ; la production reste à faire.

## 0. Décisions

| # | Sujet | Décision |
|---|---|---|
| C1 | Accès | `prices` reste ouvert et reçoit des prix **agrégés, sans marchand** (décision de David, 2026-10-07). Le détail reste dans les jeux réservés |
| C2 | Estimation | Les engrais minéraux sans prix relevé sont chiffrés par la valeur des unités (décision de David, 2026-10-07) |
| C3 | Forme | `master_prices` et `master_phytosanitary_prices` ne changent pas de colonnes (CA5). La provenance va dans une table nouvelle, `master_price_sources` |
| C4 | Historique | Un article peut avoir plusieurs prix datés : seul le plus récent est remplacé |
| C5 | Lecture des jeux hebdomadaires | Pendant `normalize`, dans la base de build : `depends_on :fertilizers, :seeds, :phytosanitary_prices, :fuel_prices` |
| C6 | GNR | Nouvel article `non_road_diesel` dans `variants`, et son prix |
| C7 | Garde de l'estimation | Tonne, pas de Mg ni de Ca, N + P2O5 + K2O d'au moins 20 % |

### Pourquoi une table de provenance plutôt que des colonnes (C3)

Ekylibre lit ces deux tables : leur ajouter des colonnes demandait de coordonner un changement de schéma avec
lui. Une table à côté ne lui coûte rien, et dit pour chaque prix s'il est relevé, estimé ou repris des fichiers,
avec la valeur qu'il a remplacée.

### Pourquoi restreindre l'estimation (C7)

Sans garde, la formule donnait 253 € la tonne à un 0-0-30 + 43 SO3 + 10 MgO, quand un produit de ce type est
relevé à plus de 600 € : la valeur du soufre tirée du sulfate d'ammoniaque est basse, et le magnésium ne vaut
rien dans le calcul. Un 10-45-0 vendu au kilo perdait la moitié de son prix.

## 1. Mesures (2026-10-07)

| Mesure | Valeur |
|---|---|
| Prix d'engrais relevés | 16 |
| Prix d'engrais estimés | 17 |
| Prix de semences relevés | 13 |
| Produits phytosanitaires mis à jour | 4, et 12 ajoutés |
| GNR | 1,6889 €/L |
| Articles d'engrais dont le dernier prix est de 2026 | 33 sur 75 |
| Articles de semences dont le dernier prix est de 2026 | 13 sur 23 |
| Articles d'intrants des itinéraires sans prix | 6 sur 128, inchangé |
| Articles d'intrants des itinéraires avec un prix de 2026 | 18 sur 128 |

## 2. Corrections faites au passage

- 65 lignes de `prices - equipment_costs.csv` portaient une année sur deux chiffres (« 01/01/19 ») : 260 prix de
  matériel étaient datés de l'an 19.
- Le quatrième segment de coût des matériels recevait la date comme un texte ; elle est maintenant convertie
  comme les autres.

## 3. Ce que le lot ne règle pas

| Sujet | État |
|---|---|
| CA4, zéro article d'itinéraire sans prix | 6 restent : cinq numéros d'AMM sans source de prix, et `cow_insemination_straw` |
| Prix des phytos des itinéraires | 104 articles gardent un prix de 2016 à 2021 : une seule source, 16 produits |
| Semences à la dose (maïs, tournesol, colza, betterave) | Pas de prix au kilo, donc pas de mise à jour |
| Amendements, solutions azotées, engrais organiques | Ni relevés sous un article existant, ni estimables |
| `budgets`, `technical_workflows`, `technical_workflow_sequences` | Signalés périmés : à reconstruire contre les nouveaux `variants` et `prices` |
| Tests | Les règles sont en SQL dans `normalize` : pas de test unitaire, vérifiées sur la base de build et la base de service |
