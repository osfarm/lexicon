# Datasource `cap_beneficiaries` — Bénéficiaires des aides de la PAC

Les bénéficiaires des aides de la Politique agricole commune (FEAGA et
FEADER) et le détail de leurs aides, année par année. Source : ASP, sur
data.gouv.fr, Licence Ouverte 2.0.

## Tables produites

| Table | Contenu |
|---|---|
| `registered_cap_beneficiaries` | Une ligne par SIREN et par année : nom, commune, code postal et code INSEE (à partir de 2025), totaux par fonds |
| `registered_cap_subsidies` | Une ligne par aide : SIREN, année, intervention, dates, montants FEAGA, FEADER et cofinancé |

Les deux tables portent une colonne `year` : interroger le passé, c'est
filtrer sur elle. Les montants de deux années ne s'additionnent pas.

## Fichiers attendus

Un fichier par année dans `raw/cap_beneficiaries/`, nommé
`cap_beneficiaries_<année>.csv`, extrait de l'archive publiée par l'ASP.
`collect` en tire un fichier `…_filled.csv` au format commun.

La source a changé de forme avec le fichier 2025 :

| Année | Forme | Séparateur | Particularités |
|---|---|---|---|
| 2024 | hiérarchique : une ligne pour le bénéficiaire, puis une ligne par aide, sans identité | virgule | prénom et société dans des colonnes à part |
| 2025 | à plat : chaque ligne porte l'identité de son bénéficiaire | point-virgule, fins de ligne Windows | code postal et code INSEE ; ni prénom ni société |

## Règles de traitement

- **Bénéficiaires sans SIREN** (environ 10 000 par an, surtout des personnes
  physiques) : écartés, avec leurs aides.
- **Totaux** : ils ne sont pas lus dans la source, mais calculés comme la
  somme des aides. Un même SIREN a parfois plusieurs lignes de totaux (une par
  commune ou par dénomination), et la source ne les remplit pas toujours de la
  même façon : certaines portent leur part, d'autres répètent le total.
- **Petits bénéficiaires anonymisés** : la source remplace leur nom par
  « VALEUR ANONYMISEE » et leur commune par « COMMUNE ANONYMISEE » mais laisse
  leur SIREN. Ils sont repris tels quels.
- `total_eu_cofinanced` = FEAGA + FEADER + cofinancé ;
  `total_feader_cofinanced` = FEADER + cofinancé.

## Ajouter une année

1. Déposer `cap_beneficiaries_<année>.csv` dans `raw/cap_beneficiaries/`.
2. Regarder sa première ligne : séparateur et noms de colonnes.
3. Ajouter l'année à `FORMATS` dans `lib/datasources/cap_beneficiaries.rb`,
   avec sa forme (`:hierarchical` ou `:flat`), et mettre `LAST_UPDATED` à la
   date du fichier.
4. `./lexicon run cap_beneficiaries`, puis vérifier que la somme des aides
   égale le total de chaque bénéficiaire.
5. `./lexicon run enterprise_links` : les fiches entreprise reprennent la
   dernière année. Puis `package` et `publish` des deux.

## Contrôle après normalisation

```sql
SELECT b.year, count(*) FILTER (WHERE abs(b.total_eu_cofinanced - s.total) > 0.02) AS ecarts
  FROM lexicon.registered_cap_beneficiaries b
  JOIN (SELECT siren, year, sum(COALESCE(feaga_amount,0) + COALESCE(feader_amount,0) + COALESCE(cofinanced_amount,0)) AS total
          FROM lexicon.registered_cap_subsidies GROUP BY 1, 2) s USING (siren, year)
 GROUP BY 1;
```

Doit donner zéro écart pour chaque année.
