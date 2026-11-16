# 15. Window Functions: Ranking Rows and Looking at Neighbors

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 14](14-cte-and-recursive-queries.md)

> **In one line:** A window function calculates across related rows but keeps every row, while `GROUP BY` collapses them.

## What you will learn

- The difference between a window function and `GROUP BY`
- `ROW_NUMBER`, `RANK` and `DENSE_RANK`, and which to pick from the question's tie rule
- Why window functions are not allowed in `WHERE`, and the standard fix
- Top-N per group, the most asked window function problem
- `LAG` and `LEAD`, month-over-month growth, and the missing month trap

## The core idea

`GROUP BY` gives one row per group. You lose the detail.

```sql
SELECT dept_id, ROUND(AVG(salary), 2) AS dept_avg
FROM employees
WHERE dept_id = 40
GROUP BY dept_id;
```

```text output
 dept_id | dept_avg
---------+----------
      40 | 76500.00
(1 row)
```

A window function gives the same number, but keeps every row. So you can show the detail and the group value side by side.

```sql
SELECT first_name, dept_id, salary,
       ROUND(AVG(salary) OVER (PARTITION BY dept_id), 2) AS dept_avg
FROM employees
WHERE dept_id = 40
ORDER BY emp_id;
```

```text output
 first_name | dept_id | salary | dept_avg
------------+---------+--------+----------
 Omar       |      40 |  95000 | 76500.00
 Nina       |      40 |  58000 | 76500.00
(2 rows)
```

The word "window" means the set of rows the function can see for the current row.

## Anatomy of OVER

`OVER (...)` is what makes a function a window function. It has three optional parts:

```text
function() OVER (PARTITION BY ...   which rows belong together
                 ORDER BY ...       their order inside the window
                 ROWS BETWEEN ...)  a sliding subset (Chapter 16)
```

See what each part does:

```sql
SELECT first_name, salary,
       SUM(salary) OVER () AS whole_table,
       SUM(salary) OVER (PARTITION BY dept_id) AS whole_dept,
       ROW_NUMBER() OVER (ORDER BY salary DESC, emp_id) AS pay_position
FROM employees
WHERE dept_id IN (20, 40)
ORDER BY emp_id;
```

```text output
 first_name | salary | whole_table | whole_dept | pay_position
------------+--------+-------------+------------+--------------
 James      |  95000 |      420000 |     267000 |            1
 Omar       |  95000 |      420000 |     153000 |            2
 Lena       |  60000 |      420000 |     267000 |            3
 Diego      |  60000 |      420000 |     267000 |            4
 Mei        |  52000 |      420000 |     267000 |            6
 Nina       |  58000 |      420000 |     153000 |            5
(6 rows)
```

- `OVER ()` treats all rows as one window.
- `PARTITION BY` alone gives a value per group.
- `ORDER BY` alone ranks across all rows.

Three facts to remember:

- `PARTITION BY` does not remove rows, and it does not sort the output.
- The `ORDER BY` inside `OVER` orders only the calculation. The result still needs its own final `ORDER BY`.
- NULL keys form one partition. Tom Baker's NULL `dept_id` is a group of one.

## Where window functions run

Window functions run after `FROM`, `WHERE`, `GROUP BY` and `HAVING`, and before `DISTINCT`, the final `ORDER BY` and row limiting. Two things follow:

1. They see only the rows that survived those earlier steps.
2. They are allowed only in the `SELECT` list and `ORDER BY`.

So this fails:

```sql error=window
SELECT first_name, ROW_NUMBER() OVER (ORDER BY salary DESC) AS rn
FROM employees
WHERE ROW_NUMBER() OVER (ORDER BY salary DESC) = 1;
```

```text output
ERROR:  window functions are not allowed in WHERE
LINE 3: WHERE ROW_NUMBER() OVER (ORDER BY salary DESC) = 1;
              ^
```

Oracle gives `ORA-30483: window functions are not allowed here`.

**The fix is a wrapper.** Compute the value in a CTE or a derived table, then filter in the outer query. You will use this pattern constantly.

```sql
WITH ranked AS (
  SELECT first_name, salary,
         ROW_NUMBER() OVER (ORDER BY salary DESC, emp_id) AS rn
  FROM employees
)
SELECT first_name, salary
FROM ranked
WHERE rn = 1;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
(1 row)
```

Some engines have `QUALIFY`, which filters on a window result in one query block, the way `HAVING` filters groups. Snowflake, BigQuery, Databricks, DuckDB and Oracle 26ai have it. PostgreSQL, MySQL and SQL Server do not. Use the wrapper in an interview unless you know the engine.

### Employees above their department average

This is a common question, and now you have two answers.

```sql
WITH with_avg AS (
  SELECT first_name, dept_id, salary,
         AVG(salary) OVER (PARTITION BY dept_id) AS dept_avg
  FROM employees
)
SELECT first_name, dept_id, salary, ROUND(dept_avg, 2) AS dept_avg
FROM with_avg
WHERE salary > dept_avg
ORDER BY dept_id, first_name;
```

```text output
 first_name | dept_id | salary | dept_avg
------------+---------+--------+----------
 James      |      20 |  95000 | 66750.00
 Arjun      |      30 | 105000 | 97250.00
 Priya      |      30 | 120000 | 97250.00
 Omar       |      40 |  95000 | 76500.00
(4 rows)
```

Prefer this over the correlated subquery from [Chapter 13](../part-2-sql-basics/13-subqueries.md) when you also want the average in the output. They differ on NULL keys: with `>=`, the window form returns Tom Baker, alone in the NULL partition, and the correlated form does not.

### Nesting rules

An aggregate can sit inside a window call, because `GROUP BY` runs first:

```sql
SELECT dept_id, SUM(salary) AS total_pay,
       RANK() OVER (ORDER BY SUM(salary) DESC) AS pay_rank
FROM employees
WHERE dept_id IS NOT NULL
GROUP BY dept_id
ORDER BY pay_rank;
```

```text output
 dept_id | total_pay | pay_rank
---------+-----------+----------
      30 |    389000 |        1
      20 |    267000 |        2
      10 |    180000 |        3
      40 |    153000 |        4
(4 rows)
```

A window function cannot sit inside an aggregate, or inside another window function. Compute it in a CTE first.

## ROW_NUMBER vs RANK vs DENSE_RANK

Here is the most common window function question. Watch what each does with the tied salaries.

```sql
SELECT first_name, salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC, emp_id) AS row_num,
       RANK()       OVER (ORDER BY salary DESC) AS rnk,
       DENSE_RANK() OVER (ORDER BY salary DESC) AS dense_rnk
FROM employees
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary | row_num | rnk | dense_rnk
------------+--------+---------+-----+-----------
 Sara       | 180000 |       1 |   1 |         1
 Priya      | 120000 |       2 |   2 |         2
 Arjun      | 105000 |       3 |   3 |         3
 James      |  95000 |       4 |   4 |         4
 Omar       |  95000 |       5 |   4 |         4
 Emma       |  82000 |       6 |   6 |         5
 Yusuf      |  82000 |       7 |   6 |         5
 Lena       |  60000 |       8 |   8 |         6
 Diego      |  60000 |       9 |   8 |         6
 Nina       |  58000 |      10 |  10 |         7
 Mei        |  52000 |      11 |  11 |         8
 Tom        |  30000 |      12 |  12 |         9
(12 rows)
```

| Function | On a tie | Pattern |
|---|---|---|
| `ROW_NUMBER` | Always unique | 1, 2, 3, 4 |
| `RANK` | Same rank, then a gap | 1, 1, 3, 4 |
| `DENSE_RANK` | Same rank, no gap | 1, 1, 2, 3 |

**`ROW_NUMBER` on ties is not repeatable.** Tied rows can swap numbers between runs. That is why the query above has `emp_id` as a tie-breaker.

### Choose from the tie rule in the question

| The question says | Use | Why |
|---|---|---|
| Exactly one row per group | `ROW_NUMBER` | It never ties |
| Top 3 distinct salaries, or Nth highest | `DENSE_RANK` | No gaps |
| Competition ranking: a tie for first means the next person is third | `RANK` | It leaves gaps |

Say the tie rule out loud in an interview. If the question does not state it, ask.

### NULLs in ranking

With `ORDER BY commission DESC`, Oracle and PostgreSQL sort NULLs first, so people with no commission take the top ranks.

```sql
SELECT first_name, commission,
       RANK() OVER (ORDER BY commission DESC) AS wrong_rank,
       RANK() OVER (ORDER BY commission DESC NULLS LAST) AS right_rank
FROM employees
WHERE dept_id = 20 OR emp_id = 1
ORDER BY right_rank;
```

```text output
 first_name | commission | wrong_rank | right_rank
------------+------------+------------+------------
 Lena       |       8000 |          2 |          1
 Diego      |       6500 |          3 |          2
 James      |       5000 |          4 |          3
 Mei        |          0 |          5 |          4
 Sara       |       NULL |          1 |          5
(5 rows)
```

Add `NULLS LAST`, or filter the NULLs out. MySQL and SQL Server sort NULLs lowest, and have no `NULLS LAST`.

### Aggregate first, then rank

Rank totals, not raw transactions. Which customers spent the most?

```sql
WITH spend AS (
  SELECT o.customer_id, SUM(i.quantity * i.unit_price) AS total_spent
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  GROUP BY o.customer_id
)
SELECT customer_id, total_spent,
       DENSE_RANK() OVER (ORDER BY total_spent DESC) AS spend_rank
FROM spend
ORDER BY spend_rank;
```

```text output
 customer_id | total_spent | spend_rank
-------------+-------------+------------
           6 |     2337.50 |          1
           3 |     1985.00 |          2
           2 |     1472.00 |          3
           4 |     1137.99 |          4
           1 |     1037.45 |          5
           5 |     1016.98 |          6
(6 rows)
```

## Top-N overall: a recap

[Chapter 8](../part-2-sql-basics/08-select-filter-sort.md) covered this:

- `FETCH FIRST n ROWS ONLY` on Oracle 12c and later, and PostgreSQL
- `LIMIT` on PostgreSQL and MySQL
- `TOP` or `OFFSET ... FETCH` on SQL Server

On Oracle, `WHERE ROWNUM <= 10 ORDER BY salary DESC` does **not** give the top 10 earners, because `ROWNUM` is given out before the sort. On 11g, sort in an inline view and apply `ROWNUM` outside it, or use `ROW_NUMBER()`.

## Top-N per group

**Find the top 2 earners in each department.** `GROUP BY` cannot do this, because it collapses the rows you need. This is the pattern to memorize: rank with `PARTITION BY` in a CTE, then filter on the rank outside.

```sql
WITH ranked AS (
  SELECT first_name, dept_id, salary,
         DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS pay_rank
  FROM employees
  WHERE dept_id IS NOT NULL
)
SELECT dept_id, first_name, salary, pay_rank
FROM ranked
WHERE pay_rank <= 2
ORDER BY dept_id, pay_rank, first_name;
```

```text output
 dept_id | first_name | salary | pay_rank
---------+------------+--------+----------
      10 | Sara       | 180000 |        1
      20 | James      |  95000 |        1
      20 | Diego      |  60000 |        2
      20 | Lena       |  60000 |        2
      30 | Priya      | 120000 |        1
      30 | Arjun      | 105000 |        2
      40 | Omar       |  95000 |        1
      40 | Nina       |  58000 |        2
(8 rows)
```

Dept 20 returns 3 people, because Lena and Diego tie for second. If you need exactly 2 rows, use `ROW_NUMBER` with a tie-breaker, and be ready to say that a tied person is being dropped. [Chapter 21](../part-3-advanced-sql/21-classic-query-patterns.md) collects the variants.

## NTILE, PERCENT_RANK and CUME_DIST

| Function | Gives |
|---|---|
| `NTILE(n)` | A bucket number from 1 to n. Bucket sizes differ by at most one, and earlier buckets are larger |
| `PERCENT_RANK()` | (rank - 1) / (rows - 1) |
| `CUME_DIST()` | The share of rows at or before the current row |

```sql
SELECT first_name, salary,
       NTILE(3) OVER (ORDER BY salary DESC, emp_id) AS pay_band,
       CAST(PERCENT_RANK() OVER (ORDER BY salary DESC) AS NUMERIC(4,2)) AS pct_rank,
       CAST(CUME_DIST() OVER (ORDER BY salary DESC) AS NUMERIC(4,2)) AS cume
FROM employees
WHERE dept_id IN (20, 30)
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary | pay_band | pct_rank | cume
------------+--------+----------+----------+------
 Priya      | 120000 |        1 |     0.00 | 0.13
 Arjun      | 105000 |        1 |     0.14 | 0.25
 James      |  95000 |        1 |     0.29 | 0.38
 Emma       |  82000 |        2 |     0.43 | 0.63
 Yusuf      |  82000 |        2 |     0.43 | 0.63
 Lena       |  60000 |        2 |     0.71 | 0.88
 Diego      |  60000 |        3 |     0.71 | 0.88
 Mei        |  52000 |        3 |     1.00 | 1.00
(8 rows)
```

Two traps with `NTILE`: tied values can land in different buckets, and it over-selects in small groups. With 12 rows, bucket 1 of `NTILE(100)` holds 8 percent of the rows, not 1 percent. For "the top 1 percent", test `PERCENT_RANK() <= 0.01` instead.

## LAG and LEAD: looking at neighbors

`LAG` reads an earlier row, and `LEAD` reads a later one, in window order.

```text
LAG(expression, offset, default)   offset defaults to 1, default to NULL
```

**How many days passed between each customer's orders?**

```sql
SELECT customer_id, order_id, order_date,
       LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS previous_order,
       order_date - LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS days_since
FROM orders
WHERE customer_id IN (1, 4)
ORDER BY customer_id, order_date;
```

```text output
 customer_id | order_id | order_date | previous_order | days_since
-------------+----------+------------+----------------+------------
           1 |     1001 | 2024-01-05 | NULL           |       NULL
           1 |     1004 | 2024-02-02 | 2024-01-05     |         28
           1 |     1009 | 2024-03-30 | 2024-02-02     |         57
           1 |     1014 | 2024-06-01 | 2024-03-30     |         63
           4 |     1005 | 2024-02-14 | NULL           |       NULL
           4 |     1011 | 2024-04-21 | 2024-02-14     |         67
(6 rows)
```

The first row of each partition gets NULL, which is correct: there is no earlier order. `PARTITION BY` is what stops one customer's order being compared with another customer's.

`ORDER BY` gives `LAG` its meaning. Oracle and SQL Server require it. PostgreSQL accepts its absence, but then returns an arbitrary neighbor.

### LAG replaces a self-join

The old way joins each row to the previous id. It breaks when ids have gaps.

```sql
SELECT cur.order_id, cur.order_date, prev.order_date AS previous_date
FROM orders cur
JOIN orders prev ON prev.order_id = cur.order_id - 1
WHERE cur.order_id <= 1003
ORDER BY cur.order_id;
```

```text output
 order_id | order_date | previous_date
----------+------------+---------------
     1002 | 2024-01-09 | 2024-01-05
     1003 | 2024-01-20 | 2024-01-09
(2 rows)
```

`LAG` needs no consecutive ids, and it keeps the first row:

```sql
SELECT order_id, order_date,
       LAG(order_date) OVER (ORDER BY order_date, order_id) AS previous_date
FROM orders
WHERE order_id <= 1003
ORDER BY order_date, order_id;
```

```text output
 order_id | order_date | previous_date
----------+------------+---------------
     1001 | 2024-01-05 | NULL
     1002 | 2024-01-09 | 2024-01-05
     1003 | 2024-01-20 | 2024-01-09
(3 rows)
```

### Finding a local peak

Use `LAG` and `LEAD` together to compare a value with both neighbors. For example, `amount > LAG(amount) ... AND amount > LEAD(amount) ...` finds days that beat the days around them.

## Month-over-month growth

This is a very common analytics question. First aggregate to one row per month, then compare each month with the previous one.

```sql
WITH monthly AS (
  SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
         SUM(i.quantity * i.unit_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  WHERE o.status <> 'CANCELLED'
  GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
),
with_previous AS (
  SELECT order_month, revenue,
         LAG(revenue) OVER (ORDER BY order_month) AS previous_revenue
  FROM monthly
)
SELECT order_month, revenue, previous_revenue,
       ROUND(100.0 * (revenue - previous_revenue)
             / NULLIF(previous_revenue, 0), 2) AS growth_pct
FROM with_previous
ORDER BY order_month;
```

```text output
 order_month | revenue | previous_revenue | growth_pct
-------------+---------+------------------+------------
 2024-01     | 2411.98 |             NULL |       NULL
 2024-02     | 1108.49 |          2411.98 |     -54.04
 2024-03     |  973.98 |          1108.49 |     -12.13
 2024-04     |  868.00 |           973.98 |     -10.88
 2024-05     | 1178.00 |           868.00 |      35.71
 2024-06     | 2047.47 |          1178.00 |      73.81
(6 rows)
```

Three details interviewers look for:

- The NULL in the first month is correct. Do not replace it with 0, which invents a growth figure.
- `NULLIF` guards against a zero baseline.
- `100.0` avoids integer division on counts on PostgreSQL.

### The missing month trap

`LAG` returns the previous **stored row**, not the previous calendar period. Employee 7 has no orders in April.

```sql
WITH monthly AS (
  SELECT TO_CHAR(order_date, 'YYYY-MM') AS order_month, COUNT(*) AS order_count
  FROM orders
  WHERE emp_id = 7
  GROUP BY TO_CHAR(order_date, 'YYYY-MM')
)
SELECT order_month, order_count,
       LAG(order_month) OVER (ORDER BY order_month) AS compared_with
FROM monthly
ORDER BY order_month;
```

```text output
 order_month | order_count | compared_with
-------------+-------------+---------------
 2024-02     |           1 | NULL
 2024-03     |           1 | 2024-02
 2024-05     |           1 | 2024-03
 2024-06     |           1 | 2024-05
(4 rows)
```

May is compared with March, and nothing warns you. The same problem means `LAG(x, 12)` is a correct year-over-year only when no month is missing.

The fix is to join to a generated list of months first, so that every month has a row. [Chapter 14](14-cte-and-recursive-queries.md) shows a row generator, and [Chapter 20](20-modern-sql.md) covers date series.

## Named windows and engine support

To reuse one window definition, PostgreSQL, MySQL 8.0, Oracle 21c and SQL Server 2022 allow a `WINDOW` clause:

```sql postgres
SELECT first_name,
       RANK() OVER w AS rnk,
       DENSE_RANK() OVER w AS dense_rnk
FROM employees
WHERE dept_id = 30
WINDOW w AS (ORDER BY salary DESC)
ORDER BY rnk, first_name;
```

```text output
 first_name | rnk | dense_rnk
------------+-----+-----------
 Priya      |   1 |         1
 Arjun      |   2 |         2
 Emma       |   3 |         3
 Yusuf      |   3 |         3
(4 rows)
```

Everything else in this chapter runs on your Oracle 11g. PostgreSQL has had window functions since 8.4. SQL Server has had ranking since 2005, and `LAG` and `LEAD` since 2012. MySQL needs 8.0. Each different window order in a query can add a sort step ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Write `ROW_NUMBER() OVER (...) = 1` in `WHERE` | An error, because window functions run after `WHERE` | Wrap the query, and filter outside |
| Believe `PARTITION BY` reduces rows | It does not | Use `GROUP BY`, or filter on a rank |
| Rely on the `ORDER BY` inside `OVER` to sort the output | The output order is not guaranteed | Add a final `ORDER BY` |
| Use `ROW_NUMBER` for "highest paid" when two people tie | One is silently dropped | Use `RANK` or `DENSE_RANK`, or say you want one |
| Use `RANK` for "top 3 distinct salaries" | Gaps leave fewer than three values | Use `DENSE_RANK` |
| Rank raw rows when the question ranks totals | The ranking is meaningless | Aggregate first |
| Use `SELECT DISTINCT` with `ROW_NUMBER` | Every row has a different number, so nothing is removed | Filter on the row number instead |
| Forget `PARTITION BY` in `LAG` | One customer is compared with another | Partition by the customer |
| Replace the first-row NULL from `LAG` with 0 | It invents a growth figure | Leave it NULL |
| Divide by `LAG(x)` with no `NULLIF` | Division by zero, or 0 from integer division | Use `NULLIF` and `100.0` |
| Use `LAG(x, 12)` when months can be missing | The wrong months are compared | Fill the months first |
| Forget `NULLS LAST` on a nullable descending rank | NULLs take the top ranks | Add `NULLS LAST` |
| Write `WHERE ROWNUM <= 10 ORDER BY ...` on Oracle | Ten arbitrary rows are sorted | Sort in an inline view first |

## Interview questions

**Q1. What is the difference between ROW_NUMBER, RANK and DENSE_RANK?**

All three number rows in window order. `ROW_NUMBER` always gives unique numbers: 1, 2, 3, 4. `RANK` gives ties the same number and then leaves a gap: 1, 1, 3, 4. `DENSE_RANK` gives ties the same number with no gap: 1, 1, 2, 3. I choose by the tie rule: `ROW_NUMBER` for exactly one row, `DENSE_RANK` for the Nth distinct value.

**Q2. Why can't you use a window function in WHERE, and what do you do instead?**

Window functions run after `WHERE`, `GROUP BY` and `HAVING`, so the values do not exist yet at `WHERE`. I compute the value in a CTE or derived table and filter in the outer query. Some engines, including Oracle 26ai, also have `QUALIFY`.

**Q3. What is the difference between window functions and GROUP BY?**

`GROUP BY` collapses each group into one row, so the detail is gone. A window function calculates across related rows but keeps every row, so I can show a salary next to its department average.

**Q4. Find the highest-paid employee in each department.**

Use `RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC)` in a CTE, then keep rank 1 outside. `RANK` keeps ties. If only one person may be returned, I use `ROW_NUMBER` with a tie-breaker and say so.

**Q5. Find employees who earn more than the average salary in their department.**

Compute `AVG(salary) OVER (PARTITION BY dept_id)` in a CTE and filter outside with `salary > dept_avg`. A correlated subquery also works. The window form lets me show the average too.

**Q6. Find month-on-month sales growth.**

First aggregate to one row per month. Then use `LAG(revenue) OVER (ORDER BY month)` and compute (current - previous) / previous, with `NULLIF` for a zero baseline. The first month stays NULL. If a month can have no rows, I join to a list of months first, because `LAG` reads the previous row, not the previous month.

**Q7. Why does `WHERE ROWNUM <= 10 ORDER BY salary DESC` not give the top 10 earners in Oracle?**

`ROWNUM` is assigned as rows pass `WHERE`, before `ORDER BY` runs. So it picks 10 arbitrary rows, then sorts them. I would sort in an inline view and apply `ROWNUM` outside, or use `FETCH FIRST 10 ROWS ONLY` from 12c.

## Practice

**1. Number the products within each category, most expensive first.**

<details>
<summary>Show solution</summary>

```sql
SELECT category_id, product_name, price,
       ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price DESC, product_id) AS price_position
FROM products
ORDER BY category_id, price_position;
```

```text output
 category_id |  product_name   |  price  | price_position
-------------+-----------------+---------+----------------
           2 | Phone X         |  799.00 |              1
           2 | Phone Lite      |  399.00 |              2
           3 | Laptop Pro      | 1499.00 |              1
           3 | Laptop Air      |  999.00 |              2
           4 | Desk Lamp       |   35.00 |              1
           5 | Coffee Maker    |   89.50 |              1
           5 | Blender         |   49.00 |              2
           6 | Database Design |   45.00 |              1
           6 | SQL Basics      |   29.00 |              2
           7 | Phone Case      |   19.99 |              1
(10 rows)
```

</details>

**2. Find the third highest distinct salary.**

<details>
<summary>Show solution</summary>

```sql
WITH ranked AS (
  SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS pay_rank
  FROM employees
)
SELECT DISTINCT salary
FROM ranked
WHERE pay_rank = 3;
```

```text output
 salary
--------
 105000
(1 row)
```

</details>

**3. Show each customer's most recent order. If a customer has two on the same day, return one.**

<details>
<summary>Show solution</summary>

```sql
WITH ranked AS (
  SELECT customer_id, order_id, order_date,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC, order_id DESC) AS rn
  FROM orders
)
SELECT customer_id, order_id, order_date
FROM ranked
WHERE rn = 1
ORDER BY customer_id;
```

```text output
 customer_id | order_id | order_date
-------------+----------+------------
           1 |     1014 | 2024-06-01
           2 |     1013 | 2024-05-19
           3 |     1016 | 2024-06-18
           4 |     1011 | 2024-04-21
           5 |     1012 | 2024-05-02
           6 |     1015 | 2024-06-11
(6 rows)
```

</details>

**4. For each order of customer 1, show the next order's date.**

<details>
<summary>Show solution</summary>

```sql
SELECT order_id, order_date,
       LEAD(order_date) OVER (ORDER BY order_date) AS next_order
FROM orders
WHERE customer_id = 1
ORDER BY order_date;
```

```text output
 order_id | order_date | next_order
----------+------------+------------
     1001 | 2024-01-05 | 2024-02-02
     1004 | 2024-02-02 | 2024-03-30
     1009 | 2024-03-30 | 2024-06-01
     1014 | 2024-06-01 | NULL
(4 rows)
```

</details>

**5. Show each employee's salary, and how far it is below the top salary in their department.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, dept_id, salary,
       MAX(salary) OVER (PARTITION BY dept_id) - salary AS below_top
FROM employees
WHERE dept_id IN (20, 40)
ORDER BY dept_id, salary DESC, emp_id;
```

```text output
 first_name | dept_id | salary | below_top
------------+---------+--------+-----------
 James      |      20 |  95000 |         0
 Lena       |      20 |  60000 |     35000
 Diego      |      20 |  60000 |     35000
 Mei        |      20 |  52000 |     43000
 Omar       |      40 |  95000 |         0
 Nina       |      40 |  58000 |     37000
(6 rows)
```

</details>

**6. Rank the sales reps by the revenue of their delivered orders.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.emp_id,
       SUM(i.quantity * i.unit_price) AS revenue,
       RANK() OVER (ORDER BY SUM(i.quantity * i.unit_price) DESC) AS revenue_rank
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.status = 'DELIVERED'
GROUP BY o.emp_id
ORDER BY revenue_rank;
```

```text output
 emp_id | revenue | revenue_rank
--------+---------+--------------
      6 | 2386.50 |            1
      5 | 1750.96 |            2
      7 | 1105.99 |            3
(3 rows)
```

</details>

## Recap

- A window function keeps every row. `GROUP BY` collapses them.
- `PARTITION BY` groups, and `ORDER BY` inside `OVER` orders only the calculation.
- `ROW_NUMBER` is unique, `RANK` leaves gaps, and `DENSE_RANK` does not.
- Window functions run after `WHERE`. Wrap the query and filter outside.
- Top-N per group: rank with `PARTITION BY` in a CTE, then filter on the rank.
- `LAG` and `LEAD` read neighboring rows. Always partition correctly.
- `LAG` reads the previous row, not the previous month. Fill missing months first.

**Next:** [Chapter 16: Frames and running totals](16-window-functions-frames-and-running-totals.md)
