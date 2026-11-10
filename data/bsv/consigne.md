# Consigne d'extraction d'un Bulletin de santé du végétal (BSV)

Tu lis un BSV français, le PDF lui-même : texte, tableaux, jauges, curseurs et couleurs. Tu en tires un objet
JSON de cette forme exacte :

```json
{
  "region": "Nouvelle-Aquitaine",
  "regions_citees": [],
  "zone": "Aquitaine",
  "filiere": "grandes cultures",
  "sous_filiere": null,
  "numero": "31",
  "date": "2026-11-05",
  "nature": "bulletin",
  "lignes": [
    {
      "culture": "colza",
      "bioagresseur": "grosse altise",
      "type": "ravageur",
      "stade": "levée à 4-5 feuilles",
      "bbch_min": 9,
      "bbch_max": 15,
      "zadoks_min": null,
      "zadoks_max": null,
      "niveau": "fort",
      "conditionnel": true,
      "niveau_texte": "risque fort dans les parcelles en cours de levée n'ayant pas dépassé le stade 4-5 feuilles",
      "condition": "parcelles en cours de levée n'ayant pas dépassé le stade 4-5 feuilles",
      "periode_risque": "de la levée au stade 4 feuilles",
      "seuil": "8 pieds sur 10 avec morsures",
      "observations": "Morsures observées sur les parcelles en cours de levée.",
      "lieux": ["Asques 33"],
      "page": 3,
      "extrait": "Grosse altise : risque fort dans les parcelles en cours de levée n'ayant pas dépassé le stade 4-5 feuilles."
    }
  ],
  "remarques": "ce qui t'a gêné dans ce bulletin, en une ou deux phrases, ou une chaîne vide"
}
```

## En-tête

- `region` : région administrative actuelle qui publie le bulletin (Nouvelle-Aquitaine, Occitanie, Pays de la
  Loire…).
- `regions_citees` : les autres régions administratives actuelles que le bulletin dit couvrir, quand il est commun
  à plusieurs (« BSV Bretagne, Normandie, Pays de la Loire » publié par la Bretagne → `["Normandie", "Pays de la
  Loire"]`). Liste vide sinon.
- `zone` : l'édition ou le territoire du bulletin s'il est plus petit que la région (« Aquitaine », « Limousin »,
  « Poitou-Charentes », « Languedoc-Roussillon », « Grand Sud-Ouest »), sinon null.
- `filiere` : une de : grandes cultures, viticulture, arboriculture, maraîchage, petits fruits, horticulture,
  JEVI, cultures tropicales.
- `sous_filiere` : la culture ou le groupe quand le bulletin est consacré à une seule (« kiwi », « fruits à
  noyau », « châtaignier », « fraise-framboise », « fruits à transformer »), sinon null.
- `numero`, `date` (AAAA-MM-JJ, date de publication).
- `nature` : « bulletin », « bilan » (bilan de campagne) ou « note » (note nationale, note commune).

## Lignes

Une ligne par **culture × bioagresseur** traité dans le bulletin, et une ligne par culture avec `bioagresseur`
null pour le **stade et l'avancement** de la culture quand le bulletin les donne.

**Sois exhaustif.** Chaque bioagresseur qui a sa rubrique, son paragraphe ou sa ligne de tableau renseignée dans
le bulletin donne sa ligne, même sans évaluation ni observation. Un nom seul dans un tableau ou un sommaire dont les
cases sont vides ne donne pas de ligne. Ne regroupe pas plusieurs bioagresseurs en une ligne
(« pucerons » et « acariens » font deux lignes), et quand une rubrique vaut pour plusieurs cultures nommées
(« pêcher et abricotier »), fais une ligne par culture. Parcours tout le bulletin avant de répondre, y compris les
tableaux et les encadrés.

- `culture` : la plante cultivée, au singulier, en minuscules (« blé tendre », « orge d'hiver », « maïs »,
  « pommier », « vigne », « kiwi »). Jamais le bioagresseur. Une rubrique qui vaut pour plusieurs cultures
  (« céréales à paille ») garde ce nom.
- `bioagresseur` : tel que nommé dans le bulletin, nom courant d'abord (« puceron cendré », « tavelure »,
  « mildiou », « drosophile à ailes tachetées »). Null pour une ligne de stade : jamais « stade phénologique ».
- `type` : « maladie », « ravageur », « adventice », « auxiliaire », « physiologique » (gel, échaudage,
  carence), ou null pour une ligne de stade. Un auxiliaire (carabes, staphylins, coccinelles, chrysopes,
  syrphes…) n'est pas un risque : son `niveau` est toujours `non_precise`, même si la phrase voisine évalue le
  risque d'un ravageur ; ce risque va sur la ligne du ravageur.
- `stade` : le stade observé ou concerné, tel qu'écrit. `bbch_min`, `bbch_max` : seulement si le bulletin écrit un
  code BBCH (0 à 99) ; sinon null. `zadoks_min`, `zadoks_max` : seulement si le bulletin écrit un code Zadoks
  (« Z30 », « Z32-Z37 ») ; sinon null. Ne convertis pas toi-même un stade en code, ni un code dans l'autre échelle.
- `niveau` : l'**évaluation du risque** que le bulletin donne **pour la période à venir**, et seulement elle,
  ramenée à l'échelle : `nul`, `faible`, `moyen`, `fort`, `tres_fort`, ou `non_precise` quand le bulletin ne donne
  aucune évaluation pour cette ligne. Règles : « modéré » → moyen ; « élevé », « important », « sérieux » → fort ;
  « très élevé », « très important », « maximal » → tres_fort ; « pas de risque », « risque nul », « absence » →
  nul ; « très faible », « peu important », « peu élevé », « limité » → faible (l'échelle n'a pas de « très
  faible » : ce n'est jamais tres_fort). **Une fourchette prend toujours le niveau le plus haut** : « faible à
  moyen », « faible à modéré » → moyen ; « moyen à fort », « modéré à élevé » → fort ; « fort à très fort » →
  tres_fort ; « faible voire nul » → faible. Quand le risque dépend des situations (« fort dans les parcelles
  levées tardivement, nul ailleurs »), prends le niveau le plus élevé, mets `conditionnel` à true et recopie la
  situation où ce niveau vaut dans `condition` ; sinon `conditionnel` est false et `condition` null. Un curseur,
  une jauge, une couleur ou un tableau de risque visibles sur la page valent évaluation : dis-le dans
  `niveau_texte` (« curseur à 3 sur 5 ») et donne le niveau correspondant (« curseur positionné vers le niveau
  fort » → fort) ; une ligne dont `niveau_texte` décrit un curseur ou une couleur n'est jamais `non_precise`.
  **Une évaluation commune vaut pour chaque ligne qu'elle couvre**, où qu'elle soit écrite (en tête de rubrique,
  dans un encadré, un résumé ou « À retenir ») : « au vu des observations, le risque concernant les ravageurs est
  important » donne fort à chaque ravageur de la rubrique, « le risque est faible pour l'ensemble des maladies »
  donne faible à chaque maladie.
  **Le texte d'une rubrique « Évaluation du risque » ou « Analyse de risque » est une évaluation**, quels que
  soient ses mots : ramène-le au niveau le plus proche (« quelques foyers à des niveaux faibles »,
  « occasionnel », « peu répandu » → faible ; « le risque augmente, populations encore faibles » → faible). Il ne
  donne `non_precise` que s'il ne dit rien du niveau.
  **Ce qui n'est pas une évaluation du risque**, et donne donc `non_precise` hors d'une rubrique d'évaluation :
  l'intensité de ce qui a été observé (« populations faibles », « quelques symptômes »), l'absence d'observation
  ou de signalement (« non observé », « pas de signalement », « absent de cette culture »), une tendance sans
  niveau (« le risque augmente », « en hausse »), « à surveiller », « période à risque », des conditions
  favorables ou défavorables. Ces textes vont dans `observations` ou `niveau_texte`, pas dans `niveau`. « Nul » ne
  s'emploie que si le bulletin dit que le **risque** est nul ou absent (« risque nul », « pas de risque », « fin
  de la période de risque »).
- `niveau_texte` : la phrase d'évaluation du bulletin, recopiée (raccourcie si elle est longue), null si aucune.
- `periode_risque`, `seuil` : tels qu'écrits, null s'ils ne sont pas donnés.
- `observations` : ce qui a été observé sur le terrain cette semaine (fréquence, intensité, nombre de parcelles),
  une ou deux phrases, en reprenant les chiffres du bulletin.
- `lieux` : communes ou lieux cités pour les observations, tels qu'écrits, avec le département s'il est donné
  (« Issigeac 24 »). Liste vide sinon.
- `page` : la page du PDF où se trouve la ligne, la première page étant 1.
- `extrait` : **une phrase recopiée mot pour mot** du texte, d'où vient l'essentiel de la ligne (l'évaluation de
  préférence). Elle servira de contrôle : elle doit se retrouver dans le texte du PDF, sans rien ajouter ni reformuler.

## Ce qu'on ne prend pas

Prévisions météo, annonces de réunions, coordonnées et noms des animateurs, rappels réglementaires (abeilles,
mentions légales), généralités sur la biologie d'un bioagresseur sans rapport avec la semaine, méthodes de lutte.
N'invente rien : ce qui n'est pas dans le texte est null.
