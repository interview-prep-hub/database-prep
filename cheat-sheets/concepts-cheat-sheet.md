# Concepts Cheat Sheet: Normal Forms, Formulas and Where to Do What

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 1, 4, 5 and 6

> **In one line:** The theory on one sheet: definitions, tables, formulas and decisions.

## Three levels of a database ([Ch 1](../part-1-foundations/01-what-is-a-database.md))

| Level | Holds | Independence |
|---|---|---|
| External | Views | |
| Conceptual | Tables and constraints | Logical independence: change this and keep the views. The harder of the two |
| Internal | Files and indexes | Physical independence: change this and keep the logical schema |

## Keys and integrity ([Ch 2](../part-1-foundations/02-relational-model-and-keys.md))

| Term | Meaning |
|---|---|
| Superkey | Columns that identify a row |
| Candidate key | A minimal superkey |
| Primary key | The candidate key you chose |
| Alternate key | A candidate key you did not choose |
| Foreign key | Refers to a key in another table, or its own |
| Composite key | A key of several columns |
| Surrogate key | A generated value with no business meaning |
| Natural key | A real-world value, such as an email |
| Prime attribute | A member of any candidate key |

**Integrity rules:** domain, key, entity (no NULL in a primary key) and referential. A foreign key may be NULL, and may reference its own table.

## Relational algebra to SQL ([Ch 3](../part-1-foundations/03-relational-algebra.md))

| Algebra | SQL |
|---|---|
| Selection | `WHERE` |
| Projection | `SELECT` list |
| Product | `CROSS JOIN` |
| Join | `JOIN` |
| Union, intersection | `UNION`, `INTERSECT` |
| Difference | `EXCEPT` |
| Rename | `AS` |
| Division | Double `NOT EXISTS` |

Projection removes duplicates. SQL `SELECT` does not.

## ER to tables ([Ch 4](../part-1-foundations/04-er-modeling.md))

| ER item | Table rule |
|---|---|
| Strong entity | A table |
| Weak entity | A table that takes the owner's key |
| Multivalued attribute | A new table |
| M:N | A new table |
| 1:N | Foreign key on the many side |
| 1:1 | Foreign key on the total-participation side |

Cardinality is the maximum. Participation is the minimum.

| Inheritance option | Pick it when |
|---|---|
| One table with a type column | Few subclass columns |
| Subclass tables only | Queries rarely span subclasses |
| Superclass plus subclass tables | Many shared and many specific columns |

## Functional dependencies ([Ch 22](../part-4-database-design/22-functional-dependencies.md))

- **`X -> Y`:** rows equal on X are equal on Y.
- **Armstrong's axioms:** reflexivity, augmentation, transitivity.
- **Derived rules:** union, decomposition, pseudotransitivity.
- **Closure of X:** start with X, then add the right side of each dependency whose left side is inside, until nothing changes.
- **Finding keys:** attributes on no right side are in every key. Attributes only on right sides are in none. Test combinations of the rest.

## Normal forms ([Ch 23](../part-4-database-design/23-normalization.md))

| Form | Rule | Violation | Fix |
|---|---|---|---|
| 1NF | Each column holds one atomic value | A comma-separated phones column | One row per phone |
| 2NF | 1NF, and no non-prime column depends on part of a candidate key | `order_items(order_id, product_id, quantity, product_name)` with `product_id -> product_name` | Move `product_name` out |
| 3NF | 2NF, and for each non-trivial `X -> A`, X is a superkey or A is prime | `employees(emp_id, dept_id, dept_name)` with `dept_id -> dept_name` | Move `dept_name` out |
| BCNF | For each non-trivial `X -> Y`, X is a superkey | `rep_cover(customer_id, category_id, emp_id)` with `emp_id -> category_id` | Split on `emp_id` |
| 4NF | For each non-trivial `X ->> Y`, X is a superkey | `emp_skill_language(emp_id, skill, language)` with independent lists | One table per list |
| 5NF | Each join dependency follows from the candidate keys | Splits losslessly into three projections, but not two | Split into three |

**Quick rules:**

- Forms nest: 5NF inside 4NF inside BCNF inside 3NF inside 2NF inside 1NF.
- Find every candidate key before testing.
- Only single-attribute keys means at least 2NF.
- Every attribute prime means at least 3NF.
- Any two-column table is in BCNF.
- 3NF but not BCNF needs overlapping composite candidate keys.

**Decomposition:**

- **Binary lossless test:** the shared columns are a superkey of one side.
- Lossless and dependency preserving are independent.
- BCNF decomposition is always lossless, but may lose dependencies.
- 3NF synthesis gives both.
- A lossy split adds spurious rows. It does not drop rows.

4NF and 5NF rarely come up, because most tables get their extra columns from one fact. They matter when a table stores two independent lists, or a rule among three things.

## Denormalization ([Ch 24](../part-4-database-design/24-denormalization-and-trade-offs.md))

| Question | Answer |
|---|---|
| You gain | Fewer joins, faster reads |
| You pay | Extra storage, slower writes, risk of disagreement |
| Justified by | A measured read problem |
| Try first | Index, materialized view, summary table, cache |

## OLTP and OLAP ([Ch 26](../part-4-database-design/26-data-warehouse-design.md))

| | OLTP | OLAP |
|---|---|---|
| Work | Many small reads and writes | Few large scans |
| Design | Normalized | Star or snowflake |
| Storage | Row store | Column store |
| Measure | Transactions per second | Query time |

- **Star schema:** one fact table, with denormalized dimensions.
- **Snowflake schema:** dimensions normalized further.
- **Fact table:** measures at a stated grain.
- **Dimension table:** the context to filter and group by.
- **Slowly changing dimensions:** type 1 overwrites, type 2 adds a row, type 3 adds a column.

## Storage ([Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md))

| Layout | Good at |
|---|---|
| Heap | Fast inserts |
| Sorted file | Ranges |
| Hash file | Equality |
| Clustered | Reading neighbors by key |
| Row store | Whole rows, OLTP |
| Column store | Scanning few columns, OLAP |
| B+ tree | Reads and ranges |
| LSM tree | Heavy writes, with slower reads and background compaction |

**Buffer replacement.** LRU evicts the least recently used page. Clock approximates it cheaply. MRU suits repeated scans. Sequential flooding is a scan larger than the pool that pushes everything out.

## Index chooser ([Ch 29](../part-5-internals-and-performance/29-indexes.md))

| Index | Use it when | Avoid it when |
|---|---|---|
| B+ tree | Equality, ranges, sorting | Very small tables |
| Hash | Equality only | Ranges or sorting |
| Bitmap | Low-cardinality columns in warehouses | Many concurrent writers |
| Clustered | One main access order | Keys that change often |
| Non-clustered | Extra access paths | Heavily updated columns |
| Covering | A hot query, to avoid table lookups | Wide column lists |
| Composite | Combined filters, by the left-prefix rule | Leading column is not filtered |
| Partial | A small interesting subset | Most rows qualify |

- **Dense:** an entry for every key. **Sparse:** one per block.
- **When not to index:** very small tables, low selectivity, and heavily updated columns.

## Query processing ([Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md))

**Stages:** parse, optimize, execute. The cost-based optimizer uses statistics to pick the cheapest plan.

| Join | Picks when |
|---|---|
| Nested loop | Few outer rows, with an index on the inner side |
| Hash join | Large inputs, on equality |
| Sort-merge | Inputs already sorted, or inequality joins |

## Transactions ([Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md), [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md))

| ACID | Means | Provided by |
|---|---|---|
| Atomicity | All or nothing | Logging and recovery |
| Consistency | Rules still hold | Constraints and correct transactions |
| Isolation | Concurrent work does not interfere | Concurrency control |
| Durability | Committed work survives a crash | Logging and recovery |

| Level | Dirty read | Non-repeatable read | Phantom | Lost update | Write skew |
|---|---|---|---|---|---|
| `READ UNCOMMITTED` | Possible | Possible | Possible | Possible | Possible |
| `READ COMMITTED` | No | Possible | Possible | Possible | Possible |
| `REPEATABLE READ` | No | No | Possible | By engine | Possible |
| Snapshot | No | No | No | No | Possible |
| `SERIALIZABLE` | No | No | No | No | No |

Snapshot is shown separately, because it stops the three ANSI phenomena and still allows write skew. [Dialect Differences](dialect-differences.md) has each engine's behavior.

| Method | Guarantees | Suits |
|---|---|---|
| Basic 2PL | Serializable | Teaching. Allows cascading aborts |
| Strict 2PL | Plus no cascading aborts, by holding X locks to commit | Most lock-based systems |
| Rigorous 2PL | Plus commit order equals serial order, by holding all locks | Strong guarantees |
| Conservative 2PL | Plus no deadlock, by locking everything first | Known lock sets |
| Timestamp ordering | Serializable, no deadlock, more restarts | Few conflicts |
| Optimistic validation | Checks at commit | Read-heavy work |
| MVCC | Readers and writers do not block | Mixed loads |

**Deadlock handling.** Detect with a waits-for graph and pick a victim, or use timeouts. Wait-die: an older transaction waits, and a younger one dies. Wound-wait: an older transaction wounds a younger one, and a younger one waits. Lock ordering prevents the cycle. 2PL does not prevent deadlocks.

**Lock compatibility:**

| | IS | IX | S | SIX | X |
|---|---|---|---|---|---|
| **IS** | Yes | Yes | Yes | Yes | No |
| **IX** | Yes | Yes | No | No | No |
| **S** | Yes | No | Yes | No | No |
| **SIX** | Yes | No | No | No | No |
| **X** | No | No | No | No | No |

Lock top-down, and release bottom-up.

## Logging and recovery ([Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md))

- **Write-ahead rule:** the log reaches disk before the data page.
- **Commit** means the log is on stable storage, not the data pages.
- **Checkpoint:** limits how far back recovery reads.
- **Undo** removes uncommitted work. **Redo** repeats committed work.
- **Full and incremental backups**, plus logs, give point-in-time recovery.
- **RPO** is the data you can lose. **RTO** is the time you can be down.

The steal and force grid and ARIES phases are in [Last-Day Revision](last-day-revision.md).

## Inside a database server ([Ch 35](../part-6-architecture-and-scale/35-database-architecture.md))

```text
client -> parser -> optimizer -> executor -> buffer pool -> data files
                                                  |
                                             log buffer -> log files
```

| Role | Oracle | PostgreSQL |
|---|---|---|
| Shared memory | SGA | `shared_buffers` |
| Private memory | PGA | Backend memory |
| Writes data pages | DBWn | Background writer, checkpointer |
| Writes the log | LGWR | WAL writer, and backends at commit |
| Checkpoints | CKPT | Checkpointer |
| Cleans up | SMON, PMON | Autovacuum, postmaster |

Two-tier means the client talks to the database. Three-tier puts an application server between them. A connection pool sits between the application and the database, and reuses connections, which are costly to open.

## Scaling ([Ch 36](../part-6-architecture-and-scale/36-partitioning.md), [Ch 37](../part-6-architecture-and-scale/37-replication-and-high-availability.md), [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md))

| Step | Why, in order |
|---|---|
| Fix the query | Free, and the most common cause |
| Add an index | Cheap, with a small write cost |
| Cache | Removes repeated reads |
| Read replicas | Spreads reads |
| Partition | Prunes scans, eases retention |
| Shard | Spreads writes. Last, because it is the costliest |

- **Vertical:** a bigger server. **Horizontal:** more servers.
- **Synchronous replication** waits for a replica. **Asynchronous** does not, so a failover can lose data.
- **Partition methods:** range, hash, round-robin.
- **Shared memory, shared disk, shared nothing:** how much the nodes share.

**Distributed:**

- **Two-phase commit:** prepare, then commit. Participants block if the coordinator dies.
- **CAP:** during a network partition, choose consistency or availability.
- **PACELC:** else, with no partition, choose latency or consistency.
- **Quorum:** `R + W > N` makes reads see the latest write.
- **Consensus:** Raft or Paxos agree on one value despite failures.
- **Consistent hashing:** adding a node moves few keys.
- **BASE:** basically available, soft state, eventual consistency.

## Database families ([Ch 39](../part-6-architecture-and-scale/39-nosql-and-choosing-a-database.md))

| Family | Suits | Cost you accept |
|---|---|---|
| Relational | The default | Scaling writes takes work |
| Document | Nested records that vary | Weaker joins |
| Key-value | Lookups by key | No rich queries |
| Wide-column | Huge write volume, known queries | Query-first design |
| Graph | Deep relationships | Niche skills |
| Time-series | Metrics and samples | Narrow use |
| Search | Text relevance | Not a system of record |

## Formula sheet

**Symbols.** Books reuse B for block size and buffer count, and "order" means different things, so read the definition in the question. Here:

| Symbol | Means |
|---|---|
| n | Attributes, or pointers in a node, as stated |
| N | Pages to sort |
| M | Buffer pages |
| \|R\|, \|S\| | Pages of R and S |
| t | Tuples per page of R |
| C | Cost of one index lookup |
| V(A) | Distinct values of A |

**Keys ([Ch 2](../part-1-foundations/02-relational-model-and-keys.md)).** One candidate key of k attributes out of n gives `2^(n-k)` superkeys. Two keys K1 and K2 give `2^(n-|K1|) + 2^(n-|K2|) - 2^(n-|K1 union K2|)`.

> R(A, B, C, D, E) with keys {A} and {B, C}: 16 + 8 - 4 = 20.

**Storage ([Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md)).**

```text
blocking factor  = floor(block size / record size)      (unspanned)
data blocks      = ceil(records / blocking factor)
index entries    = floor(block size / (key + pointer))
binary search    = ceil(log2(blocks)) block reads
access time      = seek + half a rotation + transfer
```

> 4096-byte blocks, 200-byte records, 100,000 records: 20 per block, 5,000 blocks.

**B+ trees ([Ch 29](../part-5-internals-and-performance/29-indexes.md)).**

```text
internal node    n x pointer + (n - 1) x key <= block size
leaf             entries x (key + record pointer) + next pointer <= block size
levels at worst  ceil(log base ceil(n/2) of K), for K key values
total reads      levels + 1, when the record lives outside the tree
```

Non-root nodes stay at least half full, and a non-leaf root needs two children.

> 4096-byte block, 12-byte key, 8-byte pointer: n = 205.

**External merge sort ([Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).**

```text
initial runs  ceil(N / M)
merge fan-in  M - 1
passes        1 + ceil(log base (M - 1) of runs)
total I/O     2N x passes
two passes    possible when M x (M - 1) >= N
```

> N = 1,000 and M = 11: 91 runs, 3 passes, 6,000 I/Os. Input order does not change the count.

**Join cost in page I/O ([Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).**

```text
page nested loop    |R| + |R| x |S|
tuple nested loop   |R| + t x |R| x |S|
block nested loop   |R| + ceil(|R| / (M - 2)) x |S|
index nested loop   |R| + t x |R| x C
sort-merge          sort(R) + sort(S) + |R| + |S|
Grace hash          3 x (|R| + |S|), when partitions fit in memory
```

> Block nested loop with |R| = 100, |S| = 1,000, M = 12: 10,100. With the larger table outer: 11,000. Some books also count seeks, so check what the question counts.

**Selectivity ([Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).**

```text
equality   1 / V(A)
range      (high - value) / (high - low)
AND        s1 x s2
OR         s1 + s2 - s1 x s2
NOT        1 - s
join size  tuples(R) x tuples(S) / max(V(A, R), V(A, S))
```

Work in tuples first, then pages.

**Counting.**

```text
serial schedules of n transactions       n!
interleavings of n and m operations      (n + m)! / (n! x m!)
join orders of n tables                  (2(n - 1))! / (n - 1)!
quorum rule                              R + W > N
replicas to survive F failures           2F + 1
RAID usable disks, out of n              RAID 0: n, RAID 1: n / 2, RAID 5: n - 1, RAID 6: n - 2
```

**Bloom filter.** No false negatives, and a false positive rate of about `(1 - e^(-kn/m))^k`.

**Extendible hashing.** The directory doubles only when the full bucket's local depth equals the global depth.

## Where to do what ([Ch 41](../part-6-architecture-and-scale/41-where-to-do-what.md))

| Decision | Pick | Because |
|---|---|---|
| Enforce a rule | Constraint first, trigger only for what a constraint cannot state, application checks for friendly messages | A constraint holds for every path into the data |
| Business logic | Application by default. Stored procedure when many rows move inside the database, or many applications share the rule | Testing and deployment are easier in the application |
| Reuse a query | View for logic, materialized view when costly and staleness is fine, CTE for one statement, temporary table for a multi-step batch | Each stores a different thing for a different time |
| Speed up a read | Fix the query, then index, summary or materialized view, cache, read replica | Cheapest first |
| Big table | Partition for pruning and lifecycle. Shard only when one server cannot take the write load | Sharding is costly |
| Remove data | `DELETE` for some rows, `TRUNCATE` for all, `DROP` for the table, soft delete when history matters | Each differs in scope and speed |
| Keys | Surrogate primary key, plus `UNIQUE` on the natural key | Stable joins, with real uniqueness |
| Money | `NUMERIC` | Floats drift |
| Time | A timestamp with a clear time zone rule | Local times are ambiguous |
| Design | Normalize first, denormalize for a measured need | Fewer bugs by default |
| Store | Relational, unless the workload gives a reason to leave | It is the safest default |

**Also:** least privilege, roles, bind variables and encryption at rest and in transit ([Ch 40](../part-6-architecture-and-scale/40-database-security.md)). History tables and validity periods for time ([Ch 25](../part-4-database-design/25-schema-design-patterns.md)). Shared table, shared database or separate database for tenants ([Ch 25](../part-4-database-design/25-schema-design-patterns.md)).

## Common mistakes

| What people do | What is true |
|---|---|
| Say 3NF means no transitive dependency, and stop | The rule allows a prime right side, which separates 3NF from BCNF |
| Test 2NF or 3NF against the primary key only | Use every candidate key |
| Claim no dependencies means no redundancy | Multivalued dependencies can still cause it |
| Prove a dependency from sample data | Data can disprove one, never prove one |
| Assume BCNF is always better | It can lose dependency preservation |
| Add superkey counts without the overlap | Subtract the overlap of two keys |
| Use all buffers as the merge fan-in | One buffer is for output, so it is M - 1 |
| Forget the final data block | Count it in B+ tree accesses |
| Treat the C in ACID and CAP as one word | ACID means rules hold, CAP means one up-to-date copy |
| Say CAP means pick any two | The choice appears during a partition |
| Use partitioning and sharding as synonyms | One database, vs many servers |
| Believe 2PL prevents deadlocks | It gives serializability, and deadlocks can occur |

## Quick self-test

1. State each normal form in one line, with its violation.
2. R(A, B, C, D, E) has candidate keys {A} and {B, C}. How many superkeys?
3. Blocks are 4096 bytes and records 200 bytes. How many blocks hold 100,000 unspanned records?
4. With 4096-byte blocks, 12-byte keys and 8-byte pointers, what is the maximum pointer count in a B+ tree internal node?
5. How many passes does merge sort need for 1,000 pages with 11 buffers?
6. How do you estimate the selectivity of `A = 5 AND B > 10`, and `A = 5 OR B > 10`?
7. A query is slow. What do you try, in order, before buying hardware?
8. What is the difference between ACID and BASE?

**Next:** [Glossary](glossary.md)
