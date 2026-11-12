# MIT 8103 Advanced Database Systems — Portfolio

**Student:** Adama Sani
**Matric number:** 2026/A/MIT/0340
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (2026/2027 First Semester CA)
**GitHub repository:** [GitHub link]

## Case study

**Crumble Studio** is a bakery and café in Abuja, Nigeria. It has one central kitchen
where all baking happens and three retail outlets: **Jabi**, **Wuse 2** and **Gwarinpa**.

Every morning the central kitchen bakes batches of bread, croissants, pies and cookies
from recipes. Each recipe lists ingredients and the quantity needed per unit baked.
Ingredients are received in batches from suppliers and each batch has an expiry date;
the kitchen always uses the oldest unexpired batch first (FIFO). Baked items are sent
to the outlets and sold either over the counter or for online pickup.

The database must capture: outlets, products, ingredients, recipes, ingredient batches
(with expiry and supplier), production runs (what was baked, when, how many), batch
usage (which batches a run consumed), outlet stock (per outlet, per product, per day),
sales (per outlet, per time, per channel) and sale lines.

## Repository structure

```
advanced-database-portfolio/
├── README.md                              <- this file
├── setup.sh                               <- installs PostgreSQL 16 + MongoDB 8 in Codespaces
├── docs/
│   ├── 00_brief_summary.md                <- CA summary + portfolio-to-session map
│   └── REFERENCES.md
├── portfolio-1-database-design/
│   ├── README.md
│   ├── run_p1.sh
│   ├── 01_schema.sql
│   ├── 02_constraints_triggers.sql
│   ├── 03_seed.sql
│   ├── 04_bulk_generate.sql
│   ├── 05_constraint_tests.sql
│   └── er_diagram.md
├── portfolio-2-query-optimisation/
│   ├── README.md
│   ├── run_p2.sh
│   ├── 01_queries.sql
│   ├── 02_indexes.sql
│   └── 03_explain_compare.md
├── portfolio-3-transactions-concurrency/
│   ├── README.md
│   ├── run_p3.sh
│   ├── 01_sell_items.sql
│   ├── 02_bake_run.sql
│   ├── 03_rollback_demo.sql
│   ├── 04_race_condition.md
│   ├── 05_deadlock.md
│   └── 06_isolation_levels.md
├── portfolio-4-nosql/
│   ├── README.md
│   ├── run_p4.sh
│   ├── 01_schema_validation.js
│   ├── 02_seed_oven_logs.js
│   ├── 03_seed_recipe_cards.js
│   ├── 04_aggregations.js
│   ├── 05_indexes.js
│   └── 06_sql_vs_nosql.md
└── portfolio-5-distributed-cloud/
    ├── README.md
    ├── run_p5.sh
    ├── 01_partition.sql
    ├── 02_replica_setup.sh
    ├── 03_replica_demo.sql
    └── 04_cloud_architecture.md
```

## One-time setup (Codespaces)

```bash
bash setup.sh
```

This installs PostgreSQL 16 and MongoDB 8, starts both services, and creates the
`crumble` database (Postgres) and `crumble` database (MongoDB).

## Running each portfolio

Each portfolio has its own `run_pN.sh`. Run them in order:

```bash
bash portfolio-1-database-design/run_p1.sh
bash portfolio-2-query-optimisation/run_p2.sh
bash portfolio-3-transactions-concurrency/run_p3.sh
bash portfolio-4-nosql/run_p4.sh
bash portfolio-5-distributed-cloud/run_p5.sh
```

See each portfolio's `README.md` for what to screenshot and the suggested git commit.

## AI-use declaration

AI tools (Z.ai) were used as a learning aid to scaffold the schema, the SQL/JS scripts
and the documentation structure. All output was reviewed, corrected where needed, and
the student remains responsible for the accuracy and understanding of every line
submitted. A full AI-use declaration will be included in the final LMS documentation.
