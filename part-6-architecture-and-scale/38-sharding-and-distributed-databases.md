# 38. Sharding and Distributed Databases

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 37](37-replication-and-high-availability.md)

> **In one line:** Sharding spreads rows across servers, which adds scale and takes away easy joins, transactions and consistency, so most of this chapter is about living with that.

## What you will learn

- When to shard, and how to choose a shard key
- Consistent hashing
- CAP and PACELC, stated correctly
- Two-phase commit, and why it blocks
- The outbox pattern, sagas and idempotency
- Distributed SQL

## Scaling and when to shard

**Vertical scaling** is a bigger machine. **Horizontal scaling** is more machines. Modern single servers go a very long way, so the old "shard at 100 GB" rule is obsolete.

**Shard only when** writes or storage exceed what one instance can handle, after query fixes, indexes, replicas, caching and partitioning.

## What is sharding?

Rows of one logical table live on different servers. A **shard key** decides where each row goes.

### Choosing a shard key

**Which shard key would you choose, and what are its failure modes?** A good key has high cardinality, even load, is immutable, and matches the dominant query. Avoid monotonic keys, because all new writes then hit one shard.

| Method | How | Failure mode |
|---|---|---|
| **Range** | Key ranges | A hot tail on recent keys |
| **Hash** | Hash of the key | No efficient range queries |
| **Directory** | A lookup table | The directory is a bottleneck |
| **Geo** | By region | Uneven regions |

### Why hash(key) % N fails

Changing N remaps almost every key. Going from 4 to 5 shards moves about 80 percent of keys:

```sql postgres
-- PostgreSQL
SELECT ROUND(100.0 * COUNT(CASE WHEN MOD(k, 4) <> MOD(k, 5) THEN 1 END) / COUNT(*), 1) AS pct_moved
FROM generate_series(1, 100000) AS k;
```

```text output
 pct_moved
-----------
      80.0
(1 row)
```

**Consistent hashing** puts keys and nodes on a ring, so adding or losing a node moves only a small share of keys. **Virtual nodes** even out the load.

**Fixed logical shards** are simpler: create many more logical shards than servers, then move whole logical shards between hosts. Redis Cluster does this with 16,384 slots.

### Hot keys

**One tenant is now 40 percent of traffic, and the shard key is tenant ID. What now?** Hashing does not help, because one key lands on one shard. Give that tenant its own shard, or split by a compound key, and cache its reads.

### Global ids

**How do you generate unique ids across shards?** Per-shard sequences collide. Use separate ranges or steps per shard, UUIDv7, or Snowflake-style ids (time, worker, sequence).

### Cross-shard queries

**Scatter-gather** asks every shard, and the slowest one sets the latency. To avoid it, co-locate related data, and copy small reference tables to every shard.

| Distributed join | When |
|---|---|
| Co-located | Both tables are sharded on the join key |
| Broadcast | One table is small |
| Shuffle | Neither: very expensive |

**How do you enforce a unique email across shards?** Each shard's unique index sees only its own rows. Use a lookup table keyed by email, written first, or shard that table by email.

### Resharding

**How do you add shards later without downtime?**

1. Copy data to the new layout.
2. Dual-write, or replay the change log.
3. Backfill, comparing versions.
4. Run dark reads, to compare old and new.
5. Cut over, with a rollback plan.

**Do not do it during your busiest week.** Plan ahead, while you still have headroom.

**The permanent cost:** cross-shard restore, DDL on every shard, monitoring, rebalancing, and no foreign keys across shards.

**Build or buy?** Citus, Vitess, or distributed SQL.

## Why distribution is hard

Messages can be delayed, lost or reordered. Nodes fail independently. Clocks disagree. And you cannot tell a slow node from a dead one.

## CAP

**Explain the CAP theorem.** During a network **partition**, a system must choose **consistency** or **availability**. With no partition, it can have both.

- **C** is linearizability: it behaves like one copy.
- **A** means every non-failed node answers.
- **P** is a network split.

**Is the C in CAP the same as the C in ACID?** No. CAP's C means a read sees the latest write. ACID's C means rules are kept.

**Can a distributed system be CA?** Not in the face of partitions, which you cannot rule out. A single-node database is "CA" only because it has no network to split.

**Can a system commit during a partition without losing consistency?** Not immediately, on the side that lacks a majority. It either refuses or delays the commit (consistent), or accepts it and reconciles later (available).

**Why is it misleading to label a database CP or AP?** Behavior varies by operation and configuration. One system can have strong reads on one path, and eventual reads on another.

### PACELC

**What does PACELC add to CAP?** If **P**artition, choose **A** or **C**. **E**lse, choose **L**atency or **C**onsistency. Latency is the everyday trade-off.

| System | On partition | Else |
|---|---|---|
| Cassandra | Availability | Latency |
| DynamoDB | Availability | Latency |
| Spanner | Consistency | Consistency |

**Consistency is a per-feature choice.** Buying a ticket needs strong consistency, and browsing events can be eventual.

### Consistency models

From weakest to strongest: eventual, read-your-writes, monotonic reads, causal, sequential, linearizable.

**Linearizability vs serializability.** Linearizability is about one object in real-time order. Serializability is about many objects, in any equivalent serial order. Having both is **strict serializability**.

**Does W + R > N make the system linearizable?** No. It gives overlap, but concurrent reads can still see different values.

## Distributed transactions

**A transaction must touch two shards. What breaks?** Each shard can commit or fail alone, so atomicity is lost.

### Two-phase commit (2PC)

```text
Phase 1, prepare:  coordinator asks everyone. Each makes its work durable, and votes.
Phase 2, commit:   if all voted yes, the coordinator logs COMMIT, and tells everyone.
```

**What happens if the coordinator crashes after all participants vote yes?** They **block**, holding locks, because they cannot decide alone. That is the weakness of 2PC.

**How consensus removes the blocking:** replicate the coordinator's decision through a consensus group, so that another node can finish it. Spanner does this.

**Consensus** lets a group agree on a value, as long as a majority is alive. **Raft** has an elected leader, terms, log replication and commit by majority.

**When would you actually use 2PC?** With a few participants, all databases you control, short transactions, and one data center. Many participants cannot join: message brokers and HTTP APIs have no prepare step.

**Oracle over database links** runs 2PC for you, and `RECO` resolves in-doubt transactions.

### Deadlocks at scale

**How do you handle deadlocks in a high-transaction system?** A consistent lock order, short transactions, and retrying the victim with backoff. For one hot row, use the counter options in [Chapter 24](../part-4-database-design/24-denormalization-and-trade-offs.md).

## Without 2PC: outbox and sagas

### The dual-write problem

A **message broker** carries events on **topics** to **consumers**. A service writes to its database, and publishes to the broker. If one succeeds and the other fails, they disagree.

**The transactional outbox.** Write the event row in the **same transaction** as the business change. A relay publishes it later. So the database and the event can never disagree. **Change data capture** can be that relay: log-based CDC reads the WAL or redo, and sees every change.

### Idempotent consumers

**Two `OrderPlaced` events arrive for the same order. Does the customer get charged twice?** Not if consumers are idempotent. Delivery repeats, so dedupe by event id. "Exactly once" in practice means at-least-once delivery, with idempotent handling.

### Sagas

A **saga** is a sequence of local transactions, each with a compensation.

**Payment succeeds, and the inventory write fails. Now what?** Run the compensation: refund the payment. A compensation is a new business action, not a rollback.

**Payment captured, inventory failed, and the refund also fails. What now?** Retry with backoff, send it to a dead-letter queue, and alert a human. Put irreversible steps last.

### Other patterns

- **Database per service:** private tables per service, with API composition.
- **CQRS:** separate read and write models.
- **Event sourcing:** append-only events are the source of truth.

## Distributed SQL

Data is split into ranges or tablets, each with its own Raft or Paxos group.

**Spanner TrueTime** gives clocks with bounded uncertainty. A commit waits until its timestamp is certainly in the past, which gives external consistency. **Spanner does not beat CAP:** it is technically CP, and effectively available because of Google's private network.

**Aurora DSQL** uses optimistic concurrency, checked at commit. **Why does it return SQLSTATE 40001 at commit?** A conflict was found, so the application must retry the whole transaction.

**When would you pick Spanner or CockroachDB over Postgres with read replicas?** For multi-region writes, or write scale beyond one primary. Most systems fit PostgreSQL.

**How can you ensure data consistency across distributed databases?** It depends on the need: synchronous replication or quorums for strong consistency in one system, 2PC for a few databases you control, the outbox and sagas across services, and reconciliation jobs to catch what slips through.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Shard too early | Permanent complexity | Exhaust simpler options |
| Use a monotonic shard key | One hot shard | Hash, or use a compound key |
| Use `hash % N` | Resharding moves almost everything | Use consistent hashing, or logical shards |
| State CAP as "pick 2 of 3" | It only applies during a partition | State it correctly |
| Use 2PC across services | Blocking, and many cannot join | Use the outbox and sagas |
| Write to a database and a broker separately | They can disagree | Use the outbox |
| Assume exactly-once delivery | Duplicates happen | Make consumers idempotent |
| Treat compensation as a rollback | Others saw the first step | Design a business action |

## Interview questions

**Q1. Why does hash(key) % N fail when you add a node, and what does consistent hashing change?**

Changing N remaps almost every key: going from 4 to 5 shards moves about 80 percent. Consistent hashing places keys and nodes on a ring, so only a small share moves.

**Q2. What is the CAP theorem?**

During a network partition, a system must choose consistency or availability. With no partition, it can offer both. C means linearizability, unlike the C in ACID.

**Q3. What does PACELC add to CAP?**

It adds the normal case: with no partition, you still trade latency against consistency. Cassandra and DynamoDB favor availability and latency. Spanner favors consistency.

**Q4. What is the difference between linearizability and serializability?**

Linearizability concerns one object, in real-time order. Serializability concerns transactions on many objects, in some serial order, not necessarily real time.

**Q5. Explain two-phase commit. What happens if the coordinator crashes after all participants vote yes?**

In prepare, each participant makes its work durable and votes. In commit, the coordinator tells them the outcome. If it crashes after the votes, participants block, holding locks, until it recovers.

**Q6. What is the dual-write problem, and how does the transactional outbox solve it?**

Writing to a database and a broker separately can leave them disagreeing. The outbox writes the event in the same transaction as the data, and a relay publishes it later.

**Q7. Payment succeeds and the inventory write fails. Now what?**

Run a compensating refund. I design the saga so that irreversible steps come last, and consumers are idempotent.

## Practice

**1. You choose `created_at` as a range shard key. What goes wrong?**

<details>
<summary>Show solution</summary>

All new writes hit the newest shard, so it becomes a hot spot. Hash a high-cardinality key instead, such as `user_id`.

</details>

**2. A cluster has N = 3, W = 1, R = 1. Can a read miss the latest write?**

<details>
<summary>Show solution</summary>

Yes. W + R = 2, which is not above 3, so the read and write sets may not overlap.

</details>

**3. Where do you put the event in an outbox design: before, or inside, the transaction?**

<details>
<summary>Show solution</summary>

Inside it, as a row in an outbox table, so that it commits or rolls back with the business change.

</details>

## Recap

- Shard last, and choose the key from the dominant query.
- `hash % N` moves most keys. Use consistent hashing, or logical shards.
- CAP applies during a partition. PACELC adds latency.
- 2PC blocks if the coordinator dies.
- The outbox solves dual writes.
- Sagas use compensations, not rollbacks.
- Consumers must be idempotent.

**Next:** [Chapter 39: NoSQL and choosing a database](39-nosql-and-choosing-a-database.md)
