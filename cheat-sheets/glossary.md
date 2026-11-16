# Glossary: Database Words in Plain English

**Level:** Basic | **Interview priority:** Should know | **Before this:** Nothing

> **In one line:** Every database word in this book, in one plain sentence, with where to learn it.

Words are alphabetical inside each section. Examples use the [sample database](../setup/sample-database.md).

## Words interviewers use without explaining

| Word | Meaning | Chapter |
|---|---|---|
| Anti-join | Return left rows with no match, usually with `NOT EXISTS`, such as customers 7 and 8 who have no orders | [Ch 21](../part-3-advanced-sql/21-classic-query-patterns.md) |
| Cohort | A group that shares a start event, such as customers by signup month, followed over time | [Ch 21](../part-3-advanced-sql/21-classic-query-patterns.md) |
| Fan-out | A join multiplies rows because one row matches many, as with order 1003 and its two payments. It also means the child pointers in a B+ tree node | [Ch 11](../part-2-sql-basics/11-joins.md) |
| Frame | The rows a window function sees for the current row, inside the partition | [Ch 16](../part-3-advanced-sql/16-window-functions-frames-and-running-totals.md) |
| Grain | What one row represents. `order_items` has one row per order line. State the grain before you join or sum | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Island | An unbroken run of consecutive values, such as days in a row with an order. A gap is the break between islands | [Ch 21](../part-3-advanced-sql/21-classic-query-patterns.md) |
| Peer row | A row with the same `ORDER BY` value as the current row, such as James and Omar at 95000 | [Ch 16](../part-3-advanced-sql/16-window-functions-frames-and-running-totals.md) |
| Sargable | Written so an index can seek on it. `order_date >= DATE '2024-01-01'` is sargable, and a function around `order_date` usually is not | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Semi-join | Return each left row with at least one match, once, usually with `EXISTS` or `IN`. There is no `SEMI JOIN` keyword on these four engines | [Ch 13](../part-2-sql-basics/13-subqueries.md) |

## One word, several meanings

| Word | Meanings |
|---|---|
| Cardinality | Rows in a relation, the ER maximum, distinct values in a column, or the optimizer's row estimate |
| Checkpoint | A database recovery point, or a saved state in other tools |
| Cluster | A table cluster, a clustered index, a PostgreSQL database cluster, or a group of servers |
| Consistency | Rules hold (ACID), one up-to-date copy (CAP), or a stable read view (read consistency) |
| Degree | Columns in a relation, or entity types in a relationship |
| Instance | The data at one moment, or a running database server |
| Key | Any key in the key family, or a B+ tree search value |
| Order | B+ tree capacity, which books define differently, or sort order |
| Partition | A table partition, a window `PARTITION BY`, or a network partition |
| Schema | A design, a namespace, or an Oracle user |
| Snapshot | A consistent read view, a copy of a disk, or a replica of data |

## Same idea, different names

| These mean the same, or nearly | Note |
|---|---|
| Relation, table | |
| Tuple, row | |
| Attribute, column | |
| Intension, schema | |
| Extension, instance | |
| Multiset, bag | |
| Block, page | |
| Lossless join, nonadditive join | |
| Discriminator, partial key | |
| Primary index, clustering index | Silberschatz treats them as synonyms. Elmasri separates them by whether the ordering field is a key |
| Canonical cover, minimal cover | Silberschatz merges equal left sides, Elmasri keeps single right sides, and neither is unique |
| Rigorous 2PL, strong strict 2PL | Berkeley's Strict 2PL also means rigorous |

## Relational model and keys

| Word | Meaning | Chapter |
|---|---|---|
| Alternate key | A candidate key you did not pick, such as `email` | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Attribute | A column | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Candidate key | A minimal set of columns that identifies a row | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Composite key | A key of several columns, such as `(order_id, product_id)` | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Domain | The allowed values of a column | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Entity integrity | No NULL in a primary key | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Foreign key | Columns that must match a key elsewhere, such as `orders.customer_id` | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Instance | The data in a table at one moment | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Natural key | A real-world value used as a key | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| NULL | Unknown or missing, not zero and not empty | [Ch 5](../part-1-foundations/05-data-types-and-null.md) |
| Prime attribute | A member of any candidate key | [Ch 22](../part-4-database-design/22-functional-dependencies.md) |
| Primary key | The chosen candidate key, such as `emp_id` | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Referential integrity | Each foreign key value exists in the parent | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Relation | A table | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Schema | The design of tables and columns | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Superkey | Columns that identify a row, possibly with extras | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Surrogate key | A generated value with no business meaning | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |
| Tuple | A row | [Ch 2](../part-1-foundations/02-relational-model-and-keys.md) |

## SQL words

| Word | Meaning | Chapter |
|---|---|---|
| Aggregate | A function over many rows, such as `SUM` | [Ch 10](../part-2-sql-basics/10-aggregation-group-by-having.md) |
| Collation | The rules for comparing and sorting text | [Ch 5](../part-1-foundations/05-data-types-and-null.md) |
| Correlated subquery | A subquery that reads the outer row | [Ch 13](../part-2-sql-basics/13-subqueries.md) |
| CTE | A named result for one statement, with `WITH` | [Ch 14](../part-3-advanced-sql/14-cte-and-recursive-queries.md) |
| DCL | `GRANT` and `REVOKE` | [Ch 1](../part-1-foundations/01-what-is-a-database.md) |
| DDL | `CREATE`, `ALTER`, `DROP` | [Ch 6](../part-2-sql-basics/06-ddl-and-constraints.md) |
| Derived table | A subquery in `FROM` | [Ch 13](../part-2-sql-basics/13-subqueries.md) |
| DML | `INSERT`, `UPDATE`, `DELETE` | [Ch 7](../part-2-sql-basics/07-dml-insert-update-delete.md) |
| DUAL | Oracle's one-row table, for selecting with no real table | [Ch 8](../part-2-sql-basics/08-select-filter-sort.md) |
| Implicit conversion | The engine changes a type for you, which can hide an index | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Inline view | Oracle's name for a derived table | [Ch 13](../part-2-sql-basics/13-subqueries.md) |
| Materialized view | A stored query result that needs refreshing | [Ch 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md) |
| Pagination | Fetching results page by page | [Ch 31](../part-5-internals-and-performance/31-query-tuning-playbook.md) |
| Pivot | Turning rows into columns | [Ch 17](../part-3-advanced-sql/17-advanced-grouping-and-pivot.md) |
| Predicate | A condition that gives TRUE, FALSE or UNKNOWN | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| ROWID | Oracle's physical address of a row | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| ROWNUM | Oracle's temporary row number, given as rows are returned | [Ch 8](../part-2-sql-basics/08-select-filter-sort.md) |
| Scalar subquery | A subquery that gives one value | [Ch 13](../part-2-sql-basics/13-subqueries.md) |
| Set operator | `UNION`, `INTERSECT`, `EXCEPT` | [Ch 12](../part-2-sql-basics/12-set-operations.md) |
| TCL | `COMMIT`, `ROLLBACK`, `SAVEPOINT` | [Ch 1](../part-1-foundations/01-what-is-a-database.md) |
| Three-valued logic | TRUE, FALSE and UNKNOWN | [Ch 5](../part-1-foundations/05-data-types-and-null.md) |
| UNKNOWN | The result of comparing with NULL | [Ch 5](../part-1-foundations/05-data-types-and-null.md) |
| Upsert | Update if the row exists, else insert | [Ch 18](../part-3-advanced-sql/18-advanced-dml.md) |
| View | A stored query | [Ch 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md) |
| Window function | Calculates across related rows and keeps each row | [Ch 15](../part-3-advanced-sql/15-window-functions-ranking-and-offset.md) |

## Design words

| Word | Meaning | Chapter |
|---|---|---|
| Anomaly | An update, insert or delete problem caused by redundancy | [Ch 23](../part-4-database-design/23-normalization.md) |
| Cardinality ratio | 1:1, 1:N or M:N | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| Decomposition | Splitting a table into smaller ones | [Ch 23](../part-4-database-design/23-normalization.md) |
| Denormalization | Deliberate redundancy for reads | [Ch 24](../part-4-database-design/24-denormalization-and-trade-offs.md) |
| Dependency preservation | Each dependency can be checked inside one table | [Ch 23](../part-4-database-design/23-normalization.md) |
| Dimension table | Context for facts, such as a product | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Entity | A thing you store data about, such as a customer | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| ER diagram | A picture of entities and relationships | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| Fact table | Measures at a stated grain, such as sales lines | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Functional dependency | Equal X forces equal Y, such as `dept_id -> dept_name` | [Ch 22](../part-4-database-design/22-functional-dependencies.md) |
| Join dependency | A table equals the join of its projections | [Ch 23](../part-4-database-design/23-normalization.md) |
| Junction table | A table that links M:N, such as `order_items` | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| Multivalued dependency | One value fixes a set of values, independent of other columns | [Ch 23](../part-4-database-design/23-normalization.md) |
| Normal form | A rule level for table design | [Ch 23](../part-4-database-design/23-normalization.md) |
| Partial dependency | A column depends on part of a composite key | [Ch 23](../part-4-database-design/23-normalization.md) |
| Participation | Whether each entity must take part in a relationship | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| Relationship | A link between entities, such as customer places order | [Ch 4](../part-1-foundations/04-er-modeling.md) |
| Slowly changing dimension | A way to keep dimension history | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Snowflake schema | A star with normalized dimensions | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Star schema | One fact table with denormalized dimensions | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Transitive dependency | A non-key column depends on another non-key column | [Ch 23](../part-4-database-design/23-normalization.md) |
| Weak entity | Identified through its owner, such as an order line | [Ch 4](../part-1-foundations/04-er-modeling.md) |

## Storage and performance words

| Word | Meaning | Chapter |
|---|---|---|
| B+ tree | A balanced tree index with data in linked leaves | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Bind variable | A placeholder for a value, sent apart from the SQL text | [Ch 31](../part-5-internals-and-performance/31-query-tuning-playbook.md) |
| Buffer pool | Pages cached in memory | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| Clustered index | Rows stored in index order | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Composite index | An index on several columns | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Covering index | Holds each column a query needs | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Execution plan | The steps the database will run | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Extent | A run of contiguous pages | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| Full table scan | Reading every row | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Hard parse | Building a plan from scratch | [Ch 31](../part-5-internals-and-performance/31-query-tuning-playbook.md) |
| Hash join | Builds a hash table on one input, probes with the other | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Heap | A table with no row order | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| Hint | A note to steer the optimizer | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Index | A structure to find rows without scanning | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Index scan | Reading through an index | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Index seek | Jumping straight to keys in an index | [Ch 29](../part-5-internals-and-performance/29-indexes.md) |
| Merge join | Merges two sorted inputs | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Nested loop | For each outer row, look up inner rows | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Optimizer | The part that picks the plan | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Page | The unit of disk I/O | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| Partition pruning | Skipping partitions a query cannot need | [Ch 36](../part-6-architecture-and-scale/36-partitioning.md) |
| Predicate pushdown | Filtering as early as possible | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Segment | The storage of one object on Oracle | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |
| Selectivity | The fraction of rows a filter keeps | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Soft parse | Reusing a cached plan | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Statistics | Row counts and value spreads for the optimizer | [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) |
| Tablespace | A named storage area | [Ch 28](../part-5-internals-and-performance/28-how-data-is-stored.md) |

## Transaction and recovery words

| Word | Meaning | Chapter |
|---|---|---|
| ACID | Atomicity, consistency, isolation, durability | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| ARIES | A recovery method: analysis, redo, undo | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Autocommit | Each statement commits on its own | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Checkpoint | A marker that limits how far recovery reads | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Deadlock | A cycle of transactions waiting for each other | [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| Dirty read | Reading uncommitted data | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Force | Writing pages to disk at commit | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Isolation level | How much a transaction sees of others | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Latch | A brief lock on a memory structure | [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| Lock | A claim on data until commit | [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| Lost update | One write overwrites another | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| MVCC | Keeping row versions, so readers and writers do not block | [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| Non-repeatable read | One row changes between two reads | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Phantom | New rows appear in a repeated range query | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Redo | Repeating logged changes | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Savepoint | A named point to roll back to | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Schedule | An order of operations from transactions | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Serializable | The result matches some one-at-a-time order | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Snapshot isolation | Each transaction reads one stable version | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Steal | Writing uncommitted pages to disk | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Transaction | A group of changes that succeed or fail together | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Two-phase locking | Take locks, then release, never take after releasing | [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| Undo | Removing uncommitted changes | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Write skew | Two transactions read, then write different rows, and break a rule | [Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) |
| Write-ahead log | Changes are logged before data pages are written | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |

## Architecture words

| Word | Meaning | Chapter |
|---|---|---|
| BASE | Basically available, soft state, eventual consistency | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| CAP | During a network partition, choose consistency or availability | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Change data capture | Reading the log to stream changes | [Ch 24](../part-4-database-design/24-denormalization-and-trade-offs.md) |
| Connection pool | Reusable open connections | [Ch 35](../part-6-architecture-and-scale/35-database-architecture.md) |
| Consensus | Nodes agree on one value despite failures | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Data lake | Raw files at low cost | [Ch 39](../part-6-architecture-and-scale/39-nosql-and-choosing-a-database.md) |
| Data warehouse | A database built for analysis | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| ELT | Extract, load, then transform in the warehouse | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| ETL | Extract, transform, then load | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| Eventual consistency | Copies agree if writes stop | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Failover | A replica takes over from a failed primary | [Ch 37](../part-6-architecture-and-scale/37-replication-and-high-availability.md) |
| OLAP | Large analytical reads | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| OLTP | Many small transactions | [Ch 26](../part-4-database-design/26-data-warehouse-design.md) |
| PACELC | CAP, plus latency vs consistency when healthy | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Partitioning | Splitting a table inside one database | [Ch 36](../part-6-architecture-and-scale/36-partitioning.md) |
| Quorum | Enough nodes agree, with `R + W > N` | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Read replica | A copy that serves reads | [Ch 37](../part-6-architecture-and-scale/37-replication-and-high-availability.md) |
| Replication | Keeping copies of data on other servers | [Ch 37](../part-6-architecture-and-scale/37-replication-and-high-availability.md) |
| RPO | The data you can afford to lose | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| RTO | The time you can afford to be down | [Ch 34](../part-5-internals-and-performance/34-backup-and-recovery.md) |
| Shared nothing | Each node has its own memory and disk | [Ch 35](../part-6-architecture-and-scale/35-database-architecture.md) |
| Sharding | Spreading rows across servers | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |
| Two-phase commit | Prepare on all, then commit on all | [Ch 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) |

## PL/SQL words

| Word | Meaning | Chapter |
|---|---|---|
| %ROWTYPE | A variable shaped like a whole row | [Ch 42](../part-7-plsql/42-plsql-basics.md) |
| %TYPE | A variable shaped like one column | [Ch 42](../part-7-plsql/42-plsql-basics.md) |
| Anonymous block | PL/SQL code with no name | [Ch 42](../part-7-plsql/42-plsql-basics.md) |
| Autonomous transaction | A unit that commits on its own | [Ch 52](../part-7-plsql/52-advanced-plsql.md) |
| BULK COLLECT | Fetches many rows into a collection, in one trip | [Ch 50](../part-7-plsql/50-bulk-processing.md) |
| Collection | An in-memory list or map | [Ch 49](../part-7-plsql/49-records-and-collections.md) |
| Context switch | The hop between the SQL and PL/SQL engines | [Ch 50](../part-7-plsql/50-bulk-processing.md) |
| Cursor | A handle on a query's result | [Ch 44](../part-7-plsql/44-cursors.md) |
| Definer's rights | Runs with the owner's privileges | [Ch 52](../part-7-plsql/52-advanced-plsql.md) |
| FORALL | Sends one DML for many elements, in one trip | [Ch 50](../part-7-plsql/50-bulk-processing.md) |
| Invoker's rights | Runs with the caller's privileges | [Ch 52](../part-7-plsql/52-advanced-plsql.md) |
| Mutating table | A row trigger reads the table it is changing | [Ch 48](../part-7-plsql/48-triggers.md) |
| Package | A named group of related code | [Ch 47](../part-7-plsql/47-packages.md) |
| PL/Scope | A compiler tool that records identifiers | [Ch 53](../part-7-plsql/53-plsql-performance-and-best-practices.md) |
| Pragma | An instruction to the compiler | [Ch 45](../part-7-plsql/45-exceptions.md) |
| REF CURSOR | A cursor you can pass around | [Ch 44](../part-7-plsql/44-cursors.md) |
| Trigger | Code that runs on an event | [Ch 48](../part-7-plsql/48-triggers.md) |

## Abbreviations

| Short | Long |
|---|---|
| ACID | Atomicity, consistency, isolation, durability |
| ARIES | Algorithms for Recovery and Isolation Exploiting Semantics |
| ASH | Active Session History |
| AWR | Automatic Workload Repository |
| BCNF | Boyce-Codd normal form |
| CDC | Change data capture |
| CTE | Common table expression |
| DDL, DML | Data definition language, data manipulation language |
| FD | Functional dependency |
| IOT | Index-organized table |
| LSN | Log sequence number |
| MVCC | Multi-version concurrency control |
| OCC | Optimistic concurrency control |
| PGA, SGA | Program global area, system global area |
| RCSI | Read committed snapshot isolation |
| RID | Row identifier |
| SSI | Serializable snapshot isolation |
| WAL | Write-ahead log |

## Engine word translation

| Oracle | PostgreSQL |
|---|---|
| Redo | WAL |
| Undo | Dead tuples in the table |
| `ROWID` | `ctid` |
| SGA | `shared_buffers` and other shared memory |
| Tablespace, with data files it manages | Tablespace, a directory on disk |

## Words about query answers

| Word | Meaning |
|---|---|
| Deterministic | The same input always gives the same output |
| Exclusive bound | The end value is left out, as in `< next_day` |
| Idempotent | Running it twice has the same effect as once |
| Inclusive bound | The end value is kept, as in `BETWEEN` |
| Nullable | The column may hold NULL |

## Everyday analytics words

| Word | Meaning |
|---|---|
| Attribution | Which step gets credit for a result |
| Churn | Customers who stop |
| Funnel | Counts at each step toward a goal |
| Retention | Customers who come back |
| Sessionization | Grouping events into visits by time gaps |

## Common mistakes

| What people do | What is true |
|---|---|
| Use fan-out without saying which meaning | It means join row multiplication, or B+ tree child pointers |
| Use cardinality without saying which meaning | High cardinality in a column means many distinct values, and ER cardinality is a maximum count |
| Think semi-join is SQL syntax | You write `EXISTS` or `IN`, and the optimizer may run it as a semi-join |
| Think sargable means an index exists | It means the predicate is written so an index could be used |
| Call every row in a partition a peer | Peers share the same `ORDER BY` value |
| Mix up partition and frame | `PARTITION BY` splits rows, and the frame is the moving subset inside one partition |
| Hear primary index and think primary key index | Books differ, so ask |
| Treat grain as a warehouse word only | Every table and query result has a grain |
| Use schema as if it means one thing | It differs by engine |

**Next:** [Last-Day Revision](last-day-revision.md)
