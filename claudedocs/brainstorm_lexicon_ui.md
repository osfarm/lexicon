# Brainstorm — Nouvelle interface du Lexicon

Date : 2026-10-04. Statut : besoins validés, décisions en §7.

Demande : améliorer l'interface de `lexicon-rest-api` en reprenant le style du
site <https://www.osfarm.org/> et le nouveau logo du Lexicon
(`lexicon-icon.svg`, branche `v2` du dépôt lexicon) ; ajouter à l'accueil un
schéma dynamique qui explique le Lexicon et l'interopérabilité entre données
agricoles ; déplacer le contenu actuel de l'accueil dans un nouveau menu
« Explorer ».

## 1. Objectifs

1. **Appartenance** : au premier regard, le Lexicon est un commun d'OSFarm.
2. **Compréhension** : un visiteur qui ne connaît pas le Lexicon comprend en
   une minute ce qu'il est (des référentiels agricoles collectés, normalisés
   et **reliés entre eux**) et pourquoi c'est utile.
3. **Orientation** : l'accueil explique, « Explorer » donne accès aux données.
4. Ne rien casser : mêmes adresses, mêmes formats JSON et CSV.

## 2. État des lieux

| Sujet | Aujourd'hui |
|---|---|
| Accueil | Un avertissement « en développement », la grille des huit sections de données, deux outils, « utiliser en 3 étapes », un lien vers la documentation |
| Menu | Accueil, Catalogue, Documentation |
| Style | `public/style.css` (400 lignes), police système, fond blanc, titre « Lexicon » en texte ; beaucoup de styles en ligne dans `Layout.tsx` |
| Logo | L'ancien `public/images/lexicon-icon.svg`, commenté dans le gabarit |
| Pages | Rendues côté serveur (JSX), htmx et Alpine chargés, cartes Leaflet, graphiques ECharts |
| Langues | Français et anglais, selon le navigateur |
| Administration | `/admin` a son propre gabarit (`AdminLayout`), en français |

### Ce que dit le site osfarm.org

| Élément | Valeur relevée |
|---|---|
| Police | « OSFarm Ubuntu » (Ubuntu 500 et 700, fichiers woff2 servis par le site), repli Helvetica / Arial |
| Verts | `#338000` (principal), `#245c00` (foncé), `#16210f` et `#1f2d1a` (très foncés, fonds et titres), `#5d6d58` (texte secondaire) |
| Verts clairs | `#d6e2cf`, `#e3f4d7` (fonds de bloc) |
| Accent | `#ffcc00` (jaune) |
| Formes | Boutons en pilule (`border-radius: 999px`), cartes à 12 px ou 8 px |
| Structure d'accueil | Bandeau avec un titre fort et un chapô, sections titrées, cartes de solutions, bloc « Rejoindre OSFarm », pied de page à trois colonnes, assistant en bas de page |

### Le nouveau logo

`lexicon-icon.svg` : 93 Ko, 81 tracés issus d'une vectorisation automatique,
format large (2816 × 1536), **fond blanc opaque** inclus dans le dessin.
Couleurs dominantes : bleu-vert foncé `#125e6f`, bleu `#5b99c7`, turquoise
clair `#b0d2d1`, jaune `#fdd548`. Il n'est donc pas dans les verts d'OSFarm ;
son jaune rejoint l'accent du site.

## 3. Besoins fonctionnels

### Navigation

- F1. Menu principal : **Accueil**, **Explorer**, **Catalogue**, **Outils**,
  **Documentation**. L'entrée de la page courante est marquée.
- F2. Le logo du Lexicon, à gauche, ramène à l'accueil.
- F3. Le menu reste utilisable au téléphone (repli en bouton).
- F4. Pied de page dans l'esprit d'osfarm.org : le site, l'association,
  crédits, GitHub, version, logo OSFarm.

### Page « Explorer » (nouvelle)

- F5. Nouvelle adresse (`/explore`) qui reprend **tout** ce que l'accueil
  montre aujourd'hui : les huit sections de données, les outils, « utiliser en
  3 étapes », le lien vers la documentation.
- F6. Chaque section est une carte avec son icône et une phrase qui dit ce
  qu'on y trouve.
- F7. Les fils d'Ariane des pages de données passent par « Explorer ».

### Page d'accueil (refaite)

- F8. Un bandeau : logo, une phrase qui dit ce qu'est le Lexicon, deux
  actions (« Explorer les données », « Interroger Duke » ou « Documentation »).
- F9. **Le schéma dynamique** (voir §4).
- F10. Quelques chiffres tirés du catalogue : nombre de jeux de données, de
  lignes, date de la dernière mise à jour.
- F11. Trois façons de s'en servir : l'API (JSON, CSV), les packages à
  télécharger, les agents IA (MCP, Duke).
- F12. Un bloc « commun d'OSFarm » : licence, contribution, adhésion pour une
  clé.
- F13. L'avertissement « en cours de développement » : à garder, déplacer ou
  retirer (question 6).

### Style d'ensemble

- F14. Police, couleurs, boutons en pilule et cartes d'osfarm.org.
- F15. Le style s'applique à toutes les pages publiques : listes, fiches,
  formulaires de filtre, cartes, catalogue, fiches commune et entreprise,
  documents de R&D, Duke, identificateur de parcelle.
- F16. Nouveau logo dans l'en-tête et comme icône d'onglet.

## 4. Le schéma dynamique

### Ce qu'il doit faire comprendre

1. **D'où viennent les données** : des sources publiques dispersées (IGN,
   ASP, ANSES, INSEE, MSA, Météo-France, plateforme R&D agricole…), chacune
   avec son format et sa licence.
2. **Ce que fait le Lexicon** : il les collecte, les met dans une forme
   commune, et surtout les **relie** par des clés partagées — la commune, le
   SIREN, la parcelle cadastrale, le code culture PAC, le taxon, la
   production, la station météo.
3. **Ce que ça permet** : poser une question qui traverse plusieurs sources
   (« quelle culture sur cette parcelle depuis 2022, à qui appartient-elle,
   quelles aides, quels travaux de R&D sur cette culture »), par l'API, par
   téléchargement, ou par un agent IA.

### Ce que « dynamique » veut dire ici

- S1. **Interactif** : survoler ou toucher un jeu de données met en évidence
  les clés qu'il porte et les jeux auxquels elles le relient ; survoler une
  clé montre tous les jeux qu'elle relie.
- S2. **Nourri par les vraies données** : les jeux, leurs clés et leurs taux
  de liaison viennent du catalogue (manifestes des packages en service), pas
  d'une image figée. Un jeu ajouté demain apparaît sans retoucher le schéma.
- S3. **Animé avec mesure** : un flux discret des sources vers les usages au
  chargement ; rien qui tourne en boucle.
- S4. Un clic sur un jeu mène à sa page du catalogue ; un clic sur une clé
  explique ce qu'elle est.
- S5. Un exemple guidé, en trois ou quatre pas, suit une question réelle à
  travers les jeux (par exemple un point → parcelle cadastrale → parcelle PAC
  et son historique de cultures → commune → entreprises).

### Contraintes du schéma

- S6. Lisible sans JavaScript : la même information existe en texte ou en
  liste.
- S7. Lisible au téléphone : version empilée plutôt qu'un graphe réduit.
- S8. Utilisable au clavier et par un lecteur d'écran ; respecte le réglage
  « réduire les animations ».
- S9. Les jeux réservés aux adhérents sont montrés comme tels, sans rien
  révéler de leur contenu.

## 5. Besoins non fonctionnels

- N1. **Pas de régression** : adresses, JSON, CSV, MCP et administration
  inchangés. Les tests existants passent.
- N2. **Sobriété** : pas de cadriciel d'interface ; CSS écrit à la main,
  JavaScript minimal. Les pages qui n'en ont pas besoin ne chargent plus
  Leaflet et ECharts (aujourd'hui chargés partout).
- N3. **Polices servies par nous** (pas d'appel à un tiers), avec repli système.
- N4. **Accessibilité** : contrastes suffisants (le vert `#338000` sur blanc
  passe ; le jaune ne porte jamais de texte), focus visible, titres ordonnés.
- N5. **Adaptatif** : du téléphone au grand écran.
- N6. **Bilingue** : tout nouveau texte existe en français et en anglais.
- N7. **Échappement** : les enfants JSX ne sont pas échappés par la
  bibliothèque utilisée ; tout ce qui vient de la base passe par
  `Html.escapeHtml`.
- N8. **Poids** : le logo actuel fait 93 Ko avec un fond blanc ; il faut une
  version allégée, à fond transparent, et une version carrée pour l'onglet.

## 6. Récits d'usage et critères d'acceptation

1. *Visiteur qui découvre.* J'arrive sur l'accueil ; sans faire défiler plus
   d'un écran, je lis ce qu'est le Lexicon et je vois le schéma. Je survole
   « RPG » : les clés « commune » et « code culture » s'allument, avec les
   jeux qu'elles relient.
2. *Habitué.* Je clique sur « Explorer » et je retrouve exactement les
   entrées que l'accueil proposait hier ; mes favoris vers les pages de
   données fonctionnent toujours.
3. *Membre d'OSFarm.* Je reconnais la police, les verts et les boutons du
   site de l'association.
4. *Au téléphone.* Le menu se replie, le schéma s'empile, rien ne déborde.
5. *Sans JavaScript.* L'accueil reste compréhensible et tous les liens
   fonctionnent.
6. *Intégrateur.* Mes appels à `…/resource.json` renvoient la même chose
   qu'avant.

## 7. Décisions (réponses du 2026-10-04)

| # | Question | Décision |
|---|---|---|
| 1 | Skill de design | Le skill **frontend design**, pour la conception et la réalisation |
| 2 | Couleurs | **Teinte propre au Lexicon**, tirée du logo (bleu-vert `#125e6f`, bleu `#5b99c7`, jaune `#fdd548`), dans le cadre graphique d'OSFarm : police, boutons en pilule, cartes, structure des pages |
| 3 | Logo | Nettoyer le SVG fourni : retirer le fond, alléger, tirer une icône carrée |
| 4 | Données du schéma | **Structure dessinée à la main**, avec les chiffres du catalogue |
| 5 | Périmètre | Toutes les pages publiques **et l'administration** |
| 6 | Avertissement « en cours de développement » | Conservé |
| 7 | Menu | Ordre de F1 retenu ; **sélecteur de langue** visible, français par défaut |
| 8 | Adresse d'« Explorer » | `/explore` |
| 9 | Police | Les fichiers Ubuntu d'osfarm.org sont repris et servis par le Lexicon |
| 10 | Thème sombre | Hors périmètre |

### Ce que ces décisions entraînent

- **Couleurs (2).** Le vert d'OSFarm ne sert plus de couleur principale : il
  reste dans le logo de l'association au pied de page. Les contrastes sont à
  revérifier avec la nouvelle teinte (N4) : `#125e6f` sur blanc convient au
  texte et aux boutons ; `#5b99c7` et le jaune ne portent pas de texte.
- **Schéma (4).** S2 est réduit : la structure (sources, jeux, clés, usages)
  est écrite dans le code, seuls les chiffres viennent du catalogue (nombre de
  lignes, date, taux de liaison quand il est mesuré). Un jeu ajouté plus tard
  n'apparaît pas tout seul : il faut l'ajouter au schéma. Un jeu du schéma
  absent du catalogue s'affiche sans chiffre plutôt que de faire échouer la page.
- **Administration (5).** `AdminLayout` adopte le même style. L'interface
  d'administration reste en français, hors du sélecteur de langue.
- **Langue (7).** Aujourd'hui la langue suit l'en-tête du navigateur. Avec un
  sélecteur et le français par défaut, il faut retenir le choix du visiteur
  (un cookie) ; un visiteur sans choix voit le français, quel que soit son
  navigateur. Les formats JSON et CSV suivent la même règle.
- **F13.** L'avertissement reste sur l'accueil.

## 8. Points laissés à la conception

1. Le texte du bandeau et des blocs de l'accueil, en français et en anglais.
2. La liste exacte des jeux, des clés et des usages montrés dans le schéma,
   et la question suivie par l'exemple guidé.
3. La technique du schéma (SVG en ligne et CSS, avec ou sans bibliothèque).
4. L'ordre de livraison : en-tête et accueil d'abord, ou tout d'un coup.
