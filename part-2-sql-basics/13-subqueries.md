# 13. Subqueries

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 12](12-set-operations.md)

> **In one line:** A subquery is a `SELECT` inside another statement, used when you need an answer in order to ask the real question.

## What you will learn

- Scalar, multi-row, correlated and inline subqueries
- The `NOT IN` trap, and why `NOT EXISTS` is the safe choice
- `IN` vs `EXISTS`, and the truth about which is faster
- How to answer "for all" questions
- How to choose between a subquery and a join

## What is a subquery?

A subquery sits in parentheses inside another statement. It can appear in `WHERE`, `FROM`, `SELECT` and `HAVING`.

The simplest use is comparing with a value you do not know yet. Who earns more than the company average? You do not know the average, so you ask for it.

```sql
SELECT first_name, salary
FROM employees
WHERE salary > (SELECT AVG(salary) FROM employees)
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
 James      |  95000
 Omar       |  95000
(5 rows)
```

Oracle or PostgreSQL works out the inner query first, gets 84916.67, then uses it like a plain number.

## Scalar subqueries: one row, one column

A subquery that returns a single value is called **scalar**. You can use it anywhere a value fits.

Two edge cases matter:

**Zero rows gives NULL, not an error.** And a comparison with NULL matches nothing:

```sql
SELECT first_name
FROM employees
WHERE salary > (SELECT salary FROM employees WHERE emp_id = 999);
```

```text output
 first_name
------------
(0 rows)
```

**More than one row is an error.** Department 40 has two people, so the `=` has two values to compare with:

```sql error=more
SELECT first_name
FROM employees
WHERE salary = (SELECT salary FROM employees WHERE dept_id = 40);
```

```text output
ERROR:  more than one row returned by a subquery used as an expression
```

Oracle gives `ORA-01427: single-row subquery returns more than one row`. This bug is sneaky: the query works in testing, then fails in production on the day a second row appears.

### Second highest salary

This is a classic first question.

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

It handles ties, and it returns NULL if only one distinct salary exists. [Chapter 21](../part-3-advanced-sql/21-classic-query-patterns.md) compares every other way to solve this.

## Multi-row subqueries: IN, ANY and ALL

When a subquery returns several rows, use `IN`.

```sql
SELECT first_name
FROM employees
WHERE dept_id IN (SELECT dept_id FROM departments WHERE location = 'London')
ORDER BY emp_id;
```

```text output
 first_name
------------
 James
 Lena
 Diego
 Mei
(4 rows)
```

`ANY` and `ALL` compare against a list of values:

- `> ALL (subquery)` means greater than every value.
- `> ANY (subquery)` means greater than at least one value.
- `= ANY` is the same as `IN`.
- `<> ALL` is the same as `NOT IN`.

Who earns more than everyone in Sales?

```sql
SELECT first_name, salary
FROM employees
WHERE salary > ALL (SELECT salary FROM employees WHERE dept_id = 20)
ORDER BY salary DESC, emp_id;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
(3 rows)
```

**Edge cases.** Over an empty subquery, `> ALL` is TRUE and `> ANY` is FALSE. So `> ALL` is not always the same as `> (SELECT MAX(...))`. Legal has no employees, which shows the difference:

```sql
SELECT COUNT(*) AS kept
FROM employees
WHERE salary > ALL (SELECT salary FROM employees WHERE dept_id = 50);
```

```text output
 kept
------
   12
(1 row)
```

```sql
SELECT COUNT(*) AS kept
FROM employees
WHERE salary > (SELECT MAX(salary) FROM employees WHERE dept_id = 50);
```

```text output
 kept
------
    0
(1 row)
```

In the second query, `MAX` over no rows gives NULL, so nothing passes. A NULL inside the subquery also stops `> ALL` from ever being TRUE.

## Pairwise subqueries: comparing two columns

You can compare several columns at once. This finally solves the trap from [Chapter 10](10-aggregation-group-by-having.md): it returns the actual rows that hold each department's highest salary.

```sql
SELECT first_name, dept_id, salary
FROM employees
WHERE (dept_id, salary) IN (SELECT dept_id, MAX(salary)
                            FROM employees
                            GROUP BY dept_id)
ORDER BY dept_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 Sara       |      10 | 180000
 James      |      20 |  95000
 Priya      |      30 | 120000
 Omar       |      40 |  95000
(4 rows)
```

Tom Baker is missing. His NULL `dept_id` never matches. This form works on Oracle, PostgreSQL and MySQL, but not on SQL Server.

## Correlated subqueries

So far, each subquery could run alone. A **correlated** subquery refers to a column of the outer row, so it has a different answer for each outer row.

Who earns more than the average of their own department?

```sql
SELECT e.first_name, e.dept_id, e.salary
FROM employees e
WHERE e.salary > (SELECT AVG(i.salary)
                  FROM employees i
                  WHERE i.dept_id = e.dept_id)
ORDER BY e.emp_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 James      |      20 |  95000
 Priya      |      30 | 120000
 Omar       |      40 |  95000
 Arjun      |      30 | 105000
(4 rows)
```

Read it like this, for each employee `e`:

```text
James, dept 20:  average of dept 20 is 66750.   95000 > 66750   keep
Lena,  dept 20:  average of dept 20 is 66750.   60000 > 66750   drop
Sara,  dept 10:  average of dept 10 is 180000. 180000 > 180000  drop
Tom,   dept NULL: i.dept_id = NULL matches nothing, so the average is NULL. drop
```

| | Plain subquery | Correlated subquery |
|---|---|---|
| Refers to the outer query | No | Yes |
| Can run on its own | Yes | No |
| Conceptually runs | Once | Once per outer row |

"Once per outer row" describes the meaning, not always the plan. Optimizers often rewrite a correlated subquery as a join.

A correlated subquery also gives a second answer to "top earner per department", and it keeps ties:

```sql
SELECT e.first_name, e.dept_id, e.salary
FROM employees e
WHERE e.salary = (SELECT MAX(m.salary)
                  FROM employees m
                  WHERE m.dept_id = e.dept_id)
ORDER BY e.dept_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 Sara       |      10 | 180000
 James      |      20 |  95000
 Priya      |      30 | 120000
 Omar       |      40 |  95000
(4 rows)
```

### The name scoping trap

An unqualified name binds to the nearest table that has it. So a column that is missing from the inner table silently binds to the **outer** table.

```sql
SELECT COUNT(*) AS matched
FROM customers
WHERE customer_id IN (SELECT customer_id FROM departments);
```

```text output
 matched
---------
       8
(1 row)
```

`departments` has no `customer_id`. There is no error. The inner `customer_id` is the outer one, so every customer matches themselves. Always qualify every column in a subquery: `SELECT d.customer_id` would have failed at once.

## EXISTS and semi-joins

`EXISTS` is true if the subquery returns at least one row.

```sql
SELECT c.customer_name
FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id)
ORDER BY c.customer_id;
```

```text output
 customer_name
---------------
 Alice Morgan
 Bilal Ahmed
 Chloe Martin
 David Lee
 Fatima Noor
 George Hall
(6 rows)
```

- It tests only for existence, so the `SELECT` list does not matter. `SELECT 1`, `SELECT *` and `SELECT NULL` behave the same.
- It can stop at the first match.
- Unlike `IN`, it never gives UNKNOWN. The answer is always TRUE or FALSE.

**Semi-join.** `IN` and `EXISTS` return each left row at most once. A plain `JOIN` repeats it for every match. So rewriting `IN` as a `JOIN` can multiply rows:

```sql
SELECT COUNT(*) AS row_count
FROM customers c
WHERE c.customer_id IN (SELECT o.customer_id FROM orders o);
```

```text output
 row_count
-----------
         6
(1 row)
```

```sql
SELECT COUNT(*) AS row_count
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id;
```

```text output
 row_count
-----------
        16
(1 row)
```

## The NOT IN trap

This is one of the most important facts in SQL.

**If the subquery returns even one NULL, `NOT IN` returns no rows.**

Find employees who are not managers. This looks fine:

```sql
SELECT COUNT(*) AS not_managers
FROM employees
WHERE emp_id NOT IN (SELECT manager_id FROM employees);
```

```text output
 not_managers
--------------
            0
(1 row)
```

Zero, and no error. The cause is Sara Khan, whose `manager_id` is NULL. `NOT IN` expands into a chain:

```text
emp_id <> 1 AND emp_id <> 2 AND ... AND emp_id <> NULL
                                        ^^^^^^^^^^^^^^
                                        always UNKNOWN
```

An `AND` chain with UNKNOWN in it can never be TRUE, so every row is rejected.

**The fix is `NOT EXISTS`:**

```sql
SELECT COUNT(*) AS not_managers
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM employees r WHERE r.manager_id = e.emp_id);
```

```text output
 not_managers
--------------
            7
(1 row)
```

You could also add `WHERE manager_id IS NOT NULL` inside the subquery, but `NOT EXISTS` cannot go wrong this way, so make it your habit.

The same trap hits "employees who took no order", because website orders have a NULL `emp_id`:

```sql
SELECT COUNT(*) AS with_not_in
FROM employees
WHERE emp_id NOT IN (SELECT emp_id FROM orders);
```

```text output
 with_not_in
-------------
           0
(1 row)
```

```sql
SELECT COUNT(*) AS with_not_exists
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.emp_id = e.emp_id);
```

```text output
 with_not_exists
-----------------
               9
(1 row)
```

## Rows in one table but not in another

You now know four ways. Which should you pick?

| Method | NULL safe? | Duplicates | Columns you can return |
|---|---|---|---|
| `NOT EXISTS` | Yes | Keeps left rows as they are | Any from the left table |
| `LEFT JOIN ... IS NULL` | Yes | Keeps left rows as they are | Any |
| `NOT IN` | **No** | Keeps left rows as they are | Any from the left table |
| `EXCEPT` (`MINUS` on Oracle) | Treats NULLs as equal | Removes duplicates | Only the compared columns |

**Pick `NOT EXISTS` by default.**

The difference shows up on real data. Which customer cities have no department?

**Oracle:**

```sql oracle
SELECT city FROM customers
MINUS
SELECT location FROM departments;
```

**PostgreSQL:**

```sql postgres
SELECT city FROM customers
EXCEPT
SELECT location FROM departments
ORDER BY city;
```

```text output
 city
-------
 Paris
 Tokyo
 NULL
(3 rows)
```

`NULL` is in that result. It is also in the `NOT EXISTS` version, but not in the `NOT IN` version:

```sql
SELECT DISTINCT c.city
FROM customers c
WHERE c.city NOT IN (SELECT d.location FROM departments d)
ORDER BY c.city;
```

```text output
 city
-------
 Paris
 Tokyo
(2 rows)
```

## "For all" questions

**Find customers who bought every product in the Books category.** The same shape appears as "students registered for every course in a department".

SQL has no "for all" keyword, so turn the sentence around: find customers for whom **there is no Books product they have not bought**. That double negative becomes two `NOT EXISTS`.

```sql
SELECT c.customer_name
FROM customers c
WHERE NOT EXISTS (
        SELECT 1
        FROM products p
        WHERE p.category_id = 6
          AND NOT EXISTS (
                SELECT 1
                FROM orders o
                JOIN order_items i ON i.order_id = o.order_id
                WHERE o.customer_id = c.customer_id
                  AND i.product_id = p.product_id))
ORDER BY c.customer_id;
```

```text output
 customer_name
---------------
 Bilal Ahmed
 David Lee
(2 rows)
```

The other common form counts instead: did they buy as many different Books products as exist?

```sql
SELECT c.customer_name
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id
WHERE p.category_id = 6
GROUP BY c.customer_id, c.customer_name
HAVING COUNT(DISTINCT p.product_id) = (SELECT COUNT(*) FROM products WHERE category_id = 6)
ORDER BY c.customer_id;
```

```text output
 customer_name
---------------
 Bilal Ahmed
 David Lee
(2 rows)
```

The two disagree in one case. If the required set is empty, the double `NOT EXISTS` returns everyone, and the counting form returns no one. This is the SQL form of relational division ([Chapter 3](../part-1-foundations/03-relational-algebra.md)).

## Derived tables (inline views)

A subquery in `FROM` acts as a temporary table for one query. It is called a **derived table**, or an **inline view** on Oracle.

Its most common use is reusing a calculated alias:

```sql
SELECT t.first_name, t.annual_pay
FROM (SELECT first_name, salary * 12 AS annual_pay
      FROM employees) t
WHERE t.annual_pay > 1300000
ORDER BY t.annual_pay DESC;
```

```text output
 first_name | annual_pay
------------+------------
 Sara       |    2160000
 Priya      |    1440000
(2 rows)
```

It also counts distinct pairs, which `COUNT(DISTINCT a, b)` cannot do outside MySQL:

```sql
SELECT COUNT(*) AS distinct_pairs
FROM (SELECT DISTINCT dept_id, job_title FROM employees) t;
```

```text output
 distinct_pairs
----------------
              9
(1 row)
```

And it aggregates before a join, as you saw in [Chapter 11](11-joins.md).

**Alias rules.** MySQL and SQL Server require an alias on a derived table. PostgreSQL required one before version 16. Oracle does not require one, and it never accepts `AS` before it. So always write a short alias with no `AS`, which works everywhere.

### Odd rows

**Show only the odd rows of a table.** Testing `MOD(emp_id, 2)` is the wrong answer, because ids can have gaps. Number the rows first. `ROW_NUMBER()` numbers rows in a chosen order, and [Chapter 15](../part-3-advanced-sql/15-window-functions-ranking-and-offset.md) teaches it. For now, treat it as a recipe.

```sql
SELECT t.emp_id, t.first_name
FROM (SELECT emp_id, first_name,
             ROW_NUMBER() OVER (ORDER BY emp_id) AS rn
      FROM employees
      WHERE dept_id = 20) t
WHERE MOD(t.rn, 2) = 1
ORDER BY t.emp_id;
```

```text output
 emp_id | first_name
--------+------------
      2 | James
      6 | Diego
(2 rows)
```

The rows in department 20 are ids 2, 5, 6 and 7, so the 1st and 3rd are ids 2 and 6. `MOD(emp_id, 2) = 1` would wrongly give 5 and 7.

On Oracle, `WHERE MOD(ROWNUM, 2) = 1` written directly returns only one row, for the same reason `ROWNUM = 2` fails ([Chapter 8](08-select-filter-sort.md)). You must capture `ROWNUM` in an inline view first.

### Pages on Oracle 11g

Here is the recipe from [Chapter 8](08-select-filter-sort.md) in full. To show rows 6 to 10, you need three levels: sort, keep the first 10 and name their numbers, then skip the first 5.

```sql oracle
SELECT emp_id, first_name
FROM (SELECT t.*, ROWNUM AS rn
      FROM (SELECT emp_id, first_name
            FROM employees
            ORDER BY emp_id) t
      WHERE ROWNUM <= 10)
WHERE rn > 5;
```

```text output
EMP_ID FIRST_NAME
------ ----------
     6 Diego
     7 Mei
     8 Arjun
     9 Emma
    10 Yusuf
```

## Subqueries in SELECT and HAVING

A scalar subquery in `SELECT` runs for each row. Many of them can be slower than one join.

```sql
SELECT d.dept_name,
       (SELECT COUNT(*) FROM employees e WHERE e.dept_id = d.dept_id) AS headcount,
       (SELECT MAX(e.salary) FROM employees e WHERE e.dept_id = d.dept_id) AS top_salary
FROM departments d
ORDER BY d.dept_id;
```

```text output
  dept_name  | headcount | top_salary
-------------+-----------+------------
 Executive   |         1 |     180000
 Sales       |         4 |      95000
 Engineering |         4 |     120000
 Finance     |         2 |      95000
 Legal       |         0 |       NULL
(5 rows)
```

Look at Legal. `COUNT` gives 0 and `MAX` gives NULL.

In `HAVING`, a subquery compares a group with something else. Which department has the highest total pay?

```sql
SELECT dept_id, SUM(salary) AS total_pay
FROM employees
WHERE dept_id IS NOT NULL
GROUP BY dept_id
HAVING SUM(salary) >= ALL (SELECT SUM(salary)
                           FROM employees
                           WHERE dept_id IS NOT NULL
                           GROUP BY dept_id);
```

```text output
 dept_id | total_pay
---------+-----------
      30 |    389000
(1 row)
```

## Reading nested queries

Exams often show you a nested query and ask what it returns. Work from the inside out, and write down each result.

```text
SELECT first_name FROM employees
WHERE dept_id NOT IN (SELECT dept_id FROM departments WHERE location = 'London')
  AND salary > 90000;

Step 1  Inner query: departments in London    ->  20
Step 2  NOT IN (20): removes dept 20, and also removes Tom, because NULL <> 20 is UNKNOWN
Step 3  salary > 90000 on what is left        ->  Sara, Priya, Omar, Arjun
```

## Subquery or join?

| You need | Use |
|---|---|
| Columns from the other table | A join |
| Only to test for a match | `EXISTS` or `IN` |
| Rows with no match | `NOT EXISTS` |
| A total from the other table | A derived table |

### IN vs EXISTS: which is faster?

The old rule says "use `IN` for small lists and `EXISTS` for big ones". It dates from rule-based optimizers. Modern Oracle and PostgreSQL usually turn both into the same semi-join plan. So do not repeat the rule. Check the plan ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)). The real difference is about NULLs when you negate them: `NOT EXISTS` is safe, and `NOT IN` is not.

## Changing data from another table

A subquery can feed an `UPDATE` on any engine. The `WHERE EXISTS` matters: without it, rows with no match are set to NULL.

```sql
UPDATE products p
SET price = (SELECT MAX(i.unit_price)
             FROM order_items i
             WHERE i.product_id = p.product_id)
WHERE EXISTS (SELECT 1 FROM order_items i WHERE i.product_id = p.product_id);
```

[Chapter 18](../part-3-advanced-sql/18-advanced-dml.md) teaches the rest. A `WITH` clause is a named derived table that reads from top to bottom, and [Chapter 14](../part-3-advanced-sql/14-cte-and-recursive-queries.md) covers it.

`ORDER BY` inside a subquery is pointless without a row limit, because only the final `ORDER BY` decides the output order. Oracle rejects it in an `IN` subquery with `ORA-00907`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use `NOT IN` on a nullable column | No rows, and no error | Use `NOT EXISTS` |
| Write a scalar subquery that can return two rows | It works in tests, then fails in production | Make sure it returns one row, or use `IN` |
| Assume `> ALL` equals `> MAX` | They differ on an empty result | Think about the empty case |
| Rewrite `IN` as a `JOIN` without checking keys | Rows multiply | Check for duplicates, or keep `EXISTS` |
| Leave columns unqualified in a subquery | A missing column binds to the outer table | Qualify every column |
| Forget the correlation | The subquery gives the same answer for every row | Compare with the outer row |
| Add `ORDER BY` in a subquery to control the output | It has no effect | Use the outer `ORDER BY` |
| Repeat "`EXISTS` is faster than `IN`" | Modern optimizers usually treat them the same | Check the plan |
| Forget the derived table alias, or add `AS` on Oracle | An error on one engine or another | Always use a short alias with no `AS` |
| Match `m.dept_id = e.dept_id` and expect NULL departments | NULLs never match | Handle NULL in the test |
| Use `ROW_NUMBER` for the top earner when ties matter | Only one of the tied rows is kept | Use the correlated `MAX`, or `RANK` |

## Interview questions

**Q1. How can you find records in one table that are not present in another?**

I would use `NOT EXISTS` with a correlated subquery, because it is safe with NULLs and can return any column of the left table. `LEFT JOIN ... IS NULL` also works. I would avoid `NOT IN` on a nullable column. `MINUS` or `EXCEPT` works when I only need the compared columns, though it also removes duplicates.

**Q2. What happens to a NOT IN query when the subquery returns a NULL, and how would you rewrite it?**

It returns no rows and no error. `NOT IN` expands to a chain of `<>` joined by `AND`, and `x <> NULL` is UNKNOWN, so the chain can never be TRUE. I would rewrite it with `NOT EXISTS`, or add `IS NOT NULL` inside the subquery.

**Q3. Write a query to find the students registered for every course offered by department D01.**

I would turn it around: find students for whom no D01 course exists that they have not taken. That is a double `NOT EXISTS`. Another way is to group registrations for D01 courses by student and keep those where `COUNT(DISTINCT course)` equals the number of D01 courses.

**Q4. Write a query to show only the odd rows from a table.**

I number the rows with `ROW_NUMBER()` in a derived table, then filter with `MOD(rn, 2) = 1`. I would not test the id itself, because ids can have gaps. On Oracle, `ROWNUM` must be captured in an inline view first.

**Q5. Find the second highest salary.**

`SELECT MAX(salary) FROM employees WHERE salary < (SELECT MAX(salary) FROM employees)`. It handles ties, and it gives NULL if there is no second value. `DENSE_RANK` is the general answer for the Nth highest.

**Q6. Find the highest-paid employee in each department.**

A correlated subquery that compares the salary with `MAX(salary)` for the same department keeps ties. `RANK()` in a derived table is the window function answer. Either way I would ask whether ties should all be returned.

**Q7. What is the difference between a correlated and a non-correlated subquery?**

A non-correlated subquery can run on its own, and conceptually it runs once. A correlated subquery refers to the outer row, so conceptually it runs once for each outer row. The optimizer may still rewrite it as a join.

**Q8. What is the difference between IN and EXISTS, and which is faster?**

`IN` compares a value with a list, and `EXISTS` tests whether any row exists. On modern optimizers they usually produce the same plan, so the old rule about which is faster no longer holds. The key difference is when negated: `NOT IN` breaks on NULLs, and `NOT EXISTS` does not.

**Q9. When would you use a subquery instead of a join?**

When I only need to test for a match, because `EXISTS` cannot multiply rows. When I need rows with no match. And when I need to aggregate before joining. If I need columns from the other table, a join is the natural choice.

## Practice

**1. List the products that cost more than the average product price.**

<details>
<summary>Show solution</summary>

```sql
SELECT product_name, price
FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY price DESC;
```

```text output
 product_name |  price
--------------+---------
 Laptop Pro   | 1499.00
 Laptop Air   |  999.00
 Phone X      |  799.00
 Phone Lite   |  399.00
(4 rows)
```

</details>

**2. List the names of customers who have at least one PENDING order.**

<details>
<summary>Show solution</summary>

```sql
SELECT c.customer_name
FROM customers c
WHERE EXISTS (SELECT 1
              FROM orders o
              WHERE o.customer_id = c.customer_id
                AND o.status = 'PENDING')
ORDER BY c.customer_id;
```

```text output
 customer_name
---------------
 Alice Morgan
 Chloe Martin
 George Hall
(3 rows)
```

</details>

**3. List the departments that have no employees.**

<details>
<summary>Show solution</summary>

```sql
SELECT d.dept_name
FROM departments d
WHERE NOT EXISTS (SELECT 1 FROM employees e WHERE e.dept_id = d.dept_id);
```

```text output
 dept_name
-----------
 Legal
(1 row)
```

</details>

**4. Show each employee with the difference between their salary and their department's highest salary.**

<details>
<summary>Show solution</summary>

```sql
SELECT e.first_name,
       e.salary,
       (SELECT MAX(m.salary) FROM employees m WHERE m.dept_id = e.dept_id) - e.salary AS below_top
FROM employees e
WHERE e.dept_id = 30
ORDER BY e.emp_id;
```

```text output
 first_name | salary | below_top
------------+--------+-----------
 Priya      | 120000 |         0
 Arjun      | 105000 |     15000
 Emma       |  82000 |     38000
 Yusuf      |  82000 |     38000
(4 rows)
```

</details>

**5. Find the most expensive product in each category. Keep ties.**

<details>
<summary>Show solution</summary>

```sql
SELECT p.category_id, p.product_name, p.price
FROM products p
WHERE p.price = (SELECT MAX(x.price)
                 FROM products x
                 WHERE x.category_id = p.category_id)
ORDER BY p.category_id;
```

```text output
 category_id |  product_name   |  price
-------------+-----------------+---------
           2 | Phone X         |  799.00
           3 | Laptop Pro      | 1499.00
           4 | Desk Lamp       |   35.00
           5 | Coffee Maker    |   89.50
           6 | Database Design |   45.00
           7 | Phone Case      |   19.99
(6 rows)
```

</details>

**6. Find customers whose total spending on all their orders is above the average total spending per customer.**

<details>
<summary>Show solution</summary>

```sql
SELECT t.customer_id, t.total_spent
FROM (SELECT o.customer_id, SUM(i.quantity * i.unit_price) AS total_spent
      FROM orders o
      JOIN order_items i ON i.order_id = o.order_id
      GROUP BY o.customer_id) t
WHERE t.total_spent > (SELECT AVG(x.total_spent)
                       FROM (SELECT o.customer_id, SUM(i.quantity * i.unit_price) AS total_spent
                             FROM orders o
                             JOIN order_items i ON i.order_id = o.order_id
                             GROUP BY o.customer_id) x)
ORDER BY t.customer_id;
```

```text output
 customer_id | total_spent
-------------+-------------
           3 |     1985.00
           6 |     2337.50
(2 rows)
```

The same inner query appears twice. A `WITH` clause removes that repetition ([Chapter 14](../part-3-advanced-sql/14-cte-and-recursive-queries.md)).

</details>

## Recap

- A scalar subquery gives one value. Zero rows gives NULL, and two rows is an error.
- A correlated subquery refers to the outer row, and conceptually it runs once per row.
- `EXISTS` tests existence and never gives UNKNOWN.
- `NOT IN` returns no rows if the subquery has a NULL. Use `NOT EXISTS`.
- `IN` and `EXISTS` do not multiply rows, and a `JOIN` can.
- A "for all" question is a double `NOT EXISTS`, or a count compared with the total.
- Qualify every column in a subquery, or a missing column binds to the outer table.
- On modern optimizers, `IN` vs `EXISTS` is about meaning, not speed.

**Next:** [Chapter 14: CTEs and recursive queries](../part-3-advanced-sql/14-cte-and-recursive-queries.md)
