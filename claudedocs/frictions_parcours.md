# Frictions du parcours de validation

Ce qui a gêné en suivant le parcours de `doc/PUBLICATION.md` §3, jeu après jeu. Ce relevé sert de cahier des
charges à l'outil de contribution (`claudedocs/brainstorm_intrants.md`, F23).

| Date | Jeu | Étape | Ce qui a gêné | Ce qui l'aurait évité |
|---|---|---|---|---|
| 2026-10-07 | — | Installation | `docker/db/z_initdb_postgis.sql` finit par un `GRANT SELECT ON DATABASE` invalide : la base redémarre une fois à sa création | Retirer la ligne |
| 2026-10-07 | — | Installation | L'API démarre avant que le loader ait créé le rôle `lexicon_api` : elle refuse l'accès jusqu'à son redémarrage | Faire attendre l'API, ou qu'elle réessaie |
| 2026-10-07 | `fuel_prices` | 3 | `run` affiche les journaux de débogage et un avertissement Ruby, pas un résumé de ce qui a été chargé | Une ligne par table : lignes chargées, période couverte |
| 2026-10-07 | `fuel_prices` | 3 | Une erreur dans `normalize` laisse les tables de build à moitié écrites : il a fallu mettre les contrôles dans `load` | Restaurer la sauvegarde des tables sur toute erreur, pas seulement sur une clé étrangère |
| 2026-10-07 | `fuel_prices` | 7 | Rien ne dit quand le loader passera : jusqu'à 5 minutes d'attente sans retour | `status --wait`, ou un loader local plus fréquent |
| 2026-10-07 | `fuel_prices` | 8 | Un jeu neuf n'a pas de route dans l'API : on ne le voit que dans le catalogue ou en SQL | Une route générique de lecture par table |
| 2026-10-07 | `fuel_prices` | 2 à 9 | Six commandes à enchaîner, chacune avec sa sortie à lire | Une commande qui enchaîne et s'arrête à la première erreur |
| 2026-10-07 | `phytosanitary_substances` | 3 | Une valeur inattendue (« 2060088 - 2100111 » comme numéro d'AMM) n'est apparue qu'à `normalize`, tables de build déjà vidées | Même remède : restaurer sur toute erreur ; et un essai à blanc de `normalize` |
| 2026-10-07 | `phytosanitary_substances` | 4 | Le taux de liaison vers les AMM n'est pas mesurable : `phytosanitary` n'est pas construit sur le poste, alors qu'il est en service à côté | Mesurer les pivots contre la base de service locale quand la référence manque en build |
| 2026-10-07 | `phytosanitary_substances` | 1 | Le squelette ne dit rien des listes sans licence nommée ; il a fallu lire le contrôleur pour trouver `licence_exception` | Le citer en commentaire dans le squelette |
| 2026-10-07 | `phytosanitary_substances` | 3 | Deux des trois sources ne se téléchargent qu'avec un navigateur déclaré, par une adresse lue dans une page | Un utilitaire commun « trouver un lien dans une page, puis télécharger » |
| 2026-10-07 | `fertilizers` | 3 | Un jeu dont les relevés s'additionnent n'a pas de place prévue pour son historique : les tables de build sont recréées à chaque `normalize` | Un mode « ajout » déclaré par la datasource, ou la relecture du dernier package faite par le socle |
| 2026-10-07 | `fertilizers` | 3 | Une pagination mal lue a demandé une centaine de pages vides au marchand avant d'être vue | Un plafond de requêtes par collecte, et un compte rendu des pages lues |
| 2026-10-07 | `fertilizers` | 3 | Un fichier CSV de règles avec une virgule dans une expression a cassé le chargement | Valider les fichiers de `data/` dans `check --static` |
| 2026-10-07 | `seeds`, `phytosanitary_prices` | 3 | Trois jeux lisent la même page d'un marchand ; rien ne permet à une datasource de dire qu'elle réutilise la collecte d'une autre, il a fallu aller la chercher dans `raw/fertilizers/` | Des ressources collectées une fois et partagées entre datasources |
| 2026-10-07 | `seeds` | 1 | Les lecteurs de marchands vivent dans la datasource `fertilizers` alors que trois jeux s'en servent | Un emplacement commun pour ce qui lit une source, hors des datasources |
| 2026-10-07 | `seeds` | 4 | Le lien des espèces à la taxonomie n'est vérifiable que contre la base de service : même friction qu'au lot 2 | Idem |
| 2026-10-07 | `seed_varieties` | 3 | Pour construire un jeu qui a une clé étrangère, il a fallu deviner la chaîne à construire avant lui (`translations`, puis `taxonomy`) à partir des messages d'erreur | `run <ds> --with-dependencies`, ou un message qui nomme le jeu manquant |
| 2026-10-07 | `seed_varieties` | 3 | Une jointure écarte en silence 1 420 lignes de la source dont l'espèce n'est pas dans une table du dépôt | Compter et afficher ce qu'une jointure de `normalize` laisse de côté |
| 2026-10-07 | `seed_varieties` | 5 | Rien ne dit, avant de publier, ce qui disparaît par rapport à la version en service (772 variétés) | Un résumé des lignes ajoutées et retirées dans `package` ou `status` |
| 2026-10-07 | `prices` | 3 | Des dates à année sur deux chiffres dans un fichier de `data/` donnaient des prix datés de l'an 19, en service depuis longtemps | Un contrôle des plages de dates dans `check` |
| 2026-10-07 | `prices` | 3 | Un jeu qui en lit quatre autres doit être reconstruit après eux ; rien n'ordonne la série | `run` qui suit les dépendances déclarées |
| 2026-10-07 | `prices` | 4 | Des règles écrites en SQL dans `normalize` ne se testent que sur une base remplie | Une base d'essai pour les datasources, comme celle des tests du loader |

## Ce que le lot 7 a traité (2026-10-07)

| Friction | Réponse |
|---|---|
| `GRANT` invalide dans le script d'initialisation de la base | Ligne retirée |
| Six commandes à enchaîner | `./lexicon ship` |
| Rien ne dit quand le loader passera | `ship` attend la mise en service et affiche les raisons d'un refus |
| Une erreur dans `normalize` laisse les tables à moitié écrites | Les tables précédentes sont remises, le reste est mis de côté |
| Le squelette ne dit rien de `licence_exception` | Ajouté en commentaire |
| Un fichier de `data/` mal formé n'est vu qu'au chargement | Pour les contributions tabulaires : `./lexicon contribute` |

Restent ouvertes : l'API qui redémarre avant la création de son rôle, le résumé de ce que `run` a chargé, une route
générique pour un jeu neuf, les pivots mesurés contre la base de service, l'utilitaire de téléchargement par lien,
le mode « ajout » pour les jeux qui s'accumulent, le plafond de requêtes par collecte, les ressources partagées
entre datasources, l'emplacement des lecteurs de marchands, `run` qui suit les dépendances, le compte de ce qu'une
jointure écarte, le résumé des lignes ajoutées et retirées, le contrôle des plages de dates, une base d'essai pour
les datasources.

