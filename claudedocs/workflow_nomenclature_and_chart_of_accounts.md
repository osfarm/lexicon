# Workflow — open_nomenclature → master_nomenclatures + chart_of_accounts CSV completion

**Status:** PLAN ONLY (no code executed). Run `/sc:implement` to execute.
**Date:** 2026-06-23
**Scope:** Two related tasks sharing the `onoma` gem (`gem 'onoma', gitlab: 'ekylibre/onoma', branch: 'lexicon'`).

---

## Objective

1. **open_nomenclature** — stop creating one raw table per nomenclature; load **all** nomenclatures into a single final lexicon table `master_nomenclatures`.
2. **chart_of_accounts** — complete `data/chart_of_accounts/chart_of_accounts - chart_of_accounts.csv` (824/1595 rows have an empty `name`) by matching rows against `onoma`'s `accounts` nomenclature.

---

## Current State (verified)

### open_nomenclature (`lib/datasources/open_nomenclature.rb`)
- `load` iterates `Onoma.each` (61 nomenclatures), and for each does
  `DROP/CREATE TABLE <nomenclature.name> (name VARCHAR, label JSONB)` + `COPY` of `(name, label-jsonb)`.
- No `table_definitions`, no `normalize` → output lives only in the raw schema, never reaches the versioned `lexicon` schema / packages.
- Reference pattern for final tables: see `units.rb` (`table_definitions` declares `master_*`, `normalize` inserts from raw schema).

### chart_of_accounts (`lib/datasources/chart_of_accounts.rb`)
- `collect` copies the CSV; `load` → `load_csv(... 'chart_of_accounts')`; `normalize` inserts into `master_chart_of_accounts (id, reference_name, previous_reference_name, fr_pcga, fr_pcg82, name jsonb)`.
- CSV columns: `N°,name,previous_name,label_fr,fr_pcg82,fr_pcga`. **824 empty `name`.** Quoted commas present → use Ruby `CSV`.

### onoma `accounts` (verified in container)
- 601 items. Properties: `centralizing, debtor, fr_pcg2019, fr_pcg2023, fr_pcg82, fr_pcga, fr_pcga2023, pt_snc` (sentinel `"NONE"` = unset).
- Coverage: `fr_pcg82` set on 485 items, `fr_pcga` set on 488.
- French label via `item.l(locale: :fra)` (after `Onoma.load_locales` + `I18n.reload!`). `item.human_name` raises — use `item.l`.
- Access: `Onoma["accounts"].list` ; per-item `item.name`, `item.attributes` (hash of the properties above).

---

## Task 1 — open_nomenclature → `master_nomenclatures`

**Design decision:** one consolidated table, keyed by `(nomenclature, name)`, mirroring the established raw-load → `normalize`-insert pattern (safest; works with the existing search_path/dump machinery). Keep item properties so downstream consumers (e.g. account codes) aren't lost.

### Step 1.1 — Rewrite `load` to fill ONE raw table
- Replace per-nomenclature `DROP/CREATE/COPY` with a single raw table:
  - `DROP TABLE IF EXISTS nomenclatures`
  - `CREATE TABLE nomenclatures (nomenclature VARCHAR NOT NULL, name VARCHAR NOT NULL, label JSONB, properties JSONB)`
- Single `COPY nomenclatures (nomenclature, name, label, properties) FROM STDIN`, iterating:
  ```ruby
  Onoma.each do |nomenclature|
    nomenclature.find_each do |item|
      tr    = I18n.available_locales.each_with_object({}) { |l, h| h[l] = item.l(locale: l) }
      props = (item.attributes || {}).to_json
      c.call "#{nomenclature.name}\t#{item.name}\t#{tr.to_json}\t#{props}\n"
    end
  end
  ```
- Keep the locale setup (`I18n.available_locales = %i[arb cmn deu eng fra ita jpn por spa]`, `Onoma.load_locales`, `I18n.reload!`, `Onoma.load!`).
- **Edge cases:** labels/properties may contain TAB or newline → sanitize before `c.call` (e.g. `gsub(/[\t\n]/, ' ')` on label values) to keep COPY's TSV framing intact. (Current code already risks this; fix it here.)

### Step 1.2 — Add `self.table_definitions(builder)`
```ruby
builder.table :master_nomenclatures, sql: <<~SQL
  CREATE TABLE master_nomenclatures (
    nomenclature character varying NOT NULL,
    name         character varying NOT NULL,
    label        jsonb,
    properties   jsonb,
    PRIMARY KEY (nomenclature, name)
  );
  CREATE INDEX master_nomenclatures_nomenclature ON master_nomenclatures(nomenclature);
SQL
```

### Step 1.3 — Add `normalize`
```ruby
query <<-SQL
  INSERT INTO master_nomenclatures (nomenclature, name, label, properties)
    SELECT nomenclature, name, label, properties
    FROM open_nomenclature.nomenclatures
SQL
```

### Step 1.4 — Validate
- `./lexicon validate` (schema vs definitions).
- `./lexicon run open_nomenclature` then in `./lexicon console` confirm row counts:
  `SELECT nomenclature, count(*) FROM lexicon.master_nomenclatures GROUP BY 1;` — expect 61 nomenclatures, `accounts` ≈ 601.

**Decision to confirm with user:** keep the `properties` column? (Recommended — Task 2 and ERP consumers benefit.) If not wanted, drop it from all three steps.

---

## Task 2 — Complete `chart_of_accounts` CSV from onoma/accounts

**Goal:** fill empty `name` (and optionally empty `label_fr`) for the 824 rows by matching each CSV row to an onoma `accounts` item.

**Match strategy (in priority order), one-off generator script:**
1. By `fr_pcga` code (CSV `fr_pcga` ↔ onoma `fr_pcga`) — primary key for the "PCG agricole" plan this dataset targets.
2. Fallback by `fr_pcg82` code.
3. Fallback by normalized French label (CSV `label_fr` ↔ `item.l(locale: :fra)`, accent/case-insensitive).
4. No match → leave row unchanged, log to an unmatched report.

### Step 2.1 — Build the generator (one-off, not a datasource phase)
- Location: `bin/` or `scripts/` ruby script run inside the container (`docker compose -f docker-compose-dev.yml exec lexicon_runner bundle exec ruby ...`).
- Load onoma; build lookup hashes: `by_pcga`, `by_pcg82`, `by_label` (skip `"NONE"`/blank; detect & report code collisions where two items share a code).
- Parse CSV with Ruby `CSV` (`headers: true`) — **required** because of quoted commas.

### Step 2.2 — Fill rules (non-destructive)
- Only write `name` when currently empty AND a unique match exists.
- Never overwrite a non-empty `name`; on conflict (existing name ≠ matched name) log a warning, keep CSV value.
- Optionally backfill empty `label_fr` from `item.l(:fra)`.
- Preserve column order/header exactly: `N°,name,previous_name,label_fr,fr_pcg82,fr_pcga`.

### Step 2.3 — Report & review
- Emit counts: filled, already-set, ambiguous (multi-match), unmatched. Write unmatched rows to `claudedocs/chart_of_accounts_unmatched.csv` for manual review.
- **Backup** original CSV before overwrite (`git` diff is the safety net; commit only after review).

### Step 2.4 — (Optional) extend the datasource
- The task says "update the datasource". Minimal = updated CSV only (no `.rb` change needed; schema unchanged).
- Optional enhancement: add `fr_pcg2019` / `fr_pcg2023` columns sourced from onoma → requires editing the CSV header, `master_chart_of_accounts` definition, and `normalize`. **Confirm with user before doing this** (schema change, larger blast radius).

### Step 2.5 — Validate
- `./lexicon run chart_of_accounts`; confirm `SELECT count(*) FROM lexicon.master_chart_of_accounts WHERE reference_name IS NOT NULL;` increased by ~the number of filled rows.

---

## Dependencies & Order
- Tasks are independent but both rely on onoma. Do **Task 1 first** (smaller, self-contained, exercises onoma access), then **Task 2**.
- Task 2's generator can reuse the onoma `accounts` access patterns proven in Task 1.

## Open Questions for User
1. `master_nomenclatures`: keep a `properties` JSONB column? (Recommended: yes.)
2. CSV completion: match primarily on **fr_pcga** (agricultural plan) — confirm that's the right key vs fr_pcg82.
3. Also backfill empty `label_fr` from onoma, or only `name`?
4. Add new pcg-variant columns to chart_of_accounts (schema change), or keep current schema?

## Risk Notes
- COPY TSV framing: labels/properties with tabs/newlines corrupt rows — sanitize (Task 1.1).
- CSV quoted commas: must use Ruby `CSV`, never line/awk splitting (Task 2.1).
- Ambiguous code→item matches in onoma: detect collisions; don't guess.
- Non-destructive fill: never overwrite existing `name` values; keep original under version control until reviewed.
