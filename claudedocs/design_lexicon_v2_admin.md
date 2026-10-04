# Conception — Lexicon v2, jalon J6 : accès et administration

Conception du 2026-10-03. Exigences F30 à F37 de
`claudedocs/brainstorm_lexicon_v2.md`. Ce jalon s'appuie sur J1 pour une
seule page (état des datasources) ; le reste en est indépendant et peut être
livré avant.

## 0. Décisions de conception

| # | Sujet | Décision |
|---|---|---|
| A1 | Emplacement | **Dans `lexicon-rest-api`**, sous `/admin`. Pas de passerelle séparée |
| A2 | Accès anonyme | **Conservé**, avec un quota bas par adresse IP |
| A3 | Création des clés | **Par un administrateur, pour un adhérent OSFarm.** Pas de libre-service : l'adhésion est la condition d'obtention d'une clé |
| A4 | Limitation de débit | **Dans le processus de l'API**, en mémoire, par clé ou par IP. Traefik garde une limite grossière par IP en amont |
| A5 | État | Schéma Postgres **`lexicon_access`**, jamais touché par le loader, sauvegardé chaque jour vers S3 |
| A6 | Comptes administrateurs | **Deux comptes** locaux. Table dédiée, mot de passe haché (argon2id), session par cookie, création en ligne de commande. Pas de connexion déléguée |
| A7 | Ressources réservées | `cadastre_owners` et `rd_agri` exigent une clé ; tout le reste est ouvert |
| A8 | Plans | Les valeurs du §2.3 sont retenues comme valeurs initiales |

### Pourquoi dans l'API plutôt qu'ailleurs

L'API actuelle n'a ni authentification ni limitation de débit, mais tout son
trafic passe par un seul point : la boucle de `listen()` dans `src/API.ts`,
qui enveloppe chaque handler. Y insérer le contrôle d'accès touche un fichier.

| Option | Pour | Contre |
|---|---|---|
| **Dans `lexicon-rest-api`** | Même pile (Bun, JSX rendu côté serveur), même base, aucun conteneur en plus ; les pages d'admin réutilisent `generateTablePage` | La limitation en mémoire suppose une seule instance de l'API |
| Passerelle dédiée (Kong, APISIX, Unkey…) | Fonctions prêtes à l'emploi | Deux à quatre conteneurs et une base en plus sur un serveur de 32 Go ; une seconde interface à maintenir ; ne sait rien des datasources |
| Traefik seul | Déjà présent avec Dokploy | Limite par IP uniquement : ni clés, ni plans, ni interface |

Une seule instance suffit à la charge visée. Si l'API devait être répliquée,
les compteurs passeraient dans Redis sans changer le reste.

## 1. Vue d'ensemble

```
                    ┌──────────────────── lexicon-rest-api ────────────────────┐
 requête ─▶ Traefik │  contrôle d'accès ─▶ handler existant ─▶ réponse         │
            (limite │   1. identifie : clé (en-tête) ou IP                     │
             par IP)│   2. vérifie plan, portée, expiration                    │
                    │   3. consomme un jeton du seau                           │
                    │   4. compte l'usage (en mémoire)                         │
                    │                                                          │
                    │  /admin  ─▶ session administrateur ─▶ pages de gestion   │
                    └───────┬──────────────────────────────────┬───────────────┘
                            │ lecture seule                    │ lecture / écriture
                            ▼                                  ▼
                     lexicon, lexicon_meta              lexicon_access
```

## 2. Modèle d'accès

### 2.1 Identification

- Clé transmise par `Authorization: Bearer <clé>` ou `X-API-Key: <clé>`.
- Jamais dans l'URL : une clé en paramètre finit dans les journaux, les
  historiques et les liens partagés.
- Sans clé : l'appelant est identifié par son adresse IP (en-tête
  `X-Forwarded-For` posé par Traefik) et reçoit le plan `anonymous`.

### 2.2 Format d'une clé

`lex_<préfixe 8 car.>_<secret 32 car.>`

- Le préfixe est stocké en clair : il identifie la clé dans l'interface et
  les journaux.
- Le secret n'est stocké que sous forme de SHA-256. Les clés sont longues et
  aléatoires, un hachage rapide suffit, et il doit être vérifié à chaque
  requête.
- La clé complète est affichée une seule fois, à la création (F36).

### 2.3 Plans

Un plan fixe les limites ; une clé a un plan.

| Plan (proposé) | Par minute | Par jour | Taille de page max | Portées |
|---|---:|---:|---:|---|
| `anonymous` | 30 | 2 000 | 150 | données ouvertes |
| `standard` | 120 | 20 000 | 1 000 | données ouvertes, `members` |
| `partner` | 600 | 200 000 | 5 000 | données ouvertes, `members`, bundles désignés |
| `internal` | illimité | illimité | 10 000 | tout |

Les plans sont des lignes de table, modifiables depuis l'interface. Les
valeurs ci-dessus sont des points de départ.

### 2.4 Portées

Une portée désigne un groupe de ressources. Elle sert à deux choses :

- réserver des ressources sensibles ou sous licence restrictive
  (`cadastre_owners`, `rd_agri` en CC BY-NC-SA) ;
- réserver des bundles privés (`bundle:cultia`, F37).

Chaque namespace de l'API déclare la portée qu'il exige ; par défaut, `open`.
`cadastre_owners` et `rd_agri` exigent la portée `members`, que portent tous
les plans sauf `anonymous` (A7).

### 2.5 Adhésion OSFarm

Une clé n'est délivrée qu'à un adhérent OSFarm (A3). L'API ne connaît pas le
registre des adhérents : l'administrateur vérifie l'adhésion à la création.

- La clé enregistre l'adhérent (`owner_name`) et la **fin d'adhésion**
  (`membership_until`).
- `expires_at` vaut par défaut la fin d'adhésion : une adhésion non
  renouvelée ferme la clé sans action manuelle.
- La page des clés signale celles qui expirent dans les 30 jours ; les
  prolonger est une action d'un clic, une fois l'adhésion renouvelée.

## 3. Limitation de débit

- **Seau à jetons** par identité (clé ou IP), en mémoire : capacité égale à
  la limite par minute, rechargé en continu.
- **Quota journalier** : compteur par identité, remis à zéro à minuit UTC,
  rechargé depuis `usage_daily` au démarrage.
- **Coût d'une requête** : 1 par défaut ; les sorties CSV et GeoJSON de
  plusieurs pages coûtent le nombre de pages servies.
- Réponse normale : en-têtes `RateLimit-Limit`, `RateLimit-Remaining`,
  `RateLimit-Reset`.
- Dépassement : `429`, avec `Retry-After`. Clé inconnue, révoquée ou
  expirée : `401`. Portée insuffisante : `403`.
- **Garde-fou sur la base** : `statement_timeout` posé par requête selon le
  plan (5 s en anonyme, 30 s pour une clé), pour qu'une requête coûteuse ne
  monopolise pas le serveur ni ne retarde la bascule d'une datasource.
- Les seaux inactifs depuis une heure sont purgés ; la mémoire reste bornée.

## 4. Données : schéma `lexicon_access`

```sql
CREATE TABLE lexicon_access.plans (
  name            varchar PRIMARY KEY,
  per_minute      integer,              -- NULL = illimité
  per_day         integer,
  max_page_size   integer NOT NULL,
  statement_timeout_ms integer NOT NULL,
  scopes          text[] NOT NULL DEFAULT '{open}'
);

CREATE TABLE lexicon_access.api_keys (
  id           bigserial PRIMARY KEY,
  prefix       varchar NOT NULL UNIQUE,
  secret_hash  bytea   NOT NULL,
  plan         varchar NOT NULL REFERENCES lexicon_access.plans(name),
  owner_name   varchar NOT NULL,          -- adhérent OSFarm
  owner_email  varchar NOT NULL,
  membership_until date,                  -- fin d'adhésion ; NULL pour le plan internal
  note         text,
  extra_scopes text[] NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   bigint REFERENCES lexicon_access.admins(id),
  expires_at   timestamptz,
  revoked_at   timestamptz,
  last_used_at timestamptz
);

CREATE TABLE lexicon_access.usage_daily (
  day        date    NOT NULL,
  identity   varchar NOT NULL,            -- préfixe de clé, ou 'anonymous'
  namespace  varchar NOT NULL,
  requests   bigint  NOT NULL DEFAULT 0,
  throttled  bigint  NOT NULL DEFAULT 0,  -- réponses 429
  errors     bigint  NOT NULL DEFAULT 0,  -- réponses 5xx
  PRIMARY KEY (day, identity, namespace)
);

CREATE TABLE lexicon_access.admins (
  id            bigserial PRIMARY KEY,
  email         varchar NOT NULL UNIQUE,
  password_hash varchar NOT NULL,         -- argon2id
  created_at    timestamptz NOT NULL DEFAULT now(),
  disabled_at   timestamptz
);

CREATE TABLE lexicon_access.sessions (
  token_hash bytea PRIMARY KEY,
  admin_id   bigint NOT NULL REFERENCES lexicon_access.admins(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);

CREATE TABLE lexicon_access.audit_log (
  id       bigserial PRIMARY KEY,
  at       timestamptz NOT NULL DEFAULT now(),
  admin_id bigint REFERENCES lexicon_access.admins(id),
  action   varchar NOT NULL,              -- key.create, key.revoke, plan.update…
  target   varchar,
  detail   jsonb
);
```

- L'usage anonyme est **agrégé** sous l'identité `anonymous` : aucune adresse
  IP n'est écrite en base. Les seaux par IP ne vivent qu'en mémoire.
- Les clés sont lues en mémoire au démarrage et rafraîchies toutes les
  30 secondes : une révocation prend effet en moins d'une minute, sans
  requête SQL par appel.
- Les compteurs d'usage et `last_used_at` sont écrits par lot, une fois par
  minute.

### Rôles Postgres

L'API se connecte aujourd'hui avec un seul utilisateur. Elle passe à un rôle
`lexicon_api` : lecture seule sur `lexicon` et `lexicon_meta`, lecture et
écriture sur `lexicon_access` seulement. Le loader garde un rôle distinct,
propriétaire de `lexicon`.

## 5. Interface web `/admin`

Rendue côté serveur comme le reste du site (JSX vers HTML, sans état client).

| Page | Contenu | Actions |
|---|---|---|
| `/admin/login` | Connexion | — |
| `/admin` | Synthèse : requêtes du jour, part de 429, clés actives, datasources `stale` | — |
| `/admin/keys` | Liste : préfixe, adhérent, plan, dernière utilisation, état, fin d'adhésion ; alerte sur les clés qui expirent sous 30 jours | Filtrer, prolonger |
| `/admin/keys/new` | Formulaire : adhérent, e-mail, fin d'adhésion, plan, portées, note | Créer ; la clé s'affiche une fois |
| `/admin/keys/:prefix` | Détail et consommation sur 30 jours par namespace | Révoquer, renouveler (nouvelle clé, ancienne valable 7 jours), changer de plan |
| `/admin/plans` | Limites et portées de chaque plan | Modifier |
| `/admin/usage` | Consommation par jour, par clé, par namespace ; top des clés ; 429 et erreurs | Exporter en CSV |
| `/admin/datasources` | Version en service, date de chargement, `stale`, derniers chargements et échecs (lit `lexicon_meta`, J1) | Lecture seule |
| `/admin/audit` | Journal des actions d'administration | — |

Déclencher un chargement ou un retour arrière depuis l'interface reste hors
périmètre : ces actions passent par `lexicon server` (J1). Les exposer sur le
web élargirait la surface d'attaque pour un gain faible avec un seul
mainteneur.

### Sécurité de l'interface

- Cookie de session `HttpOnly`, `Secure`, `SameSite=Strict`, valable
  12 heures ; seul son hachage est en base.
- Jeton anti-CSRF sur chaque formulaire. L'API n'accepte aujourd'hui que
  `GET` ; les `POST` sont limités à `/admin`.
- Connexion limitée à 5 essais par 15 minutes et par IP.
- Aucune inscription publique : `bun run bin/admin.ts create <email>` crée
  un compte et demande le mot de passe au terminal.
- Les en-têtes CORS permissifs actuels (`Access-Control-Allow-Origin: *`) ne
  s'appliquent pas à `/admin`.
- Option : restreindre `/admin` à une liste d'adresses IP dans Traefik.

## 6. Bundles privés (F37)

Le dépôt de packages est servi en statique et reste public pour les données
ouvertes. Le répertoire `_bundles/` n'est pas exposé par le serveur
statique : il est servi par une route de l'API, `/bundles/<flavor>/…`, qui
vérifie la portée `bundle:<flavor>` avant d'envoyer le fichier. Cultia
télécharge son bundle avec sa clé.

## 7. Changements dans `lexicon-rest-api`

| Fichier | Changement |
|---|---|
| `src/API.ts` | Appel du contrôle d'accès dans la boucle de `listen()`, avant le handler ; en-têtes de quota sur la réponse ; méthode `scope()` pour qu'un namespace déclare sa portée ; acceptation de `POST` sous `/admin` |
| `src/access/` (nouveau) | Résolution de l'identité, cache des clés, seaux à jetons, compteurs d'usage, écriture par lot |
| `src/namespaces/Admin/` (nouveau) | Pages du §5 |
| `src/namespaces/Bundles.ts` (nouveau) | Route du §6 |
| `src/applyRequestConfiguration.ts` | Identité et plan ajoutés au `Context` ; `statement_timeout` par requête |
| `bin/admin.ts` (nouveau) | Création et désactivation des comptes administrateurs |
| `src/assets/translations.csv` | Libellés de l'interface |

Les conventions du dépôt s'appliquent : `Result` de `shulk` à la place de
`try/catch`, `match()` à la place de `switch`, chemins en `kebab-case`. Le
dépôt n'a pas de suite de tests ; le contrôle d'accès est le premier module
qui en mérite une (seaux, expiration, portées).

Le serveur MCP (J5) réutilisera les mêmes clés et les mêmes plans.

## 8. Lots et effort

| Lot | Contenu | Effort |
|---|---|---:|
| A | Schéma `lexicon_access`, rôles Postgres, sauvegarde quotidienne | 1 j |
| B | Contrôle d'accès : identité, cache des clés, seaux, quotas, en-têtes, codes 401/403/429, tests | 3–4 j |
| C | Comptes administrateurs, session, CSRF, `bin/admin.ts` | 1–2 j |
| D | Pages clés et plans, journal d'audit | 2–3 j |
| E | Comptage d'usage et page de consommation | 1–2 j |
| F | Page des datasources (après J1), route des bundles privés | 1 j |
| | **Total** | **9–13 j** |

Les lots A à E ne dépendent pas de J1. Ils peuvent passer avant si
l'ouverture de l'API à des tiers est plus urgente que les mises à jour
indépendantes.

## 8 bis. Avancement

Travail dans `/home/djoulin/projects/lexicon-rest-api-access`, branche
`feature/access-control`.

| Lot | État |
|---|---|
| A | Schéma `lexicon_access` créé au démarrage de l'API, plans initiaux semés. Sauvegarde quotidienne du schéma : service `access-dump` de la pile, recopié dans le bucket par `backup`. **Reste** : le rôle Postgres `lexicon_api` |
| B | **Fait et en production** (API 1.3.5) : identité, cache des clés, seaux à jetons, quota journalier, en-têtes, refus 401 / 403 / 429 / 503, comptage d'usage |
| C | **Fait** (PR 21) : comptes administrateurs, sessions, jeton CSRF, limite de connexion, `bin/admin.ts` |
| D | **Fait** (PR 21) : pages des clés et des plans, journal des actions |
| E | **Fait** (PR 21) : page de consommation, export CSV |
| F | Page des datasources **faite** (PR 21). Bundles privés **faits** (PR 22 de l'API, et `publish --bundle` / `fetch` côté `lexicon`) |

Vérifié en production pour le lot B : en-têtes de quota, refus d'une clé
invalide, et 40 requêtes d'une même adresse avec un `X-Forwarded-For` forgé
différent à chaque fois donnent 29 réponses servies et 11 refus `429`.

Packages réservés et bundles (lot F) :

- Un package dont la datasource déclare `scope :members` est publié avec des
  droits `700` / `600`. Le loader tourne sous le propriétaire des fichiers et
  le charge ; le serveur de fichiers public tourne sous un utilisateur sans
  droits et répond `403`. Aucun changement d'arborescence.
- Les bundles sont publiés dans `_bundles/<flavor>/` avec les mêmes droits,
  et servis par l'API sous `/bundles/<flavor>/` aux clés portant
  `bundle:<flavor>`.
- `./lexicon fetch <url>` télécharge un bundle avec une clé, vérifie les
  checksums et respecte le délai demandé par un `429`.
- Les noms des packages réservés restent visibles dans `index.json` et
  `status.json`, qui sont publics ; leur contenu ne l'est pas.

Écarts avec la conception :

- **Délai maximal de requête** : une seule valeur, 30 secondes pour tous, au
  lieu d'une valeur par plan. Le pool de connexions est partagé ; un délai par
  plan demanderait une connexion dédiée par requête.
- **Taille de page par plan** : non appliquée. L'API n'a pas de paramètre de
  taille de page (150 lignes fixes).
- **Coût d'une requête** : toujours 1, y compris pour les exports CSV.
- **Ressource réservée demandée sans clé** : réponse 401 avec invitation à
  s'authentifier, et non 403. Le 403 est réservé à une clé valide dont le plan
  n'ouvre pas la ressource.
- **Clés en ligne de commande** : `bun run bin/key.ts create|list|revoke`,
  disponible avant l'interface web du lot D.
- **Adresse de l'appelant** : lue dans l'entrée de `X-Forwarded-For` ajoutée
  par le proxy de confiance (`TRUSTED_PROXIES`, 1 par défaut), jamais dans ce
  que l'appelant envoie, sans quoi la limite par adresse se contournerait.
- **Propriétaires de parcelles** : ils n'ont pas d'URL propre dans l'API ; ils
  apparaissent dans l'outil d'identification de parcelle, qui ne les affiche
  plus qu'aux porteurs d'une clé.
- **Langue de l'interface** : français uniquement, libellés dans les pages et
  non dans `translations.csv`.
- **Gabarit des pages d'administration** : distinct du gabarit public, qui
  charge des scripts depuis des CDN ; aucun script tiers là où les clés sont
  gérées.
- **Limite quotidienne côté visiteurs** : une adresse limitée reçoit aussi un
  `429` sur les pages HTML du site, pas seulement sur l'API.

## 9. Points confirmés

Tous les points ouverts sont tranchés (A2, A3, A6, A7, A8). Il reste une
question pratique, sans effet sur la conception : existe-t-il un registre des
adhérents OSFarm exploitable (fichier, outil d'adhésion) ? S'il y en a un, la
fin d'adhésion pourra un jour être synchronisée au lieu d'être saisie.
