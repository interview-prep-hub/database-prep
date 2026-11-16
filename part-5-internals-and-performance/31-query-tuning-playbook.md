# 31. The Query Tuning Playbook

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 30](30-execution-plans-and-the-optimizer.md)

> **In one line:** Tuning is a loop: measure, find the biggest cost, change one thing, and measure again.

## What you will learn

- How to find the slow queries
- A step-by-step answer to "this query suddenly got slow"
- Keyset pagination, and why `OFFSET` gets slow
- The N+1 query problem
- How to delete 500 million rows from a live table
- Why PL/SQL gets slow, and how to fix it

## The tuning loop

1. Measure.
2. Find the biggest cost.
3. Change one thing.
4. Measure again.

Compare buffers as well as time, because a warm cache makes a second run look fast. Test on realistic volumes, because plans on small development data can differ completely.

## Finding the slow queries

**How do you find the slowest queries in production?**

| Engine | Tool |
|---|---|
| PostgreSQL | `pg_stat_statements`, `auto_explain` |
| MySQL | Slow query log |
| Oracle | `V$SQL`, AWR and ASH (Diagnostics Pack), or Statspack |
| SQL Server | Query Store |

Rank by **total time** (calls times average), not just the slowest single run. A 5 ms query called a million times can matter more than one 10-second report.

## "It took 2 seconds, and now it takes 40"

Work through this in order:

1. **Confirm it is the query,** and not a wait.
2. **Check for locks.** Is another session holding the row? ([Chapter 33](33-locks-deadlocks-and-mvcc.md))
3. **Check whether the plan changed.**
4. **Check statistics.** Did a load make them stale?
5. **Check data growth and skew.**
6. **Check system load:** CPU, I/O, connection pool.
7. **Check what was deployed.**
8. **Fix the cause,** and measure.

### Wait events

A session's time is either working or waiting, and wait events name the wait.

| Oracle wait event | Meaning |
|---|---|
| `db file sequential read` | A single-block read, usually an index or a fetch by rowid, despite the name |
| `db file scattered read` | A multi-block read, usually a full scan |
| `log file sync` | Waiting for `COMMIT` to reach the redo log |
| `enq: TX - row lock contention` | Waiting on a row lock |

## The standard fixes

**Select only what you need.** `SELECT *` blocks covering indexes, fetches large columns, and sends more over the network.

**Filter early, and aggregate before joining.** A careless join to `payments` counts order 1003 twice ([Chapter 11](../part-2-sql-basics/11-joins.md)).

**Make predicates SARGable** ([Chapter 29](29-indexes.md)): no function on the column, matching types, and half-open ranges.

**Choose better query shapes:**

- `EXISTS` instead of a join that needs `DISTINCT`
- `UNION ALL` instead of `UNION`
- A join or window function instead of a correlated subquery that runs per row

### The smart logic anti-pattern

```sql norun
WHERE (:name IS NULL OR name = :name)
  AND (:city IS NULL OR city = :city)
```

A cached generic plan must work for every case, so it usually does a full scan. The fix is dynamic SQL that adds only the active predicates, still with binds.

### The PostgreSQL LIMIT trap

With `ORDER BY ... LIMIT 1`, the planner may follow an ordered index, expecting matches early. If matches are rare, it walks most of the index. So `LIMIT 1` can be slower than `LIMIT 100`.

## Pagination

Here is a demo table.

```sql postgres
CREATE TABLE big_orders AS
SELECT g AS order_id,
       DATE '2024-01-01' + MOD(g, 365) AS order_date
FROM generate_series(1, 100000) AS g;

CREATE INDEX big_orders_page_idx ON big_orders (order_date DESC, order_id DESC);
ANALYZE big_orders;
SET max_parallel_workers_per_gather = 0;
```

### Why is OFFSET slow?

`OFFSET` computes the skipped rows, and throws them away.

```sql postgres
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF, BUFFERS OFF)
SELECT order_id FROM big_orders
ORDER BY order_date DESC, order_id DESC
LIMIT 3 OFFSET 50000;
```

```text output nocheck
                                          QUERY PLAN
----------------------------------------------------------------------------------------------
 Limit (actual rows=3.00 loops=1)
   ->  Index Only Scan using big_orders_page_idx on big_orders (actual rows=50003.00 loops=1)
         Heap Fetches: 50003
         Index Searches: 1
(4 rows)
```

The index scan read 50,003 rows to return 3. Also, rows inserted during browsing shift the pages, so users see repeats or gaps.

### Keyset pagination

Seek from the last row seen, with a unique tie-breaker and a matching index.

```sql postgres
-- PostgreSQL
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF, BUFFERS OFF)
SELECT order_id FROM big_orders
WHERE (order_date, order_id) < (DATE '2024-07-01', 50000)
ORDER BY order_date DESC, order_id DESC
LIMIT 3;
```

```text output nocheck
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Limit (actual rows=3.00 loops=1)
   ->  Index Only Scan using big_orders_page_idx on big_orders (actual rows=3.00 loops=1)
         Index Cond: (ROW(order_date, order_id) < ROW('2024-07-01'::date, 50000))
         Heap Fetches: 3
         Index Searches: 1
(5 rows)
```

It read 3 rows. It is stable under inserts, but you cannot jump to an arbitrary page.

**Portability.** PostgreSQL row values can drive the index. Oracle rejects range comparison of row values (`ORA-01796`), so expand it:

```sql oracle since=12c
-- Oracle 12c or later
SELECT order_id, order_date
FROM orders
WHERE order_date < DATE '2024-03-01'
   OR (order_date = DATE '2024-03-01' AND order_id < 1007)
ORDER BY order_date DESC, order_id DESC
FETCH FIRST 3 ROWS ONLY;
```

**Paginating a billion-row table:** keyset for next and previous, no deep page jumps in the UI, and an approximate total from statistics, because `COUNT(*)` has to read rows.

```sql postgres
DROP TABLE big_orders;
RESET max_parallel_workers_per_gather;
```

## The N+1 query problem

One query loads a list, then lazy loading runs one more query per row. So 100 rows cost 101 queries.

```text
SELECT * FROM customers;                         -- 1 query, 8 rows
SELECT * FROM orders WHERE customer_id = 1;      -- then one per customer
SELECT * FROM orders WHERE customer_id = 2;
...                                              -- 9 queries in all
```

**How do you detect it?** SQL logs, ORM statistics, and a very high `calls` count in `pg_stat_statements` for one short query.

**How do you fix it?** Get everything in one query, or a batched one.

```sql
SELECT c.customer_name, COUNT(o.order_id) AS orders
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id;
```

```text output
 customer_name | orders
---------------+--------
 Alice Morgan  |      4
 Bilal Ahmed   |      3
 Chloe Martin  |      3
 David Lee     |      2
 Fatima Noor   |      2
 George Hall   |      2
 Hana Sato     |      0
 Ivan Novak    |      0
(8 rows)
```

In ORM terms: `JOIN FETCH`, an entity graph, batch size, or subselect fetching. `EAGER` is not a fix. `JOIN FETCH` has limits with pagination and multiple collections.

## Bulk writes

Use set-based or batched statements, not row by row. Commit per batch, not per row, because each commit waits for the log ([Chapter 34](34-backup-and-recovery.md)).

### Deleting 500 million rows from a live table

Never in one giant transaction. Choose by how much remains:

| Situation | Approach |
|---|---|
| Data is partitioned that way | Drop the partition. Instant |
| Most rows go | Copy the rows to keep into a new table, and swap |
| Some rows go | Delete in small batches, with pauses |

```sql norun
DELETE FROM events
WHERE event_id IN (SELECT event_id FROM events
                   WHERE created_at < DATE '2020-01-01'
                   ORDER BY event_id
                   LIMIT 10000);
COMMIT;
-- repeat until no rows are deleted
```

Batches keep undo, locks and replica lag small. On PostgreSQL, watch for bloat, and let `VACUUM` keep up.

## Views and materialized views for tuning

**A plain view is not a performance feature.** It only stores the query. Stacked views hide joins, and can defeat the optimizer. Check the real plan.

**Can we still use a view if the original table is deleted?** No. On Oracle, the view stays but is invalid, and querying it fails until the table returns. PostgreSQL refuses `DROP TABLE` unless you add `CASCADE`, which drops the view too.

**`REFRESH MATERIALIZED VIEW CONCURRENTLY`** builds a new result, compares it with the old, and applies the differences, so readers are not blocked. It needs a unique index, and the view must already be populated.

**Oracle fast refresh** needs materialized view logs on the base tables. Aggregates need `COUNT(*)` and `COUNT(expr)`. `DBMS_MVIEW.EXPLAIN_MVIEW` tells you why fast refresh is not possible. `ON COMMIT` adds work to every commit, so it hurts on busy tables.

**When is a materialized view the wrong tool?** When readers need current data, when base tables change constantly, or when an index would solve it.

## Where to fix a problem

Try the cheapest correct fix first.

| Symptom | Tool |
|---|---|
| Wrong plan, bad estimate | Statistics |
| Full scan on a selective filter | Index |
| Function on a column | Rewrite, or an expression index |
| Slow join with repeats | Rewrite the query |
| Expensive report, read often | Materialized view |
| Huge table, time-based queries | Partitioning |
| Same reads over and over | Cache |
| Read load too high | Read replica |
| CPU or I/O maxed after all of this | Hardware |

## Tuning PL/SQL

**A PL/SQL procedure runs slowly. How do you find the cause?** The most common cause of slow PL/SQL is slow SQL. So start with indexes, `DBMS_STATS` statistics, `EXPLAIN PLAN`, and SQL Trace with TKPROF. Use `DBMS_APPLICATION_INFO` to see what is running.

### Row by row vs set-based

Each row in a loop means a switch between the PL/SQL and SQL engines.

```sql oracle
-- Slow: one UPDATE per row
BEGIN
  FOR r IN (SELECT emp_id FROM employees WHERE dept_id = 20) LOOP
    UPDATE employees SET salary = salary * 1.05 WHERE emp_id = r.emp_id;
  END LOOP;
  ROLLBACK;
END;
/

-- Fast: one statement
UPDATE employees SET salary = salary * 1.05 WHERE dept_id = 20;
ROLLBACK;
```

When a loop is truly needed, `BULK COLLECT` with `LIMIT` and `FORALL` cut those switches ([Chapter 50](../part-7-plsql/50-bulk-processing.md)).

### Functions in SQL

**What does calling a PL/SQL function inside a query cost?** It can run once per row, each with a switch between the engines, and in `WHERE` it blocks a normal index. Reduce it with a function-based index, or with scalar subquery caching:

```sql oracle
SELECT e.first_name,
       (SELECT get_rate(e.dept_id) FROM dual) AS rate
FROM employees e;
```

Oracle caches results of a scalar subquery by input value, so the function runs once per distinct `dept_id`. `DETERMINISTIC` and the result cache also help ([Chapter 53](../part-7-plsql/53-plsql-performance-and-best-practices.md)).

### Bind variables in PL/SQL

Static SQL binds variables automatically. Concatenated dynamic SQL does not, and each new literal forces a hard parse. Use `EXECUTE IMMEDIATE ... USING`.

### PL/SQL memory

**How does PL/SQL manage memory for large collections?**

| Memory | Holds | Error when full |
|---|---|---|
| Shared pool | Code | `ORA-04031` |
| Session memory | Package state, collections | `ORA-04030`, `ORA-04036` |

An unbounded `BULK COLLECT` is the classic cause. Always use `LIMIT`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Tune without measuring | You fix the wrong thing | Find the biggest cost first |
| Change several things at once | You cannot tell what helped | Change one thing |
| Test on tiny data | Plans differ in production | Use realistic volumes |
| Compare time on a warm cache | The second run looks fast | Compare buffers |
| Use `OFFSET` for deep pages | They get slower and slower | Use keyset pagination |
| Lazy-load in a loop | N+1 queries | Join, or batch |
| Delete millions in one transaction | Undo, locks and replica lag | Batch, or drop a partition |
| Blame PL/SQL first | The SQL is usually the cause | Tune the SQL first |
| Fetch everything with `BULK COLLECT` | Memory runs out | Use `LIMIT` |

## Interview questions

**Q1. How do you find the slowest queries in a production database?**

On PostgreSQL, `pg_stat_statements`. On Oracle, AWR or `V$SQL`. On MySQL, the slow query log. On SQL Server, Query Store. I rank by total time, so that frequent small queries are not missed.

**Q2. A dashboard query that took 2 seconds now takes 40. How do you debug it?**

First confirm it is the query, and not a wait or a lock. Then check whether the plan changed, whether statistics are stale, and whether data grew. I compare the current plan with an old one, looking at estimated and actual rows. Then I fix the cause, and measure.

**Q3. Explain the wait events db file sequential read, db file scattered read and log file sync.**

Sequential read is a single-block read, usually through an index. Scattered read is a multi-block read, usually a full scan. Log file sync is waiting for a commit to reach the redo log, so it points at commit rate or slow log disks.

**Q4. Why is OFFSET 1000000 slow, and how would you paginate a billion-row table?**

`OFFSET` still reads and discards every skipped row. I would use keyset pagination: seek from the last seen key, with a unique tie-breaker and a matching index. No deep page jumps, and approximate totals from statistics.

**Q5. What is the N+1 query problem, how do you detect it, and how do you fix it?**

One query loads a list, and then one more query runs per row. I detect it in SQL logs, or from a very high call count on one short query. I fix it with a join, a batched `IN`, or `JOIN FETCH` in an ORM.

**Q6. How do you delete 500 million rows from a live table?**

Never in one transaction. If the data is partitioned, I drop partitions. If most rows go, I copy the keepers and swap. Otherwise I delete in small batches, committing each one, and watch replica lag and bloat.

**Q7. What is the difference between a view and a materialized view? Does a view make a query faster?**

A view stores the query, and a materialized view stores the result. A plain view does not make anything faster. A materialized view can, at the cost of staleness and refresh work.

**Q8. A PL/SQL procedure runs slowly. How do you find the cause and fix it?**

Usually it is the SQL inside. I trace it with TKPROF or look at `V$SQL`, tune the worst statements, replace row-by-row loops with set-based SQL, and use `BULK COLLECT` and `FORALL` when a loop is needed.

**Q9. What does calling a PL/SQL function inside a query cost, and how do you reduce it?**

A switch between the SQL and PL/SQL engines per row, and in `WHERE` it blocks a normal index. I reduce it with a function-based index, scalar subquery caching, `DETERMINISTIC`, or the result cache, or by rewriting it as a join.

## Practice

**1. Rewrite this as a keyset query for Oracle, after a page ending at (2024-03-03, 1007): `ORDER BY order_date DESC, order_id DESC OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY`.**

<details>
<summary>Show solution</summary>

```sql oracle since=12c
-- Oracle 12c or later
SELECT order_id, order_date
FROM orders
WHERE order_date < DATE '2024-03-03'
   OR (order_date = DATE '2024-03-03' AND order_id < 1007)
ORDER BY order_date DESC, order_id DESC
FETCH FIRST 5 ROWS ONLY;
```

</details>

**2. An application shows 50 orders, each with its customer's name, and runs 51 queries. What is this, and what is the fix?**

<details>
<summary>Show solution</summary>

The N+1 problem. Fix it with one join between `orders` and `customers`, or by loading the customers with a single `WHERE customer_id IN (...)`.

</details>

**3. A nightly job updates 2 million rows, with a `COMMIT` after each. It is very slow. Why?**

<details>
<summary>Show solution</summary>

Each `COMMIT` waits for the log to reach disk. Commit every few thousand rows instead, or use one set-based `UPDATE`.

</details>

## Recap

- Measure, change one thing, and measure again.
- Rank queries by total time.
- For "suddenly slow", check waits and locks, the plan, statistics, then data growth.
- `OFFSET` reads what it skips. Keyset seeks.
- N+1 means one query per row. Join, or batch.
- Delete in batches, or drop a partition.
- A plain view is not a performance feature.
- Slow PL/SQL usually means slow SQL.

**Next:** [Chapter 32: Transactions and isolation](32-transactions-and-isolation.md)
