# 00 — Brief summary of the MIT 8103 Continuous Assessment

## What the CA asks for

MIT 8103 (Advanced Database Systems) is an individual practical portfolio worth **40
marks** (40 % of the first-semester CA). It is **not a written essay**: the deliverable
is *practical technical evidence* committed progressively to a private GitHub repo and
summarised in a 2–3 page LMS submission.

**Case study rule.** Each student picks one realistic organisation and uses it
consistently across all five portfolios. We chose **Crumble Studio**, a bakery and café
in Abuja with a central kitchen and three outlets (Jabi, Wuse 2, Gwarinpa).

**Deliverables (5 portfolios + final documentation).**

| # | Portfolio | Marks | Expected evidence |
|---|-----------|-------|-------------------|
| 1 | Database Design and Modelling | 7 | Case-study description, ER diagram, relational schema, keys, constraints, normalisation explanation |
| 2 | Query Processing and Optimisation | 7 | SQL queries, results, execution plans, indexing/optimisation evidence, performance analysis |
| 3 | Transactions and Concurrency | 7 | Commit, rollback, isolation, concurrency issue or control mechanism, screenshots/output |
| 4 | NoSQL and Advanced Data Models | 7 | NoSQL model on the same case study, document/key-value/column/graph example, implementation, suitability |
| 5 | Distributed and Cloud Database Exercise | 6 | Replication, sharding, availability, consistency, deployment evidence |
| — | Final Documentation | 6 | 2–3 page summary, GitHub link, screenshots, reflection, references, AI-use declaration |
| | **Total** | **40** | |

**Page / format limit.** The LMS submission is a **2–3 page** documentation file linking
to the GitHub repo. The repo itself has no page limit but must be **progressively
committed** (committing only at the deadline reduces the marks).

**Naming rules.** The CA does not fix a filename convention, but the student's name,
matric number and programme must be on the documentation. We use
`Sani_Adama_2026-A-MIT-0340_Documentation.pdf` for the final document.

**Submission rules.** Submit on the LMS *and* keep the GitHub repo accessible to the
assessor. The repo must follow the suggested structure:
`advanced-database-portfolio/portfolio-1-database-design/…` through `portfolio-5-…`.

**AI use.** AI tools are permitted as learning aids, but a short **AI-use declaration**
must state: (i) the tool used, (ii) what it was used for, (iii) how the output was
reviewed, corrected, tested or verified. AI use does not remove the student's
responsibility for accuracy and understanding.

**Similarity / individual work.** This is individual work. General discussion with
classmates is allowed; copying is not. Verification is mainly by submitted technical
evidence + progressive GitHub activity + a short individual technical reflection. A
small sample of students may be called for a brief viva if their submission is unclear,
copied, inaccessible or suspicious.

## Marking rubric (40 marks)

| Criteria | Marks |
|----------|-------|
| Technical correctness | 8 |
| Database design quality | 6 |
| Practical implementation | 8 |
| Query and performance analysis | 5 |
| Application of advanced database concepts | 5 |
| Documentation and GitHub organisation | 5 |
| Technical reflection / individual understanding | 3 |
| **Total** | **40** |

## Portfolio → course-note study sessions

The Miva Open University MIT 8103 course notes are organised into six study sessions:
(1) Review of Traditional Relational Databases and Advanced Concepts, (2) Distributed
Database System, (3) Big Data and Cloud Database Systems, (4) Query Optimisation in
Database, (5) Emerging Trends in Database Systems, and (6) Introduction to Data
Security and Data Privacy. The table below maps each portfolio to the session(s) it
applies.

| Portfolio | Primary study session(s) | Why |
|-----------|--------------------------|-----|
| **P1 — Database Design and Modelling** | Study Session 1 (Review of Traditional Relational Databases and Advanced Concepts) | ER design, relational schema, normalisation, constraints — all covered in §1.1–1.7 of Study Session 1. |
| **P2 — Query Processing and Optimisation** | Study Session 4 (Query Optimisation in Database) | Query execution plans, cost estimation and file organisation / indexing (§4.1–4.2) are exactly the topics of this portfolio. |
| **P3 — Transactions and Concurrency** | Study Session 1 (ACID, limitations of traditional DBMS, §1.8) + Study Session 2 (CAP, ACID vs BASE, §2.2.1–2.2.2) | ACID transactions come from Session 1; the consistency-model discussion in Session 2 frames isolation levels and concurrency control. |
| **P4 — NoSQL and Advanced Data Models** | Study Session 5 (Emerging Trends — graph, edge, serverless, §5.1–5.2) + Study Session 3 (Big Data, §3.1) | NoSQL and document/graph models are presented as emerging trends; the 40k-document sensor log is a Big Data scenario from Session 3. |
| **P5 — Distributed and Cloud Database** | Study Session 2 (Distributed DB — fragmentation, replication, consistency, CAP, §2.1–2.2) + Study Session 3 (Cloud Database Systems, §3.2) | Replication, CAP, sync/async trade-offs and cloud deployment map directly onto Sessions 2 and 3. The NDPA 2023 dimension adds the data-privacy angle from Study Session 6. |

## Submission checklist (from the CA brief)

1. Case study stated clearly. ✓ Crumble Studio.
2. All five portfolios use the same case study. ✓
3. All five portfolios complete. ✓ (this repo)
4. GitHub repo properly organised. ✓ (see top-level README)
5. Practical work + supporting evidence. ✓ (screenshots to be added as I run each portfolio)
6. README / documentation explains the work. ✓
7. Required files submitted through the LMS. ⏳ (after running everything)
8. GitHub link works. ⏳ (placeholder `[GitHub link]` at the top of this README)
9. Sources, datasets, libraries referenced. ✓ see `docs/REFERENCES.md`
10. AI use declared. ✓ (top-level README + final PDF)
11. Individual technical reflection. ⏳ (in the final 2–3 page PDF)
