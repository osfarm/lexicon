# Administration de Lexicon (v2)

Guide pour exploiter le serveur Lexicon et gérer les accès à l'API. La
publication des données depuis un poste de build est décrite dans
[PUBLICATION.md](PUBLICATION.md).

## 1. Ce qui tourne

Un serveur, piloté par Dokploy, héberge une pile `lexicon` (projet « Lexicon »,
environnement `production`) décrite par `docker-compose.server.yml`.

| Service | Rôle | Adresse |
|---|---|---|
| `db` | Postgres et PostGIS. Schémas `lexicon` (données servies), `lexicon_staging`, `lexicon_meta` (versions en service), `lexicon_access` (clés, plans, usage) | interne |
| `loader` | Met en service les packages désignés dans le dépôt, toutes les cinq minutes | interne |
| `api` | API et site (`lexicon-rest-api`), interface d'administration | `https://lexicon.osfarm.org` |
| `packages` | Serveur de fichiers public du dépôt de packages | `https://lexicon-packages.osfarm.org` |
| `backup` | Copie quotidienne du dépôt vers le NAS | interne |
| `access-dump` | Export quotidien du schéma des clés | interne |

Le dépôt de packages est le répertoire `/home/ubuntu/lexicon/packages` du
serveur. La base se reconstruit entièrement depuis lui ; seul le schéma
`lexicon_access` contient un état qui n'existe nulle part ailleurs.

## 2. Gérer les accès à l'API

### 2.1 Qui accède à quoi

| Appelant | Limites | Ce qu'il voit |
|---|---|---|
| Sans clé | 30 requêtes par minute et 2 000 par jour, par adresse IP | Les données ouvertes |
| Avec une clé | Celles de son plan (120 par minute en `standard`) | Les données ouvertes et les données réservées aux adhérents |
| Avec une clé portant `bundle:<flavor>` | Idem | En plus, le téléchargement de ce bundle |

Une clé n'est délivrée qu'à un adhérent OSFarm, et expire avec son adhésion.

Données réservées aujourd'hui : les propriétaires de parcelles
(`cadastre_owners`), affichés dans l'outil d'identification de parcelle, et
`rd_agri`.

### 2.2 L'interface

`https://lexicon.osfarm.org/admin`, réservée aux comptes administrateurs.

| Page | Ce qu'on y fait |
|---|---|
| Synthèse | Requêtes du jour, part de refus pour quota, clés actives, clés qui expirent sous 30 jours, datasources périmées |
| Clés | Liste, création, détail d'une clé |
| Plans | Limites par minute et par jour, portées de chaque plan |
| Consommation | Requêtes par clé, par jour et par domaine de l'API ; export CSV |
| Datasources | Versions en service, packages périmés, derniers chargements et échecs |
| Journal | Toutes les actions d'administration, avec leur auteur |

### 2.3 Délivrer une clé

1. **Clés → Nouvelle clé.**
2. Renseigner l'adhérent, son e-mail, la **fin d'adhésion** et le plan.
3. Pour un bundle, ajouter la portée dans « Portées supplémentaires », par
   exemple `bundle:cultia`.
4. Valider. La clé s'affiche **une seule fois** : la transmettre à l'adhérent
   par un canal sûr. Seule son empreinte est conservée ; une clé perdue ne se
   retrouve pas, elle se renouvelle.

L'adhérent l'utilise dans un en-tête :

```sh
curl -H "Authorization: Bearer lex_xxxxxxxx_…" https://lexicon.osfarm.org/phytosanitary/products.json
# ou
curl -H "X-API-Key: lex_xxxxxxxx_…" https://lexicon.osfarm.org/phytosanitary/products.json
```

Jamais dans l'URL : elle finirait dans les journaux et les historiques.

### 2.4 Vie d'une clé

Depuis la page d'une clé :

| Action | Effet |
|---|---|
| **Prolonger** | Nouvelle fin d'adhésion, donc nouvelle date d'expiration |
| **Changer de plan** | Nouvelles limites, en moins d'une minute |
| **Renouveler** | Crée une nouvelle clé pour le même adhérent ; l'ancienne reste valable 7 jours |
| **Révoquer** | Définitif. Effet en moins d'une minute |

La liste des clés signale celles qui expirent sous 30 jours. Une adhésion non
renouvelée ferme la clé sans action de votre part.

### 2.5 Ce que reçoit l'appelant

Chaque réponse porte `RateLimit-Limit`, `RateLimit-Remaining` et
`RateLimit-Reset`.

| Code | Signification |
|---|---|
| `401` | Clé fausse, révoquée ou expirée ; ou ressource réservée demandée sans clé |
| `403` | Clé valide, mais son plan n'ouvre pas la ressource |
| `429` | Quota atteint ; `Retry-After` indique le délai en secondes |
| `503` | Les clés ne peuvent pas être lues pour l'instant |

Une adresse qui dépasse la limite anonyme reçoit aussi un `429` sur les pages
du site. Si des visiteurs s'en plaignent, relever les limites du plan
`anonymous` dans **Plans**.

### 2.6 Comptes administrateurs

Il n'y a pas d'inscription : un compte se crée dans le conteneur de l'API.
Dans Dokploy, ouvrir le terminal du service `api` en choisissant `/bin/sh`
(l'image n'a pas `bash`), puis :

```sh
cd /app
bun run bin/admin.ts create prenom.nom@osfarm.org     # demande le mot de passe, 12 caractères au moins
bun run bin/admin.ts disable prenom.nom@osfarm.org    # désactive le compte et ferme ses sessions
```

Refaire `create` avec la même adresse change le mot de passe. Le mot de
passe s'affiche pendant la saisie dans ce terminal : fermer l'onglet ensuite.

Une session dure 12 heures. La connexion est limitée à cinq essais par quart
d'heure et par adresse.

Les clés se gèrent aussi en ligne de commande, au même endroit :

```sh
bun run bin/key.ts list
bun run bin/key.ts create --owner "Nom" --email a@b.org --plan standard --until 2027-01-31 [--scope bundle:cultia]
bun run bin/key.ts revoke <préfixe>
```

## 3. Suivre l'état des données

Trois façons de voir ce qui est en service :

- la page **Datasources** de l'interface ;
- `https://lexicon-packages.osfarm.org/status.json` ;
- `./lexicon status` depuis un poste de build.

Un package `stale` (périmé) reste servi : il a été construit contre une
version d'un référentiel qui a changé depuis, et doit être republié. Un échec
de chargement laisse toujours l'ancienne version en service ; sa raison est
dans `status.json` et sur la page **Datasources**. Voir
[PUBLICATION.md](PUBLICATION.md), §8.

Opérations sur le serveur, dans le terminal Dokploy du service `loader` :

```sh
cd /lexicon
./lexicon-cli server status              # versions en service, derniers chargements
./lexicon-cli server sync                # charger tout de suite, sans attendre cinq minutes
./lexicon-cli server rollback <ds>       # revenir à la version précédente
./lexicon-cli server prune               # lister les versions hors rétention ; --apply pour supprimer
```

## 4. Déployer

### 4.1 La pile

Dokploy construit la pile depuis GitHub (`osfarm/lexicon`, branche `v2`,
fichier `docker-compose.server.yml`). Pour appliquer un changement : pousser
sur `v2`, puis **Deploy** dans Dokploy. Le déploiement ne recrée que les
services qui ont changé ; la base n'est pas redémarrée.

Variables de la pile, dans Dokploy :

| Variable | Rôle |
|---|---|
| `POSTGRES_PASSWORD` | Mot de passe du rôle `lexicon` |
| `LEXICON_PACKAGES_DIR` | Répertoire du dépôt sur le serveur |
| `LEXICON_BACKUP_ENDPOINT`, `LEXICON_BACKUP_BUCKET`, `LEXICON_BACKUP_ACCESS_KEY`, `LEXICON_BACKUP_SECRET_KEY` | Sauvegarde vers le NAS |
| `LEXICON_API_USER`, `LEXICON_API_PASSWORD` | Rôle Postgres de l'API (voir ci-dessous). Les deux, ou aucune |

### 4.1 bis Le rôle Postgres de l'API

Sans ces deux variables, l'API se connecte avec le rôle principal `lexicon`,
qui peut tout modifier. Avec `LEXICON_API_USER=lexicon_api` et un mot de
passe dans `LEXICON_API_PASSWORD` :

- le loader crée le rôle à son démarrage et entretient ses droits ;
- l'API s'y connecte : elle lit les données servies et le registre des
  packages, possède le schéma `lexicon_access`, et ne peut rien modifier
  d'autre.

Changer le mot de passe : modifier la variable, puis redéployer.

### 4.2 Une nouvelle version de l'API

L'image de l'API n'est construite que sur un tag Git du dépôt
`osfarm/lexicon-rest-api` :

1. fusionner la pull request dans `main` ;
2. `bun run ./bin/tag.ts` ;
3. attendre la fin de la construction sur GitHub ;
4. **Deploy** de la pile dans Dokploy, qui retélécharge l'image.

## 5. Sauvegarde et restauration

Chaque jour, le service `backup` recopie le dépôt de packages dans le bucket
`lexicon-packages` du NAS (destination « OSFarm LAVZ S3 » de Dokploy), et le
dossier `_access/` du bucket reçoit les exports du schéma des clés (30 jours
conservés).

La copie du dépôt est un **miroir** : une version supprimée par
`server prune` disparaît aussi du NAS.

Dans Dokploy, la destination S3 du NAS doit avoir le fournisseur **Other**.
Avec « AWS », le bucket est cherché comme un sous-domaine qui n'existe pas.

### Restaurer les données

1. Recopier le contenu du bucket (hors `_access/`) dans
   `/home/ubuntu/lexicon/packages`.
2. Le loader recharge tout au passage suivant.

Attention : le NAS ne conserve pas les droits des fichiers. Après une
restauration, les packages réservés et les bundles redeviennent lisibles par
tous. Avant de rouvrir le serveur de fichiers, soit les republier depuis un
poste de build, soit remettre les droits :

```sh
cd /home/ubuntu/lexicon/packages
chmod -R go-rwx _bundles rd_agri/*/ cadastre_owners/*/
```

### Restaurer les clés

Les exports sont dans le volume `/dumps` du service `access-dump`, et dans
le dossier `_access/` du bucket. Dans le terminal du service `access-dump`
(`/bin/sh`), après avoir arrêté le service `api` :

```sh
ls /dumps
psql -h db -U lexicon -d lexicon -c 'DROP SCHEMA IF EXISTS lexicon_access CASCADE'
gunzip -c /dumps/lexicon_access-AAAA-MM-JJ.sql.gz | psql -h db -U lexicon -d lexicon
```

Si le volume a été perdu, récupérer d'abord l'export depuis le NAS.

L'export contient les empreintes des clés, les e-mails des adhérents et les
mots de passe hachés des administrateurs : le bucket ne doit pas être public.

## 6. Sécurité du serveur

- **SSH** : clés uniquement, pas de mot de passe. `root` par clé seulement
  (Dokploy s'y connecte ainsi).
- **Pare-feu (UFW)** : tout est refusé en entrée sauf 22, 80 et 443. Les
  ports publiés par Docker ne passent pas par UFW.
- **Fail2Ban** : protège SSH en mode agressif ; l'adresse du serveur Dokploy
  est exemptée. Pour lever un bannissement, depuis le terminal Dokploy du
  serveur :

  ```sh
  fail2ban-client status sshd
  fail2ban-client set sshd unbanip <adresse>
  ```

- **Base de données** : non exposée ; seuls les services de la pile y
  accèdent.
- **Interface d'administration** : cookie de session limité à `/admin`,
  jeton anti-CSRF sur chaque formulaire, aucun script tiers.

Dans l'onglet Security de Dokploy, la ligne « Use PAM » reste rouge : c'est
voulu. Sur Ubuntu, désactiver PAM casse la gestion des sessions ; une fois
les mots de passe coupés, PAM ne sert plus à authentifier.

## 7. Limites connues

- Tant que `LEXICON_API_USER` et `LEXICON_API_PASSWORD` ne sont pas définies,
  l'API se connecte à la base avec le rôle principal `lexicon`.
- Le délai maximal d'une requête SQL de l'API est de 30 secondes pour tous
  les plans.
- La limitation de débit est tenue en mémoire : elle suppose une seule
  instance de l'API, et repart de zéro pour les anonymes à chaque
  redémarrage.
- Les noms des packages réservés sont visibles dans `index.json` et
  `status.json` ; leur contenu ne l'est pas.
- L'interface d'administration est en français uniquement.
