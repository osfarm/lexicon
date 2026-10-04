# Conception — Nouvelle interface du Lexicon

Conception du 2026-10-04, avec le skill `frontend-design`. Besoins et
décisions : `claudedocs/brainstorm_lexicon_ui.md`. Conception validée le
2026-10-04 (§8) ; implémentée le même jour, écarts en §9.

## 0. Le sujet, le public, le rôle de la page

- **Sujet** : un commun de données de référence agricoles françaises, dont la
  valeur est moins dans chaque jeu que dans les **liens** entre eux.
- **Public** : développeurs et intégrateurs d'outils agricoles, conseillers
  et techniciens curieux, adhérents d'OSFarm. Des gens qui lisent.
- **Rôle de l'accueil** : faire comprendre en une minute que ces données se
  répondent, puis envoyer vers « Explorer ».

Le logo fournit le vocabulaire visuel : un arbre dont le tronc est une base de
données et la ramure trois disques translucides qui se recouvrent (un lieu en
jaune, l'eau en bleu, une feuille en bleu-vert), reliés au tronc par des fils.
Deux idées en sortent et portent toute la conception : **les fils** (les clés
qui relient) et **les trois teintes** (les familles de données).

## 1. Plan de design

### Couleurs

| Nom | Valeur | Rôle |
|---|---|---|
| Encre | `#0e3d48` | Texte, titres, en-tête de l'administration |
| Lexicon | `#125e6f` | Couleur principale : liens, boutons, fil actif |
| Feuille | `#2f8f89` | Famille « cultures » (le disque bleu-vert du logo) ; jamais de texte dessus |
| Eau | `#5b99c7` | Famille « milieu » ; jamais de texte dessus |
| Lieu | `#f4c20d` | Famille « lieux » et mise en évidence ; jamais de texte dessus |
| Papier | `#fbfbfc` | Fond (celui du logo) ; les surfaces de bloc sont `#eef4f4` |

Les trois teintes de famille s'emploient comme dans le logo : en aplats
translucides qui se recouvrent, pas en dégradés.

### Typographie

Une seule famille, celle d'OSFarm : **Ubuntu**, en 500 pour le texte et 700
pour les titres, servie par le Lexicon (`public/fonts/`), repli
`"Helvetica Neue", Arial, sans-serif`. Le mot « lexicon » de l'en-tête est
composé en Ubuntu 700 bas de casse, comme dans le logo.

Échelle (rapport 1,25, base 17 px) : 14 · 17 · 21 · 27 · 33 · 52. Interligne
1,55 pour le texte, 1,15 pour les titres. Lignes de 70 caractères au plus.
Titres en casse de phrase, sans capitales forcées ni sur-titres.

Les nombres des tableaux utilisent les chiffres tabulaires d'Ubuntu
(`font-variant-numeric: tabular-nums`), pas une police à chasse fixe.

### Mise en page

Alignée à gauche partout, sur une colonne de 1 120 px ; le texte courant ne
dépasse pas 680 px. Seul le schéma prend toute la largeur.

```
┌────────────────────────────────────────────────────────────────────────┐
│ (arbre) lexicon     Accueil  Explorer  Catalogue  Outils  Documentation   FR | EN │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Les référentiels agricoles français,                                  │
│  reliés entre eux.                                                     │
│                                                                        │
│  Cadastre, parcelles déclarées à la PAC, entreprises, produits         │
│  phytosanitaires, météo, travaux de recherche : le Lexicon rassemble   │
│  ces données publiques et les relie par des clés communes.             │
│                                                                        │
│  ( Explorer les données )   ( Poser une question à Duke )              │
│                                                                        │
│  ┌─ le tissage (§3) ─ pleine largeur ─────────────────────────────┐   │
│  │ jeux en colonnes, clés en fils horizontaux                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                        │
│  Suivre une question            │  Trois façons de s'en servir         │
│  1 un point  2 la parcelle …    │  L'API · Les packages · Les agents   │
│                                                                        │
│  Un commun d'OSFarm : licences, contribuer, obtenir une clé            │
├────────────────────────────────────────────────────────────────────────┤
│ pied de page à trois colonnes, logo OSFarm                             │
└────────────────────────────────────────────────────────────────────────┘
```

### Principes

1. **Le tissage est la seule audace.** Tout le reste est calme : fond papier,
   texte encre, peu de couleur.
2. **La couleur dit la famille**, jamais la décoration : jaune pour les lieux,
   bleu pour le milieu, bleu-vert pour les cultures, encre pour les
   exploitations.
3. **Un lexique, pas un tableau de bord.** « Explorer » se lit comme un index
   d'entrées avec leur définition, pas comme une grille de vignettes.
4. **Le mouvement répond à un geste.** Un seul moment animé au chargement :
   les fils se tracent, une fois. Ensuite rien ne bouge sans action.

### Relecture contre les habitudes

Ce que j'aurais produit par défaut, et ce que je change :

| Réflexe | Ce qui est fait à la place | Pourquoi |
|---|---|---|
| Un bandeau avec trois gros chiffres (« 42 jeux, 180 M de lignes ») | Les chiffres sont **dans** le tissage, sous chaque jeu | Le chiffre isolé ne dit rien de l'interopérabilité ; le lien, si |
| Un graphe de nœuds reliés par des flèches | Un tissage : jeux en colonnes, clés en fils | Un graphe à 15 nœuds devient une pelote ; un tableau reste lisible, fonctionne sans JavaScript et se lit au lecteur d'écran |
| Une grille de cartes arrondies ombrées pour « Explorer » | Un index à deux colonnes : nom, définition, renvois | C'est un lexique ; et la grille de cartes identiques est le poncif du genre |
| Un rayon unique partout | Pilule pour les boutons (OSFarm), 12 px pour les panneaux, angles droits dans les tableaux | Le rayon suit le rôle |
| Apparition en fondu de chaque section au défilement | Un seul tracé des fils au chargement | Sobriété demandée, et respect de « réduire les animations » |
| Sur-titres en capitales espacées | Aucun | Les titres suffisent |

## 2. En-tête, pied de page, langue

### En-tête

- À gauche : l'arbre du logo (icône carrée, 36 px) et le mot « lexicon ».
- Menu : Accueil, Explorer, Catalogue, Outils, Documentation. L'entrée
  courante est en 700 avec un trait `Lexicon` de 3 px dessous, et porte
  `aria-current="page"`.
- À droite : `FR | EN`, la langue courante en gras.
- Sous 760 px : le menu passe derrière un bouton « Menu » (élément
  `<details>`, sans JavaScript).
- Fond papier, filet bas `#d9e5e5`. L'en-tête ne reste pas collé en haut.

L'entrée courante se déduit du fil d'Ariane, sans toucher aux pages :

| Page | Entrée |
|---|---|
| `/` | Accueil |
| `/catalog…` | Catalogue |
| `/tools…` | Outils |
| `/documentation` | Documentation |
| tout le reste (données, fiches, R&D, crédits) | Explorer |

`Layout` insère aussi « Explorer » dans le fil d'Ariane des pages de données,
entre « Accueil » et la section : les namespaces ne changent pas.

### Langue

- Lien `/language/fr` et `/language/en` : pose un cookie `lang` (un an,
  `SameSite=Lax`) et renvoie à la page d'où l'on vient. Le retour n'est suivi
  que si l'adresse d'origine est sur le même site ; sinon retour à l'accueil.
- **Pages HTML** : le cookie, sinon le français.
- **JSON et CSV** : le cookie s'il existe, sinon l'en-tête `Accept-Language`
  comme aujourd'hui : un intégrateur qui demande des libellés anglais par cet
  en-tête les garde (N1). Écart au brainstorm, confirmé (§8).

### Pied de page

Trois colonnes comme osfarm.org : « Le Lexicon » (documentation, catalogue,
crédits, GitHub), « L'association » (osfarm.org, adhérer), « Version » (numéro
de version, licence). Logo OSFarm à droite. Fond `Encre`, texte clair.

## 3. Le tissage (schéma de l'accueil)

### Forme

Un tableau. Les **jeux de données** sont les colonnes, regroupés par famille ;
les **clés** sont les lignes, chacune tracée comme un fil horizontal ; un
**nœud** marque chaque jeu qui porte la clé. Au-dessus des colonnes, les
**sources** ; sous le tableau, les **usages**.

```
              LIEUX (jaune)                EXPLOITATIONS (encre)      CULTURES (bleu-vert)        MILIEU (bleu)
              Cadastre  Prix   RPG         Entreprises  Aides  MSA    Productions  Phyto  R&D     Météo
              IGN       DGFiP  IGN/ASP     INSEE        ASP    MSA    OSFarm       ANSES  ACTA    Météo-France
              126 M     20 M   39 M        1,9 M        0,6 M   …      …            …      40 k    …

commune       ●─────────────────────────────●────────────●──────●─────────────────────────●
SIREN                                       ●────────────●
parcelle      ●─────────●
code culture                    ●──────────────────────────────────────●
production                                                             ●───────────────────●
taxon                                                                  ●────────────●──────●
bioagresseur                                                                        ●──────●
station météo ●·····(par la fiche commune)····································●

              par l'API (JSON, CSV)      par téléchargement (packages)      par un agent IA (MCP, Duke)
```

Les nœuds ci-dessus sont une première lecture des déclarations `pivot` et des
tables. **Chaque nœud sera vérifié sur le schéma réel à l'implémentation : le
tissage ne montre aucun lien que les données n'ont pas.** Les jeux réservés
aux adhérents (propriétaires, fiches entreprise) portent un cadenas et la
mention « adhérents ».

### Contenu fixe et contenu vivant

`src/home/Weave.ts` décrit la structure à la main (décision 4) :

```ts
type Family = "places" | "farms" | "crops" | "environment"

type WeaveDataset = {
  name: string            // nom de la datasource dans le catalogue : "cadastre"
  label: { fr: string; en: string }
  family: Family
  source: string          // "IGN"
  href: string            // page de la section dans l'API
}

type WeaveKey = {
  id: string              // "commune"
  label: { fr: string; en: string }
  definition: { fr: string; en: string }   // une phrase : ce qu'est cette clé
  carriedBy: string[]     // noms des jeux qui la portent
}

type WeaveStep = { text: { fr: string; en: string }; datasets: string[]; keys: string[] }

export const DATASETS: WeaveDataset[]
export const KEYS: WeaveKey[]
export const JOURNEY: WeaveStep[]

// Ce que le catalogue ajoute : absent, le jeu s'affiche sans chiffre
export function figuresOf(catalog: Dataset[] | undefined): Map<string, { rows: number; sourceDate: string | null; scope: string }>
```

Les chiffres (lignes, date de la source, accès) viennent de `readCatalog`. Un
jeu du tissage absent du catalogue s'affiche sans chiffre ; la page ne tombe
jamais à cause du catalogue.

### Comportement

| Geste | Effet |
|---|---|
| Survol ou focus d'une **clé** | Son fil passe en `Lexicon` épais, ses nœuds en `Lieu`, les jeux non reliés s'estompent ; sa définition s'affiche sous le tableau |
| Survol ou focus d'un **jeu** | Ses clés s'allument, ainsi que les jeux qu'elles relient |
| Clic sur un jeu | Sa page du catalogue |
| Clic sur une clé | La garde allumée (bouton à bascule, `aria-pressed`) |
| « Suivre une question » | Quatre pas numérotés (c'est une suite) ; chaque pas allume les jeux et les clés traversés |

Question suivie : « Qu'est-ce qui pousse ici, et qui le cultive ? »

1. Un point sur la carte tombe dans une **parcelle cadastrale**.
2. Au même endroit, le **RPG** donne la culture déclarée, campagne après campagne.
3. La parcelle est dans une **commune** : ses entreprises agricoles, ses chefs d'exploitation.
4. La culture renvoie à sa **production**, aux produits autorisés et aux travaux de R&D.

Chaque pas porte un lien vers l'outil réel (identificateur de parcelle,
historique des cultures, fiche commune, documents de R&D).

### Technique

- Un vrai `<table>` : en-têtes de colonnes et de lignes, nœuds en cellules
  avec un texte caché (« le cadastre porte la clé commune »). Lisible sans
  CSS, sans JavaScript, au lecteur d'écran.
- Les fils sont des bordures et des pseudo-éléments CSS ; les nœuds, des
  disques CSS. Pas de bibliothèque, pas de canevas.
- La mise en évidence d'une ligne est en CSS pur (`:hover`, `:focus-within`).
  Celle d'une colonne et le parcours guidé demandent un script :
  `public/weave.js`, une soixantaine de lignes, sans dépendance.
- Au chargement, les fils se tracent de gauche à droite en 900 ms, une seule
  fois ; rien si `prefers-reduced-motion`.
- Sous 760 px, le tableau devient une liste : un bloc par clé, avec les jeux
  qu'elle relie en pastilles colorées par famille. Même information.

## 4. Les pages

### Accueil (`/`)

Dans l'ordre : avertissement « en cours de développement » (bandeau fin, fond
`Lieu` à 25 %), titre et chapô, deux boutons, le tissage, « Suivre une
question », « Trois façons de s'en servir », « Un commun d'OSFarm ».

« Trois façons de s'en servir » : trois courts paragraphes côte à côte, sans
cadre, chacun avec un exemple vrai (une adresse `.json`, la commande
`./lexicon fetch`, la configuration MCP) et un lien.

### Explorer (`/explore`)

Un index sur deux colonnes. Chaque entrée : le nom de la section (lien, 21 px,
700), une phrase de définition, puis « voir aussi » vers ses pages les plus
utiles. Un filet fin entre les entrées, une pastille de couleur de famille
devant le nom. Suivent « Outils » (identificateur de parcelle, Duke) et
« Utiliser le Lexicon en trois étapes » (numérotées : c'est une suite), puis
le lien vers la documentation. Tout le contenu de l'accueil actuel s'y
retrouve (F5).

Les icônes actuelles (`public/icons/`) sont conservées à petite taille dans
les pages de section, pas dans l'index.

### Pages de données (listes, fiches, formulaires)

Aucun changement de structure : `generateTablePage`, `generateResourcePage`,
`AutoList` gardent leur contrat. Seul le style change.

- **Tableaux** : en-tête `Encre` sur fond `#eef4f4`, filets horizontaux
  seulement, survol de ligne, chiffres tabulaires alignés à droite.
- **Fiches** : libellés en `#4d6b72`, valeurs en `Encre`, sur deux colonnes.
- **Formulaires de filtre** : champs à bord fin, bouton pilule « Filtrer ».
- **Formats** : liens `JSON` et `CSV` en pilules discrètes en haut à droite.
- **Pagination**, **onglets** (htmx), **cartes** (Leaflet) : mêmes composants,
  nouvelles couleurs.
- **Erreurs** : dire ce qui s'est passé et quoi faire, sans s'excuser.

### Catalogue, fiches, R&D, Duke, identificateur

Mêmes règles. Duke garde son déroulé d'appels d'outils ; ses boutons
d'exemples deviennent des pilules à bord fin.

### Administration (`/admin`)

Même feuille de style, même police. Pour qu'on sache toujours où l'on est,
l'en-tête de l'administration est sur fond `Encre` avec la mention
« Administration ». Reste en français.

## 5. Changements dans `lexicon-rest-api`

| Fichier | Changement |
|---|---|
| `public/style.css` | Réécrit : variables CSS (couleurs, échelle, espacements), composants. Remplace les styles en ligne de `Layout.tsx` |
| `public/fonts/ubuntu-{500,700}-latin.woff2` | Repris d'osfarm.org |
| `public/images/lexicon-logo.svg`, `lexicon-mark.svg`, `favicon.ico` | Logo nettoyé (fond retiré, tracés allégés), arbre seul en carré, icône d'onglet |
| `public/weave.js` | Survol de colonne et parcours guidé du tissage |
| `src/API.ts` | Types `js` et `woff2` pour `/public/*` |
| `src/templates/layouts/Layout.tsx` | En-tête, pied de page, entrée courante, « Explorer » dans le fil d'Ariane, sélecteur de langue. Leaflet et ECharts ne sont plus chargés ici |
| `src/templates/components/Map.tsx`, `Chart.tsx` | Chargent eux-mêmes leur bibliothèque (comme `DonutChart3D` le fait déjà) |
| `src/templates/components/*`, `views/*` | Classes CSS à la place des styles en ligne |
| `src/templates/pages/Home.tsx` | Nouvel accueil |
| `src/templates/pages/Explore.tsx` | Nouveau : l'ancien accueil, en index |
| `src/home/Weave.ts`, `Weave.test.ts` | Structure du tissage, chiffres du catalogue |
| `src/templates/components/Weave.tsx` | Le tableau |
| `src/applyRequestConfiguration.ts` | Langue : cookie, puis règle du §2 |
| `src/index.ts` | Routes `/explore`, `/language/:code` ; l'accueil reçoit le contexte |
| `src/namespaces/Admin/AdminLayout.tsx` | Même style, en-tête `Encre` |
| `src/assets/translations.csv` | Textes nouveaux, FR et EN |

Adresses, JSON, CSV, MCP : inchangés (N1).

## 6. Accessibilité et qualité

- Contrastes calculés : `Encre` sur papier 11,4:1 ; `Lexicon` sur papier
  7,1:1 ; texte blanc sur `Lexicon` 7,4:1 ; libellés `#4d6b72` sur papier
  5,5:1 ; `Encre` sur `Lieu` 7,1:1. `Feuille` (3,8:1), `Eau` (3,0:1) et `Lieu`
  (1,6:1) ne portent jamais de texte sur papier.
- La couleur n'est jamais seule à porter une information : chaque famille est
  aussi nommée, chaque nœud a son texte.
- Focus visible : contour `Lexicon` de 3 px, décalé de 2 px. Le jaune seul
  ne contraste pas assez avec le papier pour marquer le focus.
- Ordre des titres vérifié page par page ; liens d'évitement vers le contenu.
- `prefers-reduced-motion` : aucun tracé animé.
- Vérification par captures d'écran à trois largeurs (390, 768, 1 280 px)
  pendant la réalisation.

## 7. Lots

| Lot | Contenu | Vérification |
|---|---|---|
| U1 | Logo nettoyé, polices, variables CSS, en-tête, pied de page, sélecteur de langue | Toutes les pages s'affichent ; les tests passent ; captures aux trois largeurs |
| U2 | `/explore`, fil d'Ariane, entrée courante du menu | L'ancien contenu de l'accueil y est entier |
| U3 | Accueil : textes, tissage, parcours guidé | Nœuds vérifiés sur le schéma ; sans JavaScript ; au clavier ; au téléphone |
| U4 | Pages de données : tableaux, fiches, formulaires, cartes, Duke, catalogue | Une page de chaque sorte relue |
| U5 | Administration | Les pages `/admin` relues avec une session |

U1 d'abord ; U2 et U3 ensuite ; U4 et U5 peuvent suivre dans n'importe quel ordre.

## 8. Points confirmés (2026-10-04)

| # | Point | Décision |
|---|---|---|
| 1 | Langue des JSON et CSV | Le cookie s'il existe, sinon `Accept-Language` comme aujourd'hui. Les pages HTML : le cookie, sinon le français |
| 2 | Familles du tissage | Quatre : lieux (jaune), exploitations (encre, la couleur du tronc), cultures (bleu-vert), milieu (bleu) |
| 3 | Titre de l'accueil | « Les référentiels agricoles français, reliés entre eux. » |
| 4 | Question suivie | « Qu'est-ce qui pousse ici, et qui le cultive ? » |
| 5 | Mot « lexicon » de l'en-tête | Recomposé en Ubuntu 700 bas de casse, à côté de l'arbre du logo |

## 9. Écarts à l'implémentation (2026-10-04)

| Sujet | Conçu | Réalisé | Pourquoi |
|---|---|---|---|
| Leaflet et ECharts | Chargés seulement par les composants qui s'en servent | Toujours chargés par le gabarit | Les onglets des fiches chargent leurs cartes après coup (htmx) et comptent sur une bibliothèque déjà présente : les déplacer risquait de les casser |
| Menu au téléphone | Élément `<details>` | Case à cocher et `<label>`, sans JavaScript | Un `<details>` ouvert par défaut repoussait le contenu sur petit écran |
| Lignes du tissage | commune, SIREN, parcelle, code culture, production, taxon, bioagresseur, station météo | « le lieu » ajouté, « taxon » retiré | Le lieu (géométrie) est ce qui relie cadastre et RPG ; le taxon aurait demandé une colonne de plus |
| Colonnes du tissage | Dix jeux | Douze, dont « Communes » et « Propriétaires » | Vérification sur le schéma réel |
| Pas du parcours guidé | Boutons | Blocs avec un lien ; le survol ou le focus allume le tissage | Un geste de moins, et le lien reste utilisable sans JavaScript |
| Usages sous le tissage | Une ligne « API, packages, agents » | Supprimée | Elle doublait « Trois façons de s'en servir » |
| Largeur du tissage | Pleine largeur | Jusqu'à 1 340 px, centré | Douze colonnes ne tenaient pas dans la colonne de 1 120 px |
| Adresses des fichiers statiques | — | Suffixées d'un tampon qui change à chaque démarrage | Les navigateurs gardent `/public/*` un jour : sans cela la nouvelle feuille de style n'aurait été vue que le lendemain |
| Fichiers statiques | — | `/public/*` ne sert plus que le dossier `public` | Le gestionnaire acceptait un chemin sortant du dossier ; en production le proxy l'empêchait déjà |
| Fiches | — | Les valeurs sans unité n'affichent plus « undefined », les listes plus « Unknown » | Défauts d'affichage antérieurs, visibles en relisant les pages |

Vérifié dans Chrome sur `localhost` : accueil (survol d'une clé et d'un pas,
version anglaise, version téléphone), Explorer, une liste, une fiche, le
catalogue, les documents de R&D, Duke, l'identificateur de parcelle, la carte
des parcelles PAC, la page de connexion de l'administration.

Non vérifié : les pages de l'administration une fois connecté (pas de
session), la navigation au clavier dans le tissage, un lecteur d'écran.
