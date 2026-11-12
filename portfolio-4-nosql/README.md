# Portfolio 4 — NoSQL and Advanced Data Models

**Maps to course-note Study Session 5** (Emerging Trends — graph DBs, edge DBs,
serverless, §5.1–5.2) and **Study Session 3** (Big Data, §3.1).

## Files in this folder

| File | What it does |
|------|--------------|
| `01_schema_validation.js` | Creates the `oven_logs` **time-series collection** (ovenId as metaField, ts as timeField, 90-day TTL) and the `recipe_cards` regular collection with a **`$jsonSchema` validator using `oneOf`** (NOT `if/then`) — one branch per product type (bread, pastry, pie, cookie) with type-specific required fields. |
| `02_seed_oven_logs.js` | Generates **40,320** oven sensor readings (4 ovens × 7 days × 1440 minutes). Realistic target temps, ±10°C noise, evening Ramadan boost, 4% door-open rate. Inserted in batches of 1000 with `ordered:false`. |
| `03_seed_recipe_cards.js` | 10 recipe cards (one per SQL product). Each carries the type-specific block required by the `oneOf` validator. Prints one example per type so the different shapes can be screenshotted. |
| `04_aggregations.js` | Three pipelines: (A) average baking temperature per oven per day, (B) ovens running too hot (avg > target + 15°C), (C) allergens per product + allergen roll-up. Bonus: door-open events per oven per day. |
| `05_indexes.js` | Drops any index on `recipe_cards.allergens`, runs `find({allergens:"Milk"}).explain("executionStats")` → expect **COLLSCAN**; creates a multikey index on `allergens`; re-runs the same `explain` → expect **IXSCAN**. Also shows the auto-created `(ovenId, ts)` index on the time-series collection. |
| `06_sql_vs_nosql.md` | Short comparison: what lives in PostgreSQL vs MongoDB at Crumble Studio, why each store is the right tool for each workload, CAP framing, and when we would flip a workload. |
| `run_p4.sh` | Runs everything in order; prints final document counts. |

## Commands (Codespaces)

```bash
bash setup.sh                                  # one-time
bash portfolio-4-nosql/run_p4.sh
```

To explore interactively:

```bash
mongosh crumble
> db.oven_logs.estimatedDocumentCount()
> db.recipe_cards.find({type:"bread"}).pretty()
```

## What to screenshot for evidence

1. The validator JSON printed by `01_schema_validation.js` (proves `oneOf`).
2. The "Inserted 40320 oven log documents" line + `estimatedDocumentCount()` check.
3. One example `recipe_card` per type (bread / pastry / pie / cookie) showing
   the different fields — proves the `oneOf` schema accepts all four shapes.
4. The three aggregation outputs from `04_aggregations.js`.
5. From `05_indexes.js`: the BEFORE explain (COLLSCAN, `totalDocsExamined` =
   10) and the AFTER explain (IXSCAN on `allergens_1`, `totalDocsExamined` =
   number of products containing Milk). Paste both into the README / final PDF.

## Suggested git commit

```bash
git add portfolio-4-nosql
git commit -m "P4: MongoDB oven_logs (time-series) + recipe_cards (oneOf) + aggregations + COLLSCAN->IXSCAN demo"
```

## What this demonstrates

Two MongoDB collections on the same Crumble Studio case study, each justified
by its data shape. The **time-series** `oven_logs` collection captures
high-volume sensor telemetry with an automatic `(ovenId, ts)` index and a TTL.
The `recipe_cards` collection uses a **`$jsonSchema` validator with `oneOf`**
(MongoDB supports `oneOf`/`anyOf`, not `if/then`) to validate four different
per-type document shapes in one collection. Three aggregation pipelines answer
operational questions (avg temp per oven per day, ovens running too hot,
allergen roll-up). The index demo shows a real `COLLSCAN → IXSCAN` transition
with `explain("executionStats")`. The comparison note explains why PostgreSQL
remains the system of record for transactional stock and sales while MongoDB
is the right tool for telemetry and richly-shaped documents.
