# 55. SQL Query Problems: From Warm-Ups to Hard Interview Questions

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 2 and 3

> **In one line:** This is timed practice, not new teaching: try each problem with a timer before you open the solution.

## How to use this chapter

1. Start a timer. Write the query in a plain editor.
2. Run it. Then compare your result with the solution.
3. If you got it wrong, fix it, and retry the problem two days later.

Every problem uses the [sample database](../setup/sample-database.md). Unless a solution is labeled, it runs on both Oracle and PostgreSQL. Each output below is a real result.

### First questions to ask in the room

- Which engine and version? Will the query be run, or only read?
- What should happen with ties, NULLs and empty results?
- What does one row of the result stand for?

### The routine

Restate the problem. State the grain. Name the pattern. Build in named CTEs, such as `monthly_revenue`, not `t1`. Test the edges out loud.

**The edge-case check, tied to sample rows:**

| Edge | Sample row |
|---|---|
| NULL key | Tom Baker's `dept_id` |
| NULL value vs zero | Mei Chen's commission of 0 |
| No match | Legal, Hana Sato, Desk Lamp |
| Ties | Salaries 95000, 82000 and 60000 |
| Join fan-out | Order 1003's two payments |
| Empty group | Customer 7 in a revenue report |

**Window or `GROUP BY`?** If you want one row per group, use `GROUP BY`. If every input row must stay, use a window.

## Level 1: Warm-ups (2 to 3 minutes each)

**1. List products under 50, cheapest first.**

<details>
<summary>Show solution</summary>

```sql
SELECT product_name, price
FROM products
WHERE price < 50
ORDER BY price, product_id;
```

```text output
  product_name   | price
-----------------+-------
 Phone Case      | 19.99
 SQL Basics      | 29.00
 Desk Lamp       | 35.00
 Database Design | 45.00
 Blender         | 49.00
(5 rows)
```

</details>

**2. How many employees have no commission recorded? Do not count a commission of 0.**

<details>
<summary>Show solution</summary>

```sql
SELECT COUNT(*) AS no_commission
FROM employees
WHERE commission IS NULL;
```

```text output
 no_commission
---------------
             8
(1 row)
```

</details>

**3. Show employees hired in 2021.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, hire_date
FROM employees
WHERE hire_date >= DATE '2021-01-01'
  AND hire_date <  DATE '2022-01-01'
ORDER BY hire_date;
```

```text output
 first_name | hire_date
------------+------------
 Yusuf      | 2021-05-19
 Nina       | 2021-10-11
(2 rows)
```

</details>

**4. Show the different job titles in department 20.**

<details>
<summary>Show solution</summary>

```sql
SELECT DISTINCT job_title
FROM employees
WHERE dept_id = 20
ORDER BY job_title;
```

```text output
   job_title
---------------
 Sales Manager
 Sales Rep
(2 rows)
```

</details>

**5. Show the 3 highest-paid employees, keeping ties. (Oracle 12c and later, and PostgreSQL.)**

<details>
<summary>Show solution</summary>

```sql since=12c
SELECT first_name, salary
FROM employees
ORDER BY salary DESC
FETCH FIRST 3 ROWS WITH TIES;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
(3 rows)
```

</details>

## Level 2: Joins and aggregates (5 minutes each)

**6. Show every employee with their department name, including anyone with no department.**

<details>
<summary>Show solution</summary>

```sql
SELECT e.first_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON d.dept_id = e.dept_id
WHERE e.emp_id > 9
ORDER BY e.emp_id;
```

```text output
 first_name |  dept_name
------------+-------------
 Yusuf      | Engineering
 Nina       | Finance
 Tom        | NULL
(3 rows)
```

The `WHERE` only shortens the output here. `LEFT JOIN` is what keeps Tom.

</details>

**7. Show total revenue per customer, from delivered orders, highest first.**

<details>
<summary>Show solution</summary>

```sql
SELECT c.customer_name, SUM(i.quantity * i.unit_price) AS revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id = o.order_id
WHERE o.status = 'DELIVERED'
GROUP BY c.customer_id, c.customer_name
ORDER BY revenue DESC, c.customer_id;
```

```text output
 customer_name | revenue
---------------+---------
 Chloe Martin  | 1586.00
 David Lee     | 1018.99
 Alice Morgan  |  977.48
 Fatima Noor   |  837.98
 George Hall   |  749.00
 Bilal Ahmed   |   74.00
(6 rows)
```

</details>

**8. Find customers with 2 or more orders in the first quarter of 2024.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_id, COUNT(*) AS q1_orders
FROM orders
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-04-01'
GROUP BY customer_id
HAVING COUNT(*) >= 2
ORDER BY customer_id;
```

```text output
 customer_id | q1_orders
-------------+-----------
           1 |         3
           2 |         2
           3 |         2
(3 rows)
```

</details>

**9. Which category has the highest revenue? Include subcategories only under their own name.**

<details>
<summary>Show solution</summary>

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
SELECT cat.category_name, SUM(i.quantity * i.unit_price) AS revenue
FROM order_items i
JOIN products p ON p.product_id = i.product_id
JOIN categories cat ON cat.category_id = p.category_id
GROUP BY cat.category_id, cat.category_name
ORDER BY revenue DESC
FETCH FIRST 1 ROW WITH TIES;
```

```text output
 category_name | revenue
---------------+---------
 Laptops       | 4996.00
(1 row)
```

</details>

**10. Show how many employees work in each city, including cities with none.**

<details>
<summary>Show solution</summary>

```sql
SELECT d.location, COUNT(e.emp_id) AS staff
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.location
ORDER BY staff DESC, d.location;
```

```text output
 location  | staff
-----------+-------
 London    |     4
 Toronto   |     4
 Dubai     |     2
 New York  |     1
 Singapore |     0
(5 rows)
```

</details>

**11. Show each order with its total value and its number of lines, for orders with more than one line.**

<details>
<summary>Show solution</summary>

```sql
SELECT order_id,
       COUNT(*) AS line_count,
       SUM(quantity * unit_price) AS order_value
FROM order_items
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY order_id;
```

```text output
 order_id | line_count | order_value
----------+------------+-------------
     1001 |          2 |      838.98
     1002 |          2 |       74.00
     1005 |          2 |     1018.99
     1007 |          2 |      837.98
     1011 |          2 |      119.00
     1015 |          2 |     1588.50
(6 rows)
```

</details>

## Level 3: Subqueries and set logic (6 to 8 minutes each)

**12. Find the second highest order total.**

<details>
<summary>Show solution</summary>

```sql
WITH totals AS (
  SELECT order_id, SUM(quantity * unit_price) AS total
  FROM order_items
  GROUP BY order_id
),
ranked AS (
  SELECT total, DENSE_RANK() OVER (ORDER BY total DESC) AS rnk
  FROM totals
)
SELECT DISTINCT total
FROM ranked
WHERE rnk = 2;
```

```text output
  total
---------
 1499.00
(1 row)
```

</details>

**13. Find customers who bought from both the Books and the Phones categories.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.customer_id
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id
GROUP BY o.customer_id
HAVING COUNT(CASE WHEN p.category_id = 6 THEN 1 END) > 0
   AND COUNT(CASE WHEN p.category_id = 2 THEN 1 END) > 0
ORDER BY o.customer_id;
```

```text output
 customer_id
-------------
           2
           3
(2 rows)
```

</details>

**14. Show orders that are not fully paid, with the amount still due. Leave out cancelled orders.**

<details>
<summary>Show solution</summary>

```sql
WITH totals AS (
  SELECT order_id, SUM(quantity * unit_price) AS total
  FROM order_items
  GROUP BY order_id
),
paid AS (
  SELECT order_id, SUM(amount) AS paid_amount
  FROM payments
  GROUP BY order_id
)
SELECT t.order_id, t.total - COALESCE(p.paid_amount, 0) AS due
FROM totals t
JOIN orders o ON o.order_id = t.order_id
LEFT JOIN paid p ON p.order_id = t.order_id
WHERE o.status <> 'CANCELLED'
  AND t.total > COALESCE(p.paid_amount, 0)
ORDER BY t.order_id;
```

```text output
 order_id |   due
----------+---------
     1013 |  499.00
     1014 |   59.97
     1015 | 1588.50
     1016 |  399.00
(4 rows)
```

Each child table is added up first, so order 1003's two payments cannot fan out.

</details>

**15. Find employees who have never taken an order, and are in Sales.**

<details>
<summary>Show solution</summary>

```sql
SELECT e.first_name
FROM employees e
WHERE e.dept_id = 20
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.emp_id = e.emp_id)
ORDER BY e.emp_id;
```

```text output
 first_name
------------
 James
(1 row)
```

`NOT IN` would return nothing here, because website orders have a NULL `emp_id`.

</details>

**16. Find products priced above the average price of their own category.**

<details>
<summary>Show solution</summary>

```sql
SELECT p.product_name, p.price
FROM products p
WHERE p.price > (SELECT AVG(x.price)
                 FROM products x
                 WHERE x.category_id = p.category_id)
ORDER BY p.product_id;
```

```text output
  product_name   |  price
-----------------+---------
 Phone X         |  799.00
 Laptop Pro      | 1499.00
 Coffee Maker    |   89.50
 Database Design |   45.00
(4 rows)
```

</details>

## Level 4: Window functions (8 to 10 minutes each)

**17. Find the top spender in each country. Keep ties.**

<details>
<summary>Show solution</summary>

```sql
WITH spend AS (
  SELECT c.country, c.customer_name, SUM(i.quantity * i.unit_price) AS total
  FROM customers c
  JOIN orders o ON o.customer_id = c.customer_id
  JOIN order_items i ON i.order_id = o.order_id
  GROUP BY c.country, c.customer_id, c.customer_name
),
ranked AS (
  SELECT country, customer_name, total,
         RANK() OVER (PARTITION BY country ORDER BY total DESC) AS rnk
  FROM spend
)
SELECT country, customer_name, total
FROM ranked
WHERE rnk = 1
ORDER BY country;
```

```text output
 country | customer_name |  total
---------+---------------+---------
 Canada  | David Lee     | 1137.99
 France  | Chloe Martin  | 1985.00
 UAE     | Bilal Ahmed   | 1472.00
 UK      | George Hall   | 2337.50
(4 rows)
```

</details>

**18. Show each customer's first order.**

<details>
<summary>Show solution</summary>

```sql
WITH ranked AS (
  SELECT customer_id, order_id, order_date,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS rn
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
           1 |     1001 | 2024-01-05
           2 |     1002 | 2024-01-09
           3 |     1003 | 2024-01-20
           4 |     1005 | 2024-02-14
           5 |     1007 | 2024-03-03
           6 |     1010 | 2024-04-04
(6 rows)
```

</details>

**19. Find each customer's longest gap between orders, in days.**

<details>
<summary>Show solution</summary>

```sql
WITH gaps AS (
  SELECT customer_id,
         order_date - LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS gap
  FROM orders
)
SELECT customer_id, MAX(gap) AS longest_gap
FROM gaps
GROUP BY customer_id
HAVING MAX(gap) IS NOT NULL
ORDER BY longest_gap DESC, customer_id;
```

```text output
 customer_id | longest_gap
-------------+-------------
           3 |          95
           2 |          81
           6 |          68
           4 |          67
           1 |          63
           5 |          60
(6 rows)
```

</details>

**20. Show the month-over-month change in the number of orders.**

<details>
<summary>Show solution</summary>

```sql
WITH monthly AS (
  SELECT TO_CHAR(order_date, 'YYYY-MM') AS order_month, COUNT(*) AS order_count
  FROM orders
  GROUP BY TO_CHAR(order_date, 'YYYY-MM')
)
SELECT order_month, order_count,
       order_count - LAG(order_count) OVER (ORDER BY order_month) AS change
FROM monthly
ORDER BY order_month;
```

```text output
 order_month | order_count | change
-------------+-------------+--------
 2024-01     |           3 |   NULL
 2024-02     |           3 |      0
 2024-03     |           3 |      0
 2024-04     |           2 |     -1
 2024-05     |           2 |      0
 2024-06     |           3 |      1
(6 rows)
```

</details>

**21. Show each employee's share of their department's pay, as a percentage, for department 30.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, salary,
       ROUND(100.0 * salary / SUM(salary) OVER (PARTITION BY dept_id), 2) AS pct_of_dept
FROM employees
WHERE dept_id = 30
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary | pct_of_dept
------------+--------+-------------
 Priya      | 120000 |       30.85
 Arjun      | 105000 |       26.99
 Emma       |  82000 |       21.08
 Yusuf      |  82000 |       21.08
(4 rows)
```

</details>

**22. Show the running total of payments per order, for orders with more than one payment.**

<details>
<summary>Show solution</summary>

```sql
WITH counted AS (
  SELECT order_id, payment_date, amount,
         COUNT(*) OVER (PARTITION BY order_id) AS payments_on_order,
         SUM(amount) OVER (PARTITION BY order_id ORDER BY payment_date, payment_id
                           ROWS UNBOUNDED PRECEDING) AS running_paid
  FROM payments
)
SELECT order_id, payment_date, amount, running_paid
FROM counted
WHERE payments_on_order > 1
ORDER BY order_id, payment_date;
```

```text output
 order_id | payment_date | amount  | running_paid
----------+--------------+---------+--------------
     1003 | 2024-01-21   | 1000.00 |      1000.00
     1003 | 2024-02-10   |  499.00 |      1499.00
(2 rows)
```

</details>

## Level 5: Predict the output, and find the bug (2 to 4 minutes each)

Work these out on paper first.

**23. How many rows does this return?**

```sql norun
SELECT first_name FROM employees WHERE dept_id NOT IN (10, 20, NULL);
```

<details>
<summary>Show solution</summary>

Zero. `x NOT IN (10, 20, NULL)` can never be TRUE.

</details>

**24. What is wrong with this "top earner per department"?**

```sql norun
SELECT dept_id, first_name, MAX(salary) FROM employees GROUP BY dept_id;
```

<details>
<summary>Show solution</summary>

`first_name` is neither aggregated nor grouped, so strict engines reject it. An aggregate gives a value, not the row that holds it. Use `RANK()`.

</details>

**25. This query should list all customers, with their cancelled order if any. What is wrong?**

```sql norun
SELECT c.customer_name, o.order_id
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.status = 'CANCELLED';
```

<details>
<summary>Show solution</summary>

The `WHERE` test on the right table removes the NULL rows, so it acts as an inner join. Move the test into `ON`.

</details>

**26. What does this return?**

```sql
SELECT COUNT(commission) AS a, COUNT(*) AS b, COUNT(DISTINCT dept_id) AS c
FROM employees;
```

<details>
<summary>Show solution</summary>

```text output
 a | b  | c
---+----+---
 4 | 12 | 4
(1 row)
```

</details>

**27. Why does this `SUM` come out too high for order 1003?**

```sql norun
SELECT o.order_id, SUM(i.quantity * i.unit_price)
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN payments p ON p.order_id = o.order_id
GROUP BY o.order_id;
```

<details>
<summary>Show solution</summary>

Order 1003 has two payments, so its one item row appears twice. Aggregate each child table first.

</details>

**28. On Oracle, why does this return nothing?**

```sql norun
SELECT first_name FROM employees WHERE ROWNUM = 2;
```

<details>
<summary>Show solution</summary>

The first row gets `ROWNUM` 1, fails the test, and is rejected. The next row also gets 1. No row ever reaches 2.

</details>

## Level 6: Problems that change data

**29. Delete duplicate rows, keeping the lowest id.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE dup_demo (id INTEGER PRIMARY KEY, email VARCHAR(30));
INSERT INTO dup_demo VALUES (1, 'a@x.com');
INSERT INTO dup_demo VALUES (2, 'a@x.com');
INSERT INTO dup_demo VALUES (3, 'b@x.com');

DELETE FROM dup_demo
WHERE id NOT IN (SELECT MIN(d.id) FROM dup_demo d GROUP BY d.email);

SELECT id, email FROM dup_demo ORDER BY id;

DROP TABLE dup_demo;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
INSERT 0 1
DELETE 1
 id |  email
----+---------
  1 | a@x.com
  3 | b@x.com
(2 rows)

DROP TABLE
```

</details>

**30. Give a 10 percent raise to employees earning below their department's average.**

<details>
<summary>Show solution</summary>

```sql
UPDATE employees e
SET salary = salary * 1.10
WHERE e.salary < (SELECT AVG(x.salary)
                  FROM employees x
                  WHERE x.dept_id = e.dept_id);

SELECT first_name, salary FROM employees WHERE dept_id = 40 ORDER BY emp_id;
```

```text output
UPDATE 6
 first_name | salary
------------+--------
 Omar       |  95000
 Nina       |  63800
(2 rows)
```

</details>

## Level 7: Medium reported questions (12 to 15 minutes each)

**31. Find customers who ordered in at least two different months.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_id,
       COUNT(DISTINCT TO_CHAR(order_date, 'YYYY-MM')) AS months_active
FROM orders
GROUP BY customer_id
HAVING COUNT(DISTINCT TO_CHAR(order_date, 'YYYY-MM')) >= 2
ORDER BY customer_id;
```

```text output
 customer_id | months_active
-------------+---------------
           1 |             4
           2 |             3
           3 |             3
           4 |             2
           5 |             2
           6 |             2
(6 rows)
```

</details>

**32. What is the repeat purchase rate: the share of ordering customers with more than one order?**

<details>
<summary>Show solution</summary>

```sql
WITH per_customer AS (
  SELECT customer_id, COUNT(*) AS order_count
  FROM orders
  GROUP BY customer_id
)
SELECT ROUND(100.0 * COUNT(CASE WHEN order_count > 1 THEN 1 END) / COUNT(*), 2) AS repeat_pct
FROM per_customer;
```

```text output
 repeat_pct
------------
     100.00
(1 row)
```

</details>

**33. Find the median order value.**

<details>
<summary>Show solution</summary>

```sql
WITH totals AS (
  SELECT order_id, SUM(quantity * unit_price) AS total
  FROM order_items
  GROUP BY order_id
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total) AS median_value
FROM totals;
```

```text output
 median_value
--------------
          399
(1 row)
```

</details>

## Level 8: Hard problems (20 to 25 minutes each)

**34. Find customers who ordered in 3 consecutive months.**

<details>
<summary>Show solution</summary>

Reduce to one row per customer per month, then use islands on a month number.

```sql
WITH months AS (
  SELECT DISTINCT customer_id,
         EXTRACT(YEAR FROM order_date) * 12 + EXTRACT(MONTH FROM order_date) AS month_no
  FROM orders
),
islands AS (
  SELECT customer_id, month_no,
         month_no - ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY month_no) AS island
  FROM months
)
SELECT customer_id, COUNT(*) AS run_length
FROM islands
GROUP BY customer_id, island
HAVING COUNT(*) >= 3
ORDER BY customer_id;
```

```text output
 customer_id | run_length
-------------+------------
           1 |          3
(1 row)
```

</details>

**35. Which products make up the first 80 percent of revenue, in Pareto order?**

<details>
<summary>Show solution</summary>

```sql
WITH revenue AS (
  SELECT p.product_id, p.product_name, SUM(i.quantity * i.unit_price) AS total
  FROM order_items i
  JOIN products p ON p.product_id = i.product_id
  GROUP BY p.product_id, p.product_name
),
shares AS (
  SELECT product_name, total,
         SUM(total) OVER (ORDER BY total DESC, product_id ROWS UNBOUNDED PRECEDING) AS running,
         SUM(total) OVER () AS grand_total
  FROM revenue
)
SELECT product_name, total,
       ROUND(100.0 * running / grand_total, 1) AS cumulative_pct
FROM shares
WHERE running - total < 0.8 * grand_total
ORDER BY total DESC, product_name;
```

```text output
 product_name |  total  | cumulative_pct
--------------+---------+----------------
 Laptop Pro   | 2998.00 |           33.4
 Laptop Air   | 1998.00 |           55.6
 Phone Lite   | 1596.00 |           73.4
 Phone X      | 1548.00 |           90.6
(4 rows)
```

</details>

**36. For each month, how many customers ordered that month and also the month before?**

<details>
<summary>Show solution</summary>

```sql
WITH months AS (
  SELECT DISTINCT customer_id,
         EXTRACT(YEAR FROM order_date) * 12 + EXTRACT(MONTH FROM order_date) AS month_no
  FROM orders
)
SELECT cur.month_no, COUNT(*) AS retained
FROM months cur
JOIN months prev
  ON prev.customer_id = cur.customer_id
 AND prev.month_no = cur.month_no - 1
GROUP BY cur.month_no
ORDER BY cur.month_no;
```

```text output
 month_no | retained
----------+----------
    24290 |        2
    24291 |        1
(2 rows)
```

`month_no` numbers months in one running count, so neighbors differ by 1 even across a new year. Here 24290 is `2024 * 12 + 2`, which is February 2024, and 24291 is March 2024.

</details>

**37. Find the busiest day of the week for orders. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
SELECT TO_CHAR(order_date, 'FMDay') AS weekday, COUNT(*) AS orders
FROM orders
GROUP BY TO_CHAR(order_date, 'FMDay')
ORDER BY orders DESC, weekday
LIMIT 1;
```

```text output
 weekday | orders
---------+--------
 Friday  |      3
(1 row)
```

</details>

## Follow-ups you should expect

**"How would you make it faster?"** Read the plan first. Make filters SARGable, index the filter and join columns, aggregate before joining, and remove `DISTINCT` that hides a bad join.

**"What if one customer owns 90 percent of the rows?"** Skew makes one plan good for small customers, and terrible for that one. Think of histograms, and bind peeking.

**"What if the table has 500 million rows?"** A full sort and `COUNT(DISTINCT)` over everything stop being cheap. Filter by partition, pre-aggregate, or use `APPROX_COUNT_DISTINCT`.

**"What does a CTE cost?"** PostgreSQL 12 and later folds a simple CTE used once into the query. One used more than once may be computed once and stored.

**Reading an unfamiliar schema.** Find each table's key and grain before you join anything.

## Timed sets

1. **Fast screen:** problems 12, 15, 17 and 19, at 8 minutes each.
2. **Live round:** problems 14 and 34, at 20 minutes each.
3. **Full set:** problems 7, 16, 20, 22 and 35, in 45 minutes.

## Recap

- State the grain before you write `SELECT`.
- Name your CTEs for what they hold.
- Check NULLs, ties, empty groups and fan-out out loud.
- Aggregate child tables before joining them.
- Redo every problem you got wrong, two days later.

**Next:** [Chapter 56: Concept question bank](56-concept-question-bank.md)
