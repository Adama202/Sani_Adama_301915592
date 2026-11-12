# Portfolio 4 — SQL vs NoSQL comparison (Crumble Studio)

Crumble Studio uses **both** data stores side by side. The PostgreSQL database
(Portfolios 1–3, 5) is the system of record for the bakery's *business*
data — outlets, products, ingredients, recipes, stock, sales. The MongoDB
database (this portfolio) is the system of record for *operational telemetry*
(oven sensor logs) and for *rich, semi-structured recipe cards* whose shape
varies per product type. This short note explains why each data store is the
right tool for each job, and the trade-offs.

## 1. What lives where

| Concern | PostgreSQL | MongoDB |
|---------|-----------|---------|
| Outlets, products, ingredients | ✅ | — |
| Recipes (ingredients + quantity per unit, many-to-many) | ✅ `recipe_line` | — |
| Ingredient batches + FIFO consumption | ✅ | — |
| Outlet stock + sales (relational, transactional) | ✅ | — |
| Oven sensor logs (time-series, every minute, 4 ovens, ~40k docs/week) | — | ✅ `oven_logs` (time-series collection) |
| Rich recipe cards (steps, variations, allergens, type-specific fields) | partial (only ingredient quantities) | ✅ `recipe_cards` (oneOf schema) |
| Ad-hoc analytical aggregations | ✅ (P2 queries) | ✅ (P4 aggregation pipeline) |

## 2. Why MongoDB for oven logs

* **Write volume.** 4 ovens × 1 reading per minute = 5,760 documents/day, ~2.1M
  per year. MongoDB's time-series collection stores these in a columnar
  on-disk format with automatic compression and an automatic compound index on
  `(metaField, timeField) = (ovenId, ts)`. PostgreSQL can store the same data
  but without the storage optimisation; we would need to partition by month
  (see P5) and tune autovacuum aggressively.
* **Schema flexibility.** Future sensor additions (e.g. a new gas-leak sensor)
  are just new fields in the document — no `ALTER TABLE`, no migration.
* **Time-bucketed aggregations.** The `$dateToString` + `$group` pipeline in
  `04_aggregations.js` is concise and reads naturally for time-series work.
* **TTL.** `expireAfterSeconds: 60*60*24*90` automatically drops readings older
  than 90 days — no cron job required.

## 3. Why MongoDB for recipe cards

* **Different fields per product type.** Bread needs `hydrationPct` and
  `fermentationHours`; pastry needs `laminationFolds` and `butterPct`; pie
  needs `crustType` and `filling`; cookie needs `doughRestHours` and
  `spreadFactor`. In SQL we would need a wide table with many NULL columns or
  an EAV anti-pattern. MongoDB's `$jsonSchema` with `oneOf` (see
  `01_schema_validation.js`) validates each variant cleanly.
* **Arrays of steps and variations.** Document arrays map directly to the
  domain; in SQL they would need child tables and joins.
* **Allergen search.** A multikey index on `allergens` makes "find every
  product containing Milk" an `IXSCAN` over a small index (see
  `05_indexes.js`).

## 4. Why PostgreSQL for everything else

* **ACID transactions across multiple tables.** `sell_items()` and
  `bake_run()` (P3) are multi-statement transactions that lock and update
  several tables atomically. MongoDB only supports multi-document ACID
  transactions since 4.0 and they are slower; PostgreSQL is the right default
  for OLTP.
* **Foreign keys + CHECK constraints + triggers.** Crumble Studio's
  "stock can never go below zero", "expired batches cannot be used",
  "FIFO consume exactly recipe × units" rules are enforced *in the database*
  in PostgreSQL. In MongoDB we would have to enforce them in application code
  (or via `$jsonSchema`, which cannot express cross-document rules).
* **SQL query power.** The 8 reporting queries in P2 (best sellers per outlet
  per month, waste per product, etc.) are one-page SQL statements. The
  equivalent MongoDB pipelines exist (P4) but are more verbose and less
  declarative.
* **Streaming replication + partitioning (P5).** PostgreSQL's native
  streaming replication and declarative partitioning give us a read replica
  for the sales dashboard and monthly partitions on `sale_line` — both
  required by the CA brief.

## 5. CAP theorem framing (Study Session 2)

* PostgreSQL is **CP** in CAP terms — under a network partition it refuses
  to accept writes on the minority side, preserving consistency over
  availability. This is correct for stock and sales: we cannot risk
  over-selling or double-spending an ingredient batch.
* MongoDB is **CP** by default as well (single primary, secondaries are
  eventually consistent). The oven_logs workload is **available-first** in
  spirit: a missed sensor reading is not the end of the world, so an outlet
  could buffer writes locally if the MongoDB primary is unreachable, then
  reconcile later. See the P5 cloud architecture note for how this fits the
  "outlets that keep selling when the internet drops" requirement.

## 6. When we would flip a workload

| Workload | Today | If we changed our mind, why |
|----------|-------|-----------------------------|
| Sale + sale_line | PostgreSQL | If we needed flexible per-sale metadata (promo codes, customer preferences, loyalty info of arbitrary shape) we could move to MongoDB — but we would lose FK integrity with outlet/product. |
| Oven logs | MongoDB time-series | If we needed to JOIN oven temps to production runs (e.g. "find every croissant baked while oven-3 was above 260°C") we could mirror the data into Postgres with `jsonb` columns and partition by month. |
| Recipe cards | MongoDB | If the recipes were tightly coupled to ingredient batches and procurement, a full SQL model would be cleaner. |

## 7. Bottom line

* Use **PostgreSQL** when the data is **relational, transactional, and
  constraint-heavy** (Crumble Studio's stock and sales).
* Use **MongoDB** when the data is **high-volume time-series** or
  **document-shaped with per-type variant fields** (Crumble Studio's oven
  logs and recipe cards).

Both run on the same Codespaces VM; both back the same Crumble Studio case
study; the choice per workload is driven by the data's shape, not by fashion.
