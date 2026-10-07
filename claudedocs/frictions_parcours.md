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

