# Portfolio 5 — Cloud architecture for Crumble Studio (NDPA 2023, CAP, sync vs async, offline outlets)

## 1. Regulatory anchor: NDPA 2023

The **Nigeria Data Protection Act, 2023** (NDPA 2023) is the primary Nigerian
data-protection law. It requires, among other things, that personal data of
Nigerians be:

* processed lawfully, fairly, and transparently (s. 24);
* collected for specified, explicit purposes (s. 25);
* adequate, relevant, and limited to what is necessary (s. 26);
* kept only as long as necessary (s. 28);
* secured against unauthorised access, loss, or destruction (s. 29);
* **not transferred outside Nigeria** unless the recipient country ensures an
  adequate level of protection, or appropriate safeguards are in place
  (ss. 41–43 — cross-border transfer rules).

Crumble Studio's customer data (online customer names, phone numbers, delivery
addresses) is **personal data** under NDPA 2023. The simplest compliant
architecture is to **keep all customer data inside Nigeria** — no cross-border
transfer, no adequacy assessment, no extra contractual safeguards. This is the
approach we take.

## 2. Proposed cloud architecture (data residency in Nigeria)

```
                              +----------------------------------+
                              |  Nigerian cloud region           |
                              |  (e.g. MTN NCC-licensed DC in    |
                              |   Lagos, or Mainone / MDXi Lekki)|
                              |                                  |
   3 outlets  ----Internet--->|  +----------------------------+  |
   (Jabi,                    |  |  Application tier           |  |
    Wuse 2,                  |  |  - POS web app              |  |
    Gwarinpa)                |  |  - Online ordering web app  |  |
                             |  |  - Reporting / dashboard    |  |
                             |  +-------------+--------------+  |
                             |                |                 |
                             |  +-------------v--------------+  |
                             |  | PostgreSQL PRIMARY (rw)    |  |
                             |  |  - port 5432               |  |
                             |  |  - sale_line partitioned   |  |
                             |  |    by month                |  |
                             |  |  - streaming replication --+--+
                             |  +-------------+--------------+  |
                             |                |                 |
                             |  +-------------v--------------+  |
                             |  | PostgreSQL REPLICA (ro)    |  |
                             |  |  - port 5433               |  |
                             |  |  - feeds sales dashboard   |  |
                             |  +----------------------------+  |
                             |                                  |
                             |  +----------------------------+  |
                             |  | MongoDB (oven_logs,        |  |
                             |  |   recipe_cards)            |  |
                             |  |  - replica set of 3        |  |
                             |  +----------------------------+  |
                             +----------------------------------+
                                  |
                                  | (no personal data leaves)
                                  v
                              No international egress
```

### Why a Nigerian region

| Concern | How the architecture addresses it |
|---------|------------------------------------|
| NDPA 2023 cross-border transfer (ss. 41–43) | All customer data stays inside Nigeria; no transfer, no adequacy assessment needed. |
| Latency to outlets | The Nigerian region is single-hop from Abuja outlets; round-trip < 30 ms. |
| Operational sovereignty | Even if a foreign hyperscaler has an outage, the bakery keeps running because the primary is on Nigerian soil. |
| Auditability | Nigerian DC operator can be audited under NDPA; the Data Protection Compliance Organisation (DPCO) has clear jurisdiction. |

### Chosen providers (illustrative, not a product endorsement)

* **Compute + Postgres primary**: a Nigerian-licensed cloud (e.g. MTN Cloud,
  MainOne, MDXi, or the Nigeria Data Centre corridor in Lagos). Alternatively
  self-host in the central kitchen in Abuja with a backup DC in Lagos.
* **MongoDB**: a 3-node replica set hosted in the same Nigerian DC.
* **Object storage** (for receipt PDFs, photos): same Nigerian DC.

## 3. CAP theorem framing (Study Session 2)

The CAP theorem says a distributed system can provide at most **two of {C, A, P}**
in the presence of a network partition.

| Workload | Pick | Why |
|----------|------|-----|
| PostgreSQL OLTP (stock, sales, batch usage) | **CP** | We refuse writes that would risk consistency (over-selling, double-spending ingredient batches). The atomic `UPDATE … WHERE qty >= n` from P3 fix 1 and the FIFO function enforce this even under partitions. Availability gives way: if the primary is unreachable, an outlet cannot transact against the central DB. |
| MongoDB oven_logs | **AP-ish** | Sensor readings are high-volume, low-value-per-reading. We can afford to lose a reading or two during a partition; we cannot afford to stop collecting. The oven buffers readings locally and forwards them when connectivity returns. |
| Reporting replica | **C (eventually)** | The sales dashboard reads from the replica. It is **eventually consistent** with the primary — async streaming replication means a sale written a second ago may not yet be visible. The dashboard explicitly tolerates this (the wall-clock timestamp on each chart says "as of …"). |

## 4. Synchronous vs asynchronous replication

| | Synchronous (e.g. PostgreSQL `synchronous_commit=on` + `synchronous_standby_names`) | Asynchronous (default PostgreSQL streaming replication, MongoDB secondary reads) |
|---|---|---|
| Consistency | Strong — a commit is durable on at least 2 nodes before the client gets `COMMIT OK`. | Eventual — primary commits first; replica catches up via WAL stream. |
| Latency | Higher — every commit waits for the replica's ack. | Lower — primary returns as soon as its own WAL is flushed. |
| Availability | Lower — if the replica is partitioned, writes on the primary stall (or fail). | Higher — primary keeps writing; replica catches up when partition heals. |
| Use case | Money-losing data: payments, irreversible operations. | Telemetry, reporting, read scaling. |
| Crumble Studio choice | NOT used — would force every outlet to wait for Lagos on every sale. | **Used** — async streaming replication; the sales dashboard explicitly notes "as of last replication". |

For **Crumble Studio's scale** (3 outlets, single central kitchen), async
replication is the right trade-off: sales are fast, the dashboard is a few
seconds behind, and a network blip does not stop the bakery from selling.

## 5. Outlets that keep selling when the internet drops

This is the operational requirement: a Jabi outlet whose internet link goes
down must still be able to ring up sales at the counter, then reconcile with
the central database when the link returns.

### Architecture: a small local SQLite (or embedded Postgres) at each outlet

```
   +-----------------------------+
   |  Outlet POS terminal        |
   |  (Jabi, Wuse 2, Gwarinpa)   |
   |                             |
   |  Local SQLite DB            |
   |   - pending_sales           |
   |   - product_catalog (synced)|
   |   - outlet_stock (synced)   |
   |                             |
   |  Offline mode:              |
   |   write to pending_sales,   |
   |   decrement local stock     |
   |                             |
   |  Online mode:               |
   |   flush pending_sales to    |
   |   central Postgres via      |
   |   sell_items()              |
   +-------------+---------------+
                 |
                 | Internet (may drop)
                 v
   +-----------------------------+
   |  Central Postgres PRIMARY   |
   |  (Nigerian DC)              |
   +-----------------------------+
```

### How it works

1. **Catalog + stock sync (downlink).** Once an hour (or on reconnect) the
   outlet pulls the latest `product`, `outlet_stock` snapshot for its
   `outlet_id` from the central primary into its local SQLite. This is a
   read-only mirror; the outlet never writes back to it directly.

2. **Offline sale.** When the internet link drops, the POS app switches to
   offline mode. Each sale is appended to a `pending_sales` table in the local
   SQLite, and the local `outlet_stock` copy is decremented optimistically
   (the local copy is allowed to go to zero; the central `outlet_stock` row is
   NOT touched yet).

3. **Reconciliation (uplink).** When the link returns, the outlet pushes each
   pending sale to the central primary by calling `sell_items(...)` for each
   line. The central DB re-checks stock with the atomic `UPDATE … WHERE
   quantity_left >= n` pattern from P3 fix 1, so:
   * if stock is still available, the sale commits;
   * if another outlet or online order has already taken the last units, the
     sale is rejected and the cashier sees a "could not fulfil — refund the
     customer" prompt.

4. **Conflict resolution.** Stock is the only real conflict; everything else
   (customer name, sale time, channel) is local to the sale. The atomic
   `UPDATE` is the conflict resolver — last-writer-wins is not safe, but
   `WHERE quantity_left >= n` IS safe: it converts the conflict into a clean
   accept/reject per sale line.

5. **Reporting.** The sales dashboard reads from the **streaming replica**.
   It sees the sale a few seconds after the central primary commits it. During
   an outage, sales made offline appear on the dashboard only after the link
   returns and the outlet flushes — this is documented in the dashboard UI as
   "may exclude offline sales from outlets with an active outage".

### Why this satisfies NDPA 2023

* Customer data captured at the outlet (online customer name, phone) is held
  locally on the POS terminal only briefly (during the outage) and is pushed
  to the Nigerian central primary as soon as the link returns.
* No customer data leaves Nigeria at any point.
* The local SQLite is encrypted at rest; it is wiped once a successful flush
  is acked by the central primary.

### CAP alignment

* **Central Postgres primary**: CP — refuses writes that would over-sell.
* **Outlet local SQLite during outage**: AP — always accepts sales; reconciles
  on reconnect.
* **Streaming replica for dashboard**: eventually consistent — async.

This is a deliberate, workload-by-workload CAP trade-off: the *counter sale*
workload favours availability (the bakery must keep selling bread), the
*stock* invariant favours consistency (the central DB never over-sells), and
the *dashboard* workload favours partition tolerance with eventual
consistency (a few seconds of lag is fine).

## 6. Summary table

| Dimension | Choice | Rationale |
|-----------|--------|-----------|
| Data residency | Nigerian cloud region / Nigerian DC | NDPA 2023 cross-border transfer rules |
| Relational DB | PostgreSQL 16, primary + 1 async streaming replica | Mature, ACID, native partitioning + replication |
| NoSQL DB | MongoDB 8 replica set of 3 (in Nigeria) | Time-series + flexible-schema workload |
| Replication mode | **Async** streaming | Low write latency at the outlets |
| Consistency model | CP for stock, AP for offline POS, eventual for dashboard | Workload-by-workload CAP trade-off |
| Offline outlet | Local SQLite POS app, flush via `sell_items()` on reconnect | Bakery keeps selling when internet drops |
| Conflict resolution | Atomic `UPDATE … WHERE qty >= n` | No last-writer-wins; over-sell is impossible |
| Customer data egress | None — stays inside Nigeria | NDPA 2023 compliance |
