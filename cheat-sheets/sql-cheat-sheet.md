# SQL Cheat Sheet: Quick Lookup from Basic to Advanced

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 2 and 3

> **In one line:** The SQL you look up most, in one place, with real results from the sample database.

Use this sheet for lookup and revision, not for first-time learning. Each section names the chapter that teaches the topic. Results come from the [sample database](../setup/sample-database.md), so you can check them by eye. This sheet shows standard SQL plus Oracle and PostgreSQL. All four engines are compared in [Dialect Differences](dialect-differences.md).

## Statement order ([Ch 8](../part-2-sql-basics/08-select-filter-sort.md))

| Step | You write | The database works |
|---|---|---|
| 1 | `SELECT` | `FROM` and joins |
| 2 | `FROM`, `JOIN` | `WHERE` |
| 3 | `WHERE` | `GROUP BY` |
| 4 | `GROUP BY` | `HAVING` |
| 5 | `HAVING` | Window functions |
| 6 | `ORDER BY` | `SELECT` |
| 7 | Row limit | `DISTINCT` |
| 8 | | Set operators |
| 9 | | `ORDER BY` |
| 10 | | Row limit |

**Alias visibility follows from this order.** A `SELECT` alias works in `ORDER BY`, and never in `WHERE`. In `GROUP BY` it works on PostgreSQL, and on Oracle only from 23ai.

## Filters ([Ch 8](../part-2-sql-basics/08-select-filter-sort.md))

| Operator | Example | Note |
|---|---|---|
| Comparison | `salary >= 90000`, `city <> 'London'` | |
| `BETWEEN` | `salary BETWEEN 60000 AND 82000` | Both ends included |
| `IN` | `dept_id IN (20, 30)` | |
| `LIKE` | `last_name LIKE 'K%'`, `first_name LIKE '_a%'` | `%` is any run, `_` is one character |
| `IS NULL` | `manager_id IS NULL` | Never `= NULL` |
| `AND`, `OR` | `a OR b AND c` means `a OR (b AND c)` | `AND` binds tighter, so add brackets |

## Row limiting ([Ch 8](../part-2-sql-basics/08-select-filter-sort.md))

**Oracle 12.1 and later, and PostgreSQL:**

```sql since=12c
SELECT first_name, salary
FROM employees
ORDER BY salary DESC, emp_id
FETCH FIRST 3 ROWS ONLY;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
(3 rows)
```

`FETCH FIRST 3 ROWS WITH TIES` also keeps rows tied with the last one (Oracle 12.1, PostgreSQL 13).

**Oracle 11g:** sort in a subquery first, because `ROWNUM` is assigned before `ORDER BY`.

```sql oracle
SELECT first_name, salary
FROM (SELECT first_name, salary FROM employees ORDER BY salary DESC, emp_id)
WHERE ROWNUM <= 3;
```

**PostgreSQL:** `ORDER BY salary DESC, emp_id LIMIT 3 OFFSET 0`.

**The `ROWNUM` trap:** `WHERE ROWNUM = 2` returns nothing. The first candidate row takes `ROWNUM` 1, fails the test, and the counter never reaches 2.

## NULL logic ([Ch 5](../part-1-foundations/05-data-types-and-null.md))

| AND | TRUE | FALSE | UNKNOWN |
|---|---|---|---|
| **TRUE** | TRUE | FALSE | UNKNOWN |
| **FALSE** | FALSE | FALSE | FALSE |
| **UNKNOWN** | UNKNOWN | FALSE | UNKNOWN |

| OR | TRUE | FALSE | UNKNOWN |
|---|---|---|---|
| **TRUE** | TRUE | TRUE | TRUE |
| **FALSE** | TRUE | FALSE | UNKNOWN |
| **UNKNOWN** | TRUE | UNKNOWN | UNKNOWN |

`NOT TRUE` is FALSE, `NOT FALSE` is TRUE, and `NOT UNKNOWN` is UNKNOWN.

**Where each truth value goes.** `WHERE`, `HAVING`, `ON` and `CASE WHEN` act only on TRUE. A `CHECK` constraint passes on UNKNOWN, so `CHECK (commission >= 0)` accepts a NULL commission.

| Test | Result |
|---|---|
| `x = NULL`, `x <> NULL`, `NULL = NULL` | UNKNOWN |
| `x IS NULL`, `x IS NOT NULL` | TRUE or FALSE |
| `x IN (1, NULL)` | TRUE or UNKNOWN, never FALSE |
| `x NOT IN (1, NULL)` | FALSE or UNKNOWN, never TRUE |

**Comparing two nullable columns.** Use `a IS NOT DISTINCT FROM b` on PostgreSQL. Oracle's comparison conditions do not list it through 26ai, so use `DECODE(a, b, 1, 0) = 1`, or `(a = b OR (a IS NULL AND b IS NULL))`.

| Function | Example | Result | Note |
|---|---|---|---|
| `COALESCE` | `COALESCE(dept_id, 0)` for Tom Baker | 0 | Standard, many arguments, stops at the first non-NULL |
| `NVL` | `NVL(dept_id, 0)` for Tom Baker | 0 | Oracle, two arguments, always evaluates both |
| `NVL2` | `NVL2(commission, 'yes', 'no')` for Mei Chen | `yes` | Oracle. 0 is not NULL |
| `NULLIF` | `NULLIF(commission, 0)` for Mei Chen | NULL | NULL when equal, so `x / NULLIF(y, 0)` avoids a divide by zero |
| `DECODE` | `DECODE(dept_id, NULL, 'none', 'set')` for Tom Baker | `none` | Oracle. Treats two NULLs as equal |
| `CASE` | `CASE WHEN dept_id IS NULL THEN 'none' END` | `none` | `CASE x WHEN NULL` never matches |

| Expression | Oracle | PostgreSQL |
|---|---|---|
| `''` | NULL | A real empty string |
| `'a' \|\| NULL` | `'a'` | NULL |
| `LENGTH('')` | NULL | 0 |

**NULL in aggregates.** `COUNT(*)` counts rows. Every other aggregate skips NULLs.

```sql
SELECT COUNT(*)                          AS all_rows,
       COUNT(commission)                 AS with_commission,
       COUNT(DISTINCT dept_id)           AS departments,
       ROUND(AVG(commission), 0)         AS avg_skips_null,
       ROUND(SUM(commission) / COUNT(*)) AS avg_over_all
FROM employees;
```

```text output
 all_rows | with_commission | departments | avg_skips_null | avg_over_all
----------+-----------------+-------------+----------------+--------------
       12 |               4 |           4 |           4875 |         1625
(1 row)
```

With no input rows, `COUNT` gives 0, and `SUM`, `AVG`, `MIN` and `MAX` give NULL.

**NULL in grouping and sorting.** `GROUP BY`, `DISTINCT` and set operators treat NULLs as one value, so Tom Baker forms a NULL `dept_id` group. Oracle and PostgreSQL sort NULLs last going up, and first going down. `NULLS FIRST` and `NULLS LAST` override that.

## Joins ([Ch 11](../part-2-sql-basics/11-joins.md))

On `departments` and `employees`:

| Join | Rows | Keeps |
|---|---|---|
| `INNER JOIN` | 11 | Matches only |
| `LEFT JOIN` from departments | 12 | Also Legal |
| `RIGHT JOIN` | 12 | Also Tom Baker |
| `FULL JOIN` | 13 | Both |
| `CROSS JOIN` | 60 | Every pair |

- **Self join:** `employees e JOIN employees m ON m.emp_id = e.manager_id`.
- **`USING (dept_id)`:** a shorter `ON` for a shared column name.
- **`NATURAL JOIN`:** matches all shared names, which is risky. `employees` and `customers` both have `email`.

**Filter placement on an outer join.** A right-table condition in `WHERE` removes the NULL-extended rows, so the join acts like an inner join. The same condition in `ON` keeps them.

**Semi-join and anti-join.** Use `EXISTS` or `IN` for at least one match, and `NOT EXISTS` for no match. `NOT IN` breaks here, because Tom Baker's `dept_id` is NULL:

```sql
SELECT dept_name
FROM departments
WHERE dept_id NOT IN (SELECT dept_id FROM employees);
```

```text output
 dept_name
-----------
(0 rows)
```

```sql
SELECT dept_name
FROM departments d
WHERE NOT EXISTS (SELECT 1 FROM employees e WHERE e.dept_id = d.dept_id);
```

```text output
 dept_name
-----------
 Legal
(1 row)
```

**Join fan-out.** Order 1003 has one 1499.00 line and two payments, so joining both repeats the line and doubles the sum. Aggregate each side before joining.

```sql
SELECT SUM(i.quantity * i.unit_price) AS doubled_total
FROM order_items i
JOIN payments p ON p.order_id = i.order_id
WHERE i.order_id = 1003;
```

```text output
 doubled_total
---------------
       2998.00
(1 row)
```

## Grouping ([Ch 10](../part-2-sql-basics/10-aggregation-group-by-having.md), [Ch 17](../part-3-advanced-sql/17-advanced-grouping-and-pivot.md))

**The rule.** Every selected column that is not aggregated must be grouped. Oracle raises `ORA-00979`. PostgreSQL raises an error too, unless the column depends on a grouped primary key. `WHERE` filters rows before grouping, and `HAVING` filters groups after.

| Clause | Gives |
|---|---|
| `ROLLUP (a, b)` | n + 1 levels: `(a, b)`, `(a)`, `()` |
| `CUBE (a, b)` | 2^n combinations |
| `GROUPING SETS ((a), (b))` | Exactly the levels you list |
| `GROUPING(a)` | 1 on a subtotal row, so it tells a subtotal NULL from a real NULL |

**Pivot.** `SUM(CASE WHEN status = 'SHIPPED' THEN 1 ELSE 0 END)` works on every engine. `COUNT(*) FILTER (WHERE ...)` works on PostgreSQL. `PIVOT` works on Oracle from 11.1.

## Set operators ([Ch 12](../part-2-sql-basics/12-set-operations.md))

| Operator | Result |
|---|---|
| `UNION` | Rows from both, with duplicates removed |
| `UNION ALL` | Rows from both, kept, and cheapest |
| `INTERSECT` | Rows in both |
| `EXCEPT` | Rows in the first and not the second. Spelled `MINUS` on Oracle, which also accepts `EXCEPT` from 21c |

Rules: the same column count, compatible types, names from the first query, one `ORDER BY` at the very end, and NULLs match each other.

## Subqueries ([Ch 13](../part-2-sql-basics/13-subqueries.md))

| Form | Example |
|---|---|
| Scalar | `(SELECT MAX(salary) FROM employees)` |
| Multi-row | `dept_id IN (SELECT dept_id FROM departments WHERE location = 'London')` |
| Correlated | `salary > (SELECT AVG(salary) FROM employees x WHERE x.dept_id = e.dept_id)` |
| Derived table | `FROM (SELECT ...) t` |

- A scalar subquery with no row gives NULL. With two rows it is an error (`ORA-01427`).
- `x > ALL` over an empty set is TRUE, and `x > ANY` over an empty set is FALSE.
- A NULL in the set stops `> ALL` from ever being TRUE.

## WITH clause ([Ch 14](../part-3-advanced-sql/14-cte-and-recursive-queries.md))

```sql
WITH dept_pay AS (
  SELECT dept_id, SUM(salary) AS total
  FROM employees
  GROUP BY dept_id
),
top_dept AS (
  SELECT MAX(total) AS total FROM dept_pay
)
SELECT p.dept_id, p.total
FROM dept_pay p
JOIN top_dept t ON t.total = p.total;
```

```text output
 dept_id | total
---------+--------
      30 | 389000
(1 row)
```

**Recursive.** PostgreSQL needs `WITH RECURSIVE`. Oracle uses plain `WITH` with a column list, from 11.2.

```sql postgres
WITH RECURSIVE chain AS (
  SELECT emp_id, first_name, manager_id, 1 AS depth
  FROM employees
  WHERE first_name = 'Emma'

  UNION ALL

  SELECT m.emp_id, m.first_name, m.manager_id, c.depth + 1
  FROM employees m
  JOIN chain c ON m.emp_id = c.manager_id
)
SELECT first_name, depth
FROM chain
ORDER BY depth;
```

```text output
 first_name | depth
------------+-------
 Emma       |     1
 Arjun      |     2
 Priya      |     3
 Sara       |     4
(4 rows)
```

```sql oracle
WITH chain (emp_id, first_name, manager_id, depth) AS (
  SELECT emp_id, first_name, manager_id, 1
  FROM employees
  WHERE first_name = 'Emma'

  UNION ALL

  SELECT m.emp_id, m.first_name, m.manager_id, c.depth + 1
  FROM employees m
  JOIN chain c ON m.emp_id = c.manager_id
)
SELECT first_name, depth
FROM chain
ORDER BY depth;
```

The older Oracle form:

```sql oracle
SELECT first_name, LEVEL AS depth
FROM employees
START WITH first_name = 'Emma'
CONNECT BY PRIOR manager_id = emp_id
ORDER BY depth;
```

## Window functions ([Ch 15](../part-3-advanced-sql/15-window-functions-ranking-and-offset.md), [Ch 16](../part-3-advanced-sql/16-window-functions-frames-and-running-totals.md))

**Syntax:** `function OVER (PARTITION BY ... ORDER BY ... frame)`. Rows are kept, unlike `GROUP BY`. Window functions run after `WHERE`, `GROUP BY` and `HAVING`, so filtering on one needs a subquery or CTE.

```sql
SELECT first_name, salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC, emp_id) AS row_num,
       RANK()       OVER (ORDER BY salary DESC)         AS rnk,
       DENSE_RANK() OVER (ORDER BY salary DESC)         AS dense
FROM employees
ORDER BY row_num;
```

```text output
 first_name | salary | row_num | rnk | dense
------------+--------+---------+-----+-------
 Sara       | 180000 |       1 |   1 |     1
 Priya      | 120000 |       2 |   2 |     2
 Arjun      | 105000 |       3 |   3 |     3
 James      |  95000 |       4 |   4 |     4
 Omar       |  95000 |       5 |   4 |     4
 Emma       |  82000 |       6 |   6 |     5
 Yusuf      |  82000 |       7 |   6 |     5
 Lena       |  60000 |       8 |   8 |     6
 Diego      |  60000 |       9 |   8 |     6
 Nina       |  58000 |      10 |  10 |     7
 Mei        |  52000 |      11 |  11 |     8
 Tom        |  30000 |      12 |  12 |     9
(12 rows)
```

| Function | Meaning |
|---|---|
| `NTILE(n)` | n buckets. Extra rows go to the first buckets |
| `PERCENT_RANK()` | `(rank - 1) / (rows - 1)` |
| `CUME_DIST()` | Rows up to and including the current peer group, divided by rows |
| `LAG(x, 1, 0)`, `LEAD(x, 1, 0)` | Previous or next value, with an offset and a default |
| `FIRST_VALUE`, `LAST_VALUE`, `NTH_VALUE` | A value from the frame |

**Which functions use the frame.** Aggregates, `FIRST_VALUE`, `LAST_VALUE` and `NTH_VALUE` do. Ranking functions, `NTILE`, `LAG` and `LEAD` ignore it.

**Frame syntax:** `ROWS`, `RANGE` or `GROUPS`, then `BETWEEN start AND end`, using `UNBOUNDED PRECEDING`, `n PRECEDING`, `CURRENT ROW`, `n FOLLOWING` and `UNBOUNDED FOLLOWING`. The short form `ROWS 2 PRECEDING` ends at `CURRENT ROW`. `GROUPS` and `EXCLUDE` need PostgreSQL 11 or Oracle 21c.

**Frame defaults.** With no `ORDER BY`, the frame is the whole partition. With `ORDER BY` and no frame, it is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which includes every peer of the current row.

**Why the default bites.** James and Omar both earn 95000, so they share one running total:

```sql
SELECT first_name, salary,
       SUM(salary) OVER (ORDER BY salary)
         AS default_frame,
       SUM(salary) OVER (ORDER BY salary, emp_id ROWS UNBOUNDED PRECEDING)
         AS rows_frame
FROM employees
WHERE salary >= 82000
ORDER BY salary, emp_id;
```

```text output
 first_name | salary | default_frame | rows_frame
------------+--------+---------------+------------
 Emma       |  82000 |        164000 |      82000
 Yusuf      |  82000 |        164000 |     164000
 James      |  95000 |        354000 |     259000
 Omar       |  95000 |        354000 |     354000
 Arjun      | 105000 |        459000 |     459000
 Priya      | 120000 |        579000 |     579000
 Sara       | 180000 |        759000 |     759000
(7 rows)
```

`LAST_VALUE(salary) OVER (ORDER BY salary)` has the same problem: it returns the current peer group's value, not the last row of the partition. Use `ROWS` with a unique tie-breaker, or a frame that ends at `UNBOUNDED FOLLOWING`.

## Changing data ([Ch 7](../part-2-sql-basics/07-dml-insert-update-delete.md), [Ch 18](../part-3-advanced-sql/18-advanced-dml.md))

| Statement | Form |
|---|---|
| `INSERT` | `INSERT INTO t (a, b) VALUES (1, 2)`, or `INSERT INTO t (a, b) SELECT ...` |
| Several rows | One `VALUES` list needs Oracle 23ai. Older Oracle uses `INSERT ALL`, or `SELECT ... UNION ALL` |
| `UPDATE` | `UPDATE t SET a = 1 WHERE id = 5` |
| `DELETE` | `DELETE FROM t WHERE id = 5` |

```sql norun
MERGE INTO target t
USING source s
ON (t.id = s.id)
WHEN MATCHED THEN
  UPDATE SET t.val = s.val
WHEN NOT MATCHED THEN
  INSERT (id, val) VALUES (s.id, s.val);
```

PostgreSQL writes `SET val = s.val`, with no alias on the left side.

| | `DELETE` | `TRUNCATE` | `DROP` |
|---|---|---|---|
| Type | DML | DDL | DDL |
| `WHERE` | Yes | No | No |
| Row triggers | Fire | Do not fire | Do not fire |
| Rollback | Yes | Depends on the engine | Depends on the engine |
| Space | Kept for reuse | Released | Released |
| Table definition | Stays | Stays | Gone |

## Defining tables ([Ch 5](../part-1-foundations/05-data-types-and-null.md), [Ch 6](../part-2-sql-basics/06-ddl-and-constraints.md))

- **Money:** `NUMERIC(10, 2)`, or `NUMBER(10, 2)` on Oracle, because `FLOAT` drifts.
- **Dates:** an Oracle `DATE` holds a time too.
- **The five constraints:** `PRIMARY KEY`, `UNIQUE`, `NOT NULL`, `CHECK`, `FOREIGN KEY`.
- **Default:** `status VARCHAR2(10) DEFAULT 'NEW'`.
- **Identity:** `GENERATED ALWAYS AS IDENTITY` on PostgreSQL and Oracle 12.1. On 11g, use a sequence plus a trigger.
- **`ALTER TABLE`:** `ADD`, `DROP COLUMN`, `RENAME COLUMN`, `ADD CONSTRAINT`. Oracle uses `MODIFY` to change a column type, and PostgreSQL uses `ALTER COLUMN ... TYPE`.

## Transactions ([Ch 32](../part-5-internals-and-performance/32-transactions-and-isolation.md), [Ch 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md))

`COMMIT`, `ROLLBACK`, `SAVEPOINT name`, `ROLLBACK TO name`, `SET TRANSACTION ISOLATION LEVEL ...`, and `SELECT ... FOR UPDATE` with `NOWAIT` or `SKIP LOCKED`.

SQL*Plus waits for `COMMIT`. psql commits each statement unless you start with `BEGIN`.

## Reusing a query ([Ch 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md))

| Tool | Stores | Lasts |
|---|---|---|
| View | The query text | Until dropped |
| Materialized view | The result | Until dropped, and goes stale until refreshed |
| CTE | Nothing | One statement |
| Temporary table | Rows | The session or transaction, by engine |

## Indexes and plans ([Ch 29](../part-5-internals-and-performance/29-indexes.md), [Ch 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md))

- `CREATE INDEX idx_emp_dept ON employees (dept_id, salary);` serves `dept_id`, and `dept_id` with `salary`, but not `salary` alone.
- **What stops index use:** a function on the column, a leading wildcard, and implicit conversion.
- **Oracle plan:** `EXPLAIN PLAN FOR ...`, then `SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);`.
- **PostgreSQL plan:** `EXPLAIN (ANALYZE, BUFFERS) ...`.

## Scalar functions ([Ch 9](../part-2-sql-basics/09-built-in-functions.md))

| Task | Oracle | PostgreSQL |
|---|---|---|
| Part of a string | `SUBSTR(s, 1, 3)` | `SUBSTR(s, 1, 3)`, `SUBSTRING(s FROM 1 FOR 3)` |
| Find text | `INSTR(s, '@')` | `POSITION('@' IN s)` |
| Length | `LENGTH(s)` | `LENGTH(s)` |
| Trim, replace, pad | `TRIM`, `REPLACE`, `LPAD` | The same |
| Case | `UPPER`, `LOWER` | The same |
| Round, cut | `ROUND(x, 2)`, `TRUNC(x, 2)` | `ROUND(x, 2)`, `TRUNC(x, 2)` |
| Remainder, up, down | `MOD`, `CEIL`, `FLOOR` | The same |
| Now | `SYSDATE` | `NOW()` |
| Add months | `ADD_MONTHS(d, 1)` | `d + INTERVAL '1 month'` |
| Start of month | `TRUNC(d, 'MM')` | `DATE_TRUNC('month', d)` |
| Part of a date | `EXTRACT(YEAR FROM d)` | The same |
| Date to text, text to date | `TO_CHAR`, `TO_DATE` | The same |
| Convert | `CAST(x AS NUMBER)` | `CAST(x AS NUMERIC)` |

## Pattern map ([Ch 21](../part-3-advanced-sql/21-classic-query-patterns.md))

| Problem | Technique |
|---|---|
| Nth highest | `DENSE_RANK` in a subquery |
| Top N per group | Rank in a CTE, filter outside |
| Find duplicates | `GROUP BY ... HAVING COUNT(*) > 1` |
| Delete duplicates | `ROW_NUMBER` and `ROWID` or `ctid` |
| Running total | `SUM() OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)` |
| Moving average | `AVG() OVER (... ROWS 2 PRECEDING)` |
| Month-over-month change | `LAG` |
| Gaps and islands | Value minus `ROW_NUMBER` gives a group key |
| Pivot | Conditional aggregation |
| Hierarchy | Recursive CTE |
| Median | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY x)` |

Written-out solutions are in [Last-Day Revision](last-day-revision.md).

## Smaller lookups

**Privileges ([Ch 40](../part-6-architecture-and-scale/40-database-security.md)).** `GRANT SELECT ON t TO u;`, `REVOKE SELECT ON t FROM u;`, `CREATE ROLE r;`, `GRANT r TO u;`, and `WITH GRANT OPTION` lets the receiver pass the privilege on.

**Sequences ([Ch 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md)).** `seq.NEXTVAL` on Oracle, `nextval('seq')` on PostgreSQL.

**LATERAL ([Ch 20](../part-3-advanced-sql/20-modern-sql.md)).** A subquery in `FROM` that can read earlier tables, on PostgreSQL 9.3 and Oracle 12.1. Oracle also has `CROSS APPLY`.

```sql postgres
SELECT c.customer_name, latest.order_id
FROM customers c
CROSS JOIN LATERAL (
  SELECT o.order_id
  FROM orders o
  WHERE o.customer_id = c.customer_id
  ORDER BY o.order_date DESC
  LIMIT 1
) latest
ORDER BY c.customer_id;
```

```text output
 customer_name | order_id
---------------+----------
 Alice Morgan  |     1014
 Bilal Ahmed   |     1013
 Chloe Martin  |     1016
 David Lee     |     1011
 Fatima Noor   |     1012
 George Hall   |     1015
(6 rows)
```

**Regular expressions ([Ch 20](../part-3-advanced-sql/20-modern-sql.md)).** `REGEXP_LIKE(s, '^a')` and `REGEXP_REPLACE` on Oracle, `s ~ '^a'` and `regexp_replace` on PostgreSQL.

**JSON ([Ch 20](../part-3-advanced-sql/20-modern-sql.md)).** `JSON_VALUE(doc, '$.city')` and `JSON_TABLE` on Oracle, `doc -> 'city'` and `doc ->> 'city'` on PostgreSQL.

**Row addresses.** `ROWID` on Oracle and `ctid` on PostgreSQL are physical row addresses. They are safe only for short-lived use, because a row can move.

**`MATCH_RECOGNIZE` (Oracle 12.1).** It finds patterns across ordered rows, such as a price falling and then rising.

## Error map

Oracle reworded several messages in recent releases, including `ORA-00979` and `ORA-01722`, so the text on 11g XE differs from current documentation. Learn the numbers.

| Oracle | Meaning | PostgreSQL wording |
|---|---|---|
| `ORA-00001` | Unique constraint violated | duplicate key value violates unique constraint |
| `ORA-00904` | Invalid identifier | column does not exist |
| `ORA-00934` | Group function not allowed here | aggregate functions are not allowed in WHERE |
| `ORA-00936` | Missing expression | syntax error |
| `ORA-00937` | Not a single-group group function | must appear in the GROUP BY clause |
| `ORA-00942` | Table or view does not exist | relation does not exist |
| `ORA-00979` | Not a GROUP BY expression | must appear in the GROUP BY clause |
| `ORA-01400` | Cannot insert NULL | null value violates not-null constraint |
| `ORA-01427` | Single-row subquery returned many rows | more than one row returned by a subquery |
| `ORA-01438` | Value larger than the column allows | numeric field overflow |
| `ORA-01722` | Invalid number | invalid input syntax for type |
| `ORA-02291` | Parent key not found | violates foreign key constraint |
| `ORA-02292` | Child record found | violates foreign key constraint |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Write `col = NULL` | UNKNOWN, so no rows | `IS NULL` |
| Use `NOT IN` on a nullable subquery | One NULL removes every row | `NOT EXISTS` |
| Filter the right table in `WHERE` on a `LEFT JOIN` | It becomes an inner join | Move it to `ON` |
| `SUM` after a one-to-many join | Totals grow | Aggregate each side first |
| Expect `AVG` to treat NULL as 0 | It skips NULLs | `AVG(COALESCE(x, 0))` |
| Trust the default frame | Peers share one total | Write the frame |
| `ROW_NUMBER` over ties | Numbering can change between runs | Add a unique tie-breaker |
| Filter a window function in `WHERE` | It runs after `WHERE` | Wrap it in a CTE |
| `BETWEEN` up to a plain day on an Oracle `DATE` | Rows later that day are missed | `>= start AND < next day` |
| `ROWNUM` and `ORDER BY` at one level | `ROWNUM` comes first | Order in a subquery |
| Trust `ORDER BY` inside a view | Only the outermost one counts | Order the final query |
| `CASE x WHEN NULL` | Never matches | `CASE WHEN x IS NULL` |
| Divide integers on PostgreSQL | `5 / 2` is 2 | Cast one side to `NUMERIC` |
| Treat `NVL` and `COALESCE` as identical | `NVL` always runs its second argument | Use `COALESCE` when that argument is slow |

## Quick self-test

1. In what order does a `SELECT` logically run, and why can an alias work in `ORDER BY` but not in `WHERE`?
2. What do `TRUE AND NULL`, `FALSE AND NULL`, `TRUE OR NULL` and `NOT NULL` give?
3. Why can `AVG(col)` differ from `SUM(col) / COUNT(*)`?
4. What is the default frame, and why does `LAST_VALUE` often look wrong?
5. When do `ROWS` and `RANGE` give different running totals?
6. Your `SUM` doubled after you added a join. Why, and how do you fix it?
7. Why does `WHERE ROWNUM = 2` return nothing, and how do you get the second row?
8. How do you tell a subtotal row from a real NULL?

**Next:** [PL/SQL Cheat Sheet](plsql-cheat-sheet.md)
