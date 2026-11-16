# 58. Design and Architecture Questions: Schemas, Trade-offs and Where to Do What

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 4 and 6

> **In one line:** A design round is a defense, not a drawing: you state the rules first, voice the trade-offs, and say what would change your mind.

## How these rounds are graded

You state the rules or the grain first, voice trade-offs, and adapt when challenged.

**The answer shape:** restate, ask about scale, name the key queries and invariants, draft tables and keys, enforce the invariants, add indexes, and say what breaks at 10x.

**What to put on the board:** tables, columns, types, primary keys and foreign keys.

## One-minute decision answers

Say the pick first, then the reason, then what would change your mind.

**Application code or stored procedures?** I keep data rules in the database, and orchestration in the application. Procedures give one enforcement point for every client. Application code is easier to test, deploy and scale. I would move logic into the database if many applications must share it.

**How do you enforce uniqueness?** With a unique constraint. A check-then-insert in application code races. Rails' own guide says so about its uniqueness validation.

**Constraint or trigger?** Declarative first. A trigger only where a constraint cannot express the rule.

**Why is a trigger not a dependable safety net?** Whether it fires depends on the path. SQL*Loader direct path, for example, can skip it, and a disabled trigger does nothing.

**Can a trigger enforce no overlapping bookings?** Not by itself at `READ COMMITTED`, because neither transaction sees the other's uncommitted row. What works is an exclusion constraint on PostgreSQL, one row per night with a unique key, or locking the room row.

**Why not send email from a trigger?** The trigger runs inside the transaction, so a rollback cannot unsend it. Use an outbox.

**View, materialized view, summary table or cache?** Decide by how fresh the data must be, how expensive it is, and who maintains it.

| Tool | Solves |
|---|---|
| Index | Finding few rows |
| Partition | Retention, and pruning scans |
| Materialized view | Expensive aggregates |
| Cache | Repeated identical reads |
| Read replica | Read volume, and isolation |
| Shard | Write volume and size |

**A slow dashboard.** Measure first, and read the plan. Fix the query and statistics. Then add an index, a materialized view, or a cache, and move it to a replica if it competes with OLTP.

**Foreign keys in a sharded 100 TB system.** Keep them inside a shard when parent and child share the shard key. Across shards, drop them, and use reconciliation jobs.

**Cost reasoning.** Estimate queries per second and storage. An instance, its replicas, backups and egress all cost money, and each replica adds to the bill. Say which trade-off you are buying.

## Rehearsal prompts

For each one, take 15 minutes with a blank page: requirements, queries, invariants, tables, indexes, and what breaks.

| Prompt | Twist | Direction |
|---|---|---|
| E-commerce orders ([Ch 27](../part-4-database-design/27-design-case-studies.md)) | A flash sale: 100,000 people want 500 units | Hot row: a conditional update, then a queue or a counter service |
| Movie ticketing | A seat hold expires during payment | A status plus `expires_at`, checked at capture |
| Hotel booking | Rooms sold by type, with 5 percent overbooking | Inventory per type and night, with a cap of 105 percent |
| Bank ledger | A transfer between two currencies | Two entries per currency, with a rate on the transaction |
| Ride sharing | A rider disputes a fare a month later | Keep the fare and surge used, as history |
| Chat | Unread counts in a group of 100,000 | Store a last-read position per member |
| Social feed | A post is deleted after fan-out to a million timelines | Filter on read, and clean up lazily |
| Multi-tenant SaaS | One tenant wants a restore to yesterday | Easy with a database per tenant, hard with shared tables |
| Fitness app | A wearable sends a sample every second | A time-series store, with rollups |

## Worked prompts

### URL shortener

```text
links (short_code PK, long_url, owner_id, created_at, expires_at)
```

**Key query:** look up one code, millions of times a second.

**Decisions:** Generate codes from a counter encoded in base 62, or from a random value with a unique constraint. Reads dwarf writes, so put a cache in front. A key-value store fits. Count clicks asynchronously, not in the read path.

**At 10x:** cache hit rate first, then shard on `short_code`.

### Library

```text
titles       (title_id PK, name, isbn UNIQUE)
copies       (copy_id PK, title_id FK)
members      (member_id PK, name)
loans        (loan_id PK, copy_id FK, member_id FK, due_on, returned_at)
reservations (reservation_id PK, title_id FK, member_id FK, created_at)
```

**Invariant:** a copy is on one loan at a time, with a partial unique index on `copy_id` where `returned_at IS NULL`. A title and a physical copy are different entities.

### Hospital

```text
patients      (patient_id PK, name, dob)
doctors       (doctor_id PK, name, dept_id FK)
appointments  (appt_id PK, patient_id FK, doctor_id FK, starts_at)
admissions    (admission_id PK, patient_id FK, admitted_at, discharged_at)
prescriptions (rx_id PK, appt_id FK, drug_id FK, dose)
```

**Invariants:** a doctor has one patient per slot, with `UNIQUE (doctor_id, starts_at)`. Medical data needs audit trails and strict access control.

### Food delivery

**Grain and keys:** `orders`, `order_items`, `restaurants`, `menu_items`, `couriers`, `deliveries`. Copy the menu price onto the order line, as history. One active delivery per courier is a partial unique index.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Draw tables first | Queries and rules are missed | Start from them |
| Defend a choice with "best practice" | It sounds like a guess | Give the trade-off |
| Skip invariants | Race conditions in follow-ups | Name them first |
| Reach for sharding | Over-engineering | Climb the ladder |
| Ignore cost | Senior rounds score it | Estimate |

## Recap

- State rules or grain first.
- Pick, give the reason, and say what would change your mind.
- Constraints enforce. Application checks only inform.
- Each index names a query.
- Rehearse out loud, with a timer.

**Next:** [Chapter 59: Scenario questions](59-scenario-and-troubleshooting-questions.md)
