# 33. Locks, Deadlocks and MVCC

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 32](32-transactions-and-isolation.md)

> **In one line:** Locks make transactions wait their turn, and MVCC keeps old versions of rows so that readers and writers rarely have to wait for each other.

**About the demos:** the session demos in this chapter run on PostgreSQL. On Oracle, a transaction starts by itself, so leave out `BEGIN`.

## What you will learn

- Shared and exclusive locks, and two-phase locking
- What a deadlock is, how engines resolve it, and how to prevent it
- Intention locks, lock escalation and phantoms
- `NOWAIT`, `SKIP LOCKED`, and how to build a job queue on a table
- How MVCC works on PostgreSQL, Oracle and InnoDB, and what it costs
- `VACUUM`, transaction ID wraparound and `ORA-01555`

[Chapter 32](32-transactions-and-isolation.md) showed what goes wrong. This chapter shows how engines prevent it. There are three families: locks, timestamps or validation, and multiple versions.

## Locks

A **lock** is a claim on a data item, held by a transaction and tracked by the lock manager. **Shared (S)** locks allow reading, and **exclusive (X)** locks allow writing.

| | S held | X held |
|---|---|---|
| S requested | Granted | Waits |
| X requested | Waits | Waits |

**Blocking is normal.** A session waits until the lock holder finishes.

```sql postgres session=A
BEGIN;
UPDATE products SET stock_qty = 24 WHERE product_id = 1;
```

```sql postgres session=B blocks
UPDATE products SET stock_qty = 23 WHERE product_id = 1;
```

```sql postgres session=A
COMMIT;
```

```sql postgres session=B
SELECT stock_qty FROM products WHERE product_id = 1;
```

```text output
 stock_qty
-----------
        23
(1 row)
```

Session B waited, and then its update ran.

## Two-phase locking (2PL)

**2PL** has a **growing** phase that only acquires locks, then a **shrinking** phase that only releases them. The **lock point** is the moment of the last acquire.

**What it gives:** conflict serializability, in lock-point order.

**What it does not give:** freedom from deadlocks, or from cascading aborts.

| Variant | Rule |
|---|---|
| Strict 2PL | Hold X locks until commit |
| Rigorous 2PL | Hold all locks until commit. Most systems do this |
| Conservative 2PL | Take all locks at the start. Deadlock free |

**Naming trap:** Berkeley's "Strict 2PL" and CMU's "Strong Strict 2PL" mean rigorous.

**Lock conversion.** Two S holders both upgrading to X is the classic deadlock.

## Deadlocks

| | Ends by itself? |
|---|---|
| **Blocking** | Yes, when the holder finishes |
| **Deadlock** | No. It is a cycle |
| **Livelock** | Transactions keep retrying with no progress |

Here is a real deadlock, from updating two rows in opposite order.

```sql postgres session=A
BEGIN;
UPDATE products SET stock_qty = stock_qty WHERE product_id = 1;
```

```sql postgres session=B
BEGIN;
UPDATE products SET stock_qty = stock_qty WHERE product_id = 2;
```

```sql postgres session=A blocks
UPDATE products SET stock_qty = stock_qty WHERE product_id = 2;
```

```sql postgres session=B error=deadlock
UPDATE products SET stock_qty = stock_qty WHERE product_id = 1;
```

```text output nocheck
ERROR:  deadlock detected
DETAIL:  Process 25388 waits for ShareLock on transaction 1779; blocked by process 23844.
Process 23844 waits for ShareLock on transaction 1780; blocked by process 25388.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,12) in relation "products"
```

```sql postgres session=B
ROLLBACK;
```

```sql postgres session=A
COMMIT;
```

### How engines handle it

Engines find a cycle in the **waits-for graph**, and pick a victim.

| Engine | What happens |
|---|---|
| PostgreSQL | Checks after `deadlock_timeout` (1 second), and aborts one transaction |
| Oracle | `ORA-00060` rolls back only the detecting **statement** |
| InnoDB | Prefers the smaller transaction as the victim |
| SQL Server | Chooses a victim by cost, with error 1205 |

**What happens to the rest of the transaction?** On Oracle, the transaction is still open and keeps its other locks, so the application must roll back or retry. On PostgreSQL, the victim's whole transaction is aborted, and only `ROLLBACK` is accepted.

### Preventing deadlocks in practice

- Take locks in a consistent order.
- Keep transactions short.
- Add indexes, so that fewer rows are locked.
- Retry on failure. The victim cannot be predicted, so the application must handle either side failing.

**Classic shapes:** opposite-order updates, shared-to-exclusive upgrades, unindexed foreign keys, Oracle bitmap indexes, and InnoDB gap locks on concurrent inserts.

**Why can an unindexed foreign key cause locking problems?** Deleting a parent must check the child table. Without an index, that is a scan, and Oracle takes a table-level lock on the child for the check.

### Deadlock theory

**Wait-die and wound-wait** prevent deadlocks with timestamps.

| | Older asks younger | Younger asks older | Preemptive? |
|---|---|---|---|
| **Wait-die** | Older waits | Younger dies | No |
| **Wound-wait** | Older wounds younger | Younger waits | Yes |

Restarts keep the original timestamp, to avoid starvation.

**Deadlock-free locking:** conservative 2PL, ordered locking (a global lock order), and the tree protocol.

## Locks and latches

| | Lock | Latch |
|---|---|---|
| Protects | Logical data | In-memory structures |
| Held by | A transaction | A thread, very briefly |
| Held until | Commit | A few instructions |
| Deadlock detection | Yes | No |

## Multiple granularity and intention locks

Locks can be on a database, table, page or row. **Why do intention locks exist?** So that a table lock request need not check every row. Before locking a row, a transaction puts an **intention** lock on the table.

| Lock | Means |
|---|---|
| IS | I will read some rows |
| IX | I will write some rows |
| SIX | I read the whole table and will write some rows |

| | IS | IX | S | SIX | X |
|---|---|---|---|---|---|
| **IS** | Yes | Yes | Yes | Yes | No |
| **IX** | Yes | Yes | No | No | No |
| **S** | Yes | No | Yes | No | No |
| **SIX** | Yes | No | No | No | No |
| **X** | No | No | No | No | No |

Two IX locks do not conflict, because the writers may touch different rows. Lock top-down, and release bottom-up.

**Lock escalation.** Does your database turn many row locks into a table lock?

| Engine | Escalation |
|---|---|
| SQL Server | Yes, at around 5,000 locks per statement on a table reference |
| Oracle | Never |
| InnoDB | No |
| PostgreSQL | No row lock cap, because row locks are on disk |

The consequence on SQL Server: an escalated lock blocks everyone on the table.

## Phantoms and locks

**Why don't row locks prevent phantoms?** A new row does not exist yet, so it cannot be locked. The fixes are predicate locks, index locks, InnoDB next-key locks, and SQL Server key-range locks.

### InnoDB gap and next-key locks

- A **record lock** locks one index record.
- A **gap lock** locks the space between records.
- A **next-key lock** is both, such as the interval `(10, 11]`.

**Why can an INSERT block when no row with that value exists?** Because the gap is locked. `READ COMMITTED` turns gap locks off, apart from foreign key and duplicate checks.

**InnoDB locks index records, not rows.** An `UPDATE` with no usable index locks every row scanned at `REPEATABLE READ`. A unique-key equality search takes one record lock.

## Other concurrency protocols

**Timestamp ordering.** Each item has R-TS and W-TS, and an operation that arrives too late aborts. Nobody waits, so there is no deadlock, but starvation and unrecoverable schedules are possible. The **Thomas write rule** ignores an obsolete write instead of aborting.

**Optimistic concurrency control (OCC).** Read, validate, then write, using private workspaces. It is ideal when conflicts are rare, and wasteful otherwise.

| Protocol | Conflict serializable | Deadlock free |
|---|---|---|
| Basic 2PL | Yes | No |
| Conservative 2PL | Yes | Yes |
| Ordered locking | Yes | Yes |
| Tree protocol | Yes | Yes |
| Timestamp ordering | Yes | Yes |

**Optimistic or pessimistic in applications?** Pick pessimistic for short, high-contention updates. Pick optimistic, with a version column, for long user think time or rare conflicts.

## Locking options

| Clause | Effect |
|---|---|
| `FOR UPDATE` | Wait for the lock |
| `FOR UPDATE NOWAIT` | Fail at once (`ORA-00054` on Oracle) |
| `FOR UPDATE WAIT 5` | Wait up to 5 seconds, on Oracle |
| `FOR UPDATE SKIP LOCKED` | Skip locked rows |

`SKIP LOCKED` gives an inconsistent view by design, so it suits queues, not reports.

### A job queue on a table

```sql postgres
CREATE TABLE jobs (job_id INTEGER PRIMARY KEY, status VARCHAR(10) NOT NULL);
INSERT INTO jobs VALUES (1, 'READY');
INSERT INTO jobs VALUES (2, 'READY');
```

Worker A claims the oldest job, and keeps its transaction open while it works.

```sql postgres session=A
BEGIN;
SELECT job_id FROM jobs
WHERE status = 'READY'
ORDER BY job_id
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

```text output
BEGIN
 job_id
--------
      1
(1 row)
```

Worker B runs the same query. It does not wait, and gets the next job.

```sql postgres session=B
BEGIN;
SELECT job_id FROM jobs
WHERE status = 'READY'
ORDER BY job_id
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

```text output
BEGIN
 job_id
--------
      2
(1 row)
```

```sql postgres session=A
UPDATE jobs SET status = 'DONE' WHERE job_id = 1;
COMMIT;
```

```sql postgres session=B
UPDATE jobs SET status = 'DONE' WHERE job_id = 2;
COMMIT;
DROP TABLE jobs;
```

On Oracle, `FETCH FIRST` cannot be combined with `FOR UPDATE`, so open a `FOR UPDATE SKIP LOCKED` cursor, and fetch one row.

## PostgreSQL table lock modes

| Operation | Lock |
|---|---|
| `SELECT` | `ACCESS SHARE` |
| `INSERT`, `UPDATE`, `DELETE` | `ROW EXCLUSIVE` |
| `CREATE INDEX` | `SHARE` |
| Plain `VACUUM` | `SHARE UPDATE EXCLUSIVE` |
| `VACUUM FULL`, `TRUNCATE`, many `ALTER`s | `ACCESS EXCLUSIVE` |

Only `ACCESS EXCLUSIVE` blocks plain `SELECT`.

### The lock queue outage

**Why can a fast ALTER TABLE take down production?** It waits behind one long query, and every new query then queues behind **it**.

```sql postgres session=A
BEGIN;
SELECT COUNT(*) AS row_count FROM categories;
```

```sql postgres session=B blocks
ALTER TABLE categories ADD COLUMN note VARCHAR(10);
```

```sql postgres session=C blocks
SELECT COUNT(*) AS row_count FROM categories;
```

Session C only wants to read, and session A holds only a read lock, but C is stuck behind B's waiting `ACCESS EXCLUSIVE` request.

```sql postgres session=A
COMMIT;
```

```sql postgres session=B
ALTER TABLE categories DROP COLUMN note;
```

**The fix:** set `lock_timeout` so that the `ALTER` gives up quickly, and retry it.

**Changing a large table safely on PostgreSQL:** a constant-default `ADD COLUMN` needs no rewrite from version 11, but a volatile default does. Add constraints as `NOT VALID`, then `VALIDATE`. Run backfills in batches.

### Row lock strength on PostgreSQL

`FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE` and `FOR KEY SHARE`. Foreign key checks use `FOR KEY SHARE`, so `FOR UPDATE` blocks child inserts, and `FOR NO KEY UPDATE` does not.

### Oracle TX and TM locks

Oracle keeps row locks in the data block's **ITL** (interested transaction list), not in a lock manager, which is why it never escalates. DML also takes a **TM** lock on the table. `enq: TX - row lock contention` is the wait event for row locks.

## Finding the blocker

| Engine | Tool |
|---|---|
| PostgreSQL | `pg_blocking_pids()`, with `pg_stat_activity` and `pg_locks` |
| Oracle | `V$SESSION.BLOCKING_SESSION` |
| MySQL | `performance_schema.data_locks`, `SHOW ENGINE INNODB STATUS` |
| SQL Server | `sys.dm_exec_requests`, `sys.dm_tran_locks` |

**Idle in transaction:** a session that opens a transaction and then waits keeps its locks all that time. Use `idle_in_transaction_session_timeout`, and keep remote calls outside the transaction.

## MVCC

**MVCC** (multi-version concurrency control): a write creates a new version, and a reader chooses the version visible to its snapshot. So **readers and writers do not block each other**, but writers still block writers.

"Readers do not block writers" is incomplete: `SELECT FOR UPDATE`, DDL and writer-versus-writer conflicts still block.

### On PostgreSQL

Each row version has hidden columns. `xmin` is the transaction that created it, `xmax` is the one that deleted it, and `ctid` is its physical location.

```sql postgres
CREATE TABLE mvcc_demo (id INTEGER, val INTEGER);
INSERT INTO mvcc_demo VALUES (1, 10);
SELECT ctid, id, val FROM mvcc_demo;

UPDATE mvcc_demo SET val = 11 WHERE id = 1;
SELECT ctid, id, val FROM mvcc_demo;

DROP TABLE mvcc_demo;
```

```text output
CREATE TABLE
INSERT 0 1
 ctid  | id | val
-------+----+-----
 (0,1) |  1 |  10
(1 row)

UPDATE 1
 ctid  | id | val
-------+----+-----
 (0,2) |  1 |  11
(1 row)

DROP TABLE
```

The row moved from `(0,1)` to `(0,2)`. An `UPDATE` leaves the old tuple behind and writes a new one. That old tuple is a **dead tuple** once no transaction needs it.

### Where old versions live

| Engine | Old versions | The bill |
|---|---|---|
| PostgreSQL | In the table itself | Bloat, and `VACUUM` |
| Oracle | In undo | `ORA-01555` |
| InnoDB | In undo, through a roll pointer | Undo growth, and purge lag |
| SQL Server | In `tempdb`, or the ADR version store | `tempdb` growth |

One long transaction hurts all four.

### Oracle read consistency

Undo holds the old data, and a query rebuilds a block as of its snapshot. So a long query sees one point in time, while others update the same rows.

**What causes `ORA-01555: snapshot too old`?** The undo needed for a consistent read was overwritten. Causes include long queries, fetching across commits, small undo, and delayed block cleanout. Raising `UNDO_RETENTION` is not always the fix: shorten the query, stop committing inside the fetch loop, or size undo properly. `UNDO_RETENTION` is best effort. `RETENTION GUARANTEE` swaps `ORA-01555` for DML failures.

### VACUUM

`VACUUM` has four jobs:

1. Reclaim dead tuples.
2. Keep planner statistics current (autovacuum also runs `ANALYZE`).
3. Maintain the visibility map.
4. Prevent transaction ID wraparound, by freezing old rows.

| | Plain `VACUUM` | `VACUUM FULL` |
|---|---|---|
| Space | Marked reusable | Returned to the OS |
| Runs alongside DML | Yes | No, `ACCESS EXCLUSIVE` |
| Extra disk | No | About the table's size |

**Autovacuum starts** when dead tuples pass 50 plus 20 percent of the table's rows. On big tables that is a lot, so set per-table thresholds.

**Autovacuum is running but the table keeps growing. What do you check?** What stops `VACUUM` removing dead rows is the **xmin horizon**, the oldest snapshot anything might still need. Look for long transactions, idle-in-transaction sessions, stale replication slots, `hot_standby_feedback`, and forgotten prepared transactions. Then check `n_dead_tup` and `last_autovacuum` in `pg_stat_user_tables`.

**Transaction ID wraparound.** Transaction IDs are 32-bit, so they run out. Freezing marks old rows as safe forever. `autovacuum_freeze_max_age` is 200 million. If freezing cannot keep up, the database starts warning, and finally refuses new transaction IDs. Prevent it by keeping autovacuum healthy, and by ending long transactions.

**HOT updates.** When no indexed column changes, and the new version fits on the same page, PostgreSQL makes no index writes. A lower `fillfactor` leaves room. `n_tup_hot_upd` measures it. Update-heavy tables bloat when updates are not HOT.

**Removing bloat:** `pgstattuple` measures it. `pg_repack` removes it without a long lock, unlike `VACUUM FULL`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Update tables in different orders | Deadlocks | Use one global order |
| Keep long transactions | Locks, bloat, `ORA-01555` | Keep them short |
| Leave a session idle in a transaction | It holds everything | Set timeouts |
| Run `ALTER` without `lock_timeout` | The lock queue outage | Set a timeout, and retry |
| Say MVCC means no locks | Writers still block writers | Say readers do not block writers |
| Commit inside a fetch loop on Oracle | `ORA-01555` | Commit after the loop |
| Run `VACUUM FULL` on a live table | It blocks everything | Use `pg_repack` |
| Disable autovacuum | Bloat, and then wraparound | Tune it instead |

## Interview questions

**Q1. Does two-phase locking prevent deadlocks? Does it prevent cascading aborts?**

No to both. 2PL guarantees conflict serializability. Deadlocks can still happen, and basic 2PL allows reading uncommitted data, so cascading aborts are possible. Strict 2PL stops those, and conservative 2PL stops deadlocks.

**Q2. What is the difference between strict and rigorous two-phase locking?**

Strict holds exclusive locks until commit. Rigorous holds all locks until commit. Most systems are rigorous.

**Q3. What is a deadlock? How does your database detect and resolve it, and how do you prevent it?**

A deadlock is a cycle of transactions waiting on each other. The engine finds a cycle in the waits-for graph, and aborts a victim. I prevent it with a consistent lock order, short transactions and good indexes, and I add retry logic.

**Q4. Explain wait-die and wound-wait. Which one is preemptive?**

Both use timestamps. In wait-die, an older transaction waits, and a younger one dies. In wound-wait, an older transaction wounds the younger, and a younger one waits. Wound-wait is preemptive.

**Q5. What is the difference between a lock and a latch?**

A lock protects logical data, is held by a transaction until commit, and has deadlock detection. A latch protects an in-memory structure for a very short time, and is not transactional.

**Q6. What are intention locks and why are they needed?**

They mark at table level that a transaction holds row locks. Without them, a table lock request would have to check every row.

**Q7. What is the difference between NOWAIT and SKIP LOCKED? How would you build a job queue on a SQL table?**

`NOWAIT` fails at once if a row is locked. `SKIP LOCKED` ignores locked rows. For a queue, each worker selects the next ready row with `FOR UPDATE SKIP LOCKED`, so workers do not block each other. It keeps its transaction short, and handles failed jobs.

**Q8. Why can a fast ALTER TABLE take down production?**

It needs a strong lock, and it waits behind a long query. Every new query then queues behind the `ALTER`. A `lock_timeout` with retries prevents this.

**Q9. What are gap locks and next-key locks in InnoDB?**

A gap lock locks the space between index records, and a next-key lock is a record lock plus the gap before it. They stop phantoms, which is why an `INSERT` can block even when no row with that value exists.

**Q10. How does MVCC let readers and writers avoid blocking each other, and what does it cost?**

A write creates a new version, and readers use the version matching their snapshot. The cost is storing and cleaning old versions: bloat and `VACUUM` on PostgreSQL, undo and `ORA-01555` on Oracle.

**Q11. How does MVCC work in PostgreSQL? What are xmin and xmax for?**

Each row version stores `xmin`, the transaction that created it, and `xmax`, the one that deleted it. A snapshot decides visibility from those. An `UPDATE` writes a new version, and leaves the old one as a dead tuple for `VACUUM`.

**Q12. How does MVCC differ between PostgreSQL, Oracle and InnoDB?**

PostgreSQL keeps old versions in the table, so it needs `VACUUM`. Oracle and InnoDB keep the latest version in the table, and old data in undo, so long readers can hit `ORA-01555`, or undo grows.

**Q13. Why does PostgreSQL need VACUUM, and how is VACUUM FULL different?**

It reclaims dead tuples, updates statistics and the visibility map, and freezes old rows to prevent wraparound. Plain `VACUUM` runs alongside DML, and only marks space reusable. `VACUUM FULL` rewrites the table, returns space to the OS, and takes an exclusive lock.

**Q14. What is transaction ID wraparound?**

Transaction IDs are 32-bit, so they eventually wrap around. Freezing marks old rows as visible to everyone. If freezing falls behind, PostgreSQL warns, and finally refuses new transactions. Healthy autovacuum prevents it.

**Q15. What causes ORA-01555, and how do you fix it without just raising UNDO_RETENTION?**

A query needs undo that has been overwritten. I would shorten the query, stop committing inside fetch loops, and size undo for the workload.

## Practice

**1. Transaction T1 updates account A then B. T2 updates B then A. What can happen, and what is the simplest fix?**

<details>
<summary>Show solution</summary>

A deadlock. The simplest fix is for both to lock accounts in the same order, such as by ascending id.

</details>

**2. Which waits: a `SELECT` on a row being updated in another session, on PostgreSQL?**

<details>
<summary>Show solution</summary>

Nothing waits. Under MVCC, the `SELECT` reads the last committed version. Only `SELECT ... FOR UPDATE` would wait.

</details>

**3. Wait-die: T5 (older, timestamp 5) requests a lock held by T10. What happens? What if T10 requests a lock held by T5?**

<details>
<summary>Show solution</summary>

T5 is older, so it waits. T10 is younger, so when it requests T5's lock, it dies and restarts with its original timestamp.

</details>

**4. A table has 1 million rows, and autovacuum uses the default settings. Roughly how many dead tuples trigger it?**

<details>
<summary>Show solution</summary>

`50 + 0.2 x 1,000,000 = 200,050`. On a table of 100 million rows that would be 20 million dead tuples, which is why big tables need per-table settings.

</details>

## Recap

- S locks share, and X locks are exclusive. Blocking is normal, and a deadlock is a cycle.
- 2PL gives serializability, not deadlock freedom.
- Prevent deadlocks with one lock order, short transactions and retries.
- Intention locks let a table lock skip checking every row.
- `SKIP LOCKED` builds job queues.
- A queued `ALTER` blocks everything behind it. Use `lock_timeout`.
- MVCC keeps versions, so readers and writers rarely block each other.
- PostgreSQL pays with `VACUUM`, Oracle with undo and `ORA-01555`.

**Next:** [Chapter 34: Backup and recovery](34-backup-and-recovery.md)
