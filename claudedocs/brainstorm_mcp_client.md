# Brainstorm — Assistant MCP dans les outils de l'API

Date : 2026-10-04. Statut : besoins validés, décisions en §8.

Demande : ajouter dans la partie « Outils » de l'interface (`/tools`) un client MCP
qui permet d'interroger le jeu `rd_agri` en langage naturel, pour montrer ce que
permet le Lexicon. Utiliser si possible un modèle gratuit.

## 1. Ce que l'on veut montrer

Un visiteur pose une question en français (« quels travaux sur le mildiou de la
vigne en agriculture biologique depuis 2020 ? ») et obtient une réponse courte,
appuyée sur des documents de la plateforme R&D agricole, avec leurs titres,
années, éditeurs et liens. La page montre aussi **comment** la réponse a été
obtenue : les appels d'outils MCP faits par le modèle. C'est cela, la
démonstration : un agent qui se sert du Lexicon par son serveur MCP, sans rien
connaître d'avance de ses tables.

Ce n'est pas un assistant agronomique : il ne conseille pas, il retrouve et
résume ce que disent les références.

## 2. État des lieux

| Point | Constat |
|---|---|
| Section Outils | `/tools` ne contient qu'un outil, l'identification de parcelle |
| Serveur MCP | `POST /mcp`, six outils, sans session, même contrôle d'accès que l'API |
| `rd_agri` dans l'API | **Aucune ressource** : le jeu est en service (40 523 documents, six tables) mais l'API ne le sert pas, donc `read_resource` ne peut pas le lire |
| `rd_agri`, accès | Réservé aux adhérents (`scope :members`), licence CC BY-NC-SA |
| `rd_agri`, contenu | Documents (titre, description, année, éditeur, lien) reliés aux productions, taxons, zones, systèmes de production et bioagresseurs du Lexicon |
| Serveur | 32 Go de RAM, pas de carte graphique |
| Limites de l'API | 30 requêtes par minute sans clé, 120 avec une clé `standard` |

Conséquence : avant le client, il faut que `rd_agri` soit interrogeable — par
des ressources de l'API, par un outil MCP de recherche, ou les deux.

## 3. Besoins fonctionnels

### Recherche dans `rd_agri` (prérequis)

- F1. Chercher des documents par mots du titre et de la description.
- F2. Filtrer par production, taxon, bioagresseur, système de production, zone,
  année ou période, éditeur.
- F3. Obtenir un document avec tous ses liens aux référentiels du Lexicon.
- F4. Ces recherches sont accessibles par MCP ; les résultats sont assez courts
  pour tenir dans la réponse d'un outil (60 000 caractères aujourd'hui).
- F5. Suivre un lien vers les autres jeux : d'une production citée vers sa
  fiche, d'un bioagresseur vers les produits phytosanitaires, etc. C'est ce
  croisement qui montre l'intérêt du Lexicon, plus qu'une recherche isolée.

### Page de l'outil

- F6. Une entrée « Assistant » (nom à choisir) dans `/tools`.
- F7. Un champ de question, et trois à cinq questions d'exemple cliquables.
- F8. La réponse en français, avec les documents cités : titre, année, éditeur,
  lien vers la source.
- F9. Le déroulé visible : chaque appel d'outil MCP, ses paramètres, la taille
  de sa réponse. Repliable.
- F10. Une conversation courte est possible (question de relance), dans une
  limite de tours.
- F11. Mention affichée : réponse produite par un modèle de langage, à
  vérifier dans les documents cités ; licence et fournisseur de `rd_agri`.
- F12. Quand le modèle n'est pas joignable ou que le quota est atteint, la
  page le dit et propose de réessayer plus tard ; elle ne tombe pas en erreur.

### Modèle

- F13. Le modèle doit savoir appeler des outils et répondre en français.
- F14. Le fournisseur et le modèle sont des réglages, pas du code : les offres
  gratuites changent souvent, il faut pouvoir en changer sans nouvelle version.
- F15. Le modèle ne reçoit que les outils du serveur MCP du Lexicon, avec les
  droits de l'appelant. Il ne voit rien que l'appelant ne pourrait lire.

## 4. Besoins non fonctionnels

- N1. **Coût nul ou plafonné** : pas de dépense qui croît avec l'usage.
- N2. **Pas de relais ouvert** : la page ne doit pas pouvoir servir de modèle
  gratuit à n'importe qui. Limite par appelant, plafond global par jour,
  longueur de question bornée, nombre d'appels d'outils borné par question.
- N3. **Secret** : la clé du fournisseur reste côté serveur, jamais dans la page.
- N4. **Délai** : première réponse en moins de 30 secondes, ou un affichage
  progressif.
- N5. **Licence** : `rd_agri` est en CC BY-NC-SA. Ce qui en est montré doit
  rester dans un usage non commercial, avec attribution.
- N6. **Données envoyées à un tiers** : les questions des visiteurs et des
  extraits de `rd_agri` partent chez le fournisseur du modèle. Plusieurs offres
  gratuites réutilisent ces données pour entraîner leurs modèles.
- N7. **Injection** : les titres et descriptions des documents sont du texte
  venu de l'extérieur. Le modèle n'a que des outils de lecture, ce qui borne le
  risque ; la réponse est affichée échappée.
- N8. **Journal** : nombre de questions, d'appels d'outils et d'échecs par
  jour, sans conserver le texte des questions plus longtemps que nécessaire.
- N9. Conventions du dépôt `lexicon-rest-api` : pages rendues côté serveur,
  pas de dépendance lourde côté navigateur, traductions, tests `bun test`.

## 5. Modèles gratuits envisageables

D'après la liste `awesome-free-models` (relevé du 1er octobre 2026 ; à
revérifier, ces offres bougent) :

| Option | Pour | Contre |
|---|---|---|
| **Mistral, La Plateforme** (offre gratuite) | Européen, bon en français, appels d'outils, 1 requête par seconde | Téléphone à vérifier, et **acceptation de la réutilisation des données** |
| **Groq** (offre gratuite) | Très rapide, sans carte bancaire, modèles ouverts avec appels d'outils | Hébergé aux États-Unis, quotas journaliers, conditions à lire sur les données |
| **Google AI Studio** | Offre gratuite la plus large | Données de l'offre gratuite réutilisées, hors Europe |
| **OpenRouter, modèles gratuits** | Une seule interface pour une vingtaine de modèles | La liste change sans cesse, solde à créditer même à 0 |
| **Modèle hébergé sur notre serveur** (Ollama, petit modèle ouvert) | Rien ne sort du serveur, coût nul, aucune dépendance | Sans carte graphique : lent (plusieurs dizaines de secondes), appels d'outils moins fiables avec un petit modèle, mémoire et processeur pris à la base |

Première lecture : une offre hébergée gratuite convient à une démonstration
publique sur données ouvertes ; dès que des données réservées ou des questions
d'adhérents passent par le modèle, la question N6 décide.

## 6. Récits d'usage et critères d'acceptation

1. *Visiteur.* Je clique sur une question d'exemple ; j'obtiens en moins de 30
   secondes une réponse citant au moins un document avec son lien, et je vois
   les appels d'outils faits.
2. *Visiteur.* Je pose une question hors sujet (« écris-moi un poème ») ; l'outil
   répond qu'il ne traite que des références du Lexicon.
3. *Visiteur.* Je pose une question sans résultat ; l'outil le dit, sans
   inventer de document. Tout document cité existe dans `rd_agri`.
4. *Adhérent.* (si l'accès est réservé) Sans clé, je vois la page, les exemples
   et l'invitation à adhérer ; avec ma clé, je peux poser mes questions.
5. *Administrateur.* Je vois dans l'administration la consommation de l'outil,
   et je peux le couper ou changer de modèle sans redéployer le code.
6. *Abus.* Au-delà de la limite, l'appelant reçoit un refus clair ; le plafond
   global atteint, l'outil se met en pause jusqu'au lendemain.

## 7. Hors périmètre proposé

- Conseil agronomique, génération de documents, mémoire entre les visites.
- Recherche sémantique par vecteurs (à voir plus tard si la recherche par mots
  ne suffit pas).
- Client MCP générique capable de se brancher sur d'autres serveurs.

## 8. Décisions (réponses du 2026-10-04)

| # | Question | Décision |
|---|---|---|
| 1 | Qui peut poser des questions ? | Tout le monde : `rd_agri` est déjà public à sa source |
| 2 | Où tourne le modèle ? | Mistral, La Plateforme, offre gratuite. La réutilisation d'extraits de `rd_agri` par le fournisseur est acceptée |
| 3 | `rd_agri` dans l'API | Pages consultables **et** recherche par MCP |
| 4 | Outils donnés au modèle | Tout le serveur MCP |
| 5 | Limites | 10 questions par jour sans clé |
| 6 | Compte fournisseur | Compte `lexicon@osfarm.org`, créé par David, qui détient la clé Mistral |
| 7 | Langue | Français et anglais |

### Ce que ces décisions entraînent

- **`rd_agri` devient un jeu ouvert.** Aujourd'hui la datasource déclare
  `scope :members` : son package n'est pas téléchargeable et le catalogue le
  marque réservé. Pour que tout le monde l'interroge, il faut retirer cette
  portée et republier. La licence reste CC BY-NC-SA : attribution et usage non
  commercial à afficher sur les pages et dans les réponses (N5), et
  `./lexicon check` signalera une licence non ouverte sur un jeu ouvert — à
  inscrire comme exception assumée, avec sa raison.
- **Le bundle `cultia`** contient `rd_agri` : la question de l'usage non
  commercial s'y pose toujours, indépendamment de cet outil.
- **F4 bis.** `rd_agri` a des pages dans l'API (liste, filtres, document), dans
  les trois formats habituels, et une recherche exposée par MCP.
- **F13 bis.** Le modèle répond dans la langue de l'interface (français ou
  anglais) ; les documents restent dans leur langue d'origine.
- **N2 précisé.** 10 questions par jour et par adresse sans clé.
- **N6 tranché.** Les questions des visiteurs partent chez Mistral, qui peut
  les réutiliser sur l'offre gratuite : la page doit le dire avant la saisie,
  et demander de ne pas y mettre de données personnelles.
- **Offre gratuite de Mistral** : une requête par seconde pour tout le compte.
  Une question consomme plusieurs requêtes (une par tour d'outils) : l'outil
  sert donc peu de visiteurs à la fois, et doit faire attendre plutôt
  qu'échouer (F12).

## 9. Points restant à préciser à la conception

1. Limite pour un porteur de clé, et plafond global par jour (proposition
   inchangée : 50 avec clé, 500 au total).
2. Modèle Mistral retenu parmi ceux de l'offre gratuite, et vérification de
   ses quotas réels au moment de la création du compte.
3. Nom de l'outil dans `/tools` et questions d'exemple, dans les deux langues.
4. Nombre maximal de tours d'outils par question et de relances par
   conversation.
