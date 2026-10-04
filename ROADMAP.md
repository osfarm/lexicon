# ROADMAP — Lexicon v2

## Vision

Lexicon v2 met à jour chaque source de données indépendamment des autres. Une
datasource est construite sur un poste de build, empaquetée avec sa propre
version, publiée, puis mise en service seule sur le serveur, sans reconstruire
ni recharger le reste.

```
Poste de build                          Serveur (piloté par Dokploy)
┌──────────────────────────┐            ┌────────────────────────────────────┐
│ ./lexicon run <ds>       │            │ dépôt de packages ──▶ loader       │
│ ./lexicon package <ds>   │   rsync    │        │                │          │
│ ./lexicon publish <ds>   │ ─────────▶ │        ▼                ▼          │
└──────────────────────────┘            │   HTTPS public     Postgres/PostGIS│
                                        │                        ▲           │
                                        │                       API          │
                                        │   sauvegarde quotidienne ──▶ S3    │
                                        └────────────────────────────────────┘
```

Cette feuille de route remplace celle qui prévoyait un dépôt par datasource et
Supabase : le projet reste un monorepo, et la base servie est un Postgres
simple. Les exigences sont dans `claudedocs/brainstorm_lexicon_v2.md`, la
conception dans `claudedocs/design_lexicon_v2_j1.md` (mises à jour
indépendantes) et `claudedocs/design_lexicon_v2_admin.md` (accès et
administration).

## Principes

- **Une datasource = un package = une version = une bascule.** La version est
  la date de build (`AAAA.MM.JJ.N`).
- **Chaque table appartient à une seule datasource.**
- **Le build reste local ; le serveur ne fait que charger et servir.**
- **La base servie se reconstruit depuis les packages** : ce sont eux qui sont
  sauvegardés.
- **Un échec ne casse rien** : une version refusée laisse la précédente en
  service.

## J1 — Mises à jour indépendantes

Fait :

- [x] Format de package par datasource : `manifest.json`, `structure.sql`,
      `indexes.sql`, données en CSV compressés (`./lexicon package`)
- [x] Publication par `rsync`, index des versions (`./lexicon publish`,
      `./lexicon status`)
- [x] Loader : chargement en staging, contrôles, bascule en une transaction,
      journal (`./lexicon server sync`, `status`, `watch`)
- [x] Dépendances entre datasources : références orphelines, bascule groupée,
      packages périmés, retour arrière, purge (`--together`, `rollback`,
      `prune`)
- [x] Traductions et crédits par package ; `master_translations` et
      `datasource_credits` deviennent des vues côté serveur
- [x] Bundles filtrés par flavor (`./lexicon bundle`)
- [x] Pile de service déployée par Dokploy : base, loader, dépôt public, API
- [x] Sauvegarde quotidienne du dépôt vers S3
- [x] 38 datasources en service, cadastre et hydrographie compris
- [x] Gem `lexicon-common` intégrée au dépôt (`lib/lexicon/common/`), reprise
      sous licence MIT avec l'accord d'Ekylibre

Reste :

- [ ] Publier `cadastre_owners` et `rd_agri`, réservées aux adhérents : elles
      attendent le contrôle d'accès (J6)
- [ ] Clé SSH limitée au dépôt de packages pour la publication
- [ ] Retirer les commandes de l'ancien format (`dump`, `remote`,
      `production`), dont le stockage MinIO n'existe plus
- [ ] Livrer dans `lexicon-rest-api` la correction du cache (branche
      `fix/count-cache`) : l'API gardait lignes et décomptes 24 heures, même
      après un chargement

## J2 — Catalogue et historique

- [ ] Catalogue dans l'API : datasources, versions, licences, date de la source
- [ ] Versions passées téléchargeables depuis le dépôt
- [ ] Interrogation dans le passé pour le RPG et les bénéficiaires de la PAC,
      par millésime
- [ ] Flavors paramétrés (un point et un rayon) pour l'usage embarqué sur une
      exploitation

## J3 — Liaison entre jeux de données

- [ ] Clés pivots déclarées par datasource : commune, SIREN et SIRET, parcelle
      cadastrale, parcelle PAC, numéro AMM, code culture, taxon, production,
      station météo
- [ ] Taux de correspondance mesuré à chaque build
- [ ] Fiches pré-jointes par commune, parcelle et entreprise (personnes
      morales uniquement)

## J4 — Recettes et contributeurs

- [ ] Format de recette par datasource : source, licence, schéma,
      transformation, tests
- [ ] Outil local pour créer, construire et tester une recette
- [ ] Contrôles automatiques sur les contributions : licence, données
      personnelles, schéma, taux de liaison, chute de volume

## J5 — Serveur MCP

- [ ] Accès des agents IA au catalogue, aux ressources et aux fiches

## J6 — Accès et administration

- [ ] Clés d'API délivrées aux adhérents OSFarm, plans et quotas
- [ ] Limitation de débit par clé, ou par adresse IP sans clé
- [ ] Interface web d'administration : clés, plans, consommation, état des
      datasources
- [ ] Bundles privés téléchargeables avec une clé autorisée

J6 ne dépend pas de J2 à J5 et peut passer avant.

## Hors périmètre pour l'instant

- Tuiles vectorielles, CDN, moteur analytique séparé
- Interface de dépôt de CSV pour non-développeurs
- Second serveur dédié au build
