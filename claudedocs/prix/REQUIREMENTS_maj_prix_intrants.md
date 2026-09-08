# Spécification d'exigences — Mise à jour des prix d'intrants & ITK

> Issu d'une session `/sc:brainstorm` (2026-07-02). Document de **découverte des exigences** —
> ne contient ni architecture détaillée ni code. Étape suivante : `/sc:design` ou `/sc:workflow`.

## 1. Contexte & objectif

Mettre à jour deux jeux de données de référence de Lexicon :

- `data/prices/` — 7 CSV normalisés (équipements, engrais, phyto par n° AMM, semences,
  produits de ferme, autres intrants, contrats de main d'œuvre). Valeurs **2019-2020**,
  orientées **grandes cultures**.
- `data/technical_workflows/` — 24 itinéraires techniques (ITK) `.ods`, 2 feuilles chacun
  (`conventionnel` / `biologique`).

Objectifs retenus :
- **O1 — Rafraîchir** les prix vers des valeurs actuelles.
- **O2 — Élargir** la couverture d'intrants/cultures.
- **O3 — Préserver l'intégrité** du couplage ITK ↔ prices.

## 2. Modèle de données découvert (couplage ITK ↔ prices)

Les ITK listent par intervention : `Type` (input/output), `Procedure_item`, `Article`,
`quantity`, `unit`. La clé `Article` correspond **exactement** à la colonne `article` /
`article_id` des CSV de `prices/`.

```
ITK (technical_workflows)  ──(article, quantity, unit)──►  PRICES (article → price)  ──►  coût ITK
```

**Invariant à préserver** : tout article référencé dans un ITK doit exister dans `prices/`
avec une unité cohérente (pas d'article orphelin après mise à jour).

Exemples d'articles vus dans `ITKs_ble_tendre_hiver.ods` :
`common_wheat_seed` (semence), `ammonitrate_33` / `tsp_45` / `potassium_chloride` (engrais),
`2100112` / `9800277` / `2130075` (n° AMM phyto), `common_wheat_grain` (sortie).

## 3. Cartographie sources → cibles (faisabilité vérifiée)

| Source | Accès | Contenu | Usage cible |
|---|---|---|---|
| `BD FOURNITURES-ETA.xls` (feuille `BASE DONNEES`, 286 produits) | ✅ local | Viti/arbo : doses, Prix HT, IPAMPA, `Source MAJ` | Élargir phyto/engrais/palissage viti |
| `guide cout standard avances aux cultures.pdf` (CEGARA, **déc. 2016**) | ✅ local | Grandes cultures : ITK chiffrés, coûts standards | Référence ITK + coûts (mais daté) |
| **agryco.com** | ✅ libre | Prix e-commerce HT/unité : engrais, semences, phyto | Rafraîchir prix intrants (distributeur) |
| **web-agri.fr/cotations** | ⚠️ partiel (abonnés) | Urée, GNR/énergies, céréales, lait, viande | Commodités + `farm_product_costs` |
| **groupecegara.fr/publications** | ❌ adhérent | Section « Coûts standards » récente | Téléchargement **manuel** requis (non scrapeable) |

## 4. Exigences fonctionnelles

- **EF1** — Table de correspondance « nom commercial ↔ n° AMM ↔ article-clé normalisée »
  pour raccrocher XLS et agryco aux clés existantes.
- **EF2** — Conserver strictement le schéma CSV (colonnes, `snake_case`, date `JJ/MM/AAAA`,
  devise `euro`, suffixe `_bulk`, `packaging`).
- **EF3** — Historisation : **écraser** (1 ligne par article ; prix + date remplacés en place).
  → *Décision retenue.* L'historique 2019-2020 n'est pas conservé dans le CSV
  (le versioning Git assure la trace).
- **EF4** — ITK : mettre à jour `quantity`/articles sans casser la structure ODS
  (2 feuilles, en-têtes en lignes 0-2, formules éventuelles).
- **EF5** — Arbitrage inter-sources : **priorité CEGARA > web-agri > agryco** *(par défaut,
  à confirmer)*. Retenir la source la plus haute disponible par article.

## 5. Exigences non-fonctionnelles

- **ENF1** — Traçabilité de la source par valeur (réutiliser une colonne type `Source MAJ`).
- **ENF2** — Reproductibilité du scraping (agryco/web-agri peuvent évoluer) : script rejouable.
- **ENF3** — Respect des CGU des sites (agryco libre ; web-agri : ne pas contourner le paywall).
- **ENF4** — Non-régression : le coût total calculé d'un ITK reste cohérent avant/après.

## 6. User stories / critères d'acceptation (pilote)

**Pilote retenu : blé tendre hiver.**

- *En tant que* mainteneur de Lexicon, *je veux* que tous les articles de
  `ITKs_ble_tendre_hiver.ods` existent dans `prices/` avec un prix actualisé et une source
  tracée, *afin que* le coût de l'itinéraire soit calculable et à jour.
- **CA1** : 0 article orphelin pour le blé tendre (jointure ITK → prices complète).
- **CA2** : chaque prix rafraîchi porte une date `2026` et une source identifiée.
- **CA3** : unités cohérentes entre ITK (`kg`, `l`, `q`, `t`) et `prices` (`packaging`).
- **CA4** : le schéma CSV est inchangé (diff = uniquement valeurs/dates, pas de colonnes).

## 7. Séquencement recommandé

1. **Pilote blé tendre** (bout en bout) → valide la méthode & la table de correspondance.
2. Généralisation aux autres **grandes cultures** couvertes par CEGARA/web-agri.
3. Volet **viticole** (vigne) à partir du XLS `BASE DONNEES`.
4. Élevage (bovin lait) en dernier (sources plus éparses).

## 8. Questions ouvertes / risques

- **Q1** — Arbitrage prix (EF5) : confirmer priorité CEGARA>web-agri>agryco, ou moyenne/fourchette ?
- **Q2** — Un PDF CEGARA **plus récent que 2016** existe-t-il (accès adhérent) ? Si oui, le fournir
  manuellement changerait la donne pour O1.
- **Q3** — Périmètre viti : les CSV cibles sont grandes-cultures ; faut-il **créer** de nouveaux
  articles viti (palissage, mise en bouteille…) ou rester sur le recouvrement grandes cultures ?
- **R1** — Le PDF local (2016) est **plus ancien** que les données existantes (2019-2020) :
  ne pas régresser en fraîcheur en l'utilisant pour O1.
- **R2** — Prix agryco = distributeur ponctuel, non représentatif d'un barème → réserver aux
  articles non couverts par CEGARA/web-agri.
- **R3** — Fragilité du scraping (structure des sites) → prévoir extraction manuelle de secours.

---
**Prochaine étape suggérée** : `/sc:workflow` (plan d'implémentation du pilote blé tendre) ou
`/sc:design` (schéma de la table de correspondance EF1 + règles d'arbitrage EF5).
