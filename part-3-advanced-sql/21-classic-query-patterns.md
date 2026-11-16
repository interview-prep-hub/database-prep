# 21. Classic Query Patterns Interviewers Keep Asking

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 15](15-window-functions-ranking-and-offset.md) and [Chapter 16](16-window-functions-frames-and-running-totals.md)

> **In one line:** Most hard SQL questions are one of about twenty patterns in disguise, so learn to recognize the pattern and the query follows.

## What you will learn

- A method for working any pattern question out loud
- Nth highest, top-N per group, and latest row per group
- Mean, median and mode
- Gaps and islands, streaks and sessions
- Overlapping intervals and peak concurrency
- Retention, cohorts and funnels

## How to work any pattern question

Interviewers score your process as much as your final query. Use the same five steps every time.

1. **State the grain.** "The result has one row per what?"
2. **Ask about edge cases.** Ties, NULLs, empty results, and duplicates in the input.
3. **Build in named CTE steps.** One idea per step.
4. **Say what each step does** as you write it.
5. **Test the edges.** "If a user has only one login, this returns..."

## Part 1: Ranking

### Second highest and Nth highest

Give `DENSE_RANK` first, because it works for any N and handles ties. Here is the 3rd highest distinct salary:

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

**Without `LIMIT` or ranking functions,** use a correlated subquery. A salary is the Nth highest when exactly N - 1 distinct salaries are above it.

```sql
SELECT DISTINCT e.salary
FROM employees e
WHERE 2 = (SELECT COUNT(DISTINCT o.salary)
           FROM employees o
           WHERE o.salary > e.salary);
```

```text output
 salary
--------
 105000
(1 row)
```

**What if fewer than N salaries exist?** The question usually wants NULL, not an empty result. Wrap it so that the outer query always returns one row:

```sql
SELECT MAX(t.salary) AS tenth_highest
FROM (SELECT DISTINCT salary,
             DENSE_RANK() OVER (ORDER BY salary DESC) AS pay_rank
      FROM employees) t
WHERE t.pay_rank = 10;
```

```text output
 tenth_highest
---------------
          NULL
(1 row)
```

**Trap:** `OFFSET` without `DISTINCT` repeats tied values. On this data the 5th row by salary is 95000, but the 5th highest *distinct* salary is 82000.

### Top-N per group

This was covered in [Chapter 15](15-window-functions-ranking-and-offset.md). The choice is about ties:

| The question | Function |
|---|---|
| Highest paid per department, ties kept | `RANK() ... = 1` |
| Exactly one per department | `ROW_NUMBER() ... = 1` |
| Top three distinct salaries per department | `DENSE_RANK() ... <= 3` |

### Latest row per group

`ROW_NUMBER` in a wrapper is the portable answer:

```sql
WITH ranked AS (
  SELECT customer_id, order_id, order_date,
         ROW_NUMBER() OVER (PARTITION BY customer_id
                            ORDER BY order_date DESC, order_id DESC) AS rn
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

Two shorter forms exist on specific engines:

**PostgreSQL:** `DISTINCT ON` keeps the first row of each group. Its columns must match the leftmost `ORDER BY` columns.

```sql postgres
SELECT DISTINCT ON (customer_id) customer_id, order_id, order_date
FROM orders
ORDER BY customer_id, order_date DESC, order_id DESC;
```

**Oracle:** `KEEP` gets a value from the row with the highest or lowest rank, with no wrapper.

```sql oracle
SELECT customer_id,
       MAX(order_id) KEEP (DENSE_RANK LAST ORDER BY order_date) AS latest_order
FROM orders
GROUP BY customer_id
ORDER BY customer_id;
```

```text output
CUSTOMER_ID LATEST_ORDER
----------- ------------
          1         1014
          2         1013
          3         1016
          4         1011
          5         1012
          6         1015
```

### Topper of each subject, with no nested query

An interviewer may ban subqueries. Use a self-`LEFT JOIN` on "someone in the same group with a higher value", and keep the rows where no such person exists. It also returns ties.

```sql
SELECT e.dept_id, e.first_name, e.salary
FROM employees e
LEFT JOIN employees better
       ON better.dept_id = e.dept_id
      AND better.salary > e.salary
WHERE better.emp_id IS NULL
  AND e.dept_id IS NOT NULL
ORDER BY e.dept_id;
```

```text output
 dept_id | first_name | salary
---------+------------+--------
      10 | Sara       | 180000
      20 | James      |  95000
      30 | Priya      | 120000
      40 | Omar       |  95000
(4 rows)
```

## Part 2: Statistics

### Mean, median and mode

**Median.** `PERCENTILE_CONT(0.5)` interpolates between the two middle values. `PERCENTILE_DISC(0.5)` returns a real value from the data.

```sql
SELECT ROUND(AVG(salary), 2) AS mean,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_cont,
       PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary) AS median_disc
FROM employees
WHERE dept_id = 30;
```

```text output
   mean   | median_cont | median_disc
----------+-------------+-------------
 97250.00 |       93500 |       82000
(1 row)
```

Oracle also has `MEDIAN(salary)`.

**Median by hand,** when functions are banned or missing. Number the rows, then take the middle row, or the average of the two middle rows.

```sql postgres
-- PostgreSQL
WITH numbered AS (
  SELECT salary,
         ROW_NUMBER() OVER (ORDER BY salary, emp_id) AS rn,
         COUNT(*) OVER () AS total
  FROM employees
  WHERE dept_id = 30
)
SELECT ROUND(AVG(salary), 2) AS median
FROM numbered
WHERE rn IN ((total + 1) / 2, (total + 2) / 2);
```

```text output
  median
----------
 93500.00
(1 row)
```

This relies on integer division, which PostgreSQL does on whole numbers. Oracle has no integer division, so on Oracle write `FLOOR((total + 1) / 2)` and `FLOOR((total + 2) / 2)`.

**Mode** is the most common value. Keep ties, because a column can have several modes. Salaries here have three.

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
SELECT salary, COUNT(*) AS people
FROM employees
GROUP BY salary
ORDER BY COUNT(*) DESC
FETCH FIRST 1 ROW WITH TIES;
```

Built-in functions exist too: `MODE() WITHIN GROUP (ORDER BY x)` on PostgreSQL and `STATS_MODE(x)` on Oracle, but they return only one value.

### Two-level aggregation and histograms

Count per user first, then users per count.

```sql
WITH per_customer AS (
  SELECT customer_id, COUNT(*) AS order_count
  FROM orders
  GROUP BY customer_id
)
SELECT order_count, COUNT(*) AS customers
FROM per_customer
GROUP BY order_count
ORDER BY order_count;
```

```text output
 order_count | customers
-------------+-----------
           2 |         3
           3 |         2
           4 |         1
(3 rows)
```

For numeric ranges, use `CASE` bands, or `WIDTH_BUCKET` on Oracle and PostgreSQL.

### Rate metrics

State the numerator and the denominator out loud. Here is the cancellation rate per customer, with conditional aggregation:

```sql
SELECT customer_id,
       ROUND(100.0 * COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) / COUNT(*), 2) AS cancel_pct
FROM orders
GROUP BY customer_id
ORDER BY cancel_pct DESC, customer_id;
```

```text output
 customer_id | cancel_pct
-------------+------------
           2 |      33.33
           1 |       0.00
           3 |       0.00
           4 |       0.00
           5 |       0.00
           6 |       0.00
(6 rows)
```

### Running total thresholds

**The last order before cumulative revenue passes 3000.** Compute the running total in a CTE, then filter.

```sql
WITH totals AS (
  SELECT payment_id, payment_date,
         SUM(amount) OVER (ORDER BY payment_date, payment_id) AS running
  FROM payments
)
SELECT MAX(running) AS last_total_within_limit
FROM totals
WHERE running <= 3000;
```

```text output
 last_total_within_limit
-------------------------
                 2501.48
(1 row)
```

## Part 3: Set logic

### "Bought every X" (relational division)

**Find customers who bought every Books product.** [Chapter 13](../part-2-sql-basics/13-subqueries.md) showed both forms: a double `NOT EXISTS`, or `HAVING COUNT(DISTINCT p) = (SELECT COUNT(*) ...)`. Filter to the required set first, and use `DISTINCT`, because a customer may buy the same product twice.

### Bought A and B, but not C

Use `HAVING` on conditional counts. It handles several conditions together, and it is easier to extend than `INTERSECT` and `MINUS`.

```sql
SELECT o.customer_id
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
GROUP BY o.customer_id
HAVING COUNT(CASE WHEN i.product_id = 8 THEN 1 END) > 0   -- bought SQL Basics
   AND COUNT(CASE WHEN i.product_id = 9 THEN 1 END) > 0   -- and Database Design
   AND COUNT(CASE WHEN i.product_id = 2 THEN 1 END) = 0   -- but not Phone Lite
ORDER BY o.customer_id;
```

```text output
 customer_id
-------------
           4
(1 row)
```

## Part 4: Gaps and islands

This is the hardest common family, and the one most worth practicing.

An **island** is a run of consecutive values. A **gap** is the space between runs.

Here is a demo table of daily logins:

```sql
CREATE TABLE logins (
  user_id     INTEGER NOT NULL,
  login_date  DATE NOT NULL
);

INSERT INTO logins VALUES (1, DATE '2024-03-01');
INSERT INTO logins VALUES (1, DATE '2024-03-02');
INSERT INTO logins VALUES (1, DATE '2024-03-02');
INSERT INTO logins VALUES (1, DATE '2024-03-03');
INSERT INTO logins VALUES (1, DATE '2024-03-07');
INSERT INTO logins VALUES (1, DATE '2024-03-08');
INSERT INTO logins VALUES (2, DATE '2024-03-05');
```

User 1 logged in twice on March 2. That detail matters, as you are about to see.

### Technique 1: value minus row number

Inside a run of consecutive values, **the value minus its row number is constant**. That constant becomes a group id.

```text
login_date   rn   login_date - rn
2024-03-01    1   2024-02-29
2024-03-02    2   2024-02-29     same run
2024-03-03    3   2024-02-29     same run
2024-03-07    4   2024-03-03     new run
2024-03-08    5   2024-03-03     same run
```

### Streaks: the longest run of consecutive days

**How do you find the longest streak of consecutive login days?** First reduce to one row per user per day, because a second login on one day would break the arithmetic. Then get the island key, count per island, and take the maximum.

```sql
WITH one_per_day AS (
  SELECT DISTINCT user_id, login_date
  FROM logins
),
islands AS (
  SELECT user_id, login_date,
         login_date - CAST(ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date) AS INTEGER) AS island
  FROM one_per_day
),
streaks AS (
  SELECT user_id, island, COUNT(*) AS streak_days,
         MIN(login_date) AS streak_start, MAX(login_date) AS streak_end
  FROM islands
  GROUP BY user_id, island
)
SELECT user_id, streak_start, streak_end, streak_days
FROM streaks
ORDER BY user_id, streak_start;
```

```text output
 user_id | streak_start | streak_end | streak_days
---------+--------------+------------+-------------
       1 | 2024-03-01   | 2024-03-03 |           3
       1 | 2024-03-07   | 2024-03-08 |           2
       2 | 2024-03-05   | 2024-03-05 |           1
(3 rows)
```

That one query also gives you **run boundaries**, the start and end of each range, which is a question on its own ("Report Contiguous Dates"). For the longest streak per user, add `MAX(streak_days)` grouped by `user_id`.

### Technique 2: a change flag and a running sum

Technique 1 needs numbers or dates that step by one. For status changes and thresholds, use this instead:

1. Use `LAG` to flag each row that starts a new group.
2. A running `SUM` of the flags gives a group id.

**Find runs of the same order status.** Think of it as "how many times did the status change, in date order?"

```sql
WITH flagged AS (
  SELECT order_id, status,
         CASE WHEN status = LAG(status) OVER (ORDER BY order_id) THEN 0 ELSE 1 END AS new_run
  FROM orders
),
grouped AS (
  SELECT order_id, status,
         SUM(new_run) OVER (ORDER BY order_id ROWS UNBOUNDED PRECEDING) AS run_id
  FROM flagged
)
SELECT run_id, status, MIN(order_id) AS first_order, MAX(order_id) AS last_order, COUNT(*) AS orders_in_run
FROM grouped
GROUP BY run_id, status
ORDER BY run_id;
```

```text output
 run_id |  status   | first_order | last_order | orders_in_run
--------+-----------+-------------+------------+---------------
      1 | DELIVERED |        1001 |       1005 |             5
      2 | CANCELLED |        1006 |       1006 |             1
      3 | DELIVERED |        1007 |       1010 |             4
      4 | SHIPPED   |        1011 |       1013 |             3
      5 | PENDING   |        1014 |       1016 |             3
(5 rows)
```

On the first row, `LAG` gives NULL, so the `CASE` goes to `ELSE 1`, which correctly starts run 1.

### Consecutive rows

**Find values that appear at least three times in a row.** For a fixed length, `LAG` is enough:

```sql
WITH flagged AS (
  SELECT order_id, status,
         LAG(status, 1) OVER (ORDER BY order_id) AS prev_1,
         LAG(status, 2) OVER (ORDER BY order_id) AS prev_2
  FROM orders
)
SELECT DISTINCT status
FROM flagged
WHERE status = prev_1 AND status = prev_2
ORDER BY status;
```

```text output
  status
-----------
 DELIVERED
 PENDING
 SHIPPED
(3 rows)
```

A triple self-join also works, but it does not generalize to N. For any N, use islands. Number the rows after filtering, not before.

### Finding gaps

**How do you find gaps in a sequence, like missing invoice numbers?** Use `LEAD` to compare each row with the next. Here we look for gaps among the orders that have a payment.

```sql
WITH paid AS (
  SELECT DISTINCT order_id FROM payments
),
with_next AS (
  SELECT order_id, LEAD(order_id) OVER (ORDER BY order_id) AS next_id
  FROM paid
)
SELECT order_id + 1 AS gap_start, next_id - 1 AS gap_end
FROM with_next
WHERE next_id - order_id > 1
ORDER BY gap_start;
```

```text output
 gap_start | gap_end
-----------+---------
      1006 |    1006
(1 row)
```

`LEAD` cannot see a gap at either edge, because there is no row there. State the expected range. A generated list of numbers and an anti-join covers it ([Chapter 14](14-cte-and-recursive-queries.md)).

```sql
DROP TABLE logins;
```

## Part 5: Sessions and time

### Sessionization

**Assign a session id to each event, starting a new session after 30 minutes of inactivity.** This is Technique 2 with a time test.

```sql
CREATE TABLE events (
  user_id     INTEGER NOT NULL,
  event_time  TIMESTAMP NOT NULL
);

INSERT INTO events VALUES (1, TIMESTAMP '2024-03-01 09:00:00');
INSERT INTO events VALUES (1, TIMESTAMP '2024-03-01 09:10:00');
INSERT INTO events VALUES (1, TIMESTAMP '2024-03-01 09:50:00');
INSERT INTO events VALUES (1, TIMESTAMP '2024-03-01 09:55:00');
INSERT INTO events VALUES (2, TIMESTAMP '2024-03-01 09:05:00');
```

```sql
WITH gaps AS (
  SELECT user_id, event_time,
         LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) AS previous_time
  FROM events
),
flagged AS (
  SELECT user_id, event_time,
         CASE WHEN previous_time IS NULL
                OR event_time - previous_time > INTERVAL '30' MINUTE
              THEN 1 ELSE 0
         END AS new_session
  FROM gaps
)
SELECT user_id, event_time,
       SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_time
                              ROWS UNBOUNDED PRECEDING) AS session_id
FROM flagged
ORDER BY user_id, event_time;
```

```text output
 user_id |     event_time      | session_id
---------+---------------------+------------
       1 | 2024-03-01 09:00:00 |          1
       1 | 2024-03-01 09:10:00 |          1
       1 | 2024-03-01 09:50:00 |          2
       1 | 2024-03-01 09:55:00 |          2
       2 | 2024-03-01 09:05:00 |          1
(5 rows)
```

The first event has a NULL gap and must start a session. State whether exactly 30 minutes counts as a new session: `>` says no and `>=` says yes.

```sql
DROP TABLE events;
```

### Do two intervals overlap?

Two ranges overlap when **each one starts before the other ends**:

```text
a.start < b.end AND b.start < a.end

a:  |-------|                  overlap         a:  |----|              no overlap
b:      |-------|                              b:         |----|
```

Decide whether endpoints are inclusive. Exclude the row itself in a self-join. Treat a NULL end as an open range.

### Merging overlapping intervals

Sort by start. A running `MAX(end)` over the earlier rows tells you when a new group begins: when the current start is past everything seen so far.

```sql
CREATE TABLE bookings (
  id         INTEGER PRIMARY KEY,
  start_day  INTEGER NOT NULL,
  end_day    INTEGER NOT NULL
);

INSERT INTO bookings VALUES (1, 1, 4);
INSERT INTO bookings VALUES (2, 3, 6);
INSERT INTO bookings VALUES (3, 8, 9);
INSERT INTO bookings VALUES (4, 9, 12);
INSERT INTO bookings VALUES (5, 15, 16);
```

```sql
WITH flagged AS (
  SELECT start_day, end_day,
         CASE WHEN start_day <= MAX(end_day) OVER (ORDER BY start_day, id
                                                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
              THEN 0 ELSE 1
         END AS new_group
  FROM bookings
),
grouped AS (
  SELECT start_day, end_day,
         SUM(new_group) OVER (ORDER BY start_day, end_day ROWS UNBOUNDED PRECEDING) AS group_id
  FROM flagged
)
SELECT group_id, MIN(start_day) AS merged_start, MAX(end_day) AS merged_end
FROM grouped
GROUP BY group_id
ORDER BY group_id;
```

```text output
 group_id | merged_start | merged_end
----------+--------------+------------
        1 |            1 |          6
        2 |            8 |         12
        3 |           15 |         16
(3 rows)
```

### Peak concurrency

**What is the most that were active at the same time?** Turn each interval into two events, +1 at the start and -1 at the end, then take a running sum. Order ties at the same moment on purpose. Here, an end on the same day as a start counts as overlapping, so starts go first.

```sql
WITH points AS (
  SELECT start_day AS day_no, 1 AS change, 0 AS sort_key FROM bookings
  UNION ALL
  SELECT end_day, -1, 1 FROM bookings
),
running AS (
  SELECT day_no,
         SUM(change) OVER (ORDER BY day_no, sort_key
                           ROWS UNBOUNDED PRECEDING) AS active
  FROM points
)
SELECT MAX(active) AS peak_active
FROM running;
```

```text output
 peak_active
-------------
           2
(1 row)
```

```sql
DROP TABLE bookings;
```

### As-of join

**What was the price at the time of the order?** You want the latest row at or before a given time. Use a correlated `MAX`, `ROW_NUMBER`, or `LATERAL`, and a `LEFT JOIN` with a default for when no earlier row exists. DuckDB and Snowflake have a built-in `ASOF JOIN`.

```sql norun
SELECT o.order_id,
       (SELECT h.price
        FROM price_history h
        WHERE h.product_id = o.product_id
          AND h.valid_from = (SELECT MAX(h2.valid_from)
                              FROM price_history h2
                              WHERE h2.product_id = o.product_id
                                AND h2.valid_from <= o.order_date)) AS price_then
FROM orders o;
```

## Part 6: Product analytics

### Daily active users

Reduce to one row per user per day first, then count. For the rolling form, see [Chapter 16](16-window-functions-frames-and-running-totals.md). A 7-day window is often preferred, because a 30-day window holds a varying number of weekends.

### Retention

**Report the fraction of players who logged in again on the day after their first login.** Find each player's first day, then check for a login on the next day.

```sql
CREATE TABLE activity (
  player_id   INTEGER NOT NULL,
  event_date  DATE NOT NULL
);

INSERT INTO activity VALUES (1, DATE '2024-03-01');
INSERT INTO activity VALUES (1, DATE '2024-03-02');
INSERT INTO activity VALUES (2, DATE '2024-03-05');
INSERT INTO activity VALUES (3, DATE '2024-03-01');
INSERT INTO activity VALUES (3, DATE '2024-03-04');
```

```sql
WITH firsts AS (
  SELECT player_id, MIN(event_date) AS first_day
  FROM activity
  GROUP BY player_id
)
SELECT ROUND(1.0 * COUNT(a.player_id) / COUNT(*), 2) AS day_1_retention
FROM firsts f
LEFT JOIN activity a
       ON a.player_id = f.player_id
      AND a.event_date = f.first_day + 1;
```

```text output
 day_1_retention
-----------------
            0.33
(1 row)
```

State the denominator: all players with a first day. Use `COUNT(DISTINCT ...)` if a player can have several events on one day.

### Cohort retention

**Write a cohort retention query.** A user's **cohort** is the month they first appeared. The period index is the number of months since then. Each cell is distinct users divided by cohort size.

```sql
WITH firsts AS (
  SELECT customer_id, MIN(order_date) AS first_order
  FROM orders
  GROUP BY customer_id
),
activity AS (
  SELECT f.customer_id,
         TO_CHAR(f.first_order, 'YYYY-MM') AS cohort,
         (EXTRACT(YEAR FROM o.order_date) - EXTRACT(YEAR FROM f.first_order)) * 12
           + EXTRACT(MONTH FROM o.order_date) - EXTRACT(MONTH FROM f.first_order) AS months_later
  FROM firsts f
  JOIN orders o ON o.customer_id = f.customer_id
)
SELECT cohort, months_later, COUNT(DISTINCT customer_id) AS active_customers
FROM activity
GROUP BY cohort, months_later
ORDER BY cohort, months_later;
```

```text output
 cohort  | months_later | active_customers
---------+--------------+------------------
 2024-01 |            0 |                3
 2024-01 |            1 |                2
 2024-01 |            2 |                2
 2024-01 |            4 |                1
 2024-01 |            5 |                2
 2024-02 |            0 |                1
 2024-02 |            2 |                1
 2024-03 |            0 |                1
 2024-03 |            2 |                1
 2024-04 |            0 |                1
 2024-04 |            2 |                1
(11 rows)
```

To show months with zero activity, `LEFT JOIN` from a cohort-by-period grid.

### Reactivation and churn

Compare consecutive active periods with `LAG`. A user is **reactivated** if active this month, and their previous active month is more than one month ago. They are **churned** if active last month and not this month, which an anti-join finds.

### Funnels

Count each step with conditional aggregation, then divide step by step.

```sql norun
SELECT COUNT(DISTINCT CASE WHEN event = 'view' THEN user_id END) AS viewed,
       COUNT(DISTINCT CASE WHEN event = 'cart' THEN user_id END) AS carted,
       COUNT(DISTINCT CASE WHEN event = 'pay'  THEN user_id END) AS paid
FROM events;
```

If order matters ("clicked before booking"), add a time condition in a self-join.

### Exchange seats

**Swap each pair of adjacent rows, and leave an odd last row alone.** Use `CASE` and `MOD`.

```sql
SELECT CASE WHEN MOD(dept_id / 10, 2) = 1 AND dept_id <> (SELECT MAX(dept_id) FROM departments)
            THEN dept_id + 10
            WHEN MOD(dept_id / 10, 2) = 0
            THEN dept_id - 10
            ELSE dept_id
       END AS new_position,
       dept_name
FROM departments
ORDER BY new_position;
```

```text output
 new_position |  dept_name
--------------+-------------
           10 | Sales
           20 | Executive
           30 | Finance
           40 | Engineering
           50 | Legal
(5 rows)
```

## The pattern picker

When you read a question, look for these words.

| The question says | Think of |
|---|---|
| "second highest", "Nth" | `DENSE_RANK`, or a correlated count |
| "top 3 per", "highest in each" | Rank with `PARTITION BY` in a CTE |
| "latest per", "first per" | `ROW_NUMBER` in a wrapper |
| "bought all", "every" | Relational division |
| "A and B but not C" | `HAVING` with conditional counts |
| "consecutive", "streak", "in a row" | Gaps and islands |
| "missing numbers" | `LEAD`, or a generated list and an anti-join |
| "session", "inactivity" | `LAG`, a flag, and a running `SUM` |
| "overlap" | `a.start < b.end AND b.start < a.end` |
| "at the same time", "peak" | +1 and -1 events, with a running `SUM` |
| "at the time of" | An as-of join |
| "came back", "retained" | First event, then a self-join on the later date |
| "percent of total" | `SUM(x) OVER ()` |
| "month over month" | `LAG` on one row per month |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use `OFFSET` for Nth highest without `DISTINCT` | Ties repeat a value | Use `DENSE_RANK` |
| Return an empty result when N is too big | The question wanted NULL | Wrap it in `MAX` or a scalar subquery |
| Skip the "one row per day" step for streaks | A second login on a day breaks the key | Use `DISTINCT` first |
| Number rows before filtering | The islands are wrong | Filter first, then number |
| Forget that the first event starts a session | The first group is lost | Test `previous_time IS NULL` |
| Use `LEAD` and forget the edges | Gaps at the ends are missed | State the range, or use a generated list |
| Skip the cohort grid | Zero cells are missing | `LEFT JOIN` from a grid |
| Use `COUNT(*)` where a user can repeat | Rates come out too high | Use `COUNT(DISTINCT user_id)` |

## Interview questions

**Q1. How do you find the second highest salary, and what should the query return if only one salary exists?**

`DENSE_RANK` in a CTE, keeping rank 2, or `MAX(salary)` where salary is below the overall `MAX`. If only one salary exists, it should return NULL. The `MAX` form does that by itself. The rank form needs wrapping in `MAX` or a scalar subquery, because otherwise it returns no row.

**Q2. Determine the 5th highest value in a column without using LIMIT.**

Use `DENSE_RANK() = 5`, or a correlated subquery: keep values where `4 = (SELECT COUNT(DISTINCT x) ... WHERE x > outer.x)`. It is 4, not 5, because exactly four distinct values are above the 5th.

**Q3. Find the employees who earn the top three distinct salaries in each department.**

`DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC)` in a CTE, then keep ranks up to 3. `DENSE_RANK`, not `RANK`, because gaps could leave fewer than three distinct salaries.

**Q4. Given student(name, subject, marks), return the topper of each subject. Now rewrite it without a nested query.**

First, `RANK` in a CTE. Without nesting, I self-left-join on the same subject and higher marks, and keep rows where the join found nothing. Nobody in that subject scored higher, so that row is the topper, and ties are kept.

**Q5. How do you find the longest streak of consecutive login days for a user?**

Reduce to one row per user per day. Subtract `ROW_NUMBER` from the date, which is constant inside a run. Group by that value to count each streak, then take the maximum per user.

**Q6. How do you find gaps in a sequence, like missing invoice numbers?**

`LEAD` compares each number with the next, and a difference above 1 is a gap. It cannot see gaps at the edges, so if the expected range matters, I generate the full list and use an anti-join.

**Q7. Assign a session id to each event, starting a new session after 30 minutes of inactivity.**

`LAG` gives the gap to the user's previous event. A `CASE` flags a new session when the gap is over 30 minutes or there is no previous event. A running `SUM` of the flags, partitioned by user, is the session id.

**Q8. Report the fraction of players who logged in again on the day after their first login.**

Find each player's first day with `MIN`. Left join the activity table on the same player and first day plus one. The answer is matches divided by players. I would use `1.0` to avoid integer division.

**Q9. Write a cohort retention query.**

Each user's cohort is the month of their first event. For each event, I compute the months since then. Then I count distinct users per cohort and period, and divide by the cohort size. To show zero cells, I left join from a grid of cohorts and periods.

**Q10. Calculate the mean, median and mode of a column.**

`AVG` for the mean. `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY x)` for the median. For the mode, I group by the value, sort by `COUNT(*)` descending, and keep ties, because there can be more than one.

**Q11. Find customers who bought at least one product from every product category.**

This is relational division. Join orders to products, group by customer, and keep those where `COUNT(DISTINCT category_id)` equals the number of categories. A double `NOT EXISTS` also works.

## Practice

**1. Find the second highest product price.**

<details>
<summary>Show solution</summary>

```sql
SELECT MAX(price) AS second_highest
FROM products
WHERE price < (SELECT MAX(price) FROM products);
```

```text output
 second_highest
----------------
         999.00
(1 row)
```

</details>

**2. For each category, find the cheapest product. Keep ties.**

<details>
<summary>Show solution</summary>

```sql
WITH ranked AS (
  SELECT category_id, product_name, price,
         RANK() OVER (PARTITION BY category_id ORDER BY price) AS price_rank
  FROM products
)
SELECT category_id, product_name, price
FROM ranked
WHERE price_rank = 1
ORDER BY category_id;
```

```text output
 category_id | product_name | price
-------------+--------------+--------
           2 | Phone Lite   | 399.00
           3 | Laptop Air   | 999.00
           4 | Desk Lamp    |  35.00
           5 | Blender      |  49.00
           6 | SQL Basics   |  29.00
           7 | Phone Case   |  19.99
(6 rows)
```

</details>

**3. Find the orders that were paid in more than one payment.**

<details>
<summary>Show solution</summary>

```sql
SELECT order_id, COUNT(*) AS payments
FROM payments
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY order_id;
```

```text output
 order_id | payments
----------+----------
     1003 |        2
(1 row)
```

</details>

**4. Which orders were placed within 30 days of the same customer's previous order?**

<details>
<summary>Show solution</summary>

```sql
WITH with_previous AS (
  SELECT customer_id, order_id, order_date,
         LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS previous_date
  FROM orders
)
SELECT customer_id, order_id, order_date - previous_date AS days_since
FROM with_previous
WHERE order_date - previous_date <= 30
ORDER BY customer_id, order_date;
```

```text output
 customer_id | order_id | days_since
-------------+----------+------------
           1 |     1004 |         28
(1 row)
```

The `WHERE` drops each customer's first order by itself, because `order_date - NULL` is NULL.

</details>

## Recap

- State the grain, ask about ties and NULLs, build in CTE steps, test the edges.
- Nth highest is `DENSE_RANK`, or a correlated count of N - 1 distinct values above.
- Latest per group is `ROW_NUMBER` in a wrapper.
- For islands: value minus `ROW_NUMBER` is constant in a run, or use a change flag plus a running `SUM`.
- Streaks need one row per day first.
- Sessions are `LAG`, a flag, and a running `SUM`.
- Overlap means `a.start < b.end AND b.start < a.end`.
- Peak concurrency is +1 and -1 events with a running `SUM`.

**Next:** [Chapter 22: Functional dependencies](../part-4-database-design/22-functional-dependencies.md)
