# 16. Window Functions: Frames, Running Totals and Moving Averages

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 15](15-window-functions-ranking-and-offset.md)

> **In one line:** A frame is the part of the partition a window function can see from the current row, and it is what makes running totals and moving averages possible.

## What you will learn

- Totals, percent of total and running totals
- What a frame is, and what the default frame does
- The difference between `ROWS`, `RANGE` and `GROUPS`
- Moving averages, and the three traps that come with them
- Why `LAST_VALUE` often seems to return the wrong answer

## Aggregates as window functions

`SUM`, `AVG`, `COUNT`, `MIN` and `MAX` all work with `OVER`. With no `ORDER BY` inside, every row of a partition sees the whole partition, so each row shows the group total.

```sql
SELECT first_name, dept_id, salary,
       SUM(salary) OVER (PARTITION BY dept_id) AS dept_total
FROM employees
WHERE dept_id IN (20, 40)
ORDER BY dept_id, emp_id;
```

```text output
 first_name | dept_id | salary | dept_total
------------+---------+--------+------------
 James      |      20 |  95000 |     267000
 Lena       |      20 |  60000 |     267000
 Diego      |      20 |  60000 |     267000
 Mei        |      20 |  52000 |     267000
 Omar       |      40 |  95000 |     153000
 Nina       |      40 |  58000 |     153000
(6 rows)
```

### Percent of total

Divide a row's value by the total. Use `100.0`, to avoid integer division.

```sql
SELECT first_name, salary,
       ROUND(100.0 * salary / SUM(salary) OVER (), 2) AS pct_of_all
FROM employees
WHERE dept_id = 40
ORDER BY emp_id;
```

```text output
 first_name | salary | pct_of_all
------------+--------+------------
 Omar       |  95000 |      62.09
 Nina       |  58000 |      37.91
(2 rows)
```

After a `GROUP BY`, the window needs a nested form, because the plain `salary` column no longer exists:

```sql
SELECT dept_id, SUM(salary) AS total_pay,
       ROUND(100.0 * SUM(salary) / SUM(SUM(salary)) OVER (), 2) AS pct_of_company
FROM employees
GROUP BY dept_id
ORDER BY dept_id;
```

```text output
 dept_id | total_pay | pct_of_company
---------+-----------+----------------
      10 |    180000 |          17.66
      20 |    267000 |          26.20
      30 |    389000 |          38.17
      40 |    153000 |          15.01
    NULL |     30000 |           2.94
(5 rows)
```

Read `SUM(SUM(salary)) OVER ()` from the inside: the inner `SUM` is the group total, and the outer `SUM ... OVER ()` adds up those totals. Writing `SUM(salary) OVER ()` here is an error, since a grouped query cannot see `salary` directly.

## Running totals

Add `ORDER BY` inside `OVER`, and the meaning changes from "group total" to "running total".

```sql
SELECT payment_date, amount,
       SUM(amount) OVER (ORDER BY payment_date, payment_id) AS running_total
FROM payments
WHERE payment_id <= 5
ORDER BY payment_date, payment_id;
```

```text output
 payment_date | amount  | running_total
--------------+---------+---------------
 2024-01-05   |  838.98 |        838.98
 2024-01-09   |   74.00 |        912.98
 2024-01-21   | 1000.00 |       1912.98
 2024-02-02   |   89.50 |       2002.48
 2024-02-10   |  499.00 |       2501.48
(5 rows)
```

`PARTITION BY` restarts the total for each group:

```sql
SELECT method, payment_date, amount,
       SUM(amount) OVER (PARTITION BY method ORDER BY payment_date, payment_id) AS running_by_method
FROM payments
WHERE payment_id <= 6
ORDER BY method, payment_date, payment_id;
```

```text output
 method | payment_date | amount  | running_by_method
--------+--------------+---------+-------------------
 BANK   | 2024-01-21   | 1000.00 |           1000.00
 BANK   | 2024-02-10   |  499.00 |           1499.00
 CARD   | 2024-01-05   |  838.98 |            838.98
 CARD   | 2024-01-09   |   74.00 |            912.98
 CARD   | 2024-02-02   |   89.50 |           1002.48
 CARD   | 2024-02-14   | 1018.99 |           2021.47
(6 rows)
```

**Running total of sales by date.** If a date can have several rows, aggregate to one row per date first:

```sql
WITH daily AS (
  SELECT payment_date, SUM(amount) AS day_total
  FROM payments
  GROUP BY payment_date
)
SELECT payment_date, day_total,
       SUM(day_total) OVER (ORDER BY payment_date) AS running_total
FROM daily
ORDER BY payment_date;
```

```text output
 payment_date | day_total | running_total
--------------+-----------+---------------
 2024-01-05   |    838.98 |        838.98
 2024-01-09   |     74.00 |        912.98
 2024-01-21   |   1000.00 |       1912.98
 2024-02-02   |     89.50 |       2002.48
 2024-02-10   |    499.00 |       2501.48
 2024-02-14   |   1018.99 |       3520.47
 2024-03-03   |    837.98 |       4358.45
 2024-03-16   |     87.00 |       4445.45
 2024-03-30   |     49.00 |       4494.45
 2024-04-05   |    749.00 |       5243.45
 2024-04-21   |    119.00 |       5362.45
 2024-05-02   |    179.00 |       5541.45
 2024-05-20   |    500.00 |       6041.45
(13 rows)
```

## What is a frame?

A **frame** is the set of rows inside the partition that the function can see from the current row. Think of a small window sliding down the rows.

```text
Partition, in order:     Frame for the row marked <--
                         ROWS BETWEEN 2 PRECEDING AND CURRENT ROW

row 1
row 2                    +  in the frame
row 3                    +  in the frame
row 4  <-- current       +  in the frame
row 5
row 6
```

The full syntax has a mode and two bounds:

```sql norun
{ROWS | RANGE | GROUPS} BETWEEN start AND end
```

The bounds are `UNBOUNDED PRECEDING`, `n PRECEDING`, `CURRENT ROW`, `n FOLLOWING` and `UNBOUNDED FOLLOWING`. `ROWS 2 PRECEDING` is short for `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`.

**The default frame:**

- With `ORDER BY`: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
- Without `ORDER BY`: the whole partition

**Which functions use a frame?** Aggregates, `FIRST_VALUE`, `LAST_VALUE` and `NTH_VALUE`. `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE`, `PERCENT_RANK`, `CUME_DIST`, `LAG` and `LEAD` never use one, so a frame has no effect on them.

## The default frame trap

Rows that tie on the `ORDER BY` are called **peers**. The default `RANGE` frame includes all peers of the current row, so tied rows share one running total.

```sql
SELECT first_name, salary,
       SUM(salary) OVER (ORDER BY salary) AS default_frame,
       SUM(salary) OVER (ORDER BY salary, emp_id
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS with_rows
FROM employees
WHERE salary <= 60000
ORDER BY salary, emp_id;
```

```text output
 first_name | salary | default_frame | with_rows
------------+--------+---------------+-----------
 Tom        |  30000 |         30000 |     30000
 Mei        |  52000 |         82000 |     82000
 Nina       |  58000 |        140000 |    140000
 Lena       |  60000 |        260000 |    200000
 Diego      |  60000 |        260000 |    260000
(5 rows)
```

Lena and Diego both earn 60000, and the default frame shows 260000 for both. With `ROWS`, the total grows by one row at a time.

**Rule:** for a running total, use `ROWS` with a unique tie-breaker. Using `ROWS` with a non-unique `ORDER BY` is a trap too: the order of tied rows is not fixed, so the running total can change between runs.

## ROWS vs RANGE vs GROUPS

| Mode | Measures | Use it for |
|---|---|---|
| `ROWS` | Physical rows | Running totals, fixed row counts |
| `RANGE` | Distance in the `ORDER BY` value | Value or time distances |
| `GROUPS` | Peer groups | "The previous N distinct values" |

Here are all three on the same tied data, each looking at "one back":

```sql postgres
-- PostgreSQL
SELECT first_name, salary,
       SUM(salary) OVER (ORDER BY salary, emp_id ROWS 1 PRECEDING) AS by_rows,
       SUM(salary) OVER (ORDER BY salary RANGE 2000 PRECEDING) AS by_range,
       SUM(salary) OVER (ORDER BY salary GROUPS 1 PRECEDING) AS by_groups
FROM employees
WHERE salary BETWEEN 52000 AND 82000
ORDER BY salary, emp_id;
```

```text output
 first_name | salary | by_rows | by_range | by_groups
------------+--------+---------+----------+-----------
 Mei        |  52000 |   52000 |    52000 |     52000
 Nina       |  58000 |  110000 |    58000 |    110000
 Lena       |  60000 |  118000 |   178000 |    178000
 Diego      |  60000 |  120000 |   178000 |    178000
 Emma       |  82000 |  142000 |   164000 |    284000
 Yusuf      |  82000 |  164000 |   164000 |    284000
(6 rows)
```

Follow Nina (58000):

- `ROWS 1 PRECEDING`: Nina and the row before, Mei. 58000 + 52000 = 110000.
- `RANGE 2000 PRECEDING`: salaries from 56000 to 58000, which is only Nina.
- `GROUPS 1 PRECEDING`: Nina's group and the group before. 58000 + 52000 = 110000.

Then look at Diego (60000), who is tied with Lena. `GROUPS` includes the whole tied group and the previous group: 60000 + 60000 + 58000 = 178000.

Support: `GROUPS` needs PostgreSQL 11 or Oracle 21c. MySQL and SQL Server do not have it. SQL Server's `RANGE` allows only `UNBOUNDED` and `CURRENT ROW`. A `RANGE` offset allows exactly one `ORDER BY` expression.

## Moving averages

A moving average smooths out noise by averaging the last few rows. A window of 3 rows is 2 preceding plus the current row, and a window of 7 rows is 6 preceding plus the current row.

```sql
SELECT payment_date, amount,
       ROUND(AVG(amount) OVER (ORDER BY payment_date, payment_id
                               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3,
       COUNT(*) OVER (ORDER BY payment_date, payment_id
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rows_in_frame
FROM payments
WHERE payment_id <= 5
ORDER BY payment_date, payment_id;
```

```text output
 payment_date | amount  | moving_avg_3 | rows_in_frame
--------------+---------+--------------+---------------
 2024-01-05   |  838.98 |       838.98 |             1
 2024-01-09   |   74.00 |       456.49 |             2
 2024-01-21   | 1000.00 |       637.66 |             3
 2024-02-02   |   89.50 |       387.83 |             3
 2024-02-10   |  499.00 |       529.50 |             3
(5 rows)
```

Here are the three traps:

1. **Seven rows is not seven days** when dates are missing. Payments here are often weeks apart.
2. **The first rows use partial windows.** The `rows_in_frame` column above shows this. You can keep only full windows by filtering on it in an outer query.
3. **It must run on one row per day.** On raw events, aggregate first.

`ROWS 7 PRECEDING` is 8 rows, not 7. It is an easy mistake to make.

### A true time window

`RANGE` with an interval counts real days. It works on dates in PostgreSQL 11 and later, and on Oracle.

```sql
SELECT payment_date, amount,
       SUM(amount) OVER (ORDER BY payment_date
                         RANGE BETWEEN INTERVAL '6' DAY PRECEDING AND CURRENT ROW) AS last_7_days
FROM payments
WHERE payment_id <= 6
ORDER BY payment_date, payment_id;
```

```text output
 payment_date | amount  | last_7_days
--------------+---------+-------------
 2024-01-05   |  838.98 |      838.98
 2024-01-09   |   74.00 |      912.98
 2024-01-21   | 1000.00 |     1000.00
 2024-02-02   |   89.50 |       89.50
 2024-02-10   |  499.00 |      499.00
 2024-02-14   | 1018.99 |     1517.99
(6 rows)
```

SQL Server cannot do this. There, you first fill the missing days with a generated list of dates ([Chapter 14](14-cte-and-recursive-queries.md), [Chapter 20](20-modern-sql.md)) and then use `ROWS`.

**The 7-day rolling average of daily active users.** If a missing day means zero activity, a `RANGE` average is still wrong, because it divides by the days that have rows. Filling the days with zeros first is the better answer.

## FIRST_VALUE, LAST_VALUE and NTH_VALUE

`FIRST_VALUE` works fine with the default frame. `LAST_VALUE` does not:

```sql
SELECT first_name, salary,
       FIRST_VALUE(first_name) OVER (ORDER BY salary DESC, emp_id) AS highest_paid,
       LAST_VALUE(first_name) OVER (ORDER BY salary DESC, emp_id) AS wrong_lowest,
       LAST_VALUE(first_name) OVER (ORDER BY salary DESC, emp_id
                                    ROWS BETWEEN UNBOUNDED PRECEDING
                                             AND UNBOUNDED FOLLOWING) AS right_lowest
FROM employees
WHERE dept_id = 30
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary | highest_paid | wrong_lowest | right_lowest
------------+--------+--------------+--------------+--------------
 Priya      | 120000 | Priya        | Priya        | Yusuf
 Arjun      | 105000 | Priya        | Arjun        | Yusuf
 Emma       |  82000 | Priya        | Emma         | Yusuf
 Yusuf      |  82000 | Priya        | Yusuf        | Yusuf
(4 rows)
```

The default frame ends at the current row. So the "last value" of the frame is the current row itself. To see the true last row, extend the frame to `UNBOUNDED FOLLOWING`, or use `FIRST_VALUE` with the sort reversed.

`NTH_VALUE(x, n)` depends on the frame in the same way, and it is NULL until the frame reaches row n.

## Running MIN, MAX, COUNT and a balance

```sql
SELECT payment_date, amount,
       MAX(amount) OVER (ORDER BY payment_date, payment_id
                         ROWS UNBOUNDED PRECEDING) AS largest_so_far,
       COUNT(*) OVER (ORDER BY payment_date, payment_id
                      ROWS UNBOUNDED PRECEDING) AS payments_so_far
FROM payments
WHERE payment_id <= 4
ORDER BY payment_date, payment_id;
```

```text output
 payment_date | amount  | largest_so_far | payments_so_far
--------------+---------+----------------+-----------------
 2024-01-05   |  838.98 |         838.98 |               1
 2024-01-09   |   74.00 |         838.98 |               2
 2024-01-21   | 1000.00 |        1000.00 |               3
 2024-02-10   |  499.00 |        1000.00 |               4
(4 rows)
```

A **running balance** is an opening balance plus a running sum of signed amounts: `1000 + SUM(signed_amount) OVER (ORDER BY tx_date, tx_id)`.

Variations you may be asked for:

- **Centered average:** `ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING`
- **Year-to-date:** `SUM(x) OVER (PARTITION BY year ORDER BY d)`
- **Pareto share:** a running total divided by the grand total
- **Total row count on every page:** `COUNT(*) OVER ()`

## More advanced tools

**`EXCLUDE`** removes rows from the frame, for "the average of my peers, not counting me". It needs PostgreSQL 11 or Oracle 21c.

```sql postgres
SELECT first_name, salary,
       ROUND(AVG(salary) OVER (PARTITION BY dept_id
                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                               EXCLUDE CURRENT ROW), 2) AS avg_of_others
FROM employees
WHERE dept_id = 40
ORDER BY emp_id;
```

```text output
 first_name | salary | avg_of_others
------------+--------+---------------
 Omar       |  95000 |      58000.00
 Nina       |  58000 |      95000.00
(2 rows)
```

**`COUNT(DISTINCT x) OVER (...)`** is rejected by PostgreSQL, SQL Server and MySQL. Oracle accepts it with `PARTITION BY`, but not with `ORDER BY`. The workaround, when `x` has no NULLs, is `DENSE_RANK() OVER (... ORDER BY x) + DENSE_RANK() OVER (... ORDER BY x DESC) - 1`.

**Forward fill** carries the last known value into NULL rows. `LAST_VALUE(x IGNORE NULLS)` does this on Oracle and on SQL Server 2022. PostgreSQL gains `IGNORE NULLS` only from version 19. A portable way is to use `COUNT(x) OVER (ORDER BY d)` as a group key, then `MAX(x) OVER (PARTITION BY that key)`.

**`FILTER` on a window aggregate** works on PostgreSQL and Oracle 26ai. A `CASE` inside the aggregate works everywhere.

**Performance.** Each different window order can need its own sort, and an index on the partition and order columns can avoid it. Explicit `ROWS` can be faster than the default `RANGE`, especially on SQL Server.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Trust the default frame on a non-unique `ORDER BY` | Tied rows show the same running total | Use `ROWS` with a tie-breaker |
| Use `ROWS` on a non-unique `ORDER BY` | Results can change between runs | Add a unique tie-breaker |
| Call `LAST_VALUE` with the default frame | You get the current row back | Extend the frame to `UNBOUNDED FOLLOWING` |
| Write `ROWS 7 PRECEDING` for a 7-day average | That is 8 rows | Use `6 PRECEDING` |
| Treat 7 rows as 7 days | Missing days stretch the window | Fill the days, or use `RANGE` |
| Skip days with no activity | The rolling average is too high | Count them as zero |
| Run a moving average on raw events | The window counts events, not days | Aggregate to one row per day |
| Report partial windows as full averages | Early values mislead | Filter on the frame's row count |
| Drop `ORDER BY` from `OVER` | You get the partition total on every row | Add it for a running total |
| Add `ORDER BY` to a percent of total | You get a running share | Remove it |
| Use `SUM(x) / SUM(x) OVER ()` in a grouped query | An error | Use `SUM(SUM(x)) OVER ()` |
| Write a `RANGE` offset with two sort columns | An error | Use exactly one expression |
| Expect a frame to change `ROW_NUMBER` or `LAG` | They ignore it | Frames apply only to the functions listed above |
| Write `COUNT(DISTINCT x) OVER (...)` on PostgreSQL | An error | Use the `DENSE_RANK` workaround |

## Interview questions

**Q1. What is the difference between ROWS and RANGE?**

`ROWS` counts physical rows, so `1 PRECEDING` means exactly one row back. `RANGE` measures distance in the `ORDER BY` value, and it includes all tied rows, called peers. I use `ROWS` for running totals with a unique tie-breaker, and `RANGE` for real time distances.

*Follow-up they may ask:* What is the default frame? With `ORDER BY`, it is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. That is why tied rows share a running total. With no `ORDER BY`, it is the whole partition.

**Q2. Calculate a running total of sales by date.**

First aggregate to one row per date. Then use `SUM(day_total) OVER (ORDER BY sale_date)`. If I do not aggregate first, I use `ROWS` with a unique tie-breaker so that same-day rows do not all share one total.

**Q3. What is the 7-day rolling average of daily active users?**

Make one row per day, and fill days with no activity as zero, because a missing day is a real zero. Then use `AVG(dau) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`. That is 6 rows back plus the current row. I would also say what to do with the first six days, which have partial windows.

**Q4. Why can LAST_VALUE return the current row's value instead of the last value in the partition?**

Because the default frame ends at the current row, or at its last peer. So the last row of the frame is the current row. I extend the frame with `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, or I use `FIRST_VALUE` with the sort reversed.

**Q5. How do you show each row's share of the total?**

`100.0 * x / SUM(x) OVER ()`. After a `GROUP BY`, it becomes `100.0 * SUM(x) / SUM(SUM(x)) OVER ()`.

## Practice

**1. Show each order of customer 1, with a running count of their orders.**

<details>
<summary>Show solution</summary>

```sql
SELECT order_id, order_date,
       COUNT(*) OVER (ORDER BY order_date, order_id
                      ROWS UNBOUNDED PRECEDING) AS orders_so_far
FROM orders
WHERE customer_id = 1
ORDER BY order_date, order_id;
```

```text output
 order_id | order_date | orders_so_far
----------+------------+---------------
     1001 | 2024-01-05 |             1
     1004 | 2024-02-02 |             2
     1009 | 2024-03-30 |             3
     1014 | 2024-06-01 |             4
(4 rows)
```

</details>

**2. Show each product's share of its category's total stock, as a percentage.**

<details>
<summary>Show solution</summary>

```sql
SELECT category_id, product_name, stock_qty,
       ROUND(100.0 * stock_qty / NULLIF(SUM(stock_qty) OVER (PARTITION BY category_id), 0), 2) AS pct_of_category
FROM products
WHERE category_id IN (2, 3)
ORDER BY category_id, product_id;
```

```text output
 category_id | product_name | stock_qty | pct_of_category
-------------+--------------+-----------+-----------------
           2 | Phone X      |        25 |           38.46
           2 | Phone Lite   |        40 |           61.54
           3 | Laptop Pro   |        10 |           40.00
           3 | Laptop Air   |        15 |           60.00
(4 rows)
```

</details>

**3. Show cumulative revenue by month, for non-cancelled orders.**

<details>
<summary>Show solution</summary>

```sql
WITH monthly AS (
  SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
         SUM(i.quantity * i.unit_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  WHERE o.status <> 'CANCELLED'
  GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
)
SELECT order_month, revenue,
       SUM(revenue) OVER (ORDER BY order_month) AS cumulative
FROM monthly
ORDER BY order_month;
```

```text output
 order_month | revenue | cumulative
-------------+---------+------------
 2024-01     | 2411.98 |    2411.98
 2024-02     | 1108.49 |    3520.47
 2024-03     |  973.98 |    4494.45
 2024-04     |  868.00 |    5362.45
 2024-05     | 1178.00 |    6540.45
 2024-06     | 2047.47 |    8587.92
(6 rows)
```

</details>

**4. For each employee in department 30, show the name of the lowest-paid person in the department, using `LAST_VALUE`.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, salary,
       LAST_VALUE(first_name) OVER (ORDER BY salary DESC, emp_id
                                    ROWS BETWEEN UNBOUNDED PRECEDING
                                             AND UNBOUNDED FOLLOWING) AS lowest_paid
FROM employees
WHERE dept_id = 30
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary | lowest_paid
------------+--------+-------------
 Priya      | 120000 | Yusuf
 Arjun      | 105000 | Yusuf
 Emma       |  82000 | Yusuf
 Yusuf      |  82000 | Yusuf
(4 rows)
```

</details>

**5. Show a 2-row moving average of monthly revenue.**

<details>
<summary>Show solution</summary>

```sql
WITH monthly AS (
  SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
         SUM(i.quantity * i.unit_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  WHERE o.status <> 'CANCELLED'
  GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
)
SELECT order_month, revenue,
       ROUND(AVG(revenue) OVER (ORDER BY order_month
                                ROWS BETWEEN 1 PRECEDING AND CURRENT ROW), 2) AS moving_avg
FROM monthly
ORDER BY order_month;
```

```text output
 order_month | revenue | moving_avg
-------------+---------+------------
 2024-01     | 2411.98 |    2411.98
 2024-02     | 1108.49 |    1760.24
 2024-03     |  973.98 |    1041.24
 2024-04     |  868.00 |     920.99
 2024-05     | 1178.00 |    1023.00
 2024-06     | 2047.47 |    1612.74
(6 rows)
```

</details>

## Recap

- With no `ORDER BY` in `OVER`, you get the partition total. With it, you get a running total.
- A frame is what the function can see from the current row.
- The default frame with `ORDER BY` is `RANGE ... CURRENT ROW`, so tied rows share a value.
- For running totals, use `ROWS` and a unique tie-breaker.
- Seven days is `6 PRECEDING`, and seven rows is not seven days if dates are missing.
- `LAST_VALUE` needs its frame extended to `UNBOUNDED FOLLOWING`.
- After `GROUP BY`, percent of total is `SUM(x) / SUM(SUM(x)) OVER ()`.

**Next:** [Chapter 17: Subtotals, pivots and string aggregation](17-advanced-grouping-and-pivot.md)
