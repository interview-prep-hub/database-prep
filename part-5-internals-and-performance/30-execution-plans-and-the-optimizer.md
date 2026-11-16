# 30. Execution Plans and How the Optimizer Thinks

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 29](29-indexes.md)

> **In one line:** SQL says what you want, and the execution plan says how the engine will get it.

**About the demos:** the demos in this chapter use PostgreSQL, so not all of their syntax runs on Oracle. Oracle commands are shown where they differ.

## What you will learn

- How a query gets from text to a result
- How to read a plan on PostgreSQL and Oracle
- Nested loop, hash and merge joins, and when each wins
- What statistics are, and what happens when they are wrong
- Hard parses, bind variables and plan stability

## From SQL text to a result

```text
SQL text -> parse -> optimize -> execute -> rows

Parse:     check syntax and names, build a tree
Optimize:  rewrite the query, then choose the cheapest plan
Execute:   run the plan
```

A cost-based optimizer has three parts: a **query transformer**, an **estimator** and a **plan generator**. Selectivity gives **cardinality** (a row count), and cardinality gives **cost**. So a wrong row estimate usually means a wrong plan.

**What the transformer does:** view merging, predicate pushing and subquery unnesting. So the SQL you wrote is not always the SQL that runs.

**Pipelining vs materialization.** Most operators pass rows upward one at a time. Blocking operators, such as sort and hash build, must consume their whole input first. This is why `LIMIT` can stop a pipelined plan early.

## Getting a plan

| Engine | Command |
|---|---|
| PostgreSQL | `EXPLAIN` |
| Oracle | `EXPLAIN PLAN FOR ...`, then `SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)` |
| MySQL | `EXPLAIN` |
| SQL Server | Estimated or actual plan |

Here are two demo tables, large enough for plans to be interesting.

```sql postgres
CREATE TABLE big_customers AS
SELECT g AS customer_id, 'Customer ' || g AS name
FROM generate_series(0, 999) AS g;

CREATE TABLE big_orders AS
SELECT g AS order_id,
       MOD(g, 1000) AS customer_id,
       MOD(g, 500) * 1.5 AS amount
FROM generate_series(1, 100000) AS g;

ALTER TABLE big_customers ADD PRIMARY KEY (customer_id);
CREATE INDEX big_orders_cust_idx ON big_orders (customer_id);
ANALYZE big_customers;
ANALYZE big_orders;
SET max_parallel_workers_per_gather = 0;
```

### Reading a PostgreSQL plan line

```sql postgres
EXPLAIN
SELECT * FROM big_orders WHERE amount > 740;
```

```text output nocheck
                           QUERY PLAN
-----------------------------------------------------------------
 Seq Scan on big_orders  (cost=0.00..1826.00 rows=1122 width=13)
   Filter: (amount > '740'::numeric)
(2 rows)
```

- `cost=startup..total`: startup is the work before the first row. Costs are arbitrary units, not milliseconds, and they compare plans for the same statement only.
- `rows`: the rows this node **emits**, not the rows it scans.
- `width`: the average row size in bytes.

### EXPLAIN vs EXPLAIN ANALYZE

`EXPLAIN` predicts. `EXPLAIN ANALYZE` really runs the statement, and shows what happened.

**How would you run it safely on an UPDATE?** Wrap it in a transaction and roll back. Sequences and other side effects are not undone.

```sql postgres
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF, BUFFERS OFF)
UPDATE big_orders SET amount = 0 WHERE customer_id = 7;
ROLLBACK;
```

```text output nocheck
BEGIN
                                    QUERY PLAN
-----------------------------------------------------------------------------------
 Update on big_orders (actual rows=0.00 loops=1)
   ->  Bitmap Heap Scan on big_orders (actual rows=100.00 loops=1)
         Recheck Cond: (customer_id = 7)
         Heap Blocks: exact=100
         ->  Bitmap Index Scan on big_orders_cust_idx (actual rows=100.00 loops=1)
               Index Cond: (customer_id = 7)
               Index Searches: 1
(7 rows)

ROLLBACK
```

### How to read EXPLAIN ANALYZE

**A plan is a tree.** Children feed parents, and indentation shows nesting. Follow rows upward from the deepest nodes.

Check these, in order:

1. **Compare estimated and actual rows.** An order-of-magnitude gap points at stale statistics, skew or correlated columns, not a missing index.
2. **Find where the time goes.**
3. **Multiply by loops.** Actual time and rows are per-loop averages, especially on the inner side of a nested loop.
4. **Check buffers.** Reported automatically from PostgreSQL 18.
5. **Look for rows removed by a filter.**

### PostgreSQL scan nodes

| Node | Meaning |
|---|---|
| `Seq Scan` | Read the whole table |
| `Index Scan` | Use the index, then fetch rows |
| `Index Only Scan` | The index alone is enough |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | Collect matches, then visit pages in physical order, which softens random I/O |

## Oracle plans

```sql oracle
EXPLAIN PLAN FOR
SELECT e.first_name, d.dept_name
FROM employees e
JOIN departments d ON d.dept_id = e.dept_id
WHERE e.salary > 100000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

### What order do the steps run in?

**"Read it bottom to top" is a common wrong answer.** The rule is: begin at the first leaf, children feed parents, and in a join the first child is the driving or build input.

```text
------------------------------------------------------
| Id | Operation                    | Name            |
------------------------------------------------------
|  0 | SELECT STATEMENT             |                 |
|  1 |  HASH JOIN                   |                 |
|  2 |   TABLE ACCESS FULL          | DEPARTMENTS     |
|  3 |   TABLE ACCESS BY INDEX ROWID| EMPLOYEES       |
|* 4 |    INDEX RANGE SCAN          | EMP_SALARY_IDX  |
------------------------------------------------------

Execution order: 2, 4, 3, 1, 0
  2  Build a hash table from DEPARTMENTS
  4  Range scan the index for matching rowids
  3  Fetch those EMPLOYEES rows
  1  Probe the hash table with each row
  0  Return the result
```

**Oracle access paths:** `TABLE ACCESS FULL`, `TABLE ACCESS BY INDEX ROWID`, and `INDEX UNIQUE`, `RANGE`, `FULL`, `FAST FULL` and `SKIP SCAN`.

**Access and filter predicates.** Predicate Information shows `access()` and `filter()`. PostgreSQL shows `Index Cond`, `Filter` and `Rows Removed by Filter`.

### EXPLAIN PLAN can mislead

**What is the difference between `EXPLAIN PLAN` and `DBMS_XPLAN.DISPLAY_CURSOR`?** `EXPLAIN PLAN` shows what the optimizer *would* do, not what ran. Binds, session settings, adaptive plans and changed statistics can all differ. `DISPLAY_CURSOR` reads the real plan from the shared pool.

To see actual row counts, use the hint and format together:

```sql oracle
SELECT /*+ GATHER_PLAN_STATISTICS */ COUNT(*) FROM employees WHERE salary > 100000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
```

Read `Starts`, `E-Rows`, `A-Rows`, `A-Time` and `Buffers`. Compare `A-Rows` with `E-Rows` times `Starts`.

### MySQL and SQL Server in brief

**MySQL `EXPLAIN`:** the `type` ladder, from best to worst, is `const`, `eq_ref`, `ref`, `range`, `index`, `ALL`. `Using index` means covering. `Using index condition` means part of the `WHERE` is checked inside the index. `Using filesort` and `Using temporary` name the sorting and temp work, and neither proves a spill to disk.

**SQL Server:** look at seek vs scan, and Key Lookup vs RID Lookup.

## Join algorithms

### Nested loop

For each outer row, probe the inner input. Cost is outer rows times inner probe.

```sql postgres
EXPLAIN (COSTS OFF)
SELECT c.name, o.order_id
FROM big_customers c
JOIN big_orders o ON o.customer_id = c.customer_id
WHERE c.customer_id = 7;
```

```text output
                          QUERY PLAN
--------------------------------------------------------------
 Nested Loop
   ->  Index Scan using big_customers_pkey on big_customers c
         Index Cond: (customer_id = 7)
   ->  Bitmap Heap Scan on big_orders o
         Recheck Cond: (customer_id = 7)
         ->  Bitmap Index Scan on big_orders_cust_idx
               Index Cond: (customer_id = 7)
(7 rows)
```

Great for a small outer input with an indexed inner. Disastrous when a 1-row estimate is really a million.

### Hash join

Build a hash table on the smaller input, then probe it with the larger.

```sql postgres
EXPLAIN (COSTS OFF)
SELECT c.name, SUM(o.amount) AS total
FROM big_customers c
JOIN big_orders o ON o.customer_id = c.customer_id
GROUP BY c.name;
```

```text output
                     QUERY PLAN
----------------------------------------------------
 HashAggregate
   Group Key: c.name
   ->  Hash Join
         Hash Cond: (o.customer_id = c.customer_id)
         ->  Seq Scan on big_orders o
         ->  Hash
               ->  Seq Scan on big_customers c
(7 rows)
```

It needs an equality condition. It wins for big unsorted inputs.

### Sort-merge join

Both inputs are ordered on the key, then merged in one pass. It suits already-sorted inputs, and is usually beaten by a hash join when a sort is required. Oracle can use it for inequality joins.

| Join | Best when | Needs |
|---|---|---|
| Nested loop | Small outer, indexed inner | Any condition |
| Hash | Large, unsorted inputs | Equality |
| Sort-merge | Inputs already sorted | Sort order |

Oracle, PostgreSQL and SQL Server have all three. MySQL has nested loop and hash, but no sort-merge.

**Join order.** Rows after filtering matter more than table size. `FROM` order does not decide it in a cost-based optimizer. Outer joins constrain the order.

### Textbook join costs

Relation R has 1000 pages, S has 500 pages, and memory is 102 pages.

```text
Page nested loop, S outer:  500 + 500 x 1000 = 500,500 page reads
Block nested loop, S outer: 500 + ceil(500 / 100) x 1000 = 5,500
Grace hash join:            3 x (1000 + 500) = 4,500
```

Put the smaller relation on the outside. Hash needs equality, and skew hurts it.

## Sorting and grouping

**External merge sort** handles data larger than memory. With N pages and B buffers:

```text
Initial runs:  ceil(N / B)
Passes:        1 + ceil(log_(B-1)(ceil(N / B)))
Cost:          2N I/O per pass

N = 108, B = 5
Runs:    ceil(108 / 5) = 22
Passes:  1 + ceil(log_4 22) = 1 + 3 = 4
Cost:    2 x 108 x 4 = 864 page I/Os
```

**`GROUP BY`** uses hash aggregation or sorted aggregation. `DISTINCT` uses the same two tools.

**Spill indicators.** `Sort Method: external merge Disk` and `Hash Batches` above 1 on PostgreSQL mean a spill, so raise `work_mem`, or reduce rows. On Oracle, look for temp space use and `direct path read temp`.

## Statistics

**What statistics does the optimizer rely on?** Table row and page counts, and for each column, distinct counts, null fractions, min and max, common values and histograms.

| Engine | Where to see them | How to gather them |
|---|---|---|
| PostgreSQL | `pg_class`, `pg_stats` | `ANALYZE` |
| Oracle | `USER_TAB_STATISTICS`, `USER_TAB_COL_STATISTICS` | `DBMS_STATS` |

**What happens when they are wrong?** The optimizer picks the wrong plan.

### Selectivity estimates

| Condition | Selectivity |
|---|---|
| `A = c` | 1 / (distinct values of A) |
| `A > c` | (max - c) / (max - min) |
| `p AND q` | s1 x s2, assuming independence |
| `p OR q` | s1 + s2 - s1 x s2 |

**Worked example.** r(A, B) has 1200 tuples. A is uniform over 6 to 20, and B over 1 to 20, independently. Estimate the rows for `A > 10 AND B = 5`.

```text
A > 10:  values 11 to 20 of 6 to 20, so 10 of 15 = 2/3
B = 5:   1 of 20
Rows:    1200 x 2/3 x 1/20 = 40
```

### The independence assumption

Correlated columns, such as city and country, cause underestimates, because the optimizer multiplies selectivities that are not independent. Fix it with `CREATE STATISTICS` on PostgreSQL, or extended statistics on Oracle.

**Histograms** handle skew: when one value is far more common than others. Oracle has frequency, top-frequency and hybrid histograms. PostgreSQL has a most-common-values list plus a histogram.

**Stale statistics.** PostgreSQL autoanalyze runs at 50 rows plus 10 percent changed. Oracle considers statistics stale at 10 percent. Percentage thresholds react late on billion-row tables.

**Bulk loads need fresh statistics inside the job.** Autovacuum never analyzes temporary tables.

**Oracle `DBMS_STATS`** is the supported API, rather than `ANALYZE`. It can restore earlier statistics after a bad gather, and lock them.

## Join ordering

The number of join orders for n tables is (2(n-1))! / (n-1)!. For 7 tables, that is 665,280. So optimizers use dynamic programming, and consider left-deep plans (System R).

**Equivalence rules:** push selections and projections down. Outer joins are not associative in general.

## Hard parses and bind variables

A **hard parse** does full optimization. A **soft parse** reuses a shared cursor. Each new literal in SQL text means a new statement, so literals flood the shared pool.

```text
SELECT * FROM orders WHERE order_id = 1001;     hard parse
SELECT * FROM orders WHERE order_id = 1002;     hard parse
SELECT * FROM orders WHERE order_id = :id;      one shared statement
```

**Bind variables matter twice:**

- **Performance:** one shared statement, and fewer hard parses.
- **Security:** a value can never change the SQL text, so they block SQL injection.

`CURSOR_SHARING = FORCE` replaces literals with binds to reduce parsing, but it does **not** stop SQL injection, because the injection already happened.

**Bind peeking.** On skewed data, the first bind value can decide the shared plan. **Adaptive cursor sharing** (11g) lets one statement keep several plans.

**PostgreSQL prepared statements.** The first five executions use custom plans, then a generic plan is used if its estimate is not much worse. **SQL Server parameter sniffing** is the same problem.

## Keeping plans stable

| Tool | What it does |
|---|---|
| SQL plan baselines | Accept known-good plans. Proactive |
| SQL profiles | Correct estimates. Reactive |
| Hints | Force a choice. A last resort |

Oracle silently ignores invalid hints. Common ones are `LEADING`, `USE_NL`, `USE_HASH`, `INDEX` and `FULL`. PostgreSQL has no core hints.

### A step with E-Rows of 1 and A-Rows of 2 million

Follow this procedure:

1. Check statistics freshness.
2. Look for skew, correlation, a function on the column, or a peeked bind.
3. Fix the estimate: gather statistics, add a histogram, or add extended statistics.
4. Only then consider a hint or a baseline.

### Plan red flags

- `MERGE JOIN CARTESIAN` from a missing predicate, or a 1-row estimate
- Nested loops over huge row counts
- A big gap between estimated and actual rows
- What the `Note` section says: dynamic statistics, SQL profile, or baseline

```sql postgres
DROP TABLE big_orders;
DROP TABLE big_customers;
RESET max_parallel_workers_per_gather;
```

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Treat cost as time | Costs are arbitrary units | Compare plans for one statement |
| Trust `EXPLAIN` alone | It is only a prediction | Use `EXPLAIN ANALYZE` |
| Run `EXPLAIN ANALYZE` on DML unprotected | The change is real | Wrap it in `BEGIN` and `ROLLBACK` |
| Read Oracle plans bottom to top | The order is wrong | Start at the first leaf |
| Forget to multiply by loops | Time looks small | Multiply |
| Blame a missing index first | The estimate may be the real problem | Compare estimated and actual rows |
| Force hints early | The real cause stays | Fix the estimate first |
| Say `CURSOR_SHARING = FORCE` stops injection | It does not | Use real binds |

## Interview questions

**Q1. How do you read an EXPLAIN plan?**

It is a tree, and rows flow upward from the deepest nodes. I look at the access path, the join method, and estimated rows. With `EXPLAIN ANALYZE`, I first compare estimated and actual rows, then find where the time goes, multiplying by loops.

**Q2. Does EXPLAIN ANALYZE execute the statement? How would you run it safely on an UPDATE?**

Yes, it really runs it. I wrap it in `BEGIN` and `ROLLBACK`.

**Q3. Here is an Oracle execution plan. Tell me the order in which the steps execute.**

Start at the first leaf, the deepest first child. Children finish before parents, and in a join the first child is the build or driving input. It is not simply bottom to top.

**Q4. What is the difference between EXPLAIN PLAN and DBMS_XPLAN.DISPLAY_CURSOR?**

`EXPLAIN PLAN` predicts, in the current session's environment. `DISPLAY_CURSOR` shows the plan actually used, from the shared pool, and with `ALLSTATS LAST` it shows actual rows.

**Q5. Explain nested loop, hash and merge joins. When does the optimizer choose each one?**

A nested loop probes the inner side once per outer row, so it suits a small outer and an indexed inner. A hash join builds a hash table on the smaller input, and it suits large unsorted equality joins. A merge join walks two sorted inputs, and it suits inputs that are already sorted.

**Q6. What statistics does the optimizer rely on, and what happens when they are wrong?**

Row counts, distinct values, null fractions, min and max, and histograms. Wrong statistics give wrong row estimates, which give wrong plans, such as a nested loop over millions of rows.

**Q7. How does external merge sort work, and how many passes does it need?**

Sort memory-sized runs, then repeatedly merge B - 1 runs at a time. It needs 1 + ceil(log_(B-1)(ceil(N/B))) passes, at 2N I/Os per pass.

**Q8. Why do bind variables matter?**

They let one shared statement be reused, so there are fewer hard parses. And a value can never change the SQL text, which blocks injection.

## Practice

**1. In an Oracle plan, a `HASH JOIN` has two children. Which runs first?**

<details>
<summary>Show solution</summary>

The first child, which builds the hash table. The second child then probes it.

</details>

**2. A table has 10,000 rows. `status` has 4 distinct values, uniform. How many rows for `status = 'X'`?**

<details>
<summary>Show solution</summary>

`10000 x 1/4 = 2500`.

</details>

**3. Sort N = 1000 pages with B = 11 buffers. How many passes?**

<details>
<summary>Show solution</summary>

```text
Runs: ceil(1000 / 11) = 91
Passes: 1 + ceil(log_10 91) = 1 + 2 = 3
```

</details>

**4. A plan estimates 1 row, and the actual is 500,000, on a nested loop. What do you do?**

<details>
<summary>Show solution</summary>

Check statistics freshness first. Then look for skew, correlated columns, a function on the column, or a peeked bind. Fix the estimate. A hash join would probably follow by itself.

</details>

## Recap

- A wrong row estimate usually means a wrong plan.
- `EXPLAIN` predicts, and `EXPLAIN ANALYZE` runs.
- Compare estimated and actual rows first.
- Oracle plans start at the first leaf, not the bottom.
- Nested loop: small outer. Hash: large equality. Merge: already sorted.
- Statistics drive everything. Keep them fresh, especially after bulk loads.
- Bind variables reduce hard parses and block injection.
- Fix estimates before forcing hints.

**Next:** [Chapter 31: The query tuning playbook](31-query-tuning-playbook.md)
