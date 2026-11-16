# 17. Subtotals, Pivots and Joining Rows into Strings

**Level:** Intermediate | **Interview priority:** Should know | **Before this:** [Chapter 16](16-window-functions-frames-and-running-totals.md)

> **In one line:** `ROLLUP` and `CUBE` add subtotal rows, a pivot turns rows into columns, and `LISTAGG` joins rows into one string.

## What you will learn

- `ROLLUP`, `CUBE` and `GROUPING SETS`
- How to tell a subtotal row from a row with a real NULL
- How to pivot on any engine, and with Oracle's `PIVOT`
- How to unpivot
- How to join values into a comma-separated string

## The problem

One report needs detail rows, subtotals and a grand total. Without help, you write one `GROUP BY` per level, and stack them:

```sql
SELECT dept_id, job_title, SUM(salary) AS total_pay
FROM employees WHERE dept_id IN (20, 40)
GROUP BY dept_id, job_title
UNION ALL
SELECT dept_id, NULL, SUM(salary)
FROM employees WHERE dept_id IN (20, 40)
GROUP BY dept_id
UNION ALL
SELECT NULL, NULL, SUM(salary)
FROM employees WHERE dept_id IN (20, 40)
ORDER BY dept_id, job_title;
```

```text output
 dept_id |    job_title    | total_pay
---------+-----------------+-----------
      20 | Sales Manager   |     95000
      20 | Sales Rep       |    172000
      20 | NULL            |    267000
      40 | Accountant      |     58000
      40 | Finance Manager |     95000
      40 | NULL            |    153000
    NULL | NULL            |    420000
(7 rows)
```

## ROLLUP

`ROLLUP(a, b)` produces the groupings (a, b), (a) and (). That is n + 1 levels, from detail up to a grand total.

```sql
SELECT dept_id, job_title, SUM(salary) AS total_pay
FROM employees
WHERE dept_id IN (20, 40)
GROUP BY ROLLUP (dept_id, job_title)
ORDER BY dept_id, job_title;
```

```text output
 dept_id |    job_title    | total_pay
---------+-----------------+-----------
      20 | Sales Manager   |     95000
      20 | Sales Rep       |    172000
      20 | NULL            |    267000
      40 | Accountant      |     58000
      40 | Finance Manager |     95000
      40 | NULL            |    153000
    NULL | NULL            |    420000
(7 rows)
```

Column order matters: `ROLLUP(a, b)` gives subtotals per `a`, not per `b`. The engine can compute all levels in one pass, so this can also beat the `UNION ALL` version.

## CUBE

`CUBE(a, b)` produces every combination: (a, b), (a), (b) and (). That is 2 to the power n levels.

```sql
SELECT dept_id, job_title, COUNT(*) AS staff
FROM employees
WHERE dept_id = 40
GROUP BY CUBE (dept_id, job_title)
ORDER BY dept_id, job_title;
```

```text output
 dept_id |    job_title    | staff
---------+-----------------+-------
      40 | Accountant      |     1
      40 | Finance Manager |     1
      40 | NULL            |     2
    NULL | Accountant      |     1
    NULL | Finance Manager |     1
    NULL | NULL            |     2
(6 rows)
```

## GROUPING SETS

`GROUPING SETS` lists exactly the groupings you want.

```sql
SELECT dept_id, job_title, COUNT(*) AS staff
FROM employees
WHERE dept_id = 40
GROUP BY GROUPING SETS ((dept_id), (job_title), ())
ORDER BY dept_id, job_title;
```

```text output
 dept_id |    job_title    | staff
---------+-----------------+-------
      40 | NULL            |     2
    NULL | Accountant      |     1
    NULL | Finance Manager |     1
    NULL | NULL            |     2
(4 rows)
```

**Which should you pick?** `ROLLUP` for a hierarchy, `CUBE` for all cross-totals, and `GROUPING SETS` when you want only some.

A **partial rollup** is `GROUP BY a, ROLLUP(b)`. It keeps `a` in every row, and has no grand total.

## Subtotal NULL vs real NULL

A subtotal row shows NULL in the rolled-up column, and a real NULL looks identical. Tom Baker's `dept_id` is NULL, so `ROLLUP(dept_id)` gives two NULL rows.

`GROUPING(col)` returns 1 for a subtotal row, and 0 for a real value.

```sql
SELECT CASE WHEN GROUPING(dept_id) = 1 THEN 'ALL DEPARTMENTS'
            WHEN dept_id IS NULL THEN 'NO DEPARTMENT'
            ELSE CAST(dept_id AS VARCHAR(10))
       END AS department,
       SUM(salary) AS total_pay
FROM employees
GROUP BY ROLLUP (dept_id)
ORDER BY GROUPING(dept_id), dept_id;
```

```text output
   department    | total_pay
-----------------+-----------
 10              |    180000
 20              |    267000
 30              |    389000
 40              |    153000
 NO DEPARTMENT   |     30000
 ALL DEPARTMENTS |   1019000
(6 rows)
```

`HAVING GROUPING(a) = 1` keeps only subtotal rows. `GROUPING_ID` (Oracle, SQL Server) gives one number for the grouping level.

**Dialect notes.** MySQL writes `GROUP BY a, b WITH ROLLUP`, has no `CUBE` or `GROUPING SETS`, and has `GROUPING()` from 8.0.1. SQL Server accepts `ROLLUP(a, b)` and `CUBE(a, b)`.

## Pivot: rows into columns

**How do you pivot rows into columns?** The portable way is conditional aggregation: one `SUM` or `MAX` of a `CASE` per output column, plus `GROUP BY` for the row labels.

Three roles decide a pivot:

- Which column becomes the **row labels**? (Month)
- Which column's values become **column headers**? (Method)
- Which column **fills the cells**? (Amount)

```sql
SELECT TO_CHAR(payment_date, 'YYYY-MM') AS pay_month,
       SUM(CASE WHEN method = 'CARD' THEN amount END) AS card,
       SUM(CASE WHEN method = 'BANK' THEN amount END) AS bank,
       SUM(CASE WHEN method = 'WALLET' THEN amount END) AS wallet
FROM payments
GROUP BY TO_CHAR(payment_date, 'YYYY-MM')
ORDER BY pay_month;
```

```text output
 pay_month |  card   |  bank   | wallet
-----------+---------+---------+--------
 2024-01   |  912.98 | 1000.00 |   NULL
 2024-02   | 1108.49 |  499.00 |   NULL
 2024-03   |   87.00 |    NULL | 886.98
 2024-04   |  119.00 |  749.00 |   NULL
 2024-05   |    NULL |  500.00 | 179.00
(5 rows)
```

### The PIVOT clause

Oracle (from 11.1) and SQL Server have a `PIVOT` clause. Two rules apply:

1. The value list is fixed when you write the query.
2. Every column not mentioned becomes an implicit `GROUP BY` column. So select only the columns you need, in an inner query.

```sql oracle
SELECT *
FROM (SELECT TO_CHAR(payment_date, 'YYYY-MM') AS pay_month, method, amount
      FROM payments)
PIVOT (SUM(amount) FOR method IN ('CARD' AS card, 'BANK' AS bank, 'WALLET' AS wallet))
ORDER BY pay_month;
```

```text output
PAY_MONTH       CARD       BANK     WALLET
--------- ---------- ---------- ----------
2024-01       912.98       1000       NULL
2024-02      1108.49        499       NULL
2024-03           87       NULL     886.98
2024-04          119        749       NULL
2024-05         NULL        500        179
```

PostgreSQL has no `PIVOT`. Use conditional aggregation, or `crosstab()` from the `tablefunc` extension. MySQL has none either.

### Dynamic pivot

If the columns are not known in advance, the query text itself must be generated. Build the list with `LISTAGG` or `STRING_AGG`, and run it as dynamic SQL ([Chapter 51](../part-7-plsql/51-dynamic-sql.md)).

### Pivoting text

To pivot text (HackerRank "Occupations"), number the rows in each group first, then use `MAX(CASE ...)` grouped by that number.

```sql
WITH numbered AS (
  SELECT job_title, first_name,
         ROW_NUMBER() OVER (PARTITION BY job_title ORDER BY first_name) AS rn
  FROM employees
  WHERE job_title IN ('Sales Rep', 'Developer')
)
SELECT MAX(CASE WHEN job_title = 'Sales Rep' THEN first_name END) AS sales_rep,
       MAX(CASE WHEN job_title = 'Developer' THEN first_name END) AS developer
FROM numbered
GROUP BY rn
ORDER BY rn;
```

```text output
 sales_rep | developer
-----------+-----------
 Diego     | Emma
 Lena      | Yusuf
 Mei       | NULL
(3 rows)
```

## Unpivot: columns into rows

The portable form is `UNION ALL`, with one `SELECT` per column (LeetCode "Rearrange Products Table").

```sql
SELECT product_id, 'price' AS attribute, price AS attr_value
FROM products
WHERE product_id = 1
UNION ALL
SELECT product_id, 'stock', stock_qty
FROM products
WHERE product_id = 1
ORDER BY attribute;
```

```text output
 product_id | attribute | attr_value
------------+-----------+------------
          1 | price     |     799.00
          1 | stock     |         25
(2 rows)
```

Oracle (from 11.1) and SQL Server have an `UNPIVOT` clause. Oracle drops NULLs by default, and `INCLUDE NULLS` keeps them.

```sql oracle
SELECT product_id, attribute, attr_value
FROM products
UNPIVOT (attr_value FOR attribute IN (price AS 'price', stock_qty AS 'stock'))
WHERE product_id = 1
ORDER BY attribute;
```

## Joining rows into a string

**How do you combine the values of several rows into one comma-separated string?**

**Oracle 11.2 and later:**

```sql oracle
SELECT dept_id,
       LISTAGG(first_name, ', ') WITHIN GROUP (ORDER BY first_name) AS staff
FROM employees
WHERE dept_id = 20
GROUP BY dept_id;
```

**PostgreSQL:**

```sql postgres
SELECT dept_id,
       STRING_AGG(first_name, ', ' ORDER BY first_name) AS staff
FROM employees
WHERE dept_id = 20
GROUP BY dept_id;
```

```text output
 dept_id |          staff
---------+-------------------------
      20 | Diego, James, Lena, Mei
(1 row)
```

SQL Server writes `STRING_AGG(x, ', ') WITHIN GROUP (ORDER BY x)`, and MySQL has `GROUP_CONCAT`.

**`LISTAGG` limits.** The result must fit a `VARCHAR2`: 4000 bytes by default, or 32767 with `MAX_STRING_SIZE = EXTENDED`. Beyond that, you get `ORA-01489`. `ON OVERFLOW TRUNCATE` (12.2) cuts it safely. `LISTAGG(DISTINCT x)` arrived in 19c.

`LISTAGG` is also a window function, which keeps every row: `LISTAGG(x, ',') WITHIN GROUP (ORDER BY y) OVER (PARTITION BY g)`.

On PostgreSQL, `ARRAY_AGG` gives an array when that is more useful than a string. [Chapter 20](20-modern-sql.md) shows the reverse: splitting a string into rows.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Confuse a subtotal NULL with a real NULL | Rows are mislabeled | Use `GROUPING(col)` |
| Choose the wrong `ROLLUP` order | The wrong subtotals appear | Put the highest level first |
| Use `CUBE` with many columns | Rows explode as 2 to the power n | Use `GROUPING SETS` |
| Leave extra columns in a `PIVOT` source | They silently become `GROUP BY` columns | Select only what you need |
| Expect `PIVOT` to discover its columns | The list is fixed | Use dynamic SQL |
| Use `SUM` in a text pivot | It fails on text | Use `MAX` |
| Let `LISTAGG` overflow | `ORA-01489` | Use `ON OVERFLOW TRUNCATE` |

## Interview questions

**Q1. How do you pivot rows into columns?**

The portable way is conditional aggregation: one `SUM(CASE ...)` per output column, with `GROUP BY` for the row labels. Oracle and SQL Server also have a `PIVOT` clause, but its column list is fixed. If the columns are unknown in advance, I generate the query with dynamic SQL.

**Q2. What do ROLLUP and CUBE do, and how do you tell a subtotal row from a row with a real NULL?**

`ROLLUP(a, b)` gives detail, subtotals per `a`, and a grand total. `CUBE(a, b)` gives every combination. `GROUPING(col)` returns 1 on a subtotal row and 0 on a normal row, so it separates a subtotal from a real NULL.

**Q3. How do you combine the values of several rows into one comma-separated string?**

`LISTAGG(x, ', ') WITHIN GROUP (ORDER BY x)` on Oracle, `STRING_AGG` on PostgreSQL and SQL Server, and `GROUP_CONCAT` on MySQL. On Oracle I watch for the 4000-byte limit, and on MySQL for silent truncation.

## Practice

**1. Show total revenue by status, with a grand total row labeled ALL.**

<details>
<summary>Show solution</summary>

```sql
SELECT CASE WHEN GROUPING(o.status) = 1 THEN 'ALL' ELSE o.status END AS status,
       SUM(i.quantity * i.unit_price) AS revenue
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
GROUP BY ROLLUP (o.status)
ORDER BY GROUPING(o.status), o.status;
```

```text output
  status   | revenue
-----------+---------
 CANCELLED |  399.00
 DELIVERED | 5243.45
 PENDING   | 2047.47
 SHIPPED   | 1297.00
 ALL       | 8986.92
(5 rows)
```

</details>

**2. Show each customer with one column per status, counting their orders.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_id,
       COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS delivered,
       COUNT(CASE WHEN status = 'SHIPPED' THEN 1 END) AS shipped,
       COUNT(CASE WHEN status = 'PENDING' THEN 1 END) AS pending
FROM orders
GROUP BY customer_id
ORDER BY customer_id;
```

```text output
 customer_id | delivered | shipped | pending
-------------+-----------+---------+---------
           1 |         3 |       0 |       1
           2 |         1 |       1 |       0
           3 |         2 |       0 |       1
           4 |         1 |       1 |       0
           5 |         1 |       1 |       0
           6 |         1 |       0 |       1
(6 rows)
```

</details>

**3. For each order, show a list of its product ids, as one string. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
SELECT order_id,
       STRING_AGG(CAST(product_id AS VARCHAR(10)), ',' ORDER BY product_id) AS products
FROM order_items
WHERE order_id <= 1002
GROUP BY order_id
ORDER BY order_id;
```

```text output
 order_id | products
----------+----------
     1001 | 1,3
     1002 | 8,9
(2 rows)
```

</details>

## Recap

- `ROLLUP` makes n + 1 levels, `CUBE` makes 2 to the power n, and `GROUPING SETS` makes exactly what you list.
- `GROUPING(col)` separates a subtotal from a real NULL.
- A portable pivot is one `SUM(CASE ...)` per column.
- Oracle's `PIVOT` has a fixed list, and groups by every column not mentioned.
- A portable unpivot is `UNION ALL`.
- `LISTAGG` on Oracle, `STRING_AGG` on PostgreSQL. Watch the length limits.

**Next:** [Chapter 18: Advanced data changes](18-advanced-dml.md)
