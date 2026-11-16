# 37. Replication and High Availability

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 34](../part-5-internals-and-performance/34-backup-and-recovery.md)

> **In one line:** Replication keeps copies of the data on other servers, for surviving failures and spreading reads, and everything else follows from when a commit waits for those copies.

## What you will learn

- High availability vs disaster recovery, and RPO and RTO
- Synchronous vs asynchronous replication
- Oracle Data Guard, RAC and GoldenGate
- Replication lag, and reading your own writes
- Failover, split brain and quorums
- Backup strategy, and recovering from mistakes

## Availability and recovery

**High availability** survives a server failure. **Disaster recovery** survives the loss of a whole site.

**RPO** is how much data you can lose. **RTO** is how long recovery may take. They are independent.

**Can you have RPO zero and an RTO of ten minutes?** Yes. Synchronous replication gives RPO zero, and you can still be down for minutes while failover runs.

**Why replicate?** Availability, read scaling, and lower latency for distant users. It does **not** give more write capacity, or protection from bad changes.

## How a replica stays current

The primary ships its log, and the replica replays it.

| Topology | Writes accepted by | Conflicts |
|---|---|---|
| **Single-leader** | One node | None |
| **Multi-leader** | Several nodes | Possible |
| **Leaderless** | Any node, by quorum | Possible |

### What COMMIT waits for

| Mode | Commit waits for | Data loss on failover |
|---|---|---|
| **Asynchronous** | The local log only | Some |
| **Semi-synchronous** | One replica has received it | Little |
| **Synchronous** | A replica has it durably | None |

**What happens to writes if the sync standby dies?** They wait, or the system falls back to asynchronous, depending on the engine.

**The PostgreSQL trap.** If the required standbys are gone, commits wait indefinitely. There is no automatic fallback. So configure more than one candidate, with `ANY 1 (s1, s2)`.

**PostgreSQL `synchronous_commit` levels:** `off`, `local`, `remote_write`, `on`, and `remote_apply`.

### Physical vs logical

| | Physical | Logical |
|---|---|---|
| Copies | Blocks or WAL | Row changes |
| Replica | Byte-identical | Can differ |
| Versions | Same major version | Can differ |
| Use | HA | Upgrades, selective tables |

Logical replication carries no DDL, and tables need a replica identity for `UPDATE` and `DELETE`.

## Oracle's availability stack

**RAC, Data Guard, GoldenGate: what does each protect against?**

| Tool | Protects against |
|---|---|
| **RAC** | Instance or server failure. One shared database, so no disaster protection |
| **Data Guard** | Site failure and corruption. A standby database |
| **GoldenGate** | Logical replication, for migrations and active-active |
| **RMAN** | Everything else, through backups |
| **Flashback** | Human error |

**Explain the Data Guard protection modes. Which one stops the primary?**

| Mode | Commit waits | If the standby is unreachable |
|---|---|---|
| **Maximum Performance** (default) | The local log | Carries on |
| **Maximum Availability** | The standby, usually | Falls back, and carries on |
| **Maximum Protection** | The standby, always | **The primary shuts down** |

## Replication lag

Causes are write bursts, large transactions, slow replay, and long queries on the replica.

**An async replica is 30 seconds behind, and a user just changed their email. What do they see on the next page load?** The old email, if that read goes to the replica.

**How would you guarantee read-your-writes with read replicas?**

- Route that user to the primary for a short window after a write.
- Read critical data from the primary.
- Track the log position of the write, and wait for the replica to reach it.

**Monotonic reads.** A user should not see data go backward when two reads hit different replicas. The fix is to pin each user to one replica.

**PostgreSQL hot standby limits:** no writes, no temp tables, and no `SELECT FOR UPDATE`. Replay can conflict with long queries, and cancel them.

### Replication slots

**What happens when a follower falls behind the retained log?** Without a slot, it can no longer catch up, and must be rebuilt.

**How can a replication slot take down a primary?** A slot makes the primary keep WAL until the consumer has it. A forgotten slot keeps WAL until the disk fills, and the primary stops. Set `max_slot_wal_keep_size`, and monitor slots.

## Failover

Failover has five steps:

1. Detect the failure.
2. Decide who takes over.
3. Promote.
4. Reroute clients.
5. Fence the old leader.

**Majority voting.** With 2f + 1 nodes, you survive f failures. Three nodes survive 1, and five survive 2. Four survive no more than three, which is why clusters have odd sizes.

**What is split brain, and how do you prevent it?** Two nodes both believe they are the leader, and both accept writes, usually after a network partition. Prevent it with a majority vote, and **fencing**: cut off the old leader's storage or access. Tools such as Patroni use a consensus store.

**What happens when the old leader comes back?** It must not resume as leader. It discards its unreplicated writes, and rejoins as a follower. `pg_rewind` helps on PostgreSQL.

**Failover risks.** A short timeout causes false failovers, and a long one extends the outage. Promoting a lagging replica under asynchronous replication loses data.

**Automatic failover, or a human in the loop?** Automatic shortens RTO but can misfire. A human is slower, but has context. A common answer: automatic within a region, and human for cross-region.

## Multi-leader and leaderless

**Multi-leader conflicts.** Two regions update one row at once. Last-write-wins silently loses one update. Alternatives are conflict-free data types, or application-level merging.

**Leaderless quorums.** N copies, W must confirm a write, and R are read. **W + R > N** means the read and write sets overlap, so a read sees the latest write.

```text
N = 3, W = 2, R = 2:  2 + 2 > 3, so reads overlap writes
```

**Repair:** read repair, anti-entropy and hinted handoff.

**Multi-region.** A common pattern is a same-region synchronous standby, plus a cross-region asynchronous replica.

## Backup strategy

**Is a replica a backup?** No. It replays mistakes too.

**Whiteboard a backup strategy. What do you ask first?** RPO, RTO, data size, change rate, retention and compliance. Then choose full plus incremental backups, continuous log archiving, off-site copies, and scheduled restore tests.

**If the business wants an RPO of 5 minutes, what changes?** Nightly backups are not enough. You need continuous log shipping.

**Why can't you use `pg_dump` for point-in-time recovery?** An export captures one moment. PITR needs a physical base backup plus WAL.

**In RMAN, what is the difference between differential and cumulative incremental, and between `RESTORE` and `RECOVER`?**

- Level 0 is the base.
- Level 1 **differential** copies changes since the last level 0 or 1.
- Level 1 **cumulative** copies changes since the last level 0.
- `RESTORE` copies files back from a backup. `RECOVER` applies redo to bring them forward.

**A production table was dropped. One DBA wants last night's backup, and another wants the recycle bin.** Use `FLASHBACK TABLE ... TO BEFORE DROP`, if the table is still in the recycle bin. It is instant, and it loses nothing. Restoring last night's backup loses today's changes.

**`DELETE` with no `WHERE` an hour ago, and all replicas have it too.** Stop the damage, and measure it. Then use Flashback Query on Oracle, if undo holds it, or PITR to a separate server, and copy the rows back. A **delayed replica** can also save you.

**An employee updated every row in a lookup table.** The same approach: Flashback Query, or PITR to a side server.

**GitLab, 2017.** An engineer deleted the primary's data. Backups had silently failed for a long time. The lesson: a backup is unproven until restored.

## Changing schemas with no downtime

**Can you add a new column to a table that holds gigabytes of data?** Yes. On PostgreSQL 11 and later, a constant default needs no rewrite. On Oracle 11g and later, a `NOT NULL` column with a default is metadata only. MySQL has `INSTANT` DDL from 8.0.

When a long backfill cannot be avoided, run it in small committed batches, while watching replication lag.

**How do you version and deploy PL/SQL changes safely?** Keep source in version control, and deploy with repeatable scripts. **Edition-based redefinition** (11.2) lets old and new versions run side by side ([Chapter 53](../part-7-plsql/53-plsql-performance-and-best-practices.md)).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Treat a replica as a backup | It copies mistakes | Keep real backups |
| Read your own write from a replica | Stale data | Route to the primary |
| Use one synchronous standby | Commits hang if it dies | Use `ANY 1 (s1, s2)` |
| Forget a replication slot | WAL fills the disk | Monitor, and cap it |
| Run an even number of nodes | No extra failure tolerance | Use odd numbers |
| Failover with no fencing | Split brain | Fence the old leader |
| Trust untested backups | They may not restore | Restore on a schedule |

## Interview questions

**Q1. What is the difference between synchronous and asynchronous replication? What happens to writes if the sync standby dies?**

Asynchronous commits after the local log, so failover can lose recent data. Synchronous waits for a standby, so it loses none, but adds latency. If the standby dies, writes wait, or fall back to asynchronous, depending on the engine. PostgreSQL waits.

**Q2. Explain the Oracle Data Guard protection modes. Which one stops the primary?**

Maximum Performance commits locally. Maximum Availability waits for the standby, but falls back if it is unreachable. Maximum Protection waits always, and shuts the primary down if no standby can acknowledge.

**Q3. What is split brain, and how do you prevent it?**

Two nodes both act as leader, and accept writes. I prevent it with majority quorum and fencing.

**Q4. What happens when the old leader comes back?**

It must rejoin as a follower, and discard any writes that never replicated. Those writes are lost, unless they are reconciled by hand.

**Q5. How do RPO and RTO shape failover? Can you have RPO zero and an RTO of ten minutes?**

RPO decides synchronous or not, and RTO decides automatic or manual. Yes: synchronous replication gives RPO zero, and a slow manual failover can still take ten minutes.

**Q6. Is a replica a backup?**

No. A replica copies a bad `DELETE` within moments. Backups and PITR recover from mistakes.

**Q7. How would you guarantee read-your-writes with read replicas?**

Read from the primary for a short time after a write, or wait until the replica passes the write's log position.

## Practice

**1. N = 5, W = 3. What is the smallest R that guarantees a read sees the latest write?**

<details>
<summary>Show solution</summary>

W + R > N, so R must be at least 3.

</details>

**2. You run 4 nodes in a majority-vote cluster. How many failures can you survive?**

<details>
<summary>Show solution</summary>

One, the same as with 3 nodes. A majority of 4 is 3.

</details>

**3. Your business wants no data loss and two-second failover, across regions. What is the catch?**

<details>
<summary>Show solution</summary>

Zero data loss needs synchronous replication, which adds the cross-region network delay to every commit. Fast automatic failover also risks false failovers. So the honest answer discusses the cost, and may keep the synchronous standby in the same region.

</details>

## Recap

- High availability survives a server, and disaster recovery survives a site.
- RPO is data loss, and RTO is downtime.
- Synchronous adds latency, and loses nothing. Asynchronous is fast, and can lose data.
- RAC protects servers, and Data Guard protects sites.
- Read-your-writes needs routing or waiting.
- Use odd cluster sizes, majority voting and fencing.
- A replica is not a backup.

**Next:** [Chapter 38: Sharding and distributed databases](38-sharding-and-distributed-databases.md)
