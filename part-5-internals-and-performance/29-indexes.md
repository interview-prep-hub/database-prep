# 29. Indexes: How Databases Find Rows Fast

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 28](28-how-data-is-stored.md)

> **In one line:** An index is a separate sorted structure that lets the database jump to matching rows instead of reading the whole table.

**About the demos:** the demos in this chapter use PostgreSQL, so not all of their syntax runs on Oracle. Oracle commands are shown where they differ.

## What you will learn

- What an index is, what it costs, and how to see it working
- B+ trees, and why databases use them
- Clustered and non-clustered indexes on each engine
- Composite indexes and the leftmost-prefix rule
- Covering indexes, and what makes a query SARGable
- Why an index gets ignored, and the other index types

## What is an index?

An **index** maps column values to row locations, like the index at the back of a book. Without one, the database must read every page of the table. That is a **full table scan**.

**Vocabulary:** the **search key** is the indexed column. An **index entry** is a key plus a pointer to the row. **Selectivity** is the fraction of rows a condition matches.

### Seeing the effect

The sample tables are too small for indexes to matter, because reading a few rows is always cheap. So here is a table with 100,000 rows.

```sql postgres
CREATE TABLE big_orders AS
SELECT g AS order_id,
       MOD(g, 1000) AS customer_id,
       DATE '2024-01-01' + MOD(g, 365) AS order_date,
       CASE WHEN MOD(g, 100) = 0 THEN 'PENDING' ELSE 'DELIVERED' END AS status,
       MOD(g, 500) * 1.5 AS amount
FROM generate_series(1, 100000) AS g;

ANALYZE big_orders;
SET max_parallel_workers_per_gather = 0;  -- keeps the plans simple to read
```

`EXPLAIN` shows how the database plans to run a query ([Chapter 30](30-execution-plans-and-the-optimizer.md) teaches it properly).

```sql postgres
EXPLAIN (COSTS OFF)
SELECT * FROM big_orders WHERE customer_id = 7;
```

```text output
         QUERY PLAN
-----------------------------
 Seq Scan on big_orders
   Filter: (customer_id = 7)
(2 rows)
```

`Seq Scan` means it reads the whole table. Now add an index:

```sql postgres
CREATE INDEX big_orders_cust_idx ON big_orders (customer_id);

EXPLAIN (COSTS OFF)
SELECT * FROM big_orders WHERE customer_id = 7;
```

```text output
CREATE INDEX
                   QUERY PLAN
------------------------------------------------
 Bitmap Heap Scan on big_orders
   Recheck Cond: (customer_id = 7)
   ->  Bitmap Index Scan on big_orders_cust_idx
         Index Cond: (customer_id = 7)
(4 rows)
```

The filter became an index condition. `DROP INDEX` takes only the index name on Oracle and PostgreSQL. MySQL and SQL Server also need `ON table`.

### What an index costs

- Storage
- Extra work on every `INSERT` and `DELETE`, and on `UPDATE` of an indexed column

You trade slower writes for faster reads.

### Index vs key

A **key** is a logical rule, and an **index** is a physical structure. `PRIMARY KEY` and `UNIQUE` create a unique index automatically.

**Does a foreign key get an index automatically?** Not on Oracle, PostgreSQL or SQL Server. InnoDB does create one. Without an index, joins are slow, and deleting a parent row must scan the child table, and on Oracle it can also cause locking problems ([Chapter 33](33-locks-deadlocks-and-mvcc.md)). Index your foreign keys.

## Dense and sparse indexes

| | Dense | Sparse |
|---|---|---|
| Entries | One for every search key value | Only some, usually one per block |
| Needs a sorted file | No | Yes |
| Size | Larger | Smaller |

To look up a value in a sparse index, find the largest entry not above the target, then scan forward from there.

**Must a hash index be dense? Can a tree index be sparse?** Hashing destroys order, so there is no nearby entry to start from, and a hash index must be dense. A tree index can be sparse when the file is sorted on its key.

**Terminology clash.** Silberschatz treats "primary index" and "clustering index" as synonyms. Elmasri separates primary (on an ordering key), clustering (on an ordering non-key) and secondary. Say which you mean.

## Index arithmetic

Exams love this. Here are the formulas:

```text
entry size       = key + pointer
entries per block = floor(block size / entry size)
index blocks      = ceil(entries / entries per block)
binary search     = ceil(log2(index blocks)) + 1 data block
```

**Worked example.** 25,000 fixed-length 100-byte records, a 15-byte primary key, 1024-byte blocks, and 5-byte block pointers.

```text
Data file
  Records per block: floor(1024 / 100) = 10
  Data blocks:       25000 / 10 = 2500
  Binary search on the data: ceil(log2 2500) = 12 accesses

One-level sparse index (one entry per data block)
  Entry size:        15 + 5 = 20 bytes
  Entries per block: floor(1024 / 20) = 51
  Index blocks:      ceil(2500 / 51) = 50
  Accesses:          ceil(log2 50) + 1 = 6 + 1 = 7

Multilevel index
  Second level over those 50 blocks: ceil(50 / 51) = 1 block
  Accesses: 2 index levels + 1 data block = 3
```

A **multilevel index** builds a sparse outer index over the inner index, and repeats until one block remains. Each level divides by the **fan-out**, the number of entries per block.

## B+ trees

Almost every database index is a **B+ tree**: a balanced tree of page-sized nodes.

```text
                [ 30 | 60 ]                      root
              /      |      \
      [10|20]     [40|50]     [70|80]            internal nodes (signposts)
      /  |  \     /  |  \     /  |  \
    leaves ->  leaves  ->  leaves                linked, in key order
```

- All leaves sit at the same depth.
- Internal keys only guide the search.
- Leaves hold the entries, and are linked in key order.

**B-tree vs B+ tree.** A B+ tree keeps data only in leaves, repeats keys in internal nodes, and links the leaves. That gains fan-out and cheap range scans. A classic B-tree can stop early at an internal node, but it has lower fan-out. What databases call a "B-tree index" is really a B+ tree.

**Why not a binary search tree or a hash table?** About 4 node reads find one of a million keys with 100 pointers per node, against about 20 for a balanced binary tree, because each node is a whole page with many children. Hash indexes cannot do ranges, ordering or prefix search.

### Walking through a lookup

**How does an index speed up a query?**

1. **Tree traversal:** go from the root to a leaf. This is usually 3 or 4 levels.
2. **Leaf chain walk:** read along the leaves for all matches.
3. **Table fetches:** get each row.

Only step 1 is bounded by tree depth. So a lookup can be slow with a perfectly healthy index, when it touches many leaves or rows.

### Node capacity and height

"Order" differs by book: maximum pointers n (Silberschatz), d with d to 2d keys (Berkeley), or m-way (CMU). Use the definition in the question.

Non-root nodes stay at least half full. The root needs only 2 children when it is not a leaf.

**Worked example.** 4 KB blocks, 12-byte keys, 8-byte pointers, one million records.

```text
Internal node: n pointers and (n - 1) keys
  8n + 12(n - 1) <= 4096
  20n <= 4108
  n = 205

Leaf: m (key, pointer) pairs and one next-leaf pointer
  20m + 8 <= 4096
  m = 204

Best case, with every node full
  Leaves:         ceil(1000000 / 204) = 4902
  Level above:    ceil(4902 / 205) = 24
  Root:           1
  3 levels, plus 1 data block = 4 disk accesses
```

### Inserts and deletes

**Insert:** find the leaf and add the key. A full **leaf** splits, and its separator is **copied** up, because the leaf must keep every key. A full **internal** node splits, and its middle key is **pushed** up, because a signpost is needed only once. Only a root split makes the tree taller.

**Delete:** remove the key, then borrow from a sibling or merge if the node is under-full.

**Can a key appear in an internal node but not in any leaf?** Yes. A deleted key's separator can stay behind as a signpost.

## Clustered and non-clustered indexes

In a **clustered** index, the table rows follow index order, so a range scan costs about 1 I/O per page. In an **unclustered** index, matching rows are scattered, so it costs about 1 I/O per row. A table has at most one clustered order, because rows can be stored in only one order.

| Engine | Table storage | A secondary index points at |
|---|---|---|
| InnoDB | Always the primary key B+ tree | The primary key, so a lookup walks two trees |
| SQL Server | Clustered index optional | Clustering key, or a row id on a heap |
| Oracle | Heap by default. Index-organized tables are optional | `ROWID` |
| PostgreSQL | Always a heap. `CLUSTER` reorders once and is not maintained | `ctid` |

**Why can a random UUID primary key slow down inserts?** On InnoDB and SQL Server, the table is ordered by that key. An ever-increasing key appends at the right edge. A random key lands all over the tree, splitting pages and wasting cache. Use a time-ordered id such as UUIDv7.

## Composite indexes

A **composite index** covers several columns, in **lexicographic** order: sorted by the first column, then by the second within it, like a phone book sorted by last name, then first name.

### The leftmost-prefix rule

An index on `(a, b)` serves `a`, and `a` + `b`, but not `b` alone. Finding every "John" in a phone book means reading the whole book.

| Condition, index on (a, b) | Use |
|---|---|
| `a = 1` | Clean range |
| `b = 2` | Cannot seek |
| `a = 1 AND b > 2` | Efficient: both narrow the range |
| `a > 1 AND b = 2` | Seek on `a`. `b` is only a filter |

| Condition, index on (a, b, c) | Use |
|---|---|
| `a = 1` | Clean range |
| `b = 2` | Cannot seek |
| `a = 1 AND c = 3` | Seek on `a`. `c` is only a filter |
| `a > 1 AND b = 2` | Seek on `a`. `b` is only a filter |

An **access predicate** narrows the leaf range. A **filter predicate** is checked on entries inside that range. A range on an earlier column turns later columns into filters.

```sql postgres
CREATE INDEX big_orders_cust_date_idx ON big_orders (customer_id, order_date);

EXPLAIN (COSTS OFF)
SELECT order_id FROM big_orders
WHERE customer_id = 7 AND order_date >= DATE '2024-06-01';
```

```text output
CREATE INDEX
                                   QUERY PLAN
--------------------------------------------------------------------------------
 Bitmap Heap Scan on big_orders
   Recheck Cond: ((customer_id = 7) AND (order_date >= '2024-06-01'::date))
   ->  Bitmap Index Scan on big_orders_cust_date_idx
         Index Cond: ((customer_id = 7) AND (order_date >= '2024-06-01'::date))
(4 rows)
```

### Which column goes first?

**Equality columns first, then the range column.** The popular rule "put the most selective column first" is a myth. Order is decided by which queries can use the leading prefix, and by equality versus range.

**One composite index or two single-column indexes?** A composite index serves the `AND` directly. Two separate indexes must be combined at run time, which is usually slower. Pick the composite for a query that filters both columns together. Keep singles when each column is queried alone.

**Exceptions to the rule.** Oracle `INDEX SKIP SCAN` (9i), MySQL skip scan (8.0.13) and PostgreSQL skip scan (18) can use an index without its leading column. They help only when that column has few distinct values.

**An index can replace a sort.** `(a, d)` lets `WHERE a = ? ORDER BY d DESC` finish without sorting. A B-tree can be read backward, so `(a ASC, b ASC)` serves `a DESC, b DESC`, but mixed directions need a matching index.

## Covering indexes

When the index holds every column the query needs, the table fetch disappears. On PostgreSQL this needs one more step, explained below, so we run `VACUUM` first.

```sql postgres
VACUUM big_orders;

EXPLAIN (COSTS OFF)
SELECT customer_id, order_date FROM big_orders WHERE customer_id = 7;
```

```text output
VACUUM
                          QUERY PLAN
--------------------------------------------------------------
 Index Only Scan using big_orders_cust_date_idx on big_orders
   Index Cond: (customer_id = 7)
(2 rows)
```

Adding one column outside the index forces table access again. PostgreSQL 11 and SQL Server have `INCLUDE` columns for this. On Oracle and MySQL, you add them as key columns.

**What does a PostgreSQL index-only scan need beyond the columns?** The visibility map must mark the page all-visible, because the index holds no row visibility data ([Chapter 33](33-locks-deadlocks-and-mvcc.md)). High `Heap Fetches` point to recent churn or missing vacuum, not a broken index.

## SARGable queries

**SARGable** means a condition can use an index seek, because the indexed column stands alone on one side.

A function or arithmetic on the column disables a plain index. Adding zero changes nothing logically, yet the index can no longer be used:

```sql postgres
EXPLAIN (COSTS OFF)
SELECT order_id FROM big_orders
WHERE customer_id + 0 = 7;
```

```text output
            QUERY PLAN
-----------------------------------
 Seq Scan on big_orders
   Filter: ((customer_id + 0) = 7)
(2 rows)
```

| Not SARGable | SARGable rewrite |
|---|---|
| `WHERE YEAR(order_date) = 2025` | `WHERE order_date >= DATE '2025-01-01' AND order_date < DATE '2026-01-01'` |
| `WHERE salary * 12 > 120000` | `WHERE salary > 10000` |
| `WHERE TRUNC(created_at) = d` | `WHERE created_at >= d AND created_at < d + 1` |
| `WHERE ISNULL(col, 0) = 0` | `WHERE col = 0 OR col IS NULL` |

**Implicit conversion** does the same thing, silently. Oracle turns `varchar_col = 123` into `TO_NUMBER(varchar_col) = 123` ([Chapter 5](../part-1-foundations/05-data-types-and-null.md)).

**`LIKE`:** `'abc%'` can range scan, and `'%abc'` cannot. **How would you make `LIKE '%smith'` fast?** Use `pg_trgm` with a GIN index on PostgreSQL, Oracle Text, or an index on the reversed string.

`OR`, `NOT`, `<>` and `NOT IN` rarely give a tight range. `OR` across columns may become a bitmap OR, or a hand-written `UNION ALL`.

### NULLs in indexes

Oracle B-tree indexes do not store rows whose key columns are all NULL. So `IS NULL` cannot use a single-column index on a nullable column. **How do you find NULLs quickly on Oracle?** Add a constant second column: `CREATE INDEX i ON t (col, 0)`. PostgreSQL indexes do store NULLs.

## Function-based and partial indexes

**Expression indexes** make a function SARGable. The query must use the same expression, and the function must be `DETERMINISTIC` (Oracle) or `IMMUTABLE` (PostgreSQL).

```sql postgres
CREATE INDEX big_orders_year_idx ON big_orders ((EXTRACT(YEAR FROM order_date)));
```

**Partial indexes** cover only some rows, so they are small and cheap to maintain. PostgreSQL has `CREATE INDEX ... WHERE`, and SQL Server has filtered indexes. They are ideal when you query a small slice.

```sql postgres
CREATE INDEX big_orders_pending_idx ON big_orders (order_date) WHERE status = 'PENDING';

EXPLAIN (COSTS OFF)
SELECT order_id FROM big_orders
WHERE status = 'PENDING' AND order_date = DATE '2024-03-01';
```

```text output
CREATE INDEX
                                     QUERY PLAN
------------------------------------------------------------------------------------
 Bitmap Heap Scan on big_orders
   Recheck Cond: ((order_date = '2024-03-01'::date) AND (status = 'PENDING'::text))
   ->  Bitmap Index Scan on big_orders_pending_idx
         Index Cond: (order_date = '2024-03-01'::date)
(4 rows)
```

A partial unique index enforces rules such as "one active row per user".

## When is an index ignored?

**An index exists, but the plan shows a full scan.** Here is the checklist:

- Low selectivity: the condition matches much of the table
- A small table
- Stale statistics, the summary numbers the optimizer keeps
- A function-wrapped column
- The wrong leading column
- A type mismatch
- `SELECT *` on many rows, where table fetches outweigh a scan
- `LIKE '%abc'`, `<>`, or `OR` across columns

**Clustering factor (Oracle) and correlation (PostgreSQL).** Two indexes with the same selectivity can have very different costs, depending on how well the table's physical order matches the index.

## Other index types

| Type | Good for | Not for |
|---|---|---|
| **Hash** | Equality | Ranges, sorting, prefixes |
| **Bitmap** (Oracle) | Low-cardinality, read-mostly columns | OLTP writes |
| **GIN** (PostgreSQL) | Arrays, `jsonb`, full text | Heavy writes |
| **GiST, SP-GiST** | Ranges, geometry, nearest neighbor | |
| **BRIN** | Huge tables whose values follow physical order | Random values |

**When would you use a bitmap index, and why not in OLTP?** A bitmap index has one bit per row for each distinct value, so `AND` and `OR` of bitmaps are very fast. It suits a column like `status` in a warehouse. But one row's DML locks a whole range of rows, so concurrent writers block each other.

A PostgreSQL `Bitmap Heap Scan` is a run-time structure, not a bitmap index.

**PostgreSQL index for each job:** a range on a timestamp uses a B-tree. `jsonb` containment uses GIN. Overlapping ranges use GiST. An append-only time column on a huge table uses BRIN.

### Hashing, for exams

**Static hashing** has a fixed number of buckets, and degrades as overflow chains grow.

**Extendible hashing** has a directory of 2^(global depth) pointers to buckets. A full bucket splits, and **the directory doubles only if that bucket's local depth equals the global depth**.

### Bloom filters and LSM trees

A **Bloom filter** is a bit array set by several hash functions. It has **no false negatives**, and can have false positives. More hash functions do not always help, because each one also sets more bits.

An **LSM tree** sends writes to an in-memory tree, then flushes them to immutable sorted runs, which compaction merges. Writes are sequential and fast. Reads may check several runs, using Bloom filters to skip them. Prefer it for write-heavy loads (Cassandra, RocksDB).

## Managing indexes

**How many indexes are too many?** There is no fixed number, only read benefit against write cost. Find unused ones with `pg_stat_user_indexes` on PostgreSQL, or index usage monitoring on Oracle.

**Testing a removal safely.** Oracle (11g) and MySQL (8.0) have **invisible indexes**: still maintained, but ignored by the optimizer.

**Do indexes need routine rebuilds?** That is a myth. B-trees stay balanced. A rebuild helps after mass deletes or real bloat.

**How do you add an index to a busy table without blocking writes?** A plain PostgreSQL `CREATE INDEX` blocks writes. `CREATE INDEX CONCURRENTLY` does not, but it cannot run in a transaction block, and a failed build leaves an `INVALID` index that still costs writes, so drop it and retry. Oracle has `CREATE INDEX ... ONLINE`.

```sql postgres
DROP TABLE big_orders;
RESET max_parallel_workers_per_gather;
```

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Index everything | Writes slow down | Index for real queries |
| Forget foreign key indexes | Slow joins and deletes, and locking problems | Index them |
| Put the most selective column first by habit | The index does not fit the queries | Equality first, then range |
| Wrap a column in a function | The index cannot seek | Rewrite, or use an expression index |
| Compare text with a number | The column is converted | Match the types |
| Use a random UUID as a clustered key | Page splits everywhere | Use a time-ordered id |
| Build an index on a busy table without `CONCURRENTLY` | Writes block | Use `CONCURRENTLY` or `ONLINE` |
| Use bitmap indexes in OLTP | Writers block each other | Use B-trees |
| Rebuild indexes on a schedule | Wasted work | Rebuild only for real bloat |

## Interview questions

**Q1. How does an index speed up a query? Walk me through a B-tree lookup.**

The database starts at the root and follows keys down to a leaf, which is usually 3 or 4 page reads, even with millions of rows. It then walks the linked leaves for all matches, and fetches each row from the table. Only the first step is bounded by depth, so touching many rows can still be slow.

**Q2. What is the difference between a clustered and a non-clustered index? How many of each can a table have?**

A clustered index stores the table rows in index order, so there can be only one. A non-clustered index is a separate structure with pointers to rows, and there can be many. InnoDB always clusters on the primary key, SQL Server's clustering is optional, and Oracle and PostgreSQL use heaps by default.

**Q3. Why do databases use B+ trees rather than binary search trees or hash tables?**

Each node is a whole page with hundreds of children, so the tree stays very shallow, which means few disk reads. Binary trees are much deeper. Hash tables cannot do ranges, sorting or prefix searches.

**Q4. What is the difference between a B-tree and a B+ tree?**

A B+ tree keeps data only in leaves, repeats keys in internal nodes, and links the leaves. That gives higher fan-out and cheap range scans. A classic B-tree stores data in internal nodes too.

**Q5. During a B+ tree insert, which key is copied up and which is pushed up, and why?**

A leaf split copies the separator up, because the leaf must still hold every key. An internal split pushes the middle key up, because a signpost is needed only once.

**Q6. You have an index on (a, b). Which of these can use it well: a = 1, b = 2, a = 1 AND b > 2, a > 1 AND b = 2?**

`a = 1` is a clean range. `b = 2` cannot seek, because `a` is missing. `a = 1 AND b > 2` is efficient. `a > 1 AND b = 2` seeks on `a`, and checks `b` only as a filter.

**Q7. What is a covering index?**

An index holding every column a query needs, so that the table is not read at all. On PostgreSQL, an index-only scan also needs the page to be marked all-visible.

**Q8. What makes a query SARGable? Rewrite `WHERE YEAR(order_date) = 2025`.**

The indexed column must stand alone on one side. Functions, arithmetic and implicit conversions on the column break it. The rewrite is `order_date >= DATE '2025-01-01' AND order_date < DATE '2026-01-01'`.

**Q9. An index exists, but the plan shows a full scan. List the reasons.**

Low selectivity, a small table, stale statistics, a function around the column, the wrong leading column, a type mismatch, a leading wildcard, or `OR` across columns. Sometimes the full scan really is cheaper.

**Q10. When would you choose a hash index over a B+ tree?**

Only for pure equality lookups. It cannot do ranges, sorting or prefixes, so a B-tree is usually the better default. On PostgreSQL, hash indexes are crash safe from version 10.

**Q11. What is an LSM tree, and when would you prefer it over a B+ tree?**

Writes go to memory, then flush to immutable sorted files that compaction merges. It gives fast sequential writes, at the cost of slower reads and compaction work. I would prefer it for write-heavy workloads.

**Q12. How do you add an index to a busy production table without blocking writes? What happens if it fails halfway?**

On PostgreSQL, `CREATE INDEX CONCURRENTLY`. If it fails, it leaves an `INVALID` index that still costs writes, so I drop it and retry. On Oracle, `CREATE INDEX ... ONLINE`.

## Practice

**1. For `SELECT * FROM orders WHERE customer_id = ? AND status = ? ORDER BY order_date DESC`, what index would you create?**

<details>
<summary>Show solution</summary>

`(customer_id, status, order_date)`. The two equality columns come first, then the sort column. It finds the rows and avoids a sort, because a B-tree can be read backward.

</details>

**2. Rewrite these to be SARGable: `WHERE price * 1.2 > 120` and `WHERE UPPER(email) = 'A@X.COM'`.**

<details>
<summary>Show solution</summary>

`WHERE price > 100`. For the email, either store emails in one case, or create an expression index on `UPPER(email)`.

</details>

**3. Blocks are 2048 bytes, keys 10 bytes, pointers 6 bytes. How many entries fit in an index block?**

<details>
<summary>Show solution</summary>

`floor(2048 / 16) = 128`.

</details>

**4. Which is the better index for `WHERE a = 1 AND b BETWEEN 5 AND 9 AND c = 2`: `(a, b, c)` or `(a, c, b)`?**

<details>
<summary>Show solution</summary>

`(a, c, b)`. Equality columns come first, then the range. With `(a, b, c)`, the range on `b` turns `c` into a filter.

</details>

## Recap

- An index trades write speed and storage for read speed.
- B+ trees are shallow, so a lookup takes a few page reads.
- Foreign keys are usually not indexed automatically.
- A table has at most one clustered order.
- Leftmost prefix: `(a, b)` serves `a`, not `b` alone.
- Put equality columns first, then the range.
- A function around a column breaks index use.
- Covering indexes avoid the table entirely.

**Next:** [Chapter 30: Execution plans](30-execution-plans-and-the-optimizer.md)
