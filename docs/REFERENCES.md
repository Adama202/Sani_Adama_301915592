# References

## Primary source — the CA brief

Miva Open University, School of Postgraduate Studies. (2026). *MIT 8103 Advanced
Database Systems — 2026/2027 Academic Session, First Semester Continuous Assessment
(September Cohort 2026).* 40 marks. Miva Open University, LMS + GitHub submission.

## Course notes (study sessions referenced throughout the portfolio)

Miva Open University. *MIT 8103 Advanced Database Systems — Course Notes.* Six study
sessions:

1. Review of Traditional Relational Databases and Advanced Concepts (DB design,
   normalisation, components, ACID, limitations of traditional DBMS).
2. Distributed Database System (architecture, fragmentation, replication,
   consistency models, CAP theorem, ACID vs BASE).
3. Big Data and Cloud Database Systems (Big Data, cloud DB use cases, data warehouse,
   database security).
4. Query Optimisation in Database (queries, query optimisation, execution plans,
   cost estimation, file organisation).
5. Emerging Trends in Database Systems (AI-powered DBs, blockchain, edge DBs,
   serverless DBs, graph databases and knowledge graphs).
6. Introduction to Data Security and Data Privacy (data privacy, advanced quantitative
   techniques, best practices).

## Software, documentation and standards

* PostgreSQL Global Development Group. *PostgreSQL 16 Documentation.*
  https://www.postgresql.org/docs/16/
  — schema design, CHECK constraints, triggers, PL/pgSQL functions, `EXPLAIN ANALYZE`,
  table partitioning, streaming replication, isolation levels.
* MongoDB, Inc. *MongoDB 8.0 Manual.*
  https://www.mongodb.com/docs/manual/
  — `$jsonSchema` validator with `oneOf`/`anyOf`, time-series collections, aggregation
  pipeline, `COLLSCAN` vs `IXSCAN`, `explain("executionStats")`.
* National Information Technology Development Agency (NITDA), Nigeria. *Nigeria Data
  Protection Act, 2023 (NDPA 2023).*
  https://nitda.gov.ng/wp-content/uploads/2023/06/Nigeria-Data-Protection-Act-2023.pdf
  — cited in P5 to justify keeping customer data inside Nigeria.
* PostgreSQL wiki. *Streaming replication setup.*
  https://wiki.postgresql.org/wiki/Streaming_Replication
* MongoDB. *Time Series Data.* https://www.mongodb.com/docs/manual/core/timeseries-collections/
* Brewer, E. A. (2000). *Towards robust distributed systems.* PODC keynote — the CAP
  theorem, referenced in P5.
* Gilbert, S., & Lynch, N. (2002). *Brewer's conjecture and the feasibility of
  consistent, available, partition-tolerant web services.* ACM SIGACT News 33(2).

## Libraries / tooling

* `psql` 16 (PostgreSQL client) — all P1–P3 and P5 SQL.
* `mongosh` 8 (MongoDB shell) — all P4 scripts.
* Ubuntu 24.04 packages: `postgresql-16`, `mongodb-org` 8.0.

## AI-use declaration (summary)

AI tool used: **Z.ai (GLM)**. Used to scaffold the schema, the SQL/JS scripts and the
documentation structure for all five portfolios. Every script was reviewed by the
student, corrected where needed, and is the student's responsibility. A fuller
declaration appears in the final LMS documentation file
(`Sani_Adama_2026-A-MIT-0340_Documentation.pdf`).

## Case-study data

All names, addresses, prices, customers and transactions in this portfolio are
**invented** for academic purposes. Crumble Studio is a simulated organisation; any
resemblance to a real Abuja business is coincidental. Nigerian customer names were
generated programmatically from common Yoruba, Hausa and Igbo name parts.
