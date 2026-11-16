# 36. Partitioning: Splitting a Big Table

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 29](../part-5-internals-and-performance/29-indexes.md)

> **In one line:** Partitioning stores one logical table as many smaller physical pieces on one server, while queries still name one table.

**About the demos:** the demos in this chapter use PostgreSQL, so not all of their syntax runs on Oracle. Oracle commands are shown where they differ.

## What you will learn

- Partitioning vs sharding vs replication
- Range, list and hash partitioning
- Partition pruning, and why partitioned tables can get slower
- The primary key rule
- Local vs global indexes
- How to run a rolling window

## What is partitioning?

One logical table, stored as many smaller physical pieces, on one server.

**What is the difference between sharding and partitioning?**

| | Partitioning | Sharding | Replication |
|---|---|---|---|
| Splits | A table, on one server | Data, across servers | Nothing: whole copies |
| Gives | Manageability, pruning | Write scale, size | Read scale, availability |
| Gives up | Simple keys | Joins, simple transactions | Some freshness |

**Horizontal** partitioning splits rows. **Vertical** partitioning splits columns, such as moving a large, rarely read column to a side table.

## Why partition?

Strongest reason first:

1. **Retention:** drop a whole partition instead of a bulk `DELETE`.
2. **Per-partition maintenance.**
3. **Partition pruning** for queries on the key.

It is **not** a general speed-up. An index on a single row is usually faster.

## Methods

**Range partitioning, by date, on PostgreSQL:**

```sql postgres
CREATE TABLE sales (
  sale_id    INTEGER NOT NULL,
  sale_date  DATE NOT NULL,
  amount     NUMERIC(10,2)
) PARTITION BY RANGE (sale_date);

CREATE TABLE sales_2024_01 PARTITION OF sales
  FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE sales_2024_02 PARTITION OF sales
  FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

CREATE TABLE sales_default PARTITION OF sales DEFAULT;

INSERT INTO sales VALUES (1, DATE '2024-01-10', 100);
INSERT INTO sales VALUES (2, DATE '2024-02-10', 200);
INSERT INTO sales VALUES (3, DATE '2024-07-01', 300);

SELECT tableoid::regclass AS partition_name, sale_id
FROM sales
ORDER BY sale_id;
```

```text output
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
INSERT 0 1
INSERT 0 1
INSERT 0 1
 partition_name | sale_id
----------------+---------
 sales_2024_01  |       1
 sales_2024_02  |       2
 sales_default  |       3
(3 rows)
```

`FROM` is inclusive, and `TO` is exclusive. A row with no matching partition raises an error, unless a `DEFAULT` partition exists.

**On Oracle:**

```sql oracle
CREATE TABLE sales (
  sale_id    NUMBER NOT NULL,
  sale_date  DATE NOT NULL,
  amount     NUMBER(10,2)
)
PARTITION BY RANGE (sale_date) (
  PARTITION p2024_01 VALUES LESS THAN (DATE '2024-02-01'),
  PARTITION p2024_02 VALUES LESS THAN (DATE '2024-03-01'),
  PARTITION p_max    VALUES LESS THAN (MAXVALUE)
);
```

Oracle Partitioning is a separately licensed Enterprise Edition option, and **your XE 11g does not include it**.

| Method | Use it for | Prunes on |
|---|---|---|
| **Range** | Time series and retention | Equality and ranges on the key |
| **List** | Discrete groups, such as region | Equality on the key |
| **Hash** | An even spread, with no natural range | Equality on the key |
| **Composite** | Range, then hash | Both |

**Round-robin** deals rows to partitions in turn, as some parallel warehouses do. It spreads rows evenly, but nothing prunes.

**Range, hash or round-robin: which would you choose?** Range when queries and retention are by time. Hash for even spread with equality lookups. Round-robin only for scans that read everything.

## Partition pruning

**What is partition pruning, and when does it fail to happen?** The engine skips partitions that cannot match.

```sql postgres
EXPLAIN (COSTS OFF)
SELECT * FROM sales WHERE sale_date = DATE '2024-02-10';
```

```text output
                 QUERY PLAN
--------------------------------------------
 Seq Scan on sales_2024_02 sales
   Filter: (sale_date = '2024-02-10'::date)
(2 rows)
```

Only one partition is scanned. A function around the key stops it:

```sql postgres
EXPLAIN (COSTS OFF)
SELECT * FROM sales WHERE EXTRACT(MONTH FROM sale_date) = 2;
```

```text output
                           QUERY PLAN
----------------------------------------------------------------
 Append
   ->  Seq Scan on sales_2024_01 sales_1
         Filter: (EXTRACT(month FROM sale_date) = '2'::numeric)
   ->  Seq Scan on sales_2024_02 sales_2
         Filter: (EXTRACT(month FROM sale_date) = '2'::numeric)
   ->  Seq Scan on sales_default sales_3
         Filter: (EXTRACT(month FROM sale_date) = '2'::numeric)
(7 rows)
```

Every partition is scanned. The filter must be on the partition key, in a comparable form.

**Plan-time vs execution-time.** Constants prune while planning, and bind values and subquery results prune at execution.

**On Oracle,** read the `Pstart` and `Pstop` columns of a plan, and `PARTITION RANGE SINGLE`, `ITERATOR` and `ALL`.

**We partitioned the table, and queries got slower. Why?** Without pruning, a query visits every partition, and probes every local index. More partitions also mean more planning.

## The primary key rule

PostgreSQL and MySQL require every primary and unique key to include the partition key, because each partition enforces uniqueness alone.

```sql postgres error=unique
ALTER TABLE sales ADD PRIMARY KEY (sale_id);
```

```text output
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  PRIMARY KEY constraint on table "sales" lacks column "sale_date" which is part of the partition key.
```

**What to do:** use `(sale_id, sale_date)` as the key, or add a small lookup table from `sale_id` to `sale_date`, or generate ids that are unique by design.

```sql postgres
ALTER TABLE sales ADD PRIMARY KEY (sale_id, sale_date);
DROP TABLE sales;
```

## Indexes on partitioned tables

| | Local index | Global index |
|---|---|---|
| Structure | One per partition | One across all partitions |
| Maintenance | Follows the table | Marked `UNUSABLE` by partition DDL |
| Uniqueness | Must include the key | Any column |

**In Oracle, local or global?** Local by default, for easy maintenance. Global only when you need uniqueness, or fast lookups, without the partition key.

**What happens to a global index when you drop a partition?** It is marked `UNUSABLE`, unless you say `UPDATE GLOBAL INDEXES`.

**PostgreSQL has no global indexes.** An index on the parent creates one on each partition.

## A rolling window

Create next month's partition ahead of time, then remove the oldest.

```sql norun
CREATE TABLE sales_2024_03 PARTITION OF sales
  FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

ALTER TABLE sales DETACH PARTITION sales_2024_01 CONCURRENTLY;
DROP TABLE sales_2024_01;
```

## Other things to know

**Oracle strategies:** **interval** creates partitions automatically, **reference** lets a child inherit its parent's partitioning, and **virtual column** partitions on an expression.

**Moving rows.** Updating the partition key moves the row. It is automatic on PostgreSQL 11 and later. Oracle needs `ENABLE ROW MOVEMENT`.

**Converting an existing table.** PostgreSQL cannot convert a plain table in place, so build a new one and copy, or attach the old table as a partition.

**A single table has grown too large. What are your options?** Work through them in order: fix the queries and indexes, archive old data, try a materialized view, then partition.

### Worked design: a 5 TB orders table, 13 months online

- Monthly range partitions on `order_date`.
- 13 online, pre-created by a job.
- The oldest detached, archived and dropped each month.
- Primary key `(order_id, order_date)`, plus a lookup table from `order_id` to `order_date`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Partition to speed up single-row lookups | It can slow them down | Use an index |
| Filter with a function on the key | No pruning | Compare the raw column |
| Forget a `DEFAULT` partition | Inserts fail | Add one, or pre-create |
| Create thousands of partitions | Planning gets slow | Keep the count reasonable |
| Drop an Oracle partition with a global index | It becomes `UNUSABLE` | `UPDATE GLOBAL INDEXES` |
| Expect a `UNIQUE (id)` on PostgreSQL | It needs the partition key | Include the key |

## Interview questions

**Q1. How are partitioning, sharding and replication different, and what does each give up?**

Partitioning splits a table on one server, and gives up simple unique keys. Sharding splits data across servers, and gives up easy joins and transactions. Replication copies everything, and gives up some freshness on replicas.

**Q2. What is partition pruning, and when does it fail to happen?**

The engine skips partitions that cannot match the filter. It fails when the filter is not on the partition key, or wraps the key in a function.

**Q3. A single table has grown too large and queries scan too much. Walk me through your options.**

Fix queries and indexes first. Then archive old rows. Then consider a materialized view for reports, and partitioning for retention and scans. Sharding is a last resort, for write volume.

**Q4. How would you partition a 5 TB orders table so we keep 13 months online? What happens to the primary key on order_id?**

Monthly range partitions, with a job that adds the next and drops the oldest. The primary key must include `order_date`, so I add a lookup table for `order_id` searches, or use a global index on Oracle.

**Q5. In Oracle, local or global index on a partitioned table? What happens to a global index when you drop a partition?**

Local by default. Global when I need uniqueness without the partition key. Dropping a partition marks a global index `UNUSABLE`, unless I use `UPDATE GLOBAL INDEXES`.

**Q6. We partitioned the table and queries got slower. Why?**

Queries that do not filter on the partition key now visit every partition, and probe many indexes, and planning takes longer.

## Practice

**1. An events table is queried by day, and kept for 90 days. How do you partition it?**

<details>
<summary>Show solution</summary>

Daily or weekly range partitions on the event date. Drop the oldest partition each day, which is instant, instead of a slow `DELETE`.

</details>

**2. Which filter can prune with range partitioning on `order_date`: `order_date >= DATE '2024-01-01'`, or `TO_CHAR(order_date, 'YYYY') = '2024'`?**

<details>
<summary>Show solution</summary>

The first. The second wraps the key in a function.

</details>

## Recap

- Partitioning is one table in many pieces, on one server.
- Its best use is retention.
- Pruning needs a filter on the key, in a comparable form.
- PostgreSQL and MySQL unique keys must include the partition key.
- Local indexes are the default. Global ones go `UNUSABLE`.
- Your XE 11g does not include partitioning.

**Next:** [Chapter 37: Replication and high availability](37-replication-and-high-availability.md)
