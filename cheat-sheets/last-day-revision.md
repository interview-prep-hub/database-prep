# Last-Day Revision: What to Go Over the Night Before

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** The rest of the book

> **In one line:** Revise what you know, learn nothing new, and sleep.

## How to use this chapter

A typical round mixes 4 to 8 theory questions with one SQL query.

**Two-hour plan:**

| Time | Do |
|---|---|
| 45 minutes | Write the six queries below by hand |
| 35 minutes | Go through the theory tables |
| 20 minutes | Say the spoken answers out loud |
| 20 minutes | Read the trap list |

**15-minute morning version:** read the trap list, the one-sentence pairs and the PL/SQL recall list. Say the two spoken answers once.

## Query answer routine

Before writing, ask about ties, NULLs, duplicates, empty results, row order and which engine. State your assumption, write the query, then test it on two or three rows out loud.

## Six queries to write cold

### 1. Second highest salary

The general answer for Nth highest is `DENSE_RANK` in a subquery:

```sql
SELECT DISTINCT salary
FROM (
  SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS rnk
  FROM employees
) t
WHERE rnk = 2;
```

```text output
 salary
--------
 120000
(1 row)
```

The `MAX` form:

```sql
SELECT MAX(salary) AS second_highest
FROM employees
WHERE salary < (SELECT MAX(salary) FROM employees);
```

```text output
 second_highest
----------------
         120000
(1 row)
```

With a row limit:

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
SELECT DISTINCT salary
FROM employees
ORDER BY salary DESC
OFFSET 1 ROW FETCH NEXT 1 ROW ONLY;
```

```text output
 salary
--------
 120000
(1 row)
```

**Say:** `ROW_NUMBER` and a plain `OFFSET` with no `DISTINCT` count tied salaries twice, as with the two 95000 rows. If no second value exists, the `MAX` form gives NULL, and the rank form gives no row.

### 2. Find duplicates

```sql
SELECT salary, COUNT(*) AS how_many
FROM employees
GROUP BY salary
HAVING COUNT(*) > 1
ORDER BY salary DESC;
```

```text output
 salary | how_many
--------+----------
  95000 |        2
  82000 |        2
  60000 |        2
(3 rows)
```

List the full rows:

```sql
SELECT first_name, salary
FROM (
  SELECT first_name, salary, COUNT(*) OVER (PARTITION BY salary) AS copies
  FROM employees
) t
WHERE copies > 1
ORDER BY salary DESC, first_name;
```

```text output
 first_name | salary
------------+--------
 James      |  95000
 Omar       |  95000
 Emma       |  82000
 Yusuf      |  82000
 Diego      |  60000
 Lena       |  60000
(6 rows)
```

Delete all but one, on a tiny demo table. On PostgreSQL, use `ctid`:

```sql postgres
CREATE TABLE demo_dups (val INTEGER);
INSERT INTO demo_dups VALUES (1), (1), (2), (3), (3), (3);

DELETE FROM demo_dups
WHERE ctid IN (
  SELECT ctid
  FROM (
    SELECT ctid, ROW_NUMBER() OVER (PARTITION BY val ORDER BY ctid) AS rn
    FROM demo_dups
  ) t
  WHERE rn > 1
);

SELECT val FROM demo_dups ORDER BY val;

DROP TABLE demo_dups;
```

```text output
CREATE TABLE
INSERT 0 6
DELETE 3
 val
-----
   1
   2
   3
(3 rows)

DROP TABLE
```

On Oracle, use `ROWID`:

```sql oracle
DELETE FROM demo_dups
WHERE ROWID IN (
  SELECT rid
  FROM (
    SELECT ROWID AS rid,
           ROW_NUMBER() OVER (PARTITION BY val ORDER BY ROWID) AS rn
    FROM demo_dups
  )
  WHERE rn > 1
);
```

### 3. Employee earning more than their manager

```sql
SELECT e.first_name AS employee, e.salary,
       m.first_name AS manager, m.salary AS manager_salary
FROM employees e
JOIN employees m ON m.emp_id = e.manager_id
WHERE e.salary > m.salary
ORDER BY e.emp_id;
```

```text output
 employee | salary | manager | manager_salary
----------+--------+---------+----------------
(0 rows)
```

**No rows is correct here.** No one out-earns their manager, and Sara Khan drops out because her row has a NULL `manager_id`. To prove the query works, raise one salary inside a transaction, then roll back. On Oracle, leave out `BEGIN`.

```sql postgres
BEGIN;

UPDATE employees SET salary = 110000 WHERE first_name = 'Emma';

SELECT e.first_name AS employee, e.salary,
       m.first_name AS manager, m.salary AS manager_salary
FROM employees e
JOIN employees m ON m.emp_id = e.manager_id
WHERE e.salary > m.salary
ORDER BY e.emp_id;

ROLLBACK;
```

```text output
BEGIN
UPDATE 1
 employee | salary | manager | manager_salary
----------+--------+---------+----------------
 Emma     | 110000 | Arjun   |         105000
(1 row)

ROLLBACK
```

### 4. Running total

```sql
SELECT payment_id, amount,
       SUM(amount) OVER (ORDER BY payment_date, payment_id
                         ROWS UNBOUNDED PRECEDING) AS running_total
FROM payments
ORDER BY payment_date, payment_id;
```

```text output
 payment_id | amount  | running_total
------------+---------+---------------
          1 |  838.98 |        838.98
          2 |   74.00 |        912.98
          3 | 1000.00 |       1912.98
          5 |   89.50 |       2002.48
          4 |  499.00 |       2501.48
          6 | 1018.99 |       3520.47
          7 |  837.98 |       4358.45
          8 |   87.00 |       4445.45
          9 |   49.00 |       4494.45
         10 |  749.00 |       5243.45
         11 |  119.00 |       5362.45
         12 |  179.00 |       5541.45
         13 |  500.00 |       6041.45
(13 rows)
```

Per order, add `PARTITION BY`:

```sql
SELECT order_id, payment_id, amount,
       SUM(amount) OVER (PARTITION BY order_id
                         ORDER BY payment_date, payment_id
                         ROWS UNBOUNDED PRECEDING) AS paid_so_far
FROM payments
WHERE order_id = 1003
ORDER BY payment_date, payment_id;
```

```text output
 order_id | payment_id | amount  | paid_so_far
----------+------------+---------+-------------
     1003 |          3 | 1000.00 |     1000.00
     1003 |          4 |  499.00 |     1499.00
(2 rows)
```

**Say:** `ROWS` and the tie-breaker keep rows on the same date apart. The default `RANGE` frame would give them one shared total. With no window functions, use a correlated subquery:

```sql
SELECT p.payment_id, p.amount,
       (SELECT SUM(x.amount)
        FROM payments x
        WHERE x.payment_date < p.payment_date
           OR (x.payment_date = p.payment_date
               AND x.payment_id <= p.payment_id)) AS running_total
FROM payments p
WHERE p.payment_id <= 3
ORDER BY p.payment_date, p.payment_id;
```

```text output
 payment_id | amount  | running_total
------------+---------+---------------
          1 |  838.98 |        838.98
          2 |   74.00 |        912.98
          3 | 1000.00 |       1912.98
(3 rows)
```

### 5. Top 3 per group

```sql
WITH ranked AS (
  SELECT dept_id, first_name, salary,
         DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rnk
  FROM employees
)
SELECT dept_id, first_name, salary, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY dept_id, rnk, first_name;
```

```text output
 dept_id | first_name | salary | rnk
---------+------------+--------+-----
      10 | Sara       | 180000 |   1
      20 | James      |  95000 |   1
      20 | Diego      |  60000 |   2
      20 | Lena       |  60000 |   2
      20 | Mei        |  52000 |   3
      30 | Priya      | 120000 |   1
      30 | Arjun      | 105000 |   2
      30 | Emma       |  82000 |   3
      30 | Yusuf      |  82000 |   3
      40 | Omar       |  95000 |   1
      40 | Nina       |  58000 |   2
    NULL | Tom        |  30000 |   1
(12 rows)
```

**State the choice.** `ROW_NUMBER` gives exactly three rows. `DENSE_RANK` gives three distinct salaries. `RANK` is competition style. Here the 82000 tie (Emma, Yusuf) and the 60000 tie (Lena, Diego) both appear, and Tom Baker's NULL `dept_id` forms its own partition. `QUALIFY` shortens this on Oracle 26ai only.

### 6. Customers with no orders

```sql
SELECT customer_name
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id)
ORDER BY customer_name;
```

```text output
 customer_name
---------------
 Hana Sato
 Ivan Novak
(2 rows)
```

**Say:** `NOT IN` gives no rows at all if the subquery returns a NULL, which is exactly what happens with departments and Tom Baker.

## Next most-asked queries

**Orders per customer, including zero.** Count a column from the right table, or customers with no orders show 1.

```sql
SELECT c.customer_name, COUNT(o.order_id) AS order_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id;
```

```text output
 customer_name | order_count
---------------+-------------
 Alice Morgan  |           4
 Bilal Ahmed   |           3
 Chloe Martin  |           3
 David Lee     |           2
 Fatima Noor   |           2
 George Hall   |           2
 Hana Sato     |           0
 Ivan Novak    |           0
(8 rows)
```

This total includes cancelled order 1006. To leave it out, add `AND o.status <> 'CANCELLED'` to the first `ON`.

**Highest paid per department.**

```sql
WITH ranked AS (
  SELECT dept_id, first_name, salary,
         RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rnk
  FROM employees
)
SELECT dept_id, first_name, salary
FROM ranked
WHERE rnk = 1
ORDER BY dept_id, first_name;
```

```text output
 dept_id | first_name | salary
---------+------------+--------
      10 | Sara       | 180000
      20 | James      |  95000
      30 | Priya      | 120000
      40 | Omar       |  95000
    NULL | Tom        |  30000
(5 rows)
```

**Month-over-month revenue.**

```sql
WITH monthly AS (
  SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
         SUM(i.quantity * i.unit_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
)
SELECT order_month, revenue,
       revenue - LAG(revenue) OVER (ORDER BY order_month) AS diff
FROM monthly
ORDER BY order_month;
```

```text output
 order_month | revenue |  diff
-------------+---------+---------
 2024-01     | 2411.98 |    NULL
 2024-02     | 1507.49 | -904.49
 2024-03     |  973.98 | -533.51
 2024-04     |  868.00 | -105.98
 2024-05     | 1178.00 |  310.00
 2024-06     | 2047.47 |  869.47
(6 rows)
```

**Longest run of consecutive days.** A date minus its row number is constant within a run. On Oracle, leave out the `CAST`.

```sql postgres
-- PostgreSQL
CREATE TABLE demo_days (order_day DATE);
INSERT INTO demo_days VALUES
  (DATE '2024-01-01'), (DATE '2024-01-02'), (DATE '2024-01-03'),
  (DATE '2024-01-07'), (DATE '2024-01-08');

WITH numbered AS (
  SELECT order_day,
         order_day
           - CAST(ROW_NUMBER() OVER (ORDER BY order_day) AS INTEGER) AS grp
  FROM demo_days
)
SELECT MIN(order_day) AS run_start, MAX(order_day) AS run_end,
       COUNT(*) AS days
FROM numbered
GROUP BY grp
ORDER BY days DESC, run_start
FETCH FIRST 1 ROW ONLY;

DROP TABLE demo_days;
```

```text output
CREATE TABLE
INSERT 0 5
 run_start  |  run_end   | days
------------+------------+------
 2024-01-01 | 2024-01-03 |    3
(1 row)

DROP TABLE
```

**Reporting chain.** Use a recursive CTE, as shown in the [SQL Cheat Sheet](sql-cheat-sheet.md).

**Row limit one-liners.** `ROWNUM` around an ordered subquery on 11g, `FETCH FIRST` on 12c and later, `LIMIT` on PostgreSQL and MySQL, `TOP` on SQL Server.

## SQL trap list

| Trap | Fix |
|---|---|
| `NOT IN` with NULL | `NOT EXISTS` |
| `LEFT JOIN` filter in `WHERE` | Move it to `ON` |
| `COUNT(col)` vs `COUNT(*)` | `col` skips NULLs |
| `AVG` skipping NULLs | Decide if NULL means 0 |
| Join fan-out | Aggregate before joining |
| Default window frame | Write `ROWS` |
| `ROW_NUMBER` with no tie-breaker | Add a unique column |
| Window function in `WHERE` | Use a subquery or CTE |
| `BETWEEN` on an Oracle `DATE` | `>= start AND < next day` |
| `''` as NULL on Oracle | Test with `IS NULL` |
| Integer division on PostgreSQL | Cast to `NUMERIC` |

## Theory tables

**Containment chains.** The first two are separate axes, so a conflict serializable schedule can still be unrecoverable.

```text
Serializability: serial < conflict serializable < view serializable < all schedules
Recoverability:  strict < cascadeless < recoverable < all schedules
Locking:         rigorous 2PL < strict 2PL < basic 2PL < conflict serializable
```

**Schedule check order:** serial, conflict serializable (the precedence graph has no cycle), view serializable, recoverable, cascadeless, strict.

**Lock compatibility.** S with S is allowed, and every other pair waits. Two S holders that both upgrade to X is the classic deadlock. The full matrix is in the [Concepts Cheat Sheet](concepts-cheat-sheet.md).

**Steal and force.** Steal means a dirty page of an uncommitted transaction may reach disk, so you need undo. No-force means committed changes need not be on disk at commit, so you need redo.

| | Force | No-force |
|---|---|---|
| **No-steal** | Neither, as in shadow paging | Redo only |
| **Steal** | Undo only | Undo and redo, the standard choice |

**ARIES phases:**

1. **Analysis** reads forward from the last checkpoint, and rebuilds the active transaction table and dirty page table.
2. **Redo** repeats history from the smallest recLSN, including updates by transactions that will be undone.
3. **Undo** rolls back the losers in reverse, writing compensation log records, so a crash during recovery does no work twice.

**Normal form chain:** 1NF, 2NF, 3NF, BCNF, 4NF, 5NF. For `X -> A`, 3NF allows X to be a superkey or A to be prime. BCNF allows only a superkey.

**Five formulas:**

```text
superkeys          2^(n-k), for one key of k attributes out of n
blocking factor    floor(block size / record size)
B+ tree node       n x pointer + (n - 1) x key <= block size
sort passes        1 + ceil(log base (M - 1) of ceil(N / M))
block nested loop  |R| + ceil(|R| / (M - 2)) x |S|
```

**Default isolation:** `READ COMMITTED` on Oracle, PostgreSQL and SQL Server, and `REPEATABLE READ` on MySQL InnoDB.

## Spoken answers

Keep each under 90 seconds.

**Normalization:**

> Normalization splits a table so each fact lives in one place. If `orders` repeats the customer's city on every row, changing the city means changing many rows, and missing one leaves wrong data. So I move customers to their own table and keep `customer_id` on orders. I aim for 3NF or BCNF, and I denormalize only for a measured read problem.

**ACID, with a bank transfer:**

> Take a transfer of 100 from A to B. Atomicity means both changes happen, or neither. Consistency means the rules still hold, so the total is unchanged. Isolation means a concurrent report does not see the money missing from both. Durability means once it commits, a crash cannot lose it.

## One-sentence pairs

| Pair | Difference |
|---|---|
| `WHERE`, `HAVING` | Filters rows before grouping, vs groups after |
| `INNER`, `LEFT JOIN` | Matches only, vs also unmatched left rows |
| `DELETE`, `TRUNCATE`, `DROP` | Some rows, all rows fast, the table itself |
| Primary key, `UNIQUE` | One per table with no NULLs, vs many that may allow NULLs |
| Clustered, non-clustered | Rows stored in index order, vs a separate structure |
| B-tree, B+ tree | Data in all nodes, vs data in linked leaves only |
| View, materialized view | Stored query, vs stored result |
| `UNION`, `UNION ALL` | Removes duplicates, vs keeps them and runs faster |
| 3NF, BCNF | BCNF drops the prime-column exception |
| OLTP, OLAP | Many small transactions, vs large analytical reads |
| Partitioning, sharding | One database, vs many servers |
| Procedure, function | Does work, vs returns a value usable in SQL |
| `RANK`, `DENSE_RANK` | Gaps after ties, vs no gaps |

## PL/SQL recall list

- `SELECT INTO` raises `NO_DATA_FOUND` or `TOO_MANY_ROWS`. `COUNT(*)` never raises `NO_DATA_FOUND`.
- Cursor attributes: `%FOUND` is NULL until the first `FETCH`. `SQL%ISOPEN` is always FALSE.
- `BULK COLLECT` with `LIMIT`, then `FORALL ... SAVE EXCEPTIONS`, which raises `ORA-24381`.
- Mutating table `ORA-04091`: fix with a compound trigger.
- `:OLD` is NULL on insert, and `:NEW` is NULL on delete. Change `:NEW` only in a `BEFORE` row trigger.
- `RAISE_APPLICATION_ERROR` takes -20000 to -20999.
- Recompiling a stateful package causes `ORA-04068`.
- Autonomous transactions suit logging, not silencing errors.
- The [PL/SQL Cheat Sheet](plsql-cheat-sheet.md) has every table.

## Version one-liners

- Oracle 26ai adds `QUALIFY`, `FILTER` and assertions.
- PostgreSQL 18 adds skip scan, asynchronous I/O and `uuidv7()`.
- PostgreSQL 19 is in release candidate, with general availability planned for 19 November 2026.
- MySQL 9.7 is the newest LTS.
- SQL Server 2025 adds optimized locking and the `||` operator.

The full tables are in [Dialect Differences](dialect-differences.md).

## Mini mock

Answer out loud, then check.

1. What is the difference between `DELETE` and `TRUNCATE`?
2. What is a covering index?
3. What is 3NF?
4. What does ARIES redo?
5. What is write skew?
6. What does `ORA-04091` mean?
7. **Query:** show each customer's name and total spend, with 0 for customers with no orders.

<details>
<summary>Show answers</summary>

1. `DELETE` removes chosen rows, one by one, and is logged row by row. `TRUNCATE` removes all rows fast, and is DDL.
2. An index that holds every column the query needs.
3. For each non-trivial `X -> A`, X is a superkey, or A is prime.
4. All of history, including work by transactions that will be undone.
5. Two transactions read the same data, write different rows, and together break a rule.
6. A row trigger touched its own table while it was changing.

```sql
SELECT c.customer_name,
       COALESCE(SUM(i.quantity * i.unit_price), 0) AS total_spend
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
LEFT JOIN order_items i ON i.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id;
```

```text output
 customer_name | total_spend
---------------+-------------
 Alice Morgan  |     1037.45
 Bilal Ahmed   |     1472.00
 Chloe Martin  |     1985.00
 David Lee     |     1137.99
 Fatima Noor   |     1016.98
 George Hall   |     2337.50
 Hana Sato     |           0
 Ivan Novak    |           0
(8 rows)
```

</details>

## In the room

- Think out loud.
- Name the engine you are assuming.
- Give a small example.
- Say when an answer depends on the engine.
- Say what you would check when you do not know.

At the end, ask about their data stack: which engines, how big, and who owns the schema.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Study a new topic the night before | Confusion, and less sleep | Revise and sleep |
| Write before asking | You solve the wrong problem | Ask about ties, NULLs, duplicates |
| Use `ROW_NUMBER` for Nth highest | Ties count twice | `DENSE_RANK`, or say your meaning |
| Forget the top manager | The NULL `manager_id` drops out | Mention it |
| Call the manager query wrong because it returns no rows | The data simply has no such row | Test with a temporary change |
| `COUNT(*)` after a `LEFT JOIN` | Customers with no orders show 1 | `COUNT(o.order_id)` |
| Mix up steal and force | Wrong log needs | Steal needs undo, no-force needs redo |
| Say ARIES redoes only committed work | It repeats all of history | Then it undoes the losers |
| Say conflict serializable means recoverable | They are separate properties | Check each |
| Give a definition with no example | It sounds memorized | Add a small example |
| State an engine fact as universal | It may be wrong elsewhere | Name the engine |

Good luck. You have done the work.
