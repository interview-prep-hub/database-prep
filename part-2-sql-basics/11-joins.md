# 11. Joins

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 10](10-aggregation-group-by-having.md)

> **In one line:** A join combines rows from two tables by matching a value they share.

## What you will learn

- What each join type keeps and what it drops
- How to predict the row count of any join by hand
- Why a `WHERE` test can quietly turn a `LEFT JOIN` into an inner join
- Why a total can go up after you add a join, and how to fix it
- Self-joins, non-equi joins, cross joins and anti-joins

## Why joins exist

A good database keeps each fact in one place. So `orders` does not store a customer's name. It stores `customer_id`, and the name lives only in `customers`. If a customer changes their name, you update one row.

The cost is that the data you want to see is spread across tables. A join brings it back together:

```text
orders                          customers
+----------+-------------+      +-------------+---------------+
| order_id | customer_id |      | customer_id | customer_name |
+----------+-------------+      +-------------+---------------+
| 1001     | 1           | ---> | 1           | Alice Morgan  |
| 1002     | 2           | ---> | 2           | Bilal Ahmed   |
+----------+-------------+      +-------------+---------------+
```

This is the same join you meet as a math operation in [Chapter 3](../part-1-foundations/03-relational-algebra.md).

## Inner join: keep only the matches

An inner join returns a row only when both tables have a match.

```sql
SELECT e.first_name, e.dept_id, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
ORDER BY e.emp_id;
```

```text output
 first_name | dept_id |  dept_name
------------+---------+-------------
 Sara       |      10 | Executive
 James      |      20 | Sales
 Priya      |      30 | Engineering
 Omar       |      40 | Finance
 Lena       |      20 | Sales
 Diego      |      20 | Sales
 Mei        |      20 | Sales
 Arjun      |      30 | Engineering
 Emma       |      30 | Engineering
 Yusuf      |      30 | Engineering
 Nina       |      40 | Finance
(11 rows)
```

Some things to notice:

- `JOIN` and `INNER JOIN` mean the same thing.
- `e` and `d` are table aliases, short names for the tables. Oracle does not allow `AS` before a table alias, so leave it out everywhere.
- `ON` says how to match rows.
- There are 12 employees but only 11 rows. Tom Baker has no department, so Tom has no match. Legal has no employees, so it is missing too.

If a column name exists in both tables, you must say which one you mean.

```sql error=ambiguous
SELECT first_name, dept_id, dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id;
```

```text output
ERROR:  column reference "dept_id" is ambiguous
LINE 1: SELECT first_name, dept_id, dept_name
                           ^
```

Oracle gives `ORA-00918` for the same mistake. Get into the habit of qualifying every column in a multi-table query. A query with unqualified columns can break later, the day someone adds a same-named column to the other table.

### The mental model

Picture every row of the first table paired with every row of the second. Then keep only the pairs where `ON` is TRUE.

```text
Tom's row (dept_id = NULL)  paired with Sales (20)  ->  NULL = 20 is not TRUE  ->  dropped
Lena's row (dept_id = 20)   paired with Sales (20)  ->  20 = 20 is TRUE        ->  kept
Lena's row (dept_id = 20)   paired with Legal (50)  ->  20 = 50 is FALSE       ->  dropped
```

Databases do not really work this way, because it would be slow ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) shows what they do). But the result is always the same as if they did, so this model gives you the right answer every time.

## Left, right and full outer joins

An outer join keeps rows even when they have no match, and fills the missing side with NULL.

**LEFT JOIN** keeps every row of the left table, the one written first.

```sql
SELECT e.first_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id >= 10
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

Tom is back, with NULL for the department. `LEFT OUTER JOIN` is the same thing with an extra word.

**RIGHT JOIN** is the mirror image: it keeps every row of the right table. Any right join can be rewritten as a left join by swapping the tables, so most people only ever write `LEFT`. These two queries give the same rows:

```sql
SELECT d.dept_name, e.first_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id = 50;
```

```sql
SELECT d.dept_name, e.first_name
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
WHERE d.dept_id = 50;
```

```text output
 dept_name | first_name
-----------+------------
 Legal     | NULL
(1 row)
```

**FULL OUTER JOIN** keeps the unmatched rows from both sides. Here are only the unmatched rows, so that you can see both kinds:

```sql
SELECT e.first_name, d.dept_name
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL OR d.dept_id IS NULL
ORDER BY e.first_name;
```

```text output
 first_name | dept_name
------------+-----------
 Tom        | NULL
 NULL       | Legal
(2 rows)
```

MySQL has no `FULL JOIN`. [Chapter 12](12-set-operations.md) shows how to build one with `UNION`.

### All four, on the same rows

```sql
SELECT 'inner' AS join_type, COUNT(*) AS row_count
FROM employees e JOIN departments d ON e.dept_id = d.dept_id
UNION ALL
SELECT 'left', COUNT(*)
FROM employees e LEFT JOIN departments d ON e.dept_id = d.dept_id
UNION ALL
SELECT 'right', COUNT(*)
FROM employees e RIGHT JOIN departments d ON e.dept_id = d.dept_id
UNION ALL
SELECT 'full', COUNT(*)
FROM employees e FULL JOIN departments d ON e.dept_id = d.dept_id
ORDER BY row_count, join_type;
```

```text output
 join_type | row_count
-----------+-----------
 inner     |        11
 left      |        12
 right     |        12
 full      |        13
(4 rows)
```

```text
                 INNER   = 11 matched rows
LEFT  = 11 matched + Tom            = 12
RIGHT = 11 matched + Legal          = 12
FULL  = 11 matched + Tom + Legal    = 13
```

### Which one should you pick?

| You want | Use |
|---|---|
| Rows that exist on both sides | `INNER JOIN` |
| Everything from one table, with extra data where it exists | `LEFT JOIN` |
| To compare two sources and see what is missing from each | `FULL OUTER JOIN` |
| Every combination of two sets | `CROSS JOIN` |

## Counting join rows by hand

Interviewers love this one. Two rules decide the answer:

1. A value that appears **m** times on one side and **n** times on the other gives **m x n** rows.
2. NULL never matches anything, not even another NULL, because `NULL = NULL` is UNKNOWN, not TRUE ([Chapter 5](../part-1-foundations/05-data-types-and-null.md)).

Let us try it on two tiny tables.

```sql
CREATE TABLE ta (x INTEGER);
CREATE TABLE tb (x INTEGER);

INSERT INTO ta VALUES (1);
INSERT INTO ta VALUES (1);
INSERT INTO ta VALUES (2);
INSERT INTO ta VALUES (NULL);

INSERT INTO tb VALUES (1);
INSERT INTO tb VALUES (1);
INSERT INTO tb VALUES (1);
INSERT INTO tb VALUES (3);
INSERT INTO tb VALUES (NULL);
```

So `ta` holds 1, 1, 2, NULL and `tb` holds 1, 1, 1, 3, NULL. Work it out before you look at the result.

```text
Inner:  value 1 appears 2 times in ta and 3 times in tb    2 x 3 = 6 rows
        nothing else matches                               Total   6

Left:   the 6 matches                                              6
        ta rows with no match: 2 and NULL                          2
                                                           Total   8

Right:  the 6 matches                                              6
        tb rows with no match: 3 and NULL                          2
                                                           Total   8

Full:   the 6 matches + 2 from ta + 2 from tb              Total  10
```

```sql
SELECT 'inner' AS join_type, COUNT(*) AS row_count FROM ta JOIN tb ON ta.x = tb.x
UNION ALL
SELECT 'left', COUNT(*) FROM ta LEFT JOIN tb ON ta.x = tb.x
UNION ALL
SELECT 'right', COUNT(*) FROM ta RIGHT JOIN tb ON ta.x = tb.x
UNION ALL
SELECT 'full', COUNT(*) FROM ta FULL JOIN tb ON ta.x = tb.x
ORDER BY row_count, join_type;
```

```text output
 join_type | row_count
-----------+-----------
 inner     |         6
 left      |         8
 right     |         8
 full      |        10
(4 rows)
```

Clean up the demo tables:

```sql
DROP TABLE ta;
DROP TABLE tb;
```

## Anti-join: find rows with no match

An anti-join finds rows in one table that have no partner in another. This is one of the most common interview questions: find customers who never placed an order.

Do a `LEFT JOIN`, then keep the rows where the right side came back empty.

```sql
SELECT c.customer_id, c.customer_name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.customer_id;
```

```text output
 customer_id | customer_name
-------------+---------------
           7 | Hana Sato
           8 | Ivan Novak
(2 rows)
```

Always test a column that can never be NULL in the right table, such as its primary key. If you tested `o.emp_id` here, orders 1014 and 1016 would look like "no match", because their `emp_id` really is NULL.

The same idea finds products that were never sold:

```sql
SELECT p.product_name
FROM products p
LEFT JOIN order_items i ON i.product_id = p.product_id
WHERE i.order_id IS NULL;
```

```text output
 product_name
--------------
 Desk Lamp
(1 row)
```

[Chapter 13](13-subqueries.md) compares this with `NOT EXISTS` and `NOT IN`, and shows the NULL trap in `NOT IN`.

## ON vs WHERE in an outer join

This is the most important section of the chapter.

- `ON` decides what counts as a match.
- `WHERE` filters the finished result.

For an inner join the two give the same answer. For an outer join they do not.

Suppose you want every customer, plus their cancelled orders if they have any. This attempt is wrong:

```sql
SELECT c.customer_name, o.order_id, o.status
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.status = 'CANCELLED'
ORDER BY c.customer_id;
```

```text output
 customer_name | order_id |  status
---------------+----------+-----------
 Bilal Ahmed   |     1006 | CANCELLED
(1 row)
```

Only 1 row. What happened?

1. The `LEFT JOIN` ran and kept every customer. Hana and Ivan got NULL in `o.status`.
2. `WHERE` then ran. For those rows, `NULL = 'CANCELLED'` is UNKNOWN, so they were thrown away. Customers whose orders were not cancelled were thrown away too.

The `LEFT JOIN` has become an inner join. A test like this, which is never TRUE for NULL, is called **null-rejecting**.

Move the test into `ON`, so that it is part of the matching:

```sql
SELECT c.customer_name, o.order_id, o.status
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
                  AND o.status = 'CANCELLED'
ORDER BY c.customer_id;
```

```text output
 customer_name | order_id |  status
---------------+----------+-----------
 Alice Morgan  |     NULL | NULL
 Bilal Ahmed   |     1006 | CANCELLED
 Chloe Martin  |     NULL | NULL
 David Lee     |     NULL | NULL
 Fatima Noor   |     NULL | NULL
 George Hall   |     NULL | NULL
 Hana Sato     |     NULL | NULL
 Ivan Novak    |     NULL | NULL
(8 rows)
```

Now all 8 customers are there. `IS NULL` is not null-rejecting, which is exactly why the anti-join above works in `WHERE`.

## COUNT after a LEFT JOIN

A customer with no orders still has one row after a `LEFT JOIN`, so `COUNT(*)` counts 1 for that customer. Count a column from the right table instead, because `COUNT(column)` skips NULLs.

```sql
SELECT c.customer_name,
       COUNT(*) AS wrong_count,
       COUNT(o.order_id) AS right_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id;
```

```text output
 customer_name | wrong_count | right_count
---------------+-------------+-------------
 Alice Morgan  |           4 |           4
 Bilal Ahmed   |           3 |           3
 Chloe Martin  |           3 |           3
 David Lee     |           2 |           2
 Fatima Noor   |           2 |           2
 George Hall   |           2 |           2
 Hana Sato     |           1 |           0
 Ivan Novak    |           1 |           0
(8 rows)
```

Look at Hana and Ivan: `COUNT(*)` says 1, and the true answer is 0.

## Joining three or more tables

Keep adding `JOIN` clauses. Logically, each join adds to the result so far, from left to right.

```sql
SELECT o.order_id, c.customer_name, p.product_name, i.quantity, i.unit_price
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id
WHERE o.order_id IN (1001, 1002)
ORDER BY o.order_id, p.product_name;
```

```text output
 order_id | customer_name |  product_name   | quantity | unit_price
----------+---------------+-----------------+----------+------------
     1001 | Alice Morgan  | Phone Case      |        2 |      19.99
     1001 | Alice Morgan  | Phone X         |        1 |     799.00
     1002 | Bilal Ahmed   | Database Design |        1 |      45.00
     1002 | Bilal Ahmed   | SQL Basics      |        1 |      29.00
(4 rows)
```

The order of inner joins does not change the result, so the database is free to reorder them for speed. The order of outer joins does matter.

### The join chain trap

A later inner join can cancel an earlier left join. Say you want every customer, with their order lines:

```sql
SELECT COUNT(DISTINCT c.customer_id) AS customers_kept
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id = o.order_id;
```

```text output
 customers_kept
----------------
              6
(1 row)
```

Only 6 of the 8 customers survive. Hana has `o.order_id` = NULL after the left join. The inner join then needs `i.order_id = NULL`, which is never TRUE, so Hana is dropped.

There are two fixes. The simple one is to make the later join a `LEFT JOIN` as well:

```sql
SELECT COUNT(DISTINCT c.customer_id) AS customers_kept
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
LEFT JOIN order_items i ON i.order_id = o.order_id;
```

```text output
 customers_kept
----------------
              8
(1 row)
```

The other is to do the inner join first, in parentheses, then left join to its result:

```sql
SELECT COUNT(DISTINCT c.customer_id) AS customers_kept
FROM customers c
LEFT JOIN (orders o JOIN order_items i ON i.order_id = o.order_id)
       ON o.customer_id = c.customer_id;
```

```text output
 customers_kept
----------------
              8
(1 row)
```

## Fan-out: why your total went up

**Grain** means what one row stands for. In `orders`, one row is one order. In `order_items`, one row is one line of an order. When you join a table to something at a finer grain, each row repeats.

That is usually fine. It becomes a bug when you add up a number from the repeated side. Here we join `orders` to two child tables at once:

```sql
SELECT o.order_id,
       SUM(p.amount) AS total_paid,
       SUM(i.quantity * i.unit_price) AS total_items
FROM orders o
JOIN payments p ON p.order_id = o.order_id
JOIN order_items i ON i.order_id = o.order_id
WHERE o.order_id IN (1001, 1003)
GROUP BY o.order_id
ORDER BY o.order_id;
```

```text output
 order_id | total_paid | total_items
----------+------------+-------------
     1001 |    1677.96 |      838.98
     1003 |    1499.00 |     2998.00
(2 rows)
```

Both orders are wrong. Order 1001 was paid 838.98, not double that. Order 1003 has items worth 1499.00, not 2998.00. Here is why:

```text
Order 1001: 2 items x 1 payment  = 2 rows, so the 1 payment is counted 2 times
Order 1003: 1 item  x 2 payments = 2 rows, so the 1 item is counted 2 times
```

**How to spot it:** run `COUNT(*)` before and after adding the join. If the count rises and you did not expect that, you have a fan-out.

**How to fix it:** add up each child table first, so that it has one row per order, and then join the totals.

```sql
SELECT o.order_id, p.total_paid, i.total_items
FROM orders o
JOIN (SELECT order_id, SUM(amount) AS total_paid
      FROM payments
      GROUP BY order_id) p ON p.order_id = o.order_id
JOIN (SELECT order_id, SUM(quantity * unit_price) AS total_items
      FROM order_items
      GROUP BY order_id) i ON i.order_id = o.order_id
WHERE o.order_id IN (1001, 1003)
ORDER BY o.order_id;
```

```text output
 order_id | total_paid | total_items
----------+------------+-------------
     1001 |     838.98 |      838.98
     1003 |    1499.00 |     1499.00
(2 rows)
```

Do not reach for these two false fixes:

- `SUM(DISTINCT p.amount)` looks right here, but it breaks as soon as two real payments have the same amount, because it counts that amount only once.
- `SELECT DISTINCT` after a join hides the extra rows without fixing them. When you feel the need for `DISTINCT` after a join, stop and ask why the rows repeated.

## Self-join: a table joined to itself

A self-join treats one table as two, using two aliases. The classic use is a table whose rows point at each other, like `employees.manager_id`.

```sql
SELECT e.first_name AS employee, m.first_name AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id
ORDER BY e.emp_id;
```

```text output
 employee | manager
----------+---------
 Sara     | NULL
 James    | Sara
 Priya    | Sara
 Omar     | Sara
 Lena     | James
 Diego    | James
 Mei      | James
 Arjun    | Priya
 Emma     | Arjun
 Yusuf    | Arjun
 Nina     | Omar
 Tom      | Priya
(12 rows)
```

Read `e` as "the employee" and `m` as "the manager". Use `LEFT JOIN` here: an inner join would lose Sara Khan, who has no manager.

### Employees who earn more than their manager

```sql
SELECT e.first_name, e.salary, m.first_name AS manager, m.salary AS manager_salary
FROM employees e
JOIN employees m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;
```

```text output
 first_name | salary | manager | manager_salary
------------+--------+---------+----------------
(0 rows)
```

No rows is the correct answer on this data: nobody out-earns their manager. So how do you know the query works? Test it. Raise one salary inside a transaction, run the query, and undo the change.

```sql postgres
-- PostgreSQL
BEGIN;
UPDATE employees SET salary = 130000 WHERE emp_id = 8;

SELECT e.first_name, e.salary, m.first_name AS manager, m.salary AS manager_salary
FROM employees e
JOIN employees m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;

ROLLBACK;
```

```text output
BEGIN
UPDATE 1
 first_name | salary | manager | manager_salary
------------+--------+---------+----------------
 Arjun      | 130000 | Priya   |         120000
(1 row)

ROLLBACK
```

On Oracle, leave out the `BEGIN` line, because a transaction starts by itself. [Chapter 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) explains why.

### Finding pairs

To find employees who share a salary, join on the salary. Use `<` on the id, not `<>`.

```sql
SELECT a.first_name AS person_1, b.first_name AS person_2, a.salary
FROM employees a
JOIN employees b ON a.salary = b.salary AND a.emp_id < b.emp_id
ORDER BY a.salary DESC, a.emp_id;
```

```text output
 person_1 | person_2 | salary
----------+----------+--------
 James    | Omar     |  95000
 Emma     | Yusuf    |  82000
 Lena     | Diego    |  60000
(3 rows)
```

That is 3 pairs. With `a.emp_id <> b.emp_id` you would get 6 rows, because each pair comes back twice: (James, Omar) and (Omar, James). With no id test at all, each person also matches themselves.

## Non-equi joins

`ON` can hold any condition, not just `=`. A join with a condition other than equality is called a non-equi join. A common use is matching a value to a range.

```sql
CREATE TABLE salary_grades (
  grade       VARCHAR(1) PRIMARY KEY,
  min_salary  NUMERIC(10),
  max_salary  NUMERIC(10)
);

INSERT INTO salary_grades VALUES ('C', 0, 69999);
INSERT INTO salary_grades VALUES ('B', 70000, 109999);
INSERT INTO salary_grades VALUES ('A', 110000, 999999);
```

```sql
SELECT e.first_name, e.salary, g.grade
FROM employees e
JOIN salary_grades g ON e.salary BETWEEN g.min_salary AND g.max_salary
WHERE e.dept_id = 30
ORDER BY e.salary DESC, e.emp_id;
```

```text output
 first_name | salary | grade
------------+--------+-------
 Priya      | 120000 | A
 Arjun      | 105000 | B
 Emma       |  82000 | B
 Yusuf      |  82000 | B
(4 rows)
```

**Trap:** `BETWEEN` includes both ends. If one range ended at 70000 and the next began at 70000, an employee earning exactly 70000 would match both, and you would get two rows.

```sql
DROP TABLE salary_grades;
```

## Cross join: every combination

`CROSS JOIN` pairs every row of one table with every row of the other. It has no `ON`. With m rows and n rows you get m x n rows, and the columns of both tables.

This is rarely what you want by accident, and very useful on purpose. A common use is to build the full list of what *should* exist, then `LEFT JOIN` the real data to find the gaps.

Here is every sales rep with every order status, including the combinations with zero orders:

```sql
SELECT e.first_name, s.status, COUNT(o.order_id) AS orders
FROM employees e
CROSS JOIN (SELECT DISTINCT status FROM orders) s
LEFT JOIN orders o ON o.emp_id = e.emp_id AND o.status = s.status
WHERE e.job_title = 'Sales Rep'
GROUP BY e.first_name, s.status
ORDER BY e.first_name, s.status;
```

```text output
 first_name |  status   | orders
------------+-----------+--------
 Diego      | CANCELLED |      0
 Diego      | DELIVERED |      4
 Diego      | PENDING   |      0
 Diego      | SHIPPED   |      0
 Lena       | CANCELLED |      1
 Lena       | DELIVERED |      3
 Lena       | PENDING   |      0
 Lena       | SHIPPED   |      2
 Mei        | CANCELLED |      0
 Mei        | DELIVERED |      2
 Mei        | PENDING   |      1
 Mei        | SHIPPED   |      1
(12 rows)
```

A plain `GROUP BY` on `orders` would not show the zero rows, because those rows do not exist.

## The old comma syntax

Before `JOIN` was added to the SQL standard, people wrote joins like this. You will still see it in old code.

```sql
SELECT e.first_name, d.dept_name
FROM employees e, departments d
WHERE e.dept_id = d.dept_id
ORDER BY e.emp_id;
```

It is an inner join, and it gives the same 11 rows. The danger is that forgetting the `WHERE` line gives no error, just a huge accidental cross join:

```sql
SELECT COUNT(*) AS row_count
FROM employees e, departments d;
```

```text output
 row_count
-----------
        60
(1 row)
```

That is 12 x 5 = 60 rows. Prefer explicit `JOIN`: on Oracle and PostgreSQL, a `JOIN` with no `ON` is a syntax error, so the mistake cannot pass silently. MySQL is the exception, because it accepts `JOIN` without `ON`.

Older Oracle code also has its own outer join syntax. The `(+)` goes on the side that may have no match:

**Oracle:**

```sql oracle
SELECT e.first_name, d.dept_name
FROM employees e, departments d
WHERE e.dept_id = d.dept_id(+)
ORDER BY e.emp_id;
```

That is a left join from `employees`. It cannot express a full outer join. Read it when you meet it, but use `LEFT JOIN` in new code.

### The exam version

A university exam or a GATE paper might ask: when does `SELECT DISTINCT w, x FROM r, s` return exactly the relation `r(w, x)`?

Think of `FROM r, s` as a cross product, `WHERE` as selection, and `SELECT` as projection. The answer is: only when `r` has no duplicate rows and `s` is not empty. If `s` is empty, the cross product is empty, so you get no rows at all. If `r` has duplicates, `DISTINCT` removes them.

## USING and NATURAL JOIN

`USING` is a shortcut for when the join column has the same name on both sides. The result has one combined column.

```sql
SELECT dept_id, e.first_name, d.dept_name
FROM employees e
JOIN departments d USING (dept_id)
WHERE e.emp_id = 2;
```

```text output
 dept_id | first_name | dept_name
---------+------------+-----------
      20 | James      | Sales
(1 row)
```

On Oracle you cannot put a table alias on a `USING` column: writing `e.dept_id` above gives `ORA-25154`.

`NATURAL JOIN` goes further and matches on *every* column with the same name, by itself. That is dangerous. `employees` and `customers` both have an `email` column, so this runs without error and matches on email:

```sql
SELECT COUNT(*) AS row_count
FROM employees NATURAL JOIN customers;
```

```text output
 row_count
-----------
         0
(1 row)
```

The real danger is the future: if someone adds a same-named column to a table, every `NATURAL JOIN` on it silently changes meaning. Avoid it in real code. SQL Server has neither `USING` nor `NATURAL JOIN`.

## When NULL should match NULL

Sometimes you do want NULL to match NULL, for example when comparing two copies of a table.

**PostgreSQL:**

```sql postgres
SELECT COUNT(*) AS same_city
FROM customers a
JOIN customers b ON a.city IS NOT DISTINCT FROM b.city
WHERE a.customer_id = 8 AND b.customer_id = 8;
```

```text output
 same_city
-----------
         1
(1 row)
```

**Any engine:** write it out in full.

```sql
SELECT COUNT(*) AS same_city
FROM customers a
JOIN customers b ON a.city = b.city OR (a.city IS NULL AND b.city IS NULL)
WHERE a.customer_id = 8 AND b.customer_id = 8;
```

```text output
 same_city
-----------
         1
(1 row)
```

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Filter the right table in `WHERE` after a `LEFT JOIN` | The join becomes an inner join | Move the test into `ON` |
| Use `COUNT(*)` after a `LEFT JOIN` | Rows with no match count as 1 | Count a right-table column |
| Sum a parent-level amount after joining a child table | The amount is counted several times | Check the grain, and aggregate first |
| Add `DISTINCT` to hide repeated rows | The bug is hidden, not fixed | Find out why the rows repeated |
| Assume a join keeps the left table's row count | Duplicate keys multiply rows | Use m x n to predict the count |
| Join on a nullable column | NULLs never match each other | Use an explicit NULL test when you need it |
| Put an `INNER JOIN` after a `LEFT JOIN`, on the outer table's column | The outer join is cancelled | Make it `LEFT`, or nest it in parentheses |
| Test a nullable column in an anti-join | A real NULL looks like "no match" | Test the right table's primary key |
| Forget the condition in comma syntax | An accidental Cartesian product | Use explicit `JOIN ... ON` |
| Use `a.id <> b.id` to find pairs | Every pair appears twice | Use `a.id < b.id` |
| Use an inner self-join for manager names | The top employee is lost | Use `LEFT JOIN` |
| Use `NATURAL JOIN` in real code | A new column can change the result | Name the join columns yourself |
| Write `FROM employees AS e` on Oracle | `ORA-00933` | Leave out `AS` before table aliases |
| Leave columns unqualified | The query breaks when a same-named column is added | Qualify every column |

## Interview questions

**Q1. What are joins, and what is the difference between INNER, LEFT, RIGHT and FULL?**

A join combines rows from two tables by matching a condition. An inner join keeps only the rows that match on both sides. A left join keeps all rows from the left table and fills the right side with NULL where there is no match. A right join does the same for the right table, and a full join keeps unmatched rows from both sides.

**Q2. Table A holds 1, 1, 2, NULL. Table B holds 1, 1, 1, 3, NULL. How many rows does each join return?**

Inner is 6, because 1 appears twice in A and three times in B, and 2 x 3 = 6. Left is 8: the 6 matches, plus the 2 and the NULL from A. Right is 8: the 6 matches, plus the 3 and the NULL from B. Full is 10. NULLs do not match each other, because `NULL = NULL` is not TRUE.

**Q3. When does a LEFT JOIN behave like an INNER JOIN?**

When a later condition rejects the NULL-filled rows. The usual cause is a `WHERE` test on a right-table column, such as `o.status = 'CANCELLED'`. Another cause is a later inner join on a column from the outer table. In both cases, the rows that the left join kept are thrown away again.

**Q4. What is the difference between a condition in ON and the same condition in WHERE?**

`ON` decides which rows match, and `WHERE` filters the result after the join. For an inner join they give the same answer. For an outer join they differ: a test in `ON` keeps the unmatched left rows with NULLs, and the same test in `WHERE` usually removes them.

**Q5. Find customers who never placed an order.**

I would left join `customers` to `orders` and keep the rows where `o.order_id IS NULL`, testing the primary key because it can never be NULL in a real row. `NOT EXISTS` works just as well, and it is often my first choice because it states the intent. I would avoid `NOT IN` unless the column cannot be NULL, because one NULL in the subquery makes it return no rows.

**Q6. Find employees who earn more than their manager.**

Self-join `employees` on `e.manager_id = m.emp_id`, then filter with `e.salary > m.salary`. An inner join is correct here, since an employee with no manager cannot out-earn one.

*Follow-up they may ask:* What if the query returns nothing? Then I would prove it works, by changing a row inside a transaction, running the query, and rolling back.

**Q7. What is a self-join? Give an example.**

A self-join joins a table to itself using two aliases. It is used when rows in a table relate to other rows in the same table. The classic example is listing each employee with their manager's name, with a `LEFT JOIN` so that the top person is kept.

**Q8. What is a cross join, and when would you use one on purpose?**

A cross join pairs every row of one table with every row of another, so m rows and n rows give m x n. On purpose, I use it to build the full grid of what should exist, like every user with every date, and then left join the real data to find what is missing.

**Q9. A SUM went up after you added a join. Why, and how do you fix it?**

The join changed the grain. Rows repeated because the new table has several rows per key, so the amount was counted several times. I confirm it by comparing `COUNT(*)` before and after. To fix it, I aggregate the child table first so that it has one row per key, and then I join. I would not use `SUM(DISTINCT ...)`, because two real amounts can be equal.

**Q10. When does `SELECT DISTINCT w, x FROM r, s` return exactly `r`?**

Only when `r` has no duplicates and `s` is not empty. An empty `s` makes the cross product empty, and `DISTINCT` removes any duplicates in `r`.

## Practice

**1. List each order id with the customer's name, for orders with status SHIPPED.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.order_id, c.customer_name
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status = 'SHIPPED'
ORDER BY o.order_id;
```

```text output
 order_id | customer_name
----------+---------------
     1011 | David Lee
     1012 | Fatima Noor
     1013 | Bilal Ahmed
(3 rows)
```

</details>

**2. List every department with its number of employees, including departments with none.**

<details>
<summary>Show solution</summary>

```sql
SELECT d.dept_name, COUNT(e.emp_id) AS headcount
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name
ORDER BY d.dept_name;
```

```text output
  dept_name  | headcount
-------------+-----------
 Engineering |         4
 Executive   |         1
 Finance     |         2
 Legal       |         0
 Sales       |         4
(5 rows)
```

Counting `e.emp_id` instead of `*` is what gives Legal a 0.

</details>

**3. Find orders that have no payment.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.order_id, o.status
FROM orders o
LEFT JOIN payments p ON p.order_id = o.order_id
WHERE p.payment_id IS NULL
ORDER BY o.order_id;
```

```text output
 order_id |  status
----------+-----------
     1006 | CANCELLED
     1014 | PENDING
     1015 | PENDING
     1016 | PENDING
(4 rows)
```

</details>

**4. Show each category with its parent category's name. Top-level categories should still appear.**

<details>
<summary>Show solution</summary>

```sql
SELECT c.category_name, p.category_name AS parent_name
FROM categories c
LEFT JOIN categories p ON c.parent_id = p.category_id
ORDER BY c.category_id;
```

```text output
   category_name   | parent_name
-------------------+-------------
 Electronics       | NULL
 Phones            | Electronics
 Laptops           | Electronics
 Home              | NULL
 Kitchen           | Home
 Books             | NULL
 Phone Accessories | Phones
(7 rows)
```

</details>

**5. Show each order's total value and the amount paid so far, for all 16 orders. Show 0 where nothing was paid.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.order_id,
       i.total_items,
       COALESCE(p.total_paid, 0) AS total_paid
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS total_items
      FROM order_items
      GROUP BY order_id) i ON i.order_id = o.order_id
LEFT JOIN (SELECT order_id, SUM(amount) AS total_paid
           FROM payments
           GROUP BY order_id) p ON p.order_id = o.order_id
ORDER BY o.order_id;
```

```text output
 order_id | total_items | total_paid
----------+-------------+------------
     1001 |      838.98 |     838.98
     1002 |       74.00 |      74.00
     1003 |     1499.00 |    1499.00
     1004 |       89.50 |      89.50
     1005 |     1018.99 |    1018.99
     1006 |      399.00 |          0
     1007 |      837.98 |     837.98
     1008 |       87.00 |      87.00
     1009 |       49.00 |      49.00
     1010 |      749.00 |     749.00
     1011 |      119.00 |     119.00
     1012 |      179.00 |     179.00
     1013 |      999.00 |     500.00
     1014 |       59.97 |          0
     1015 |     1588.50 |          0
     1016 |      399.00 |          0
(16 rows)
```

Each child table is added up first, so there is no fan-out. The payments join is a `LEFT JOIN`, because some orders have no payment.

</details>

**6. Find pairs of customers from the same city. Show each pair once.**

<details>
<summary>Show solution</summary>

```sql
SELECT a.customer_name AS customer_1, b.customer_name AS customer_2, a.city
FROM customers a
JOIN customers b ON a.city = b.city AND a.customer_id < b.customer_id
ORDER BY a.city;
```

```text output
  customer_1  | customer_2  |  city
--------------+-------------+--------
 Bilal Ahmed  | Fatima Noor | Dubai
 Alice Morgan | George Hall | London
(2 rows)
```

</details>

**7. List every employee who has nobody reporting to them.**

<details>
<summary>Show solution</summary>

```sql
SELECT e.first_name, e.job_title
FROM employees e
LEFT JOIN employees r ON r.manager_id = e.emp_id
WHERE r.emp_id IS NULL
ORDER BY e.emp_id;
```

```text output
 first_name | job_title
------------+------------
 Lena       | Sales Rep
 Diego      | Sales Rep
 Mei        | Sales Rep
 Emma       | Developer
 Yusuf      | Developer
 Nina       | Accountant
 Tom        | Intern
(7 rows)
```

This is an anti-join and a self-join at once: `r` stands for "someone who reports to e".

</details>

## Recap

- An inner join keeps matches only. Left, right and full joins also keep unmatched rows, with NULLs on the missing side.
- `m x n` predicts row counts, and NULL never matches NULL.
- An anti-join is a `LEFT JOIN` plus `IS NULL` on the right table's primary key.
- `ON` decides what matches. `WHERE` filters afterward. A `WHERE` test on the right table can cancel a `LEFT JOIN`.
- After a `LEFT JOIN`, count a right-table column, not `*`.
- If a total goes up after a join, you have a fan-out. Aggregate the child table first.
- `DISTINCT` after a join is a warning sign, not a fix.
- For pairs, use `a.id < b.id`.

**Next:** [Chapter 12: Set operations](12-set-operations.md)
