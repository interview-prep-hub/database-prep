# 10. Grouping and Totals: GROUP BY and HAVING

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 9](09-built-in-functions.md)

> **In one line:** An aggregate function turns many rows into one value, and `GROUP BY` does that once per group.

## What you will learn

- What `COUNT`, `SUM`, `AVG`, `MIN` and `MAX` do with NULLs and with zero rows
- The one rule of `GROUP BY`, and the error you get for breaking it
- The difference between `WHERE` and `HAVING`
- How to find duplicates, build side-by-side counts and calculate percentages
- How to trace a grouped query by hand

## Aggregate functions

An aggregate function takes many rows and returns one value. With no `GROUP BY`, the whole table is one group, so you get exactly one row.

```sql
SELECT COUNT(*) AS staff,
       SUM(salary) AS total_pay,
       ROUND(AVG(salary), 2) AS average_pay,
       MIN(salary) AS lowest,
       MAX(salary) AS highest
FROM employees;
```

```text output
 staff | total_pay | average_pay | lowest | highest
-------+-----------+-------------+--------+---------
    12 |   1019000 |    84916.67 |  30000 |  180000
(1 row)
```

`MIN` and `MAX` also work on text and dates:

```sql
SELECT MIN(hire_date) AS first_hire, MAX(hire_date) AS last_hire, MIN(first_name) AS first_alphabetically
FROM employees;
```

```text output
 first_hire | last_hire  | first_alphabetically
------------+------------+----------------------
 2015-01-12 | 2023-07-01 | Arjun
(1 row)
```

### COUNT has three forms

| Form | Counts |
|---|---|
| `COUNT(*)` | Rows |
| `COUNT(col)` | Rows where `col` is not NULL |
| `COUNT(DISTINCT col)` | Different non-NULL values |

```sql
SELECT COUNT(*) AS all_rows,
       COUNT(commission) AS with_commission,
       COUNT(DISTINCT dept_id) AS departments_used
FROM employees;
```

```text output
 all_rows | with_commission | departments_used
----------+-----------------+------------------
       12 |               4 |                4
(1 row)
```

### Aggregates skip NULLs

Every aggregate except `COUNT(*)` ignores NULLs. This changes the meaning of an average.

```sql
SELECT ROUND(AVG(commission), 2) AS avg_skipping_nulls,
       ROUND(SUM(commission) / COUNT(*), 2) AS avg_over_everyone,
       ROUND(AVG(COALESCE(commission, 0)), 2) AS avg_null_as_zero
FROM employees;
```

```text output
 avg_skipping_nulls | avg_over_everyone | avg_null_as_zero
--------------------+-------------------+------------------
            4875.00 |           1625.00 |          1625.00
(1 row)
```

`AVG(commission)` divides by the 4 people with a value. The other two divide by all 12. Neither is wrong by itself. You have to decide what a missing value means. If it means zero, use `COALESCE`.

### Aggregates over zero rows

If no rows match, you still get one row. `COUNT` gives 0 and the others give NULL.

```sql
SELECT COUNT(*) AS how_many, SUM(salary) AS total, MAX(salary) AS highest
FROM employees
WHERE emp_id = 999;
```

```text output
 how_many | total | highest
----------+-------+---------
        0 |  NULL |    NULL
(1 row)
```

So when a report should show 0, write `COALESCE(SUM(x), 0)`:

```sql
SELECT COALESCE(SUM(salary), 0) AS total
FROM employees
WHERE emp_id = 999;
```

```text output
 total
-------
     0
(1 row)
```

With `GROUP BY` it is different: zero input rows give zero output rows, because there are no groups.

### DISTINCT inside an aggregate

`SUM(DISTINCT x)` and `AVG(DISTINCT x)` use each different value once.

```sql
SELECT SUM(salary) AS total, SUM(DISTINCT salary) AS total_of_different_values
FROM employees;
```

```text output
  total  | total_of_different_values
---------+---------------------------
 1019000 |                    782000
(1 row)
```

`COUNT(DISTINCT a, b)` works only on MySQL. Elsewhere, count distinct pairs with a subquery ([Chapter 13](13-subqueries.md)).

### Is COUNT(1) faster than COUNT(*)?

No. This is a myth. Benchmarks show no meaningful difference on Oracle, MySQL or SQL Server, and on PostgreSQL `COUNT(*)` was slightly faster in one published benchmark. The difference that matters is with `COUNT(col)`, which can give a different **answer**.

### Why is COUNT(*) slow on a big PostgreSQL table?

PostgreSQL stores no row count, because different transactions can see different rows ([Chapter 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md)). So it has to check row by row, usually by scanning the table or an index. If a rough number is enough, read the planner's estimate from `pg_class.reltuples`.

## GROUP BY

`GROUP BY` splits rows into groups, and each group produces one output row.

```sql
SELECT dept_id, COUNT(*) AS staff, SUM(salary) AS total_pay
FROM employees
GROUP BY dept_id
ORDER BY dept_id;
```

```text output
 dept_id | staff | total_pay
---------+-------+-----------
      10 |     1 |    180000
      20 |     4 |    267000
      30 |     4 |    389000
      40 |     2 |    153000
    NULL |     1 |     30000
(5 rows)
```

Look at the last row. NULL values form one group, even though `NULL = NULL` is not true. That row is Tom Baker. This surprises people.

Here is what happened:

```text
All 12 rows
    |
    |  split by dept_id
    v
dept 10: Sara                        -> 1 row:  10, count 1, sum 180000
dept 20: James, Lena, Diego, Mei     -> 1 row:  20, count 4, sum 267000
dept 30: Priya, Arjun, Emma, Yusuf   -> 1 row:  30, count 4, sum 389000
dept 40: Omar, Nina                  -> 1 row:  40, count 2, sum 153000
NULL:    Tom                         -> 1 row:  NULL, count 1, sum 30000
```

Group by several columns to get one row per combination:

```sql
SELECT dept_id, job_title, COUNT(*) AS staff
FROM employees
WHERE dept_id IN (20, 30)
GROUP BY dept_id, job_title
ORDER BY dept_id, job_title;
```

```text output
 dept_id |      job_title      | staff
---------+---------------------+-------
      20 | Sales Manager       |     1
      20 | Sales Rep           |     3
      30 | Developer           |     2
      30 | Engineering Manager |     1
      30 | Senior Developer    |     1
(5 rows)
```

`GROUP BY` does not sort. If the order matters, add `ORDER BY`.

### The GROUP BY rule

**Every column in `SELECT` must be inside an aggregate, or listed in `GROUP BY`.**

The reason is simple. A group holds many rows, so `first_name` has many values in it. The database cannot pick one.

```sql error=must
SELECT dept_id, first_name, COUNT(*) AS staff
FROM employees
GROUP BY dept_id;
```

```text output
ERROR:  column "employees.first_name" must appear in the GROUP BY clause or be used in an aggregate function
LINE 1: SELECT dept_id, first_name, COUNT(*) AS staff
                        ^
```

Oracle gives `ORA-00979: not a GROUP BY expression`. MySQL's strict mode gives an `ONLY_FULL_GROUP_BY` error.

Two exceptions are worth knowing:

- PostgreSQL and MySQL allow other columns of a table when you group by its primary key, because the key fixes their values. This is called functional dependence.
- `ANY_VALUE(col)` deliberately picks one value from the group. It exists on MySQL, Oracle from 19c, and PostgreSQL from 16.

### The top-earner trap

This looks like "the top earner in each department", and it is a classic wrong answer:

```sql error=must
SELECT dept_id, first_name, MAX(salary) AS top_salary
FROM employees
GROUP BY dept_id;
```

```text output
ERROR:  column "employees.first_name" must appear in the GROUP BY clause or be used in an aggregate function
LINE 1: SELECT dept_id, first_name, MAX(salary) AS top_salary
                        ^
```

Strict engines reject it. Old MySQL modes accept it and return some name beside the maximum, with no link between the two. An aggregate gives you a **value**, not the row that holds it. [Chapter 13](13-subqueries.md) solves this with a subquery, and [Chapter 15](../part-3-advanced-sql/15-window-functions-ranking-and-offset.md) with a window function.

## WHERE vs HAVING

- `WHERE` filters **rows**, before grouping.
- `HAVING` filters **groups**, after aggregation.

`WHERE` runs before any group exists, so an aggregate cannot go there:

```sql error=aggregate
SELECT dept_id, COUNT(*) AS staff
FROM employees
WHERE COUNT(*) > 1
GROUP BY dept_id;
```

```text output
ERROR:  aggregate functions are not allowed in WHERE
LINE 3: WHERE COUNT(*) > 1
              ^
```

Oracle gives `ORA-00934: group function is not allowed here`. Use `HAVING`:

```sql
SELECT dept_id, COUNT(*) AS staff
FROM employees
GROUP BY dept_id
HAVING COUNT(*) > 1
ORDER BY dept_id;
```

```text output
 dept_id | staff
---------+-------
      20 |     4
      30 |     4
      40 |     2
(3 rows)
```

You will often use both in one query. This one ignores low salaries, then keeps departments with a high total:

```sql
SELECT dept_id, COUNT(*) AS staff, SUM(salary) AS total_pay
FROM employees
WHERE salary >= 60000
GROUP BY dept_id
HAVING SUM(salary) > 200000
ORDER BY dept_id;
```

```text output
 dept_id | staff | total_pay
---------+-------+-----------
      20 |     3 |    215000
      30 |     4 |    389000
(2 rows)
```

Three details:

- `HAVING` can test an aggregate that is not in `SELECT`.
- A plain row test such as `HAVING dept_id = 20` works, but it filters later than it should. Move it to `WHERE`, so that fewer rows are grouped.
- `HAVING` without `GROUP BY` treats the whole table as one group, so you get one row or none.

```sql
SELECT COUNT(*) AS staff
FROM employees
HAVING COUNT(*) > 100;
```

```text output
 staff
-------
(0 rows)
```

### Trace a query by hand

Exams and interviews often ask you to work out a grouped query on paper. Take the query above with `WHERE salary >= 60000`.

```text
Step 1  FROM      all 12 employees
Step 2  WHERE     salary >= 60000 removes Mei, Nina and Tom, leaving 9 rows
Step 3  GROUP BY  dept 10: Sara
                  dept 20: James, Lena, Diego
                  dept 30: Priya, Arjun, Emma, Yusuf
                  dept 40: Omar
Step 4  HAVING    SUM(salary) > 200000
                  dept 10: 180000  removed
                  dept 20: 215000  kept
                  dept 30: 389000  kept
                  dept 40: 95000   removed
Step 5  SELECT    compute dept_id, COUNT(*), SUM(salary)
Step 6  ORDER BY  sort by dept_id
```

## Grouping by an expression

You can group by a calculation. On Oracle before 23ai you must repeat the full expression, because `GROUP BY` does not accept the alias.

```sql
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*) AS hires
FROM employees
GROUP BY EXTRACT(YEAR FROM hire_date)
ORDER BY hire_year;
```

```text output
 hire_year | hires
-----------+-------
      2015 |     1
      2016 |     2
      2017 |     1
      2018 |     2
      2019 |     1
      2020 |     1
      2021 |     2
      2022 |     1
      2023 |     1
(9 rows)
```

## DISTINCT vs GROUP BY

For plain de-duplication these two give the same rows. Use `DISTINCT` when you only want unique rows, and `GROUP BY` when you need aggregates.

```sql
SELECT DISTINCT country
FROM customers
WHERE country IS NOT NULL
ORDER BY country;
```

```sql
SELECT country
FROM customers
WHERE country IS NOT NULL
GROUP BY country
ORDER BY country;
```

```text output
 country
---------
 Canada
 France
 Japan
 UAE
 UK
(5 rows)
```

## Finding duplicates

This is a very common interview task. Group by what should be unique, and keep the groups with more than one row.

```sql
SELECT salary, COUNT(*) AS people
FROM employees
GROUP BY salary
HAVING COUNT(*) > 1
ORDER BY salary;
```

```text output
 salary | people
--------+--------
  60000 |      2
  82000 |      2
  95000 |      2
(3 rows)
```

[Chapter 18](../part-3-advanced-sql/18-advanced-dml.md) shows how to list the full duplicate rows and delete them.

## Conditional aggregation

Put a `CASE` inside an aggregate to count only some rows. This builds side-by-side columns in a single row per group, which is a simple pivot.

```sql
SELECT customer_id,
       COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS delivered,
       COUNT(CASE WHEN status = 'PENDING' THEN 1 END) AS pending,
       SUM(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled,
       COUNT(*) AS all_orders
FROM orders
GROUP BY customer_id
ORDER BY customer_id;
```

```text output
 customer_id | delivered | pending | cancelled | all_orders
-------------+-----------+---------+-----------+------------
           1 |         3 |       1 |         0 |          4
           2 |         1 |       0 |         1 |          3
           3 |         2 |       1 |         0 |          3
           4 |         1 |       0 |         0 |          2
           5 |         1 |       0 |         0 |          2
           6 |         1 |       1 |         0 |          2
(6 rows)
```

A `CASE` with no `ELSE` gives NULL when nothing matches, and `COUNT` skips NULLs. That is why the first form works. **Trap:** `COUNT(CASE WHEN ... THEN 1 ELSE 0 END)` counts every row, because 0 is not NULL. Drop the `ELSE`, or use `SUM`.

PostgreSQL has a cleaner form, which Oracle also gained in 26ai:

```sql postgres
SELECT COUNT(*) FILTER (WHERE status = 'DELIVERED') AS delivered
FROM orders;
```

```text output
 delivered
-----------
         9
(1 row)
```

### Salary bands

**How do you count employees per salary band in one query?** One way gives a row per band. Repeat the `CASE` in `GROUP BY` for Oracle before 23ai.

```sql
SELECT CASE WHEN salary < 60000 THEN 'Low'
            WHEN salary < 100000 THEN 'Medium'
            ELSE 'High'
       END AS band,
       COUNT(*) AS staff
FROM employees
GROUP BY CASE WHEN salary < 60000 THEN 'Low'
              WHEN salary < 100000 THEN 'Medium'
              ELSE 'High'
         END
ORDER BY staff DESC, band;
```

```text output
  band  | staff
--------+-------
 Medium |     6
 High   |     3
 Low    |     3
(3 rows)
```

The other gives one column per band:

```sql
SELECT COUNT(CASE WHEN salary < 60000 THEN 1 END) AS low_band,
       COUNT(CASE WHEN salary >= 60000 AND salary < 100000 THEN 1 END) AS medium_band,
       COUNT(CASE WHEN salary >= 100000 THEN 1 END) AS high_band
FROM employees;
```

```text output
 low_band | medium_band | high_band
----------+-------------+-----------
        3 |           6 |         3
(1 row)
```

**Trap:** in the first form, a band with no employees is simply missing. `GROUP BY` cannot invent rows that do not exist. To show it with 0, start from a list of bands and `LEFT JOIN` ([Chapter 11](11-joins.md)).

### Percentages

Multiply by `100.0` first, and guard against dividing by zero with `NULLIF`.

```sql
SELECT ROUND(100.0 * COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END)
             / NULLIF(COUNT(*), 0), 2) AS delivered_pct
FROM orders;
```

```text output
 delivered_pct
---------------
         56.25
(1 row)
```

Without the `100.0`, PostgreSQL divides integer by integer, so 9 divided by 16 gives 0. Oracle gives 0.5625, because it has no integer division.

```sql postgres
SELECT COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) / COUNT(*) AS wrong_on_postgres
FROM orders;
```

```text output
 wrong_on_postgres
-------------------
                 0
(1 row)
```

## Grouping by month

Always include the year. Grouping by month alone merges January 2023 with January 2024.

```sql
SELECT EXTRACT(MONTH FROM signup_date) AS signup_month, COUNT(*) AS signups
FROM customers
WHERE EXTRACT(MONTH FROM signup_date) = 1
GROUP BY EXTRACT(MONTH FROM signup_date);
```

```text output
 signup_month | signups
--------------+---------
            1 |       2
(1 row)
```

```sql
SELECT TO_CHAR(signup_date, 'YYYY-MM') AS signup_month, COUNT(*) AS signups
FROM customers
WHERE EXTRACT(MONTH FROM signup_date) = 1
GROUP BY TO_CHAR(signup_date, 'YYYY-MM')
ORDER BY signup_month;
```

```text output
 signup_month | signups
--------------+---------
 2023-01      |       1
 2024-01      |       1
(2 rows)
```

**Worked question: the average review rating for every product, every month.** This one has been reported at Amazon. Here is a small demo table.

```sql
CREATE TABLE reviews (
  review_id   INTEGER PRIMARY KEY,
  product_id  INTEGER NOT NULL,
  stars       INTEGER NOT NULL,
  review_date DATE NOT NULL
);

INSERT INTO reviews VALUES (1, 1, 5, DATE '2024-06-08');
INSERT INTO reviews VALUES (2, 1, 4, DATE '2024-06-20');
INSERT INTO reviews VALUES (3, 2, 2, DATE '2024-06-18');
INSERT INTO reviews VALUES (4, 1, 3, DATE '2024-07-01');
INSERT INTO reviews VALUES (5, 2, 4, DATE '2024-07-04');
```

```sql
SELECT TO_CHAR(review_date, 'YYYY-MM') AS review_month,
       product_id,
       ROUND(AVG(stars), 2) AS avg_stars
FROM reviews
GROUP BY TO_CHAR(review_date, 'YYYY-MM'), product_id
ORDER BY review_month, product_id;
```

```text output
 review_month | product_id | avg_stars
--------------+------------+-----------
 2024-06      |          1 |      4.50
 2024-06      |          2 |      2.00
 2024-07      |          1 |      3.00
 2024-07      |          2 |      4.00
(4 rows)
```

```sql
DROP TABLE reviews;
```

## Joining rows into one string

Each database has a function that joins a group's values into one text value.

**Oracle (from 11.2):**

```sql oracle
SELECT dept_id,
       LISTAGG(first_name, ', ') WITHIN GROUP (ORDER BY first_name) AS staff
FROM employees
WHERE dept_id IN (20, 40)
GROUP BY dept_id
ORDER BY dept_id;
```

**PostgreSQL (and SQL Server from 2017):**

```sql postgres
SELECT dept_id,
       STRING_AGG(first_name, ', ' ORDER BY first_name) AS staff
FROM employees
WHERE dept_id IN (20, 40)
GROUP BY dept_id
ORDER BY dept_id;
```

```text output
 dept_id |          staff
---------+-------------------------
      20 | Diego, James, Lena, Mei
      40 | Nina, Omar
(2 rows)
```

**MySQL:**

```sql mysql
SELECT dept_id, GROUP_CONCAT(first_name ORDER BY first_name SEPARATOR ', ') AS staff
FROM employees
GROUP BY dept_id;
```

MySQL's `GROUP_CONCAT` cuts off long results at `group_concat_max_len`, which is 1024 bytes by default, and it raises no error. [Chapter 17](../part-3-advanced-sql/17-advanced-grouping-and-pivot.md) goes deeper, and also covers `ROLLUP`, `CUBE` and `GROUPING SETS` for subtotal rows.

## A few more things

**Largest group, keeping ties.** Sort by the aggregate, then limit.

```sql since=12c
SELECT dept_id, COUNT(*) AS staff
FROM employees
GROUP BY dept_id
ORDER BY COUNT(*) DESC
FETCH FIRST 1 ROW WITH TIES;
```

```text output
 dept_id | staff
---------+-------
      30 |     4
      20 |     4
(2 rows)
```

**Nested aggregates** such as `SELECT AVG(MAX(salary)) FROM employees GROUP BY dept_id` work on Oracle. PostgreSQL rejects them, so use a subquery.

**`AVG` on SQL Server.** On an integer column it returns an integer, so cast first. PostgreSQL and Oracle keep the fraction.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Select a column that is neither grouped nor aggregated | An error, or a random value on old MySQL | Add it to `GROUP BY`, or aggregate it |
| Use `SELECT name, MAX(salary)` to find the top earner | The name is not linked to the maximum | Use a subquery or window function |
| Put an aggregate in `WHERE` | `WHERE` runs before groups exist | Use `HAVING` |
| Put plain row filters in `HAVING` | Rows are grouped for nothing | Use `WHERE` |
| Use `AVG` where NULL really means zero | The average comes out too high | Use `AVG(COALESCE(x, 0))` |
| Forget `COALESCE(SUM(x), 0)` | A report shows NULL instead of 0 | Add `COALESCE` |
| Use `COUNT(col)` when you mean rows | NULL rows are not counted | Use `COUNT(*)` |
| Write `COUNT(CASE ... ELSE 0 END)` | It counts every row | Drop the `ELSE`, or use `SUM` |
| Group by month without the year | Different years are merged | Group by year and month |
| Expect `GROUP BY` to sort | The order is not guaranteed | Add `ORDER BY` |
| Expect an empty band to appear | `GROUP BY` cannot invent rows | `LEFT JOIN` from a list of bands |
| Divide one `COUNT` by another on PostgreSQL | Integer division gives 0 | Multiply by `100.0` first |
| Claim `COUNT(1)` is faster than `COUNT(*)` | It is not | Use `COUNT(*)` |
| Trust `GROUP_CONCAT` on long lists | Silently cut off at 1024 bytes | Raise `group_concat_max_len` |
| Be surprised by a blank row | NULLs form their own group | Filter with `IS NOT NULL` if unwanted |

## Interview questions

**Q1. What is the difference between WHERE and HAVING? Can you use an aggregate in WHERE?**

`WHERE` filters rows before grouping, and `HAVING` filters groups after aggregation. You cannot use an aggregate in `WHERE`, because it runs before any group exists. Oracle gives `ORA-00934`. I put row filters in `WHERE` and aggregate filters in `HAVING`.

**Q2. What is the difference between COUNT(*), COUNT(column) and COUNT(DISTINCT column)?**

`COUNT(*)` counts rows, including rows full of NULLs. `COUNT(column)` counts rows where that column is not NULL. `COUNT(DISTINCT column)` counts different non-NULL values.

**Q3. Is COUNT(1) faster than COUNT(*)? Why is a plain COUNT(*) slow on a large PostgreSQL table?**

No, that is a myth. They are effectively the same. On PostgreSQL a plain `COUNT(*)` is slow because no row count is stored. Under MVCC, different transactions can see different rows, so it has to check visibility row by row. If an estimate is enough, I read `pg_class.reltuples`.

**Q4. How do you find duplicate records in a table?**

Group by the columns that should be unique, and use `HAVING COUNT(*) > 1`. To see the whole rows, I join back to the table or use `ROW_NUMBER`.

**Q5. How do you count employees per salary band in one query?**

Either group by a `CASE` expression, which gives one row per band, or use conditional aggregation, which gives one column per band. With the first form, a band with no rows is missing, so if it must show 0, I start from a list of bands and left join.

**Q6. Write a query to get the average review rating for every product every month.**

Group by the year and month together, plus the product, and take `AVG(stars)`. The common bug is grouping by month alone, which merges different years.

**Q7. Can you use HAVING without GROUP BY?**

Yes. The whole table is then one group, so the query returns one row or none, depending on the condition.

**Q8. What does SUM return when no rows match, and how do you return 0 instead?**

It returns NULL, in one row. `COUNT` returns 0. I wrap it as `COALESCE(SUM(x), 0)`.

**Q9. Why does AVG sometimes give a higher number than you expect?**

Because `AVG` skips NULLs, so it divides by the number of non-NULL rows. If NULL really means zero, I use `AVG(COALESCE(x, 0))`.

## Practice

**1. Show each order status with its number of orders, most common first.**

<details>
<summary>Show solution</summary>

```sql
SELECT status, COUNT(*) AS order_count
FROM orders
GROUP BY status
ORDER BY order_count DESC, status;
```

```text output
  status   | order_count
-----------+-------------
 DELIVERED |           9
 PENDING   |           3
 SHIPPED   |           3
 CANCELLED |           1
(4 rows)
```

</details>

**2. Show the total paid by each payment method, in descending order of total.**

<details>
<summary>Show solution</summary>

```sql
SELECT method, SUM(amount) AS total_paid
FROM payments
GROUP BY method
ORDER BY total_paid DESC;
```

```text output
 method | total_paid
--------+------------
 BANK   |    2748.00
 CARD   |    2227.47
 WALLET |    1065.98
(3 rows)
```

</details>

**3. Find customers with more than 2 orders.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_id, COUNT(*) AS order_count
FROM orders
GROUP BY customer_id
HAVING COUNT(*) > 2
ORDER BY customer_id;
```

```text output
 customer_id | order_count
-------------+-------------
           1 |           4
           2 |           3
           3 |           3
(3 rows)
```

</details>

**4. Show the revenue of each product, from delivered orders only, highest first.**

<details>
<summary>Show solution</summary>

```sql
SELECT p.product_name, SUM(i.quantity * i.unit_price) AS revenue
FROM order_items i
JOIN orders o ON o.order_id = i.order_id
JOIN products p ON p.product_id = i.product_id
WHERE o.status = 'DELIVERED'
GROUP BY p.product_id, p.product_name
ORDER BY revenue DESC, p.product_name;
```

```text output
  product_name   | revenue
-----------------+---------
 Phone X         | 1548.00
 Laptop Pro      | 1499.00
 Laptop Air      |  999.00
 Phone Lite      |  798.00
 SQL Basics      |  116.00
 Phone Case      |   99.95
 Coffee Maker    |   89.50
 Blender         |   49.00
 Database Design |   45.00
(9 rows)
```

</details>

**5. Show, per month in 2024, the number of orders and how many were cancelled.**

<details>
<summary>Show solution</summary>

```sql
SELECT TO_CHAR(order_date, 'YYYY-MM') AS order_month,
       COUNT(*) AS order_count,
       COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) AS cancelled
FROM orders
GROUP BY TO_CHAR(order_date, 'YYYY-MM')
ORDER BY order_month;
```

```text output
 order_month | order_count | cancelled
-------------+-------------+-----------
 2024-01     |           3 |         0
 2024-02     |           3 |         1
 2024-03     |           3 |         0
 2024-04     |           2 |         0
 2024-05     |           2 |         0
 2024-06     |           3 |         0
(6 rows)
```

</details>

**6. Find departments where the average salary is above the company average. (This needs a small subquery.)**

<details>
<summary>Show solution</summary>

```sql
SELECT dept_id, ROUND(AVG(salary), 2) AS average_pay
FROM employees
WHERE dept_id IS NOT NULL
GROUP BY dept_id
HAVING AVG(salary) > (SELECT AVG(salary) FROM employees)
ORDER BY dept_id;
```

```text output
 dept_id | average_pay
---------+-------------
      10 |   180000.00
      30 |    97250.00
(2 rows)
```

</details>

## Recap

- `COUNT(*)` counts rows, `COUNT(col)` skips NULLs, and every other aggregate skips NULLs too.
- Over zero rows, `COUNT` gives 0 and the others give NULL. Use `COALESCE(SUM(x), 0)`.
- Every `SELECT` column must be aggregated or listed in `GROUP BY`.
- `WHERE` filters rows before grouping. `HAVING` filters groups after it.
- NULLs form one group.
- Find duplicates with `GROUP BY ... HAVING COUNT(*) > 1`.
- `CASE` inside an aggregate gives conditional counts and simple pivots.
- Group by year and month, never month alone.

**Next:** [Chapter 11: Joins](11-joins.md)
