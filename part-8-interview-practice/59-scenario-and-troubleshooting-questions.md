# 59. Scenario and Troubleshooting Questions: When Production Goes Wrong

**Level:** Advanced | **Interview priority:** Must know | **Before this:** Chapters 30, 31, 33, 34, 35 and 37

> **In one line:** Scenario questions grade your method, not a magic fix: say what you would check, what each result would mean, and what you would do next.

## The answer loop

Use this for every scenario:

1. **Confirm** the symptom and its scope.
2. **Gather** evidence.
3. **Form** one hypothesis.
4. **Test** it.
5. **Mitigate,** then fix the root cause.
6. **Prevent** it from happening again.

## Where the evidence lives

| Need | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| What is running | `V$SESSION`, `V$SQL` | `pg_stat_activity` | `SHOW PROCESSLIST` | `sys.dm_exec_requests` |
| Who is blocking | `BLOCKING_SESSION` | `pg_blocking_pids()` | `data_locks` | `sys.dm_tran_locks` |
| The plan | `DBMS_XPLAN` | `EXPLAIN ANALYZE` | `EXPLAIN` | Actual plan |
| History | AWR, ASH | `pg_stat_statements` | Slow query log | Query Store |

**Licensing, which interviewers like to test.** AWR, ASH and nearly all `DBA_HIST_` views need the Diagnostics Pack. Your XE 11g has neither, so practice with `V$` views and Statspack.

## "This query suddenly became slow"

1. Confirm: which query, since when, always or sometimes?
2. Is it running, or waiting? Check for locks.
3. Did the plan change? Compare `plan_hash_value` over time.
4. Did statistics, data volume or skew change?
5. Was anything deployed?

**Causes, grouped:**

| Group | Examples |
|---|---|
| The plan changed | New statistics, bind peeking, a new index, a version upgrade |
| The data changed | Growth, skew, a value crossing a threshold |
| Something blocks it | Locks, or a long transaction |
| The system is busy | CPU, I/O, connection queueing |

**"Nothing was deployed" does not mean nothing changed:** a nightly statistics job, or data crossing a threshold, can flip a plan.

**Mitigation vs root cause.** In an incident, capture the plan and evidence in a minute, then mitigate: pin the good plan with a baseline, or kill the runaway query. Find the root cause afterward.

## "The plan looks fast, but it runs for hours"

**Part one: the plan may not be what ran.** `EXPLAIN PLAN` is a prediction. Use `DISPLAY_CURSOR` for the real one.

**Part two: the statement may be fast, and the code slow.** A 2 ms query run a million times takes 33 minutes. Trace it, and look at `executions`.

## "Fast in development, slow in production"

Data volume, statistics, literals vs binds, settings, and concurrency all differ. Compare the plans.

**Fast in SSMS, slow from the application.** SSMS sets `ARITHABORT ON` by default, and many drivers do not, so they use different cached plans. Parameter sniffing is the usual root cause.

## "The whole application is slow"

First define slow, and prove the database is the cause. Then look at system-wide waits.

**Reading an AWR report, in order:** the snapshot window, DB time against elapsed time, Load Profile, Top Timed Events, then Top SQL.

**On PostgreSQL:** group `pg_stat_activity` by state and wait event, and rank `pg_stat_statements` by total time.

**Tune by total load,** not the slowest single run.

## Blocking and deadlocks

**Sessions are hanging.** Find the head of the chain, with `V$SESSION.BLOCKING_SESSION` or `pg_blocking_pids()`. See what it is doing. Is it idle in a transaction? Kill it only with the owner's agreement, and fix the code that left it open.

**Deadlocks started after a release.** First ask what changed. Get both transactions from the trace or the log. Then find the code path that changed its lock order, the new batch job, or the new unindexed foreign key.

## "Nobody can connect"

Work layer by layer: everyone or one app, network and DNS, the host, the listener, the instance, the connection limit.

| Oracle error | Meaning |
|---|---|
| `ORA-12541` | No listener |
| `ORA-12514` | The listener does not know the service |
| `ORA-12516`, `ORA-12519` | No handler available, often `processes` exhausted |
| `ORA-00020` | Maximum processes exceeded |

**On PostgreSQL:** `FATAL: sorry, too many clients already` means `max_connections` is exhausted. Find who holds connections, and use a pooler.

## PostgreSQL disk and bloat

**A table keeps growing despite autovacuum.** `VACUUM` cannot remove rows that an old snapshot might need. Check for long transactions, idle-in-transaction sessions, and replication slots.

**`VACUUM` has run for hours.** Read `pg_stat_progress_vacuum` for its phase. Then check cost delay settings, and index count.

**A replication slot holds back cleanup.** Confirm it in `pg_replication_slots`. Find the consumer, and fix it, or drop the slot if it is abandoned. **Prevention:** alert on slot lag, and set `max_slot_wal_keep_size`.

**`pg_wal` is filling the disk.** The usual causes are a failing `archive_command`, or a stalled slot. **Never delete WAL files by hand.** Fix the cause, and let the server clean up.

## Human mistakes

**All rows were updated by mistake.** First, was it committed? If not, `ROLLBACK`. If it was, stop the application, and measure the damage. On Oracle, use Flashback Query or Flashback Table. On PostgreSQL, use PITR to a side server, and copy the old values back.

**A production table was dropped.** On Oracle, `FLASHBACK TABLE ... TO BEFORE DROP`. Otherwise, PITR to a side server. Replicas have the drop too, unless one is delayed.

**The disk is full.** Free space safely, by archiving or moving logs and old backups. Do not delete data files. Find what grew, and alert earlier next time.

**Replication lag is growing.** Check for a long query on the replica, a large transaction on the primary, and replica I/O. Reduce write bursts, and batch big changes.

## Close with prevention

End every answer with monitoring and alerts, tested restores, a delayed replica, separate accounts, and a runbook.

## Practice

Answer each one out loud in 3 minutes, using the loop.

1. Checkout latency doubled at noon. No deploy happened.
2. A report that ran in 5 minutes now takes 2 hours after a data load.
3. An `ALTER TABLE` is stuck, and every query is now waiting.
4. A developer ran `DELETE FROM orders` in production.
5. `FATAL: sorry, too many clients already` appears after an autoscaling event.

<details>
<summary>Show solution notes</summary>

1. Check waits and locks, then a plan change from a statistics job, then load. Compare top SQL with yesterday.
2. Stale statistics after the load. Gather them, and add that step to the job.
3. The lock queue. Find the long transaction ahead of the `ALTER`, cancel the `ALTER` to release the queue, and retry with `lock_timeout`.
4. Was it committed? Then flashback or PITR to a side server. Then restrict production access.
5. Connection multiplication. Add a pooler, and shrink per-instance pools.

</details>

## Recap

- Confirm, gather, hypothesize, test, mitigate, prevent.
- Check locks and plan changes first for a sudden slowdown.
- Tune by total load.
- Never delete WAL or data files by hand.
- Close with prevention.

**Next:** [Chapter 60: Mock interviews](60-mock-interviews.md)
