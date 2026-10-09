# Conception — Lot 7 : parcours consolidé et outil de contribution

Conception et implémentation du 2026-10-07. Besoins : `claudedocs/brainstorm_intrants.md` (F19 à F27, D4, D13,
Q10). Cahier des charges : `claudedocs/frictions_parcours.md`, relevé pendant les lots 1 à 6.

## 0. Décisions

| # | Sujet | Décision |
|---|---|---|
| C1 | Parcours développeur | Une commande, `./lexicon ship`, enchaîne les étapes du parcours et s'arrête à la première qui ne passe pas |
| C2 | Attente du loader | `ship` attend la mise en service et affiche les raisons d'un refus, lues dans `status.json` |
| C3 | Production | `ship --production` : la même commande va jusqu'au bout, la règle « en service en local d'abord » étant tenue par construction |
| C4 | Échec de construction | Une erreur dans `normalize` remet les tables précédentes ; ce qui a été écrit à moitié va dans `<jeu>__error` |
| C5 | Contribution sans code | Un dossier : une fiche `dataset.yml` et des CSV. Lexicon en fait une datasource au démarrage |
| C6 | Relecture | `./lexicon contribute <nom>` : en français, dans les mots d'un tableur (numéro de ligne, valeur fautive), sans base de données |
| C7 | Validation | Rien de nouveau : un mainteneur construit et publie. Un contributeur ne peut rien mettre en service |
| C8 | Emplacement de l'outil (Q10) | Pas tranché, et sans conséquence : le format est un dossier, d'où qu'il vienne |

### Pourquoi une fiche et des CSV plutôt qu'une interface de dépôt (C5, C8)

| Option | Pour | Contre |
|---|---|---|
| Formulaire de dépôt dans l'administration de l'API | Rien à installer pour le contributeur | L'API ne construit pas de packages : il faudrait y porter les contrôles, ou la relier au poste de build |
| Assistant qui écrit une datasource Ruby | Tout ce que sait faire une datasource | Un contributeur ne relit pas du Ruby ; un mainteneur doit relire du code généré |
| **Une fiche et des CSV, lus par une datasource générique** | Le contributeur ne manipule que ce qu'il connaît ; le mainteneur relit une fiche ; tout le reste du parcours est inchangé | Ne couvre que les jeux qui tiennent dans des tableaux |

Le dossier est un format, pas un lieu. Le jour où Q10 sera tranchée, un formulaire de dépôt ou une demande de
fusion assistée produiront ce même dossier, et `Contribution::Review` donnera le même verdict.

## 1. Ce qui a été fait

| Pièce | Rôle |
|---|---|
| `Contribution::Sheet` | Lit la fiche |
| `Contribution::Review` | Dit ce qui est à corriger : fiche incomplète, licence fermée, colonnes qui ne correspondent pas, valeurs qui ne sont pas du type annoncé, clé vide ou répétée, données d'apparence personnelle |
| `Contribution::TabularDatasource` | Fait de la fiche une datasource : crédits (avec l'auteur), accès, pivots, tables typées, chargement |
| `./lexicon new <nom> --tabular` | Écrit le modèle de la fiche |
| `./lexicon contribute <nom>` | La relecture |
| `./lexicon ship <noms>` | Le parcours en une commande |
| `SimpleRunner` | Remise en place des tables après un échec de `normalize` |
| `doc/CONTRIBUER_UN_TABLEAU.md` | Le guide du contributeur |

## 2. Essais (2026-10-07)

Avec un jeu d'essai, retiré depuis :

| Essai | Résultat |
|---|---|
| Fiche et tableau fautifs | Huit points nommés, dont « ligne 2 « 12,5 » » et la clé répétée |
| Fiche et tableau corrigés | Accepté |
| `./lexicon ship` du jeu | Construit, empaqueté, publié et en service en local en une commande ; présent au catalogue avec l'auteur dans les crédits |
| Tableau rendu fautif après coup, sans relecture | `normalize` échoue, les quatre lignes précédentes sont toujours là, rien n'est publié |
| Retrait | `server prune --apply` l'a sorti du service |

Tests : 13 nouveaux (relecture et datasource générique), 168 en tout.

## 3. Ce que le lot ne fait pas

| Sujet | État |
|---|---|
| Dépôt sans poste de build (F24 au sens large) | Le contributeur a besoin du dépôt et de Docker pour lancer la relecture ; sinon c'est le mainteneur qui la lance pour lui |
| Jeux à géométrie, téléchargés ou transformés | Datasource Ruby |
| Clés étrangères entre un tableau et un autre jeu | Seulement des pivots |
| Route d'API pour un jeu contribué | Il apparaît au catalogue ; une page demande une entrée dans l'API, comme pour `/inputs` |
| `ship --production` | Écrit, pas essayé : je n'ai rien publié en production avec cette commande |
