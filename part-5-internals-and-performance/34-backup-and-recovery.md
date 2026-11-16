# 34. Backup and Recovery: How Databases Survive Failures

**Level:** Advanced | **Interview priority:** Should know | **Before this:** [Chapter 33](33-locks-deadlocks-and-mvcc.md)

> **In one line:** The log makes commits durable and crashes recoverable, and backups protect against everything the log cannot.

## What you will learn

- Failure types, and write-ahead logging
- Why `COMMIT` is fast
- Steal and force
- Crash recovery, and the three phases of ARIES
- RPO and RTO, and the kinds of backup
- Point-in-time recovery, and undoing human mistakes

## What can fail?

| Failure | Example | Handled by |
|---|---|---|
| Transaction | A logical error, or a deadlock | Rollback |
| System crash | Power loss. Disk survives | Crash recovery |
| Disk failure | A lost disk | Backups, and replicas |
| Human error | `DELETE` with no `WHERE` | Backups, flashback |

**The two dangers after a crash:** a committed change that never reached the data files, and an uncommitted change that did.

## Write-ahead logging

**What is write-ahead logging, and why is it needed?** Log records reach stable storage **before** the data pages they describe. If a crash happens, the log can redo committed work, and undo the rest.

A log record holds an **LSN** (log sequence number), the transaction, the page, and the before and after values.

**When is a transaction committed?** When all its log records, including `COMMIT`, are on stable storage. Its data pages may not be on disk at that moment.

### Why is COMMIT fast?

`COMMIT` needs only a sequential log flush, not random writes to data pages. **Group commit** batches the flush for many transactions.

**On Oracle:** LGWR flushes redo, and the commit returns, while DBWn writes blocks later. "Commit writes all dirty buffers" is a myth.

**Redo vs undo in Oracle.** Redo replays changes forward. Undo reverses them, and serves read consistency. Undo blocks are themselves protected by redo.

**Why is committing inside a row-by-row loop a bad idea?** Each commit waits for a log sync, which hurts throughput. It invites `ORA-01555` when fetching across commits. And it breaks atomicity for the whole job.

### Durability knobs

| Setting | Can lose on a crash |
|---|---|
| PostgreSQL `synchronous_commit = off` | The last moments of commits, with no corruption |
| InnoDB `innodb_flush_log_at_trx_commit = 0` or `2` | About a second of commits |

### Torn pages

A crash can leave a page half written, and replaying log records cannot repair that. PostgreSQL uses `full_page_writes`, and InnoDB uses the doublewrite buffer.

## Steal and force

**What do steal and force mean?**

- **Steal:** an uncommitted page may be written to disk. This needs **undo**.
- **Force:** every changed page is written at commit. **No-force** needs **redo**.

| | No-force | Force |
|---|---|---|
| **Steal** | UNDO and REDO (standard) | UNDO only |
| **No steal** | REDO only | Neither |

Almost all systems use **steal and no-force**, because that gives the buffer pool freedom, and makes commits fast.

## Checkpoints

A **checkpoint** gives recovery a known starting point, by flushing dirty pages, and writing a record. A **fuzzy** checkpoint lets work continue while it runs.

**PostgreSQL settings:** `checkpoint_timeout` is 5 minutes, and `max_wal_size` is 1 GB. Frequent checkpoints inflate WAL, because of full-page writes.

**Reading a log, for exams.** Transactions finished before the last checkpoint are ignored. Those committed after it are **redone**. Unfinished ones are **undone**.

```text
T1 commits, then CHECKPOINT
T2 commits after the checkpoint
T3 is still running at the crash

T1: ignored     T2: redo     T3: undo
```

**The system crashes again during recovery.** Redo and undo are idempotent, so recovery simply runs again from the start.

## ARIES

**ARIES** has three principles: write-ahead logging, **repeating history** during redo, and **logging undo**.

| Phase | What it does |
|---|---|
| **Analysis** | Starts at the last checkpoint. Rebuilds the active transaction table and the dirty page table |
| **Redo** | Replays everything from the earliest change, including losers |
| **Undo** | Rolls back the losers, writing compensation log records |

**Why does redo replay updates of transactions that will be undone?** Repeating history restores the exact page state at the crash, so that undo can then work with physical logging, and with fine-grained locks.

**CLRs** (compensation log records) are redone, but never undone, so that a crash during undo does not repeat work.

**How does the database recover after a crash?**

1. Find the last checkpoint.
2. Redo from there, so the pages reflect all logged work.
3. Undo the transactions that never committed.

## Backups

**RPO and RTO.**

- **RPO** (recovery point objective): how much data you can afford to lose.
- **RTO** (recovery time objective): how long you can afford to be down.

### Kinds of backup

| Kind | What | Good | Bad |
|---|---|---|---|
| **Logical** | Rows and DDL | Portable | Slow to restore |
| **Physical** | Data files | Fast restore | Same version and platform |
| **Cold** | The database is stopped | Simple | Downtime |
| **Hot** | The database is running | No downtime | Needs logs to be consistent |

| Backup | Copies | Backup speed | Restore speed |
|---|---|---|---|
| **Full** | Everything | Slow | Fast |
| **Differential** | Changes since the last full | Medium | Medium |
| **Incremental** | Changes since the last backup | Fast | Slow, needs every piece |

### Point-in-time recovery

**How does point-in-time recovery work?** Restore a base backup, then replay archived logs up to a chosen moment. Without archived logs, you can restore only to the backup itself.

### Tools

| Engine | Logical | Physical |
|---|---|---|
| Oracle | Data Pump (`expdp`, `impdp`) | RMAN, in `ARCHIVELOG` mode |
| PostgreSQL | `pg_dump` | `pg_basebackup` plus WAL archiving |
| MySQL | `mysqldump` | Percona XtraBackup, plus binary logs |
| SQL Server | | Full, differential and log backups |

**RMAN** uses incremental levels 0 and 1, then `RESTORE` and `RECOVER`.

### NOLOGGING

**What are the risks of running `NOLOGGING` operations on production?** A direct-path load writes minimal redo, so those blocks cannot be recovered from earlier backups, and they are missing on standbys. Take a new backup straight afterward, or use `FORCE LOGGING`.

### Why pg_wal fills the disk

A failing `archive_command`, inactive replication slots, or a large `wal_keep_size`. A full `pg_wal` causes a shutdown.

## Recovering from human mistakes

**Someone ran a `DELETE` with no `WHERE` an hour ago. How do you get the data back?**

**On Oracle, Flashback Query** reads undo, and it works on 11g XE:

```sql oracle
INSERT INTO employees
SELECT * FROM employees AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '60' MINUTE)
WHERE emp_id NOT IN (SELECT emp_id FROM employees);
```

| Oracle tool | Undoes |
|---|---|
| Flashback Query | Reads old rows |
| Flashback Table | Rewinds a table |
| Flashback Drop | A dropped table |
| Flashback Database | The whole database |

**On PostgreSQL,** restore to a separate server with point-in-time recovery, just before the mistake, and copy the rows back.

**Is replication a backup?** No. A standby replays the bad `DELETE` too. Standbys give availability, and backups give recovery.

**How do you know your backups actually work?** Test restores on a schedule, and measure the real RTO. A backup you have not restored is only a hope. Keep copies off site. The **3-2-1 rule** is 3 copies, on 2 kinds of media, with 1 off site.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Say commit writes data pages | It flushes the log | Explain write-ahead logging |
| Commit per row | Slow, and `ORA-01555` | Commit per batch |
| Treat a replica as a backup | It replays mistakes | Keep real backups |
| Never test restores | The backup may not work | Restore on a schedule |
| Run `NOARCHIVELOG` in production | No point-in-time recovery | Use `ARCHIVELOG` |
| Use `NOLOGGING` without a new backup | Blocks are unrecoverable | Back up afterward |

## Interview questions

**Q1. Why is COMMIT fast even though data files are not written at commit? What is write-ahead logging?**

Log records must reach disk before the data pages they describe. `COMMIT` only flushes the log, which is a fast sequential write. Data pages are written later, and after a crash the log can rebuild them.

**Q2. What do steal and force mean? Which combination needs both undo and redo?**

Steal means uncommitted pages may reach disk, which needs undo. No-force means pages need not be written at commit, which needs redo. Steal with no-force needs both, and almost all systems use it.

**Q3. When is a transaction considered committed? Are its data pages on disk at that moment?**

When its commit record is on stable storage. Its data pages may not be on disk yet.

**Q4. What is the difference between redo and undo in Oracle?**

Redo records changes, to replay them forward after a crash. Undo holds old values, for rollback and for read consistency.

**Q5. Explain the three phases of ARIES. Why does redo replay updates of transactions that will later be undone?**

Analysis finds what was active and dirty. Redo repeats history. Undo rolls back the losers. Repeating history restores the exact state at the crash, so undo works correctly.

**Q6. What is the difference between RPO and RTO?**

RPO is how much data you can lose. RTO is how long you can be down.

**Q7. What is the difference between a logical and a physical backup?**

Logical exports rows and DDL. It is portable, but slow to restore. Physical copies data files, which is fast, but tied to the version and platform.

**Q8. What is the difference between full, differential and incremental backups?**

Full copies everything. Differential copies changes since the last full. Incremental copies changes since the last backup of any kind, so it is the fastest to take, and the slowest to restore.

**Q9. How does point-in-time recovery work?**

Restore a base backup, then replay archived logs up to the chosen moment.

**Q10. Someone ran a DELETE with no WHERE clause an hour ago. How do you get the data back?**

On Oracle, Flashback Query, if undo still holds it. Otherwise, point-in-time recovery to a separate server, and copy the rows back. I would not restore over production.

**Q11. Is replication a backup?**

No. A replica copies mistakes too. It gives availability, not recovery from a bad change.

## Practice

**1. A log shows: T1 commits. CHECKPOINT. T2 begins and commits. T3 begins. CRASH. What is redone and undone?**

<details>
<summary>Show solution</summary>

T1 is ignored, T2 is redone, and T3 is undone.

</details>

**2. A full backup runs on Sunday, with incrementals every other day. The disk dies on Thursday. What do you need?**

<details>
<summary>Show solution</summary>

Sunday's full, and every incremental from Monday through Wednesday, then the archived logs up to the failure.

</details>

**3. Your RPO is 5 minutes. Is a nightly backup enough?**

<details>
<summary>Show solution</summary>

No. You could lose up to a day. You need continuous log archiving, or replication.

</details>

## Recap

- Log before data. That is write-ahead logging.
- A transaction is committed when its log is on disk.
- Steal needs undo, and no-force needs redo.
- ARIES is analysis, redo and undo, and it repeats history.
- RPO is data loss, and RTO is downtime.
- Point-in-time recovery is a backup plus archived logs.
- A replica is not a backup. Test your restores.

**Next:** [Chapter 35: Inside a database server](../part-6-architecture-and-scale/35-database-architecture.md)
