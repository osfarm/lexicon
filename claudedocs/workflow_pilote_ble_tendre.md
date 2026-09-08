# Workflow d'implémentation — Pilote « Blé tendre hiver »

> Généré par `/sc:workflow` (2026-07-02). **Plan uniquement — aucune exécution/écriture de données.**
> Prérequis : `claudedocs/prix/REQUIREMENTS_maj_prix_intrants.md`.
> Étape suivante : `/sc:implement` phase par phase.

## 0. Objet & résultat attendu

Valider de bout en bout la méthode de mise à jour prix + ITK sur **une seule culture**
(`ITKs_ble_tendre_hiver.ods` + lignes correspondantes de `data/prices/`), avant
généralisation aux 23 autres cultures.

**Definition of Done du pilote**
- CA1 : 0 article orphelin — tout article de l'ITK blé tendre a un prix dans `prices/`.
- CA2 : prix rafraîchis datés 2026 + source tracée.
- CA3 : unités ITK (`kg`,`l`,`q`,`t`) cohérentes avec `packaging` des prix.
- CA4 : schéma CSV inchangé (diff = valeurs/dates uniquement).
- CA5 : `./lexicon run prices` + `./lexicon validate` passent sans erreur.

## 1. Analyse d'écart (déjà réalisée — factuelle)

Articles référencés par l'ITK blé tendre (feuilles `conventionnel` + `biologique`) :

| Catégorie | Articles | Présents dans `prices/` |
|---|---|---|
| seeds | `common_wheat_seed` | ✅ |
| fertilizer | `ammonitrate_33`, `tsp_45`, `potassium_chloride`, `litter_cattle_manure` | ✅ |
| **plant_medicine** | `2100112`, `2110178`, `2130075`, `2140186`, `2200102`, `9800277` | ❌ **6/6 absents** |
| matters / straw_bales | `common_wheat_grain`, `common_wheat_straw` | ✅ |

**Conclusion** : le gap bloquant est les **6 prix phyto**. Le reste = rafraîchissement de valeurs
existantes (2019 → 2026), non bloquant.

## 2. Modèle technique confirmé (code Lexicon)

- Datasource `lib/datasources/prices.rb` charge les 7 CSV → tables `master_prices`,
  `master_phytosanitary_prices`, `master_doer_contracts`.
- `prices.phytosanitary_costs.article_id` → **FK vers `registered_phytosanitary_products.id`**
  (voir `.references(...)` dans `prices.rb`, table déf. `phytosanitary.rb:64`).
- Table `registered_phytosanitary_products` (datasource `phytosanitary`) fournit la
  **correspondance automatique** :
  - `id` (integer) = clé-article utilisée dans les CSV **et** dans les ITK (`plant_medicine`).
  - `name` + `other_names[]` = nom(s) commercial(aux).
  - `france_maaid` = n° AMM officiel.
  → Jointure `id`/`name` = automatisation de EF1 pour le phyto (semences/engrais restent
    des clés lexicales manuelles type `ammonitrate_33`).

## 3. Phases d'implémentation

### Phase A — Socle correspondance (prérequis technique)
- **A1** : `./lexicon run phytosanitary` (peupler `registered_phytosanitary_products`).
- **A2** : Extraire pour les 6 AMM la correspondance `id → name / other_names / france_maaid` :
  ```sql
  SELECT id, name, other_names, france_maaid, firm_name, product_type
  FROM lexicon.registered_phytosanitary_products
  WHERE id IN (2100112,2110178,2130075,2140186,2200102,9800277);
  ```
- **A3** : Recouper avec les indices « nom commercial » déjà présents dans l'ITK
  (colonne commentaire : `BAÏA E`, `PRIMUS`, `Aviator`, `AKELA`, `AFIKILL`, `metarex`).
- **Checkpoint A** : les 6 ids résolvent bien un nom commercial. Sinon → produit
  retiré/AMM changée : décision (substitution produit dans l'ITK ?).
- **Dépendances** : aucune. **Bloque** : Phase C (prix phyto).

### Phase B — Rafraîchissement des prix existants (non-phyto)
- **B1** : Semences (`common_wheat_seed`) → prix 2026. Source : web-agri (cotation semence)
  ou CEGARA. Priorité **CEGARA > web-agri > agryco**.
- **B2** : Engrais (`ammonitrate_33`, `tsp_45`, `potassium_chloride`) → web-agri (urée/ammonitrate
  cotés) + agryco pour les moins courants. `litter_cattle_manure` : barème CEGARA.
- **B3** : Productions (`common_wheat_grain`, `common_wheat_straw`) → cotation céréales web-agri.
- **Règle EF3** : **écraser** la ligne (remplacer `price` + `date`), 1 ligne/article.
- **Checkpoint B** : chaque valeur modifiée a une source notée (traçabilité ENF1).
- **Dépendances** : indépendante de A → **parallélisable avec Phase A**.

### Phase C — Ajout des 6 prix phyto manquants
- **C1** : Pour chaque AMM, obtenir un prix HT/unité :
  1. `BD FOURNITURES-ETA.xls` feuille `BASE DONNEES` (colonnes `Nom commercial` + `Prix HT`
     + `Unité`) — source prioritaire si le produit y figure ;
  2. sinon **agryco.com** (recherche par nom commercial, prix HT/unité, accès libre) ;
  3. sinon barème CEGARA PDF.
- **C2** : Construire les 6 lignes `phytosanitary_costs.csv` au schéma exact :
  `n,name,article_id,price,currency,packaging,date`
  avec `name = <maaid|slug>_bulk`, `article_id = id`, `packaging ∈ {liter_bulk,kilo_bulk}`
  cohérent avec l'unité ITK (`l`→liter, `kg`→kilo), `date = JJ/MM/2026`.
- **Checkpoint C** : `article_id` ∈ `registered_phytosanitary_products.id` (FK valide) ;
  packaging cohérent avec l'unité de dose ITK.
- **Dépendances** : **requiert Phase A** (résolution des ids).

### Phase D — Écriture des CSV (schéma préservé)
- **D1** : Appliquer B + C dans les fichiers `data/prices/*.csv`.
- **D2** : Renuméroter la colonne `n`/`N°` si insertion de lignes (séquence continue).
- **Contrainte EF2/CA4** : ne pas ajouter/retirer de colonnes ; conserver `snake_case`,
  `euro`, format date `DD/MM/YYYY`, séparateur `,`, décimale `.`.
- **Checkpoint D** : `git diff` ne montre que valeurs/dates/lignes ajoutées.

### Phase E — Revue de l'ITK (technical_workflows)
- **E1** : Vérifier que les articles/quantités/doses de `ITKs_ble_tendre_hiver.ods` sont
  toujours d'actualité (produits non retirés, doses réglementaires courantes).
- **E2** : Si un phyto est retiré (Checkpoint A KO), le **substituer** dans l'ITK par un
  produit équivalent homologué (feuilles `conventionnel` **et** `biologique`).
- **Contrainte EF4** : préserver la structure ODS (en-têtes lignes 0-2, 2 feuilles, formules).
- **Dépendances** : dépend de Phase A (statut des produits).

### Phase F — Validation & non-régression
- **F1** : `./lexicon run prices` (recharge + normalise sans erreur).
- **F2** : `./lexicon validate` (schéma conforme aux définitions).
- **F3** : Requête d'intégrité — 0 orphelin pour le blé tendre :
  ```sql
  -- tout plant_medicine de l'ITK a un prix
  SELECT p.article_id FROM ... -- articles ITK blé tendre
  LEFT JOIN lexicon.master_phytosanitary_prices m ON m.reference_article_name = p.article_id
  WHERE m.id IS NULL;  -- doit être vide
  ```
- **F4** : Recalcul du **coût total de l'ITK** blé tendre avant/après → variation expliquée
  (les 6 phyto passent de 0 € à un coût réel + rafraîchissements).
- **Checkpoint F (Quality Gate)** : CA1–CA5 tous verts → pilote validé.

## 4. Graphe de dépendances & parallélisme

```
A (correspondance phyto) ─┬─► C (prix phyto) ─┐
                          └─► E (revue ITK)    ├─► D (écriture CSV) ─► F (validation)
B (refresh non-phyto) ─────────────────────────┘   (E écrit l'ODS)
```
- A et B en parallèle. C après A. D après B+C. E après A. F en dernier (quality gate).

## 5. Risques & mitigations (spécifiques pilote)

| Risque | Impact | Mitigation |
|---|---|---|
| Un des 6 AMM retiré / introuvable dans `registered_phytosanitary_products` | Bloque C | Checkpoint A → substitution produit dans ITK (E2) |
| Unité de dose ITK ≠ packaging prix (l vs kg) | Coût faux | Contrôle explicite Checkpoint C |
| Prix agryco = ponctuel non représentatif | Qualité barème | Priorité CEGARA/web-agri ; agryco en dernier recours |
| Scraping web-agri paywall | Manque commodités | Extraction manuelle de secours (R3 des exigences) |
| Renumérotation `n` casse un id `CONCAT('PH', n)` en doublon | Erreur normalize | Vérifier unicité des ids générés (Checkpoint D) |

## 6. Livrables du pilote
1. `data/prices/prices - phytosanitary_costs.csv` : +6 lignes.
2. `data/prices/*.csv` (seed/fertilizer/farm_product) : valeurs+dates rafraîchies.
3. `ITKs_ble_tendre_hiver.ods` : éventuelles substitutions produit.
4. Table de correspondance phyto (id ↔ nom ↔ maaid ↔ prix ↔ source) — artefact réutilisable
   pour la généralisation.
5. Rapport de validation F (résultat des quality gates + Δ coût ITK).

## 7. Généralisation (post-pilote, hors périmètre immédiat)
Rejouer A→F par culture. La Phase A devient un **batch unique** sur tous les AMM de tous les
ITK (une seule requête `registered_phytosanitary_products`). B/C se factorisent par article
partagé entre cultures (ex. `ammonitrate_33` réutilisé partout).

---
**Prochaine étape** : `/sc:implement` en commençant par **Phase A** (socle correspondance),
puis B en parallèle.
