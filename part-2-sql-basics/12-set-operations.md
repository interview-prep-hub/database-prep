# 12. Set Operations

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 11](11-joins.md)

> **In one line:** A set operator stacks the results of two queries, while a join puts tables side by side.

## What you will learn

- `UNION`, `UNION ALL`, `INTERSECT` and `EXCEPT` (`MINUS` on Oracle)
- Why `UNION ALL` is faster, and when to use it
- The rules for the columns
- How to compare two tables, and how to build a `FULL JOIN` on MySQL

## Join vs set operator

```text
JOIN adds columns, by matching rows      UNION adds rows, by stacking results

A      B        A | B                    A          A
1      1   ->   1 | 1                    1          1
2      3        (matching rows)          2          2
                                         +          3
                                         B          (stacked)
                                         3
```

## UNION and UNION ALL

`UNION ALL` stacks two results and keeps everything. `UNION` stacks them and removes duplicates across the whole result.

```sql
SELECT city FROM customers
UNION
SELECT location FROM departments
ORDER BY city;
```

```text output
   city
-----------
 Dubai
 London
 New York
 Paris
 Singapore
 Tokyo
 Toronto
 NULL
(8 rows)
```

Compare the row counts:

```sql
SELECT COUNT(*) AS with_union_all
FROM (SELECT city FROM customers
      UNION ALL
      SELECT location FROM departments) t;
```

```text output
 with_union_all
----------------
             13
(1 row)
```

```sql
SELECT COUNT(*) AS with_union
FROM (SELECT city FROM customers
      UNION
      SELECT location FROM departments) t;
```

```text output
 with_union
------------
          8
(1 row)
```

**Which is faster?** `UNION ALL`, because `UNION` has an extra sort or hash step to remove duplicates. Use `UNION ALL` when duplicates are impossible or wanted, and `UNION` only when you need them gone. `UNION` does not promise sorted output, even though it may look sorted.

## The rules

1. Both queries need the same number of columns.
2. The types must be compatible, position by position.
3. Columns match by **position**, not by name.
4. Result column names come from the first `SELECT`.

```sql error=number
SELECT first_name, last_name FROM employees
UNION
SELECT customer_name FROM customers;
```

```text output
ERROR:  each UNION query must have the same number of columns
LINE 3: SELECT customer_name FROM customers;
               ^
```

Oracle gives `ORA-01789`. A type mismatch gives `ORA-01790`:

```sql error=matched
SELECT first_name FROM employees
UNION
SELECT customer_id FROM customers;
```

```text output
ERROR:  UNION types character varying and integer cannot be matched
LINE 3: SELECT customer_id FROM customers;
               ^
```

### One ORDER BY, at the very end

`ORDER BY` applies to the whole result, and it must use a result column name or position. PostgreSQL does not allow an expression there:

```sql error=ORDER
SELECT city FROM customers
UNION
SELECT location FROM departments
ORDER BY UPPER(city);
```

```text output
ERROR:  invalid UNION/INTERSECT/EXCEPT ORDER BY clause
LINE 4: ORDER BY UPPER(city);
                 ^
DETAIL:  Only result column names can be used, not expressions or functions.
HINT:  Add the expression/function to every SELECT, or move the UNION into a FROM clause.
```

Wrap the set operation in a derived table to sort by an expression:

```sql
SELECT t.city
FROM (SELECT city FROM customers
      UNION
      SELECT location FROM departments) t
WHERE t.city LIKE 'S%'
ORDER BY UPPER(t.city);
```

```text output
   city
-----------
 Singapore
(1 row)
```

## Set operators and NULL

Set operators treat NULLs as **equal**, so two NULLs count as duplicates. That is why the NULL city appeared once in the `UNION` above. This differs from `=`, where `NULL = NULL` is UNKNOWN.

## INTERSECT

`INTERSECT` returns rows found in both results, without duplicates.

```sql
SELECT city FROM customers
INTERSECT
SELECT location FROM departments
ORDER BY city;
```

```text output
  city
---------
 Dubai
 London
 Toronto
(3 rows)
```

## EXCEPT and MINUS

`EXCEPT` returns rows in the first result that are not in the second, without duplicates. Oracle's name for it is `MINUS`.

**Oracle:**

```sql oracle
SELECT city FROM customers
MINUS
SELECT location FROM departments
ORDER BY city;
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

Order matters: `A EXCEPT B` is not `B EXCEPT A`.

| Engine | Name |
|---|---|
| Oracle | `MINUS`, and `EXCEPT` as a synonym from 21c |
| PostgreSQL, SQL Server | `EXCEPT` |
| MySQL | `EXCEPT` from 8.0.31. It does not accept `MINUS` |

The `ALL` forms (`INTERSECT ALL`, `EXCEPT ALL`) keep duplicates. PostgreSQL has them, and Oracle from 21c.

## Precedence

`INTERSECT` binds tighter than `UNION` and `EXCEPT` on PostgreSQL, MySQL and SQL Server. Oracle gives all set operators equal precedence and reads left to right, and its manual warns this might change. So **always use parentheses** when you mix them.

## Useful patterns

### Tagging rows

Add a literal column to show which branch a row came from. Pad a missing column with NULL. With a tag, `UNION` rarely removes anything, so `UNION ALL` is usually right.

```sql
SELECT 'employee' AS source, first_name AS person, NULL AS city
FROM employees
WHERE emp_id = 1
UNION ALL
SELECT 'customer', customer_name, city
FROM customers
WHERE customer_id = 1
ORDER BY source;
```

```text output
  source  |    person    |  city
----------+--------------+--------
 customer | Alice Morgan | London
 employee | Sara         | NULL
(2 rows)
```

### Turning columns into rows

A friendship stored as (a, b) counts for both people. To count friends per person, stack both columns, then group. This is called unpivoting ([Chapter 17](../part-3-advanced-sql/17-advanced-grouping-and-pivot.md)).

```sql
CREATE TABLE friends (a INTEGER, b INTEGER);

INSERT INTO friends VALUES (1, 2);
INSERT INTO friends VALUES (1, 3);
INSERT INTO friends VALUES (2, 3);
INSERT INTO friends VALUES (4, 1);
```

```sql
SELECT t.person, COUNT(*) AS friend_count
FROM (SELECT a AS person FROM friends
      UNION ALL
      SELECT b FROM friends) t
GROUP BY t.person
ORDER BY friend_count DESC, t.person;
```

```text output
 person | friend_count
--------+--------------
      1 |            3
      2 |            2
      3 |            2
      4 |            1
(4 rows)
```

```sql
DROP TABLE friends;
```

### Comparing two tables

To list rows found in only one of two tables, take both differences and stack them. NULLs compare as equal, which a join on the same columns would miss.

**PostgreSQL:**

```sql postgres
(SELECT city FROM customers EXCEPT SELECT location FROM departments)
UNION ALL
(SELECT location FROM departments EXCEPT SELECT city FROM customers)
ORDER BY city;
```

```text output
   city
-----------
 New York
 Paris
 Singapore
 Tokyo
 NULL
(5 rows)
```

**Oracle:**

```sql oracle
(SELECT city FROM customers MINUS SELECT location FROM departments)
UNION ALL
(SELECT location FROM departments MINUS SELECT city FROM customers)
ORDER BY city;
```

### FULL OUTER JOIN on MySQL

MySQL has no `FULL JOIN`, so you build one. Many people write `LEFT JOIN UNION RIGHT JOIN`, but that has a trap: `UNION` also removes genuine duplicate rows. The safe form is:

```sql mysql
SELECT e.first_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
UNION ALL
SELECT e.first_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL;
```

The second part adds only the rows the first part missed.

### UNION ALL instead of OR

`WHERE a = 1 OR b = 2` across two differently indexed columns may use neither index well. Two branches joined by `UNION ALL` can each use their own index, though you must make sure a row does not match both.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use `UNION` by habit | Slower, and real duplicates are removed | Use `UNION ALL` unless you need them removed |
| Assume `UNION` sorts | The order is not guaranteed | Add `ORDER BY` |
| Match columns by name | They match by position | List columns in the same order |
| Put `ORDER BY` in a branch | An error | One `ORDER BY`, at the end |
| Forget `MINUS` on old Oracle | `EXCEPT` fails before 21c | Use `MINUS` |
| Mix set operators with no parentheses | Oracle and others read them differently | Add parentheses |
| Use `LEFT UNION RIGHT` for a full join | Real duplicates vanish | Use `UNION ALL` with the `IS NULL` filter |

## Interview questions

**Q1. What is the difference between UNION and UNION ALL, and which is faster?**

Both stack two results. `UNION ALL` keeps everything. `UNION` removes duplicates, which needs a sort or hash step. So `UNION ALL` is faster, and I use it unless I really need duplicates removed.

**Q2. What is the difference between JOIN and UNION?**

A join adds columns, by matching rows from two tables. `UNION` adds rows, by stacking two results with the same columns.

**Q3. What are the rules for the columns in a UNION?**

Both queries need the same number of columns, with compatible types by position. Columns match by position, not by name, and the result names come from the first `SELECT`. One `ORDER BY` goes at the end.

**Q4. What is the difference between MINUS and EXCEPT?**

They mean the same thing: rows in the first result that are not in the second. `MINUS` is Oracle's name, and `EXCEPT` is the standard name, which Oracle also accepts from 21c. Both remove duplicates.

**Q5. How do you find the rows that differ between two tables?**

`(A EXCEPT B) UNION ALL (B EXCEPT A)`. It lists rows found in only one table, and it treats NULLs as equal, which a join would not.

**Q6. How do you emulate a FULL OUTER JOIN on MySQL?**

A left join, `UNION ALL`, then a right join with `WHERE left_key IS NULL`, so that matched rows are not repeated. Using plain `UNION` looks simpler, but it also removes genuine duplicate rows.

## Practice

**1. List all the distinct countries of customers and the distinct locations of departments, in one column, sorted.**

<details>
<summary>Show solution</summary>

```sql
SELECT country AS place FROM customers WHERE country IS NOT NULL
UNION
SELECT location FROM departments
ORDER BY place;
```

```text output
   place
-----------
 Canada
 Dubai
 France
 Japan
 London
 New York
 Singapore
 Toronto
 UAE
 UK
(10 rows)
```

</details>

**2. Find customers who have a DELIVERED order and also a PENDING order.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_id FROM orders WHERE status = 'DELIVERED'
INTERSECT
SELECT customer_id FROM orders WHERE status = 'PENDING'
ORDER BY customer_id;
```

```text output
 customer_id
-------------
           1
           3
           6
(3 rows)
```

</details>

**3. Find products that were never ordered, using a set operator. Write it for PostgreSQL and for Oracle.**

<details>
<summary>Show solution</summary>

**PostgreSQL:**

```sql postgres
SELECT product_id FROM products
EXCEPT
SELECT product_id FROM order_items
ORDER BY product_id;
```

```text output
 product_id
------------
         10
(1 row)
```

**Oracle:**

```sql oracle
SELECT product_id FROM products
MINUS
SELECT product_id FROM order_items
ORDER BY product_id;
```

</details>

**4. Make one list of all the money events: payments as positive amounts and cancelled orders as a zero line, with a tag column.**

<details>
<summary>Show solution</summary>

```sql
SELECT 'payment' AS source, order_id, amount FROM payments WHERE order_id <= 1002
UNION ALL
SELECT 'cancelled', order_id, 0 FROM orders WHERE status = 'CANCELLED'
ORDER BY order_id;
```

```text output
  source   | order_id | amount
-----------+----------+--------
 payment   |     1001 | 838.98
 payment   |     1002 |  74.00
 cancelled |     1006 |      0
(3 rows)
```

</details>

## Recap

- A join adds columns. A set operator adds rows.
- `UNION ALL` keeps everything. `UNION` removes duplicates, and is slower.
- Columns match by position, and names come from the first `SELECT`.
- One `ORDER BY`, at the very end.
- Set operators treat NULLs as equal.
- `EXCEPT` is `MINUS` on Oracle before 21c.
- Use parentheses when you mix set operators.

**Next:** [Chapter 13: Subqueries](13-subqueries.md)
