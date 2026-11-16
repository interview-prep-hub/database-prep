# 56. Database Concepts: The Questions You Answer Out Loud

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 1 to 6

> **In one line:** This is recall practice: cover the answer, say yours out loud, then check it.

## How a theory round runs

A typical round mixes 4 to 8 theory questions with one SQL query, so you get a few minutes for each.

**The spoken answer shape:**

1. One plain sentence that defines it.
2. One tiny example.
3. Why it matters, or the trap.

Stop there. If they want more, they will ask.

## Model answers

**"What is ACID?"**

> ACID describes what a transaction guarantees. Take a transfer of 100 from A to B. Atomicity means both changes happen, or neither. Consistency means the rules still hold afterward, so the total is unchanged. Isolation means a concurrent report does not see the money missing from both. Durability means once it commits, a crash cannot lose it.

**"What is normalization?"**

> Normalization splits a table so that each fact lives in one place. A single orders table that repeats the customer's city on every row has an update problem: changing the city means changing many rows. So I move customers into their own table, and keep only `customer_id` on orders. In practice I aim for 3NF or BCNF, and I denormalize only for a measured read problem.

**"Walk me through what happens when you run an UPDATE and then COMMIT."** ([Chapter 35](../part-6-architecture-and-scale/35-database-architecture.md))

> On Oracle: the session parses the statement, or reuses a cached cursor. It finds the block in the buffer cache, reading it from disk if needed. It takes a row lock, writes the old value to undo, changes the block, and writes redo to the log buffer. At `COMMIT`, LGWR flushes redo to disk, and that makes it durable. DBWn writes the dirty block later.

> On PostgreSQL: the backend writes a new row version in shared buffers, and WAL for it. At `COMMIT`, the WAL is flushed. The checkpointer writes pages later, and `VACUUM` removes the old version.

## Rapid-fire banks

Cover the right column.

### Foundations (Chapters 1, 2)

| Question | One-line answer |
|---|---|
| Why a DBMS over files? | Integrity, transactions, concurrency, security and queries, built in |
| DBMS vs RDBMS? | An RDBMS is a DBMS on the relational model |
| Schema vs instance? | The design vs the data at one moment |
| Physical vs logical independence? | Change storage, or change the logical schema, without breaking the level above |
| Degree vs cardinality? | Columns vs rows |
| Super vs candidate vs primary key? | Identifies a row, minimal, chosen |
| Primary vs unique key? | One and never NULL, vs many and usually NULL-able |
| Can a foreign key be NULL? | Yes |
| Types of integrity? | Domain, key, entity, referential |

### SQL meaning (Chapters 7 to 19)

| Question | One-line answer |
|---|---|
| Logical clause order? | `FROM`, `WHERE`, `GROUP BY`, `HAVING`, `SELECT`, `ORDER BY`, limit |
| `WHERE` vs `HAVING`? | Rows before grouping, vs groups after |
| `DELETE` vs `TRUNCATE` vs `DROP`? | Rows, all rows fast, the table |
| `UNION` vs `UNION ALL`? | Removes duplicates, vs keeps them, and is faster |
| `IN` vs `EXISTS`? | The same plan usually. `NOT IN` breaks on NULL |
| Correlated subquery? | Refers to the outer row |
| CTE? | A named result for one statement |
| View vs materialized view? | A stored query, vs a stored result |
| `RANK` vs `DENSE_RANK`? | Gaps after ties, vs no gaps |

### ER design (Chapter 4)

| Question | One-line answer |
|---|---|
| Cardinality vs participation? | Maximum vs minimum |
| Weak entity? | Keyed by its owner's key plus a discriminator |
| M:N in tables? | A junction table |
| 1:N in tables? | A foreign key on the many side |
| Aggregation? | Treating a relationship as an entity |

### Normalization (Chapters 22 to 24)

| Question | One-line answer |
|---|---|
| Functional dependency? | Equal X forces equal Y |
| Anomalies? | Update, insertion, deletion |
| 2NF? | No partial dependency on a candidate key |
| 3NF? | For each `X -> A`, X is a superkey, or A is prime |
| BCNF? | Every determinant is a superkey |
| 3NF but not BCNF needs? | Overlapping composite candidate keys |
| Lossless join? | The join rebuilds exactly the original |
| 4NF? | No non-key multivalued dependency |
| Denormalization? | Deliberate redundancy for reads |

### Storage and indexes (Chapters 28, 29)

| Question | One-line answer |
|---|---|
| Page? | The unit of I/O |
| Buffer pool? | Pages cached in memory |
| B+ tree vs hash? | Ranges and order, vs equality only |
| Clustered vs non-clustered? | Rows in index order, vs a separate structure |
| Dense vs sparse? | Every key, vs one per block |
| Leftmost prefix? | `(a, b)` serves `a`, not `b` alone |
| Covering index? | Holds every column the query needs |
| SARGable? | The column stands alone, so the index can seek |

### Query processing (Chapter 30)

| Question | One-line answer |
|---|---|
| Stages of a query? | Parse, optimize, execute |
| Cost-based optimizer? | Picks the cheapest plan from statistics |
| Nested loop? | Small outer, indexed inner |
| Hash join? | Large equality joins |
| Merge join? | Inputs already sorted |
| `EXPLAIN` vs `EXPLAIN ANALYZE`? | Predicts, vs really runs |

### Transactions and concurrency (Chapters 32, 33)

| Question | One-line answer |
|---|---|
| Dirty read? | Reading uncommitted data |
| Non-repeatable read? | One row changes between reads |
| Phantom? | New rows appear in a range |
| Lost update? | One write overwrites another |
| Write skew? | Two reads, then writes to different rows, break a rule |
| Default isolation? | `READ COMMITTED`, and MySQL `REPEATABLE READ` |
| MVCC? | Versions, so readers and writers do not block each other |
| 2PL? | Grow, then shrink, gives serializability |
| Deadlock? | A cycle of waits |
| Lock vs latch? | Logical data until commit, vs memory, briefly |

### Recovery and backup (Chapters 34, 37)

| Question | One-line answer |
|---|---|
| WAL? | Log before data |
| Redo vs undo? | Replay forward, vs roll back |
| Checkpoint? | A known starting point for recovery |
| ARIES? | Analysis, redo, undo |
| RPO vs RTO? | Data you can lose, vs time you can be down |
| PITR? | Base backup plus logs, to a moment |
| Is a replica a backup? | No |

### Architecture and distributed data (Chapters 35 to 39)

| Question | One-line answer |
|---|---|
| Instance vs database? | Memory and processes, vs files |
| SGA vs PGA? | Shared, vs private |
| Who writes at commit? | LGWR |
| Sync vs async replication? | Waits for a replica, vs does not |
| Partitioning vs sharding? | One server, vs many |
| CAP? | During a partition, consistency or availability |
| 2PC weakness? | It blocks if the coordinator dies |
| Outbox? | The event commits with the data |
| Saga? | Local transactions with compensations |

### Security (Chapter 40)

| Question | One-line answer |
|---|---|
| How to stop injection? | Bind values, and allow-list identifiers |
| Least privilege? | Only what is needed |
| RLS? | The database adds the row filter |
| TDE protects? | Files, not queries |

## Favorite Oracle comparisons

| Pair | Difference |
|---|---|
| `ROWNUM` vs `ROWID` vs `ROW_NUMBER` | Temporary number, physical address, window function |
| `NVL` vs `COALESCE` | Two arguments and evaluates both, vs many and stops early |
| `CHAR` vs `VARCHAR2` | Padded, vs not |
| `DECODE` vs `CASE` | Oracle-only equality, vs standard |
| `MINUS` vs `EXCEPT` | The same, by name |

## Drills

**1. The normalization pipeline.** Always in this order: attribute closures, candidate keys, prime attributes, highest normal form, decomposition, lossless check, dependency check. Try it on R(A, B, C, D) with `A -> B`, `B -> C`, `C -> D`.

<details>
<summary>Show solution</summary>

```text
Key: A. Prime: A.
2NF: yes, the key has one column.
3NF: no, B -> C has B not a superkey and C not prime.
Decompose: (A, B), (B, C), (C, D).
Lossless and dependency preserving.
```

</details>

**2. Classify a schedule.** Check serial, then conflict serializable, then view serializable, then recoverable. Try `R1(A) W2(A) W1(A) W3(A)`.

<details>
<summary>Show solution</summary>

```text
Conflicts: R1 -> W2 gives T1 -> T2. W2 -> W1 gives T2 -> T1.
Cycle, so not conflict serializable.
View equivalent to T1, T2, T3, with blind writes, so it is view serializable.
```

</details>

**3. The marbles under snapshot isolation.** One transaction turns white marbles black, and another turns black marbles white, at once. What happens?

<details>
<summary>Show solution</summary>

Both commit, because they write different rows. The colors swap, which no serial order would give. That is write skew. `SERIALIZABLE` on PostgreSQL aborts one.

</details>

**4. Counting.** How many serial schedules do 3 transactions have?

<details>
<summary>Show solution</summary>

`3! = 6`.

</details>

**5. ARIES by hand.** Log: T1 update, T2 update, fuzzy checkpoint, T1 commit, T3 update, crash. What happens?

<details>
<summary>Show solution</summary>

```text
Analysis finds T2 and T3 active at the crash.
Redo repeats history, from the earliest change.
Undo rolls back T2 and T3.
T1 stays committed.
```

</details>

## Recap

- Define, give one example, and say why it matters.
- Say answers out loud. Reading is not recall.
- Redo every question you could not answer in one breath.

**Next:** [Chapter 57: PL/SQL question bank](57-plsql-question-bank.md)
