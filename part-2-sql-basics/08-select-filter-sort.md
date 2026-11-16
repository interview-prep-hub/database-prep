# 8. SELECT: Filtering, Sorting and How a Query Runs

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 7](07-dml-insert-update-delete.md)

> **In one line:** `SELECT` asks the database a question, and the answer is a new table of rows.

## What you will learn

- How to choose columns, filter rows and sort the result
- Why `= NULL` never works, and how NULLs quietly vanish from filters
- The logical order in which a query's clauses take effect
- How to return only the top N rows on each database
- Why `WHERE ROWNUM = 2` returns nothing on Oracle

## SELECT and FROM

`SELECT` says which columns you want. `FROM` says which table they come from.

```sql
SELECT first_name, job_title, salary
FROM employees
WHERE emp_id <= 3
ORDER BY emp_id;
```

```text output
 first_name |      job_title      | salary
------------+---------------------+--------
 Sara       | CEO                 | 180000
 James      | Sales Manager       |  95000
 Priya      | Engineering Manager | 120000
(3 rows)
```

A query only reads. It returns a result and changes nothing. You can list columns in any order. `SELECT *` returns every column, which is fine while exploring.

### Expressions and aliases

A column in `SELECT` can be a calculation. Normal math rules apply: `*` and `/` before `+` and `-`, and parentheses change the order.

```sql
SELECT first_name,
       salary,
       salary * 12 AS annual_pay,
       (salary + 500) * 12 AS annual_with_raise
FROM employees
WHERE emp_id <= 2
ORDER BY emp_id;
```

```text output
 first_name | salary | annual_pay | annual_with_raise
------------+--------+------------+-------------------
 Sara       | 180000 |    2160000 |           2166000
 James      |  95000 |    1140000 |           1146000
(2 rows)
```

`AS annual_pay` is a **column alias**, a name for that column in this result only. `AS` is optional for column aliases. Always alias a calculation, because each database invents a different name for it otherwise.

An alias changes one query's output. It does not touch the table. Double quotes keep spaces and upper or lower case:

```sql
SELECT first_name, salary AS "Monthly Pay"
FROM employees
WHERE emp_id = 1;
```

```text output
 first_name | Monthly Pay
------------+-------------
 Sara       |      180000
(1 row)
```

A **table alias** is a short name for a table: `FROM employees e`. On Oracle, leave out `AS` before a table alias, or you get `ORA-00933`.

### SELECT with no table

Sometimes you just want to try an expression. Oracle before 23ai needs a `FROM`, so it provides `dual`, a tiny table with one row and one column.

**Oracle:**

```sql oracle
SELECT 2 + 3 AS result FROM dual;
```

**PostgreSQL:**

```sql postgres
SELECT 2 + 3 AS result;
```

```text output
 result
--------
      5
(1 row)
```

From 23ai, `FROM` is optional on Oracle too. MySQL and SQL Server also need no `FROM`.

### Is SELECT * bad?

It is not slow by itself. Saying "`SELECT *` is always slow" is a common wrong answer. The real reasons to avoid it in application code are these:

- An index can no longer answer the query alone ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)).
- Large text or binary columns get read even if nobody needs them.
- Unused data crosses the network.
- Code breaks or changes meaning when someone adds a column.

On Oracle before 26ai, a bare `*` cannot sit beside other columns:

```sql oracle error=ORA-00923
SELECT *, 1 AS one FROM employees;
```

Use a table alias instead:

```sql oracle
SELECT e.*, 1 AS one FROM employees e;
```

## DISTINCT removes duplicates

A plain `SELECT` keeps duplicate rows. `DISTINCT` removes them.

```sql
SELECT DISTINCT dept_id
FROM employees
ORDER BY dept_id;
```

```text output
 dept_id
---------
      10
      20
      30
      40
    NULL
(5 rows)
```

Two things to notice. All NULLs count as one value, so NULL appears once. And `DISTINCT` applies to the **whole row**, not just the first column:

```sql
SELECT DISTINCT dept_id, job_title
FROM employees
WHERE dept_id = 20
ORDER BY job_title;
```

```text output
 dept_id |   job_title
---------+---------------
      20 | Sales Manager
      20 | Sales Rep
(2 rows)
```

## WHERE keeps the rows that pass a test

The comparison operators are `=`, `<>` (or `!=`), `<`, `<=`, `>` and `>=`.

Three rules about values:

- Text goes in **single** quotes: `'Sales'`. Double quotes mean a name, such as a column. So `"Sales"` makes the database look for a column called Sales.
- A quote inside text is doubled: `'O''Brien'`.
- Dates are written `DATE '2024-01-05'`, which works on Oracle and PostgreSQL.

```sql
SELECT first_name, hire_date
FROM employees
WHERE hire_date >= DATE '2022-01-01'
ORDER BY hire_date;
```

```text output
 first_name | hire_date
------------+------------
 Mei        | 2022-01-17
 Tom        | 2023-07-01
(2 rows)
```

Text comparison is case-sensitive on Oracle and PostgreSQL, so `'sales'` does not match `'Sales'`. On MySQL and SQL Server it usually is not, because of their default settings.

### AND, OR, NOT and parentheses

The order is `NOT`, then `AND`, then `OR`. Mixing them without parentheses is a classic bug.

Say you want staff from Sales or Engineering who earn over 90000. This looks right, but it is wrong:

```sql
SELECT first_name, dept_id, salary
FROM employees
WHERE dept_id = 20 OR dept_id = 30 AND salary > 90000
ORDER BY emp_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 James      |      20 |  95000
 Priya      |      30 | 120000
 Lena       |      20 |  60000
 Diego      |      20 |  60000
 Mei        |      20 |  52000
 Arjun      |      30 | 105000
(6 rows)
```

`AND` ran first, so the database read it as "dept 20, or (dept 30 and salary over 90000)". Everyone in dept 20 got through. Parentheses fix it:

```sql
SELECT first_name, dept_id, salary
FROM employees
WHERE (dept_id = 20 OR dept_id = 30) AND salary > 90000
ORDER BY emp_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 James      |      20 |  95000
 Priya      |      30 | 120000
 Arjun      |      30 | 105000
(3 rows)
```

### IN and BETWEEN

`IN` is a short way to write several `=` tests joined by `OR`.

```sql
SELECT dept_name
FROM departments
WHERE location IN ('London', 'Dubai')
ORDER BY dept_name;
```

```text output
 dept_name
-----------
 Finance
 Sales
(2 rows)
```

`BETWEEN` includes both ends, and the low value must come first. `BETWEEN 3 AND 1` returns nothing.

```sql
SELECT first_name, salary
FROM employees
WHERE salary BETWEEN 82000 AND 95000
ORDER BY salary, emp_id;
```

```text output
 first_name | salary
------------+--------
 Emma       |  82000
 Yusuf      |  82000
 James      |  95000
 Omar       |  95000
(4 rows)
```

### Date ranges: avoid BETWEEN

Every Oracle `DATE` holds a time, and timestamps do on every engine. So `BETWEEN DATE '2024-02-01' AND DATE '2024-02-29'` stops at midnight at the start of the 29th, and it misses the rest of that day. Two neighboring `BETWEEN` ranges also count the boundary twice.

The safe pattern is: greater than or equal to the start, and less than the next start.

```sql
SELECT order_id, order_date
FROM orders
WHERE order_date >= DATE '2024-02-01'
  AND order_date <  DATE '2024-03-01'
ORDER BY order_date;
```

```text output
 order_id | order_date
----------+------------
     1004 | 2024-02-02
     1005 | 2024-02-14
     1006 | 2024-02-28
(3 rows)
```

### LIKE: pattern matching

`%` means any run of characters, including none. `_` means exactly one character.

| Pattern | Matches |
|---|---|
| `'S%'` | Starts with S |
| `'%an'` | Ends with an |
| `'%ar%'` | Contains ar |
| `'____a'` | Exactly five characters, ending in a |

```sql
SELECT first_name, last_name
FROM employees
WHERE last_name LIKE '%an'
   OR first_name LIKE '____a'
ORDER BY emp_id;
```

```text output
 first_name | last_name
------------+-----------
 Sara       | Khan
 Priya      | Sharma
(2 rows)
```

To search for a real `%` or `_`, say which character escapes it. `_` on its own matches anything, so this first query counts every customer who has an email:

```sql
SELECT COUNT(*) AS matched
FROM customers
WHERE email LIKE '%_%';
```

```text output
 matched
---------
       7
(1 row)
```

```sql
SELECT COUNT(*) AS matched
FROM customers
WHERE email LIKE '%\_%' ESCAPE '\';
```

```text output
 matched
---------
       0
(1 row)
```

`LIKE` is case-sensitive on Oracle and PostgreSQL. PostgreSQL has `ILIKE` to ignore case. On Oracle, compare `UPPER(col)` instead ([Chapter 9](09-built-in-functions.md)). A pattern that starts with `%` cannot use a normal index, so it is slow on big tables.

When `LIKE` is not enough, use regular expressions: `REGEXP_LIKE(email, pattern)` on Oracle and MySQL, or `email ~ pattern` on PostgreSQL. [Chapter 20](../part-3-advanced-sql/20-modern-sql.md) covers them.

## NULL in filters

NULL means unknown or missing. [Chapter 5](../part-1-foundations/05-data-types-and-null.md) explains it fully. For filters, you need three facts.

**1. Any comparison with NULL gives UNKNOWN, not TRUE or FALSE.** So `col = NULL` and `col <> NULL` never match anything. Use `IS NULL` and `IS NOT NULL`.

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE commission = NULL;
```

```text output
 matched
---------
       0
(1 row)
```

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE commission IS NULL;
```

```text output
 matched
---------
       8
(1 row)
```

**2. `WHERE` keeps only rows where the test is TRUE.** UNKNOWN is thrown away.

| Expression | Result |
|---|---|
| `TRUE AND UNKNOWN` | UNKNOWN |
| `FALSE AND UNKNOWN` | FALSE |
| `TRUE OR UNKNOWN` | TRUE |
| `FALSE OR UNKNOWN` | UNKNOWN |
| `NOT UNKNOWN` | UNKNOWN |

A `CHECK` constraint is the opposite: it rejects only FALSE. So UNKNOWN fails a `WHERE` but passes a `CHECK`.

**3. So `<>` silently drops NULL rows.** You might expect this to return everyone not in department 30. It returns 7 people, and there are 8:

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE dept_id <> 30;
```

```text output
 matched
---------
       7
(1 row)
```

Tom Baker has a NULL `dept_id`, so `NULL <> 30` is UNKNOWN and Tom is lost. If Tom should be included, say so:

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE dept_id <> 30 OR dept_id IS NULL;
```

```text output
 matched
---------
       8
(1 row)
```

### NULL inside IN and NOT IN

`IN` still works with a NULL in the list. `NOT IN` does not.

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE dept_id IN (30, NULL);
```

```text output
 matched
---------
       4
(1 row)
```

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE dept_id NOT IN (30, NULL);
```

```text output
 matched
---------
       0
(1 row)
```

`x NOT IN (30, NULL)` expands to `x <> 30 AND x <> NULL`. The second half is never TRUE, so the whole test is never TRUE. [Chapter 13](13-subqueries.md) shows this same trap with a subquery, where it is much easier to fall into.

## ORDER BY sorts the result

`ASC` (the default) sorts low to high, and `DESC` reverses it. Each column has its own direction, and you can sort by a column you did not select.

```sql
SELECT first_name, dept_id, salary
FROM employees
WHERE dept_id IN (20, 30)
ORDER BY dept_id ASC, salary DESC, emp_id;
```

```text output
 first_name | dept_id | salary
------------+---------+--------
 James      |      20 |  95000
 Lena       |      20 |  60000
 Diego      |      20 |  60000
 Mei        |      20 |  52000
 Priya      |      30 | 120000
 Arjun      |      30 | 105000
 Emma       |      30 |  82000
 Yusuf      |      30 |  82000
(8 rows)
```

You can also sort by an alias, or by position:

```sql
SELECT first_name, salary * 12 AS annual_pay
FROM employees
WHERE dept_id = 40
ORDER BY annual_pay DESC;
```

`ORDER BY 2` means "sort by the second column". It works, but avoid it, because it breaks silently when someone changes the `SELECT` list.

With `SELECT DISTINCT`, every sort column must be in the `SELECT` list. Oracle gives `ORA-01791`. PostgreSQL says:

```sql error=DISTINCT
SELECT DISTINCT job_title
FROM employees
ORDER BY salary;
```

```text output
ERROR:  for SELECT DISTINCT, ORDER BY expressions must appear in select list
LINE 3: ORDER BY salary;
                 ^
```

### Row order is only guaranteed by ORDER BY

Without a final `ORDER BY`, rows can come back in any order. It may look stable for months, then change after a new index, new statistics or a version upgrade. These do not guarantee order:

- A primary key or clustered index
- `GROUP BY`
- An `ORDER BY` inside a view or subquery

When rows tie on the sort, their order is undefined. Add a unique tie-breaker, such as `emp_id`, whenever the order matters.

### Where NULLs sort

Oracle and PostgreSQL treat NULL as the largest value. So NULLs come last in `ASC`, and **first** in `DESC`.

```sql
SELECT first_name, commission
FROM employees
WHERE dept_id = 20 OR emp_id = 1
ORDER BY commission DESC, emp_id;
```

```text output
 first_name | commission
------------+------------
 Sara       |       NULL
 Lena       |       8000
 Diego      |       6500
 James      |       5000
 Mei        |          0
(5 rows)
```

Sara's NULL is at the top of a "highest commission" list, which is rarely what you want. Oracle and PostgreSQL both let you say where NULLs go:

```sql
SELECT first_name, commission
FROM employees
WHERE dept_id = 20 OR emp_id = 1
ORDER BY commission DESC NULLS LAST, emp_id;
```

```text output
 first_name | commission
------------+------------
 Lena       |       8000
 Diego      |       6500
 James      |       5000
 Mei        |          0
 Sara       |       NULL
(5 rows)
```

MySQL and SQL Server do the opposite: they treat NULL as the smallest value. They have no `NULLS LAST`, so you sort on a `CASE` expression first.

## The logical order of a query

This is one of the most asked questions in all of SQL. You write a query in one order, but its clauses take effect in another.

```text
You write:                 It takes effect:

SELECT                     1. FROM and joins      Which rows exist?
FROM                       2. WHERE               Keep some rows
WHERE                      3. GROUP BY            Form groups (Chapter 10)
GROUP BY                   4. HAVING              Keep some groups (Chapter 10)
HAVING                     5. Window functions    (Chapter 15)
ORDER BY                   6. SELECT              Compute columns and aliases
FETCH FIRST                7. DISTINCT            Remove duplicates
                           8. Set operators       UNION and so on (Chapter 12)
                           9. ORDER BY            Sort
                          10. FETCH or LIMIT      Keep the first N
```

This is the **logical** order: it describes what the result must look like. The optimizer may do the real work in a different order, as long as the result is the same ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)). Say this in an interview. It shows you understand the difference.

This order explains many errors. A `SELECT` alias does not exist yet when `WHERE` runs:

```sql error=annual_pay
SELECT first_name, salary * 12 AS annual_pay
FROM employees
WHERE annual_pay > 1000000;
```

```text output
ERROR:  column "annual_pay" does not exist
LINE 3: WHERE annual_pay > 1000000;
              ^
```

Oracle gives `ORA-00904: invalid identifier` here. `ORDER BY` runs after `SELECT`, so the alias works there. To filter on it, repeat the expression:

```sql
SELECT first_name, salary * 12 AS annual_pay
FROM employees
WHERE salary * 12 > 1000000
ORDER BY first_name;
```

```text output
 first_name | annual_pay
------------+------------
 Arjun      |    1260000
 James      |    1140000
 Omar       |    1140000
 Priya      |    1440000
 Sara       |    2160000
(5 rows)
```

Engines differ in small ways, and it is worth re-reading this after [Chapter 10](10-aggregation-group-by-having.md). An alias in `GROUP BY` works on PostgreSQL and MySQL, and on Oracle only from 23ai. An alias in `HAVING` works on MySQL, and on Oracle from 23ai. An `ORDER BY` alias must stand alone on PostgreSQL and SQL Server, so `ORDER BY total + 1` fails there.

## Returning only some rows

Always pair a limit with `ORDER BY`. Without it, "the first 3 rows" means nothing.

**Standard SQL** works on PostgreSQL, and on Oracle from 12c:

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

To skip rows, which is how pages work:

```sql since=12c
SELECT first_name, salary
FROM employees
ORDER BY salary DESC, emp_id
OFFSET 3 ROWS FETCH NEXT 3 ROWS ONLY;
```

```text output
 first_name | salary
------------+--------
 James      |  95000
 Omar       |  95000
 Emma       |  82000
(3 rows)
```

**Other forms:**

```sql postgres
SELECT first_name FROM employees ORDER BY salary DESC, emp_id LIMIT 3 OFFSET 3;
```

```sql mysql
SELECT first_name FROM employees ORDER BY salary DESC, emp_id LIMIT 3, 3;  -- skip 3, take 3
```

```sql sqlserver
SELECT TOP 3 first_name FROM employees ORDER BY salary DESC, emp_id;
```

Deep pages get slow, because `OFFSET` still reads every row it skips. [Chapter 31](../part-5-internals-and-performance/31-query-tuning-playbook.md) shows keyset pagination, which avoids this.

### Ties in a top-N query

James and Omar both earn 95000. Without a tie-breaker, a top-4 list must pick one of them, and the pick can change between runs. `WITH TIES` keeps both:

```sql since=12c
SELECT first_name, salary
FROM employees
ORDER BY salary DESC
FETCH FIRST 4 ROWS WITH TIES;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
 Omar       |  95000
 James      |  95000
(5 rows)
```

That is 5 rows from a "top 4". It works on Oracle from 12c and PostgreSQL from 13. SQL Server has `TOP n WITH TIES`, and MySQL has no such feature. Oracle also has `FETCH FIRST 10 PERCENT ROWS ONLY`, which PostgreSQL does not.

## ROWNUM on Oracle

Your Oracle XE is 11g, so `FETCH FIRST` is not available there. Oracle's older tool is `ROWNUM`, and interviewers love it because it surprises people.

`ROWNUM` gives each row a number **as it passes the `WHERE` clause**, starting at 1.

```sql oracle
SELECT first_name FROM employees WHERE ROWNUM <= 3;
```

This returns 3 rows, but they are not any particular 3.

**Why does `WHERE ROWNUM = 2` return nothing?** The first row gets number 1. It fails the test `1 = 2`, so it is rejected. The next row also gets number 1, because no row has passed yet, and it fails too. No row ever reaches 2. `ROWNUM > 1` fails for the same reason.

```sql oracle
SELECT first_name FROM employees WHERE ROWNUM = 2;
```

```text output
no rows selected
```

**The ORDER BY trap.** `ROWNUM` is given out before `ORDER BY` runs, so this query picks 5 arbitrary rows, then sorts them. It is **not** the top 5 earners.

```sql oracle
SELECT first_name, salary
FROM employees
WHERE ROWNUM <= 5
ORDER BY salary DESC;
```

**The recipe for 11g:** sort in a query inside `FROM`, then apply `ROWNUM` outside it. The inner query acts as a temporary table. [Chapter 13](13-subqueries.md) explains these inline views properly.

```sql oracle
SELECT first_name, salary
FROM (SELECT first_name, salary
      FROM employees
      ORDER BY salary DESC, emp_id)
WHERE ROWNUM <= 3;
```

```text output
FIRST_NAME SALARY
---------- ------
Sara       180000
Priya      120000
Arjun      105000
```

### ROWID vs ROWNUM vs ROW_NUMBER()

| | What it is | Lifetime |
|---|---|---|
| `ROWID` | The row's physical address on Oracle. PostgreSQL's nearest is `ctid` | Stays with the row, though it can change if the row moves |
| `ROWNUM` | A temporary number for one result, given out before sorting | One query |
| `ROW_NUMBER()` | A window function that numbers rows after sorting ([Chapter 15](../part-3-advanced-sql/15-window-functions-ranking-and-offset.md)) | One query |

## Substitution variables in SQL*Plus

You will see `&name` in Oracle scripts. SQL*Plus prompts for a value and pastes the text into your SQL before sending it.

```sql oracle
SELECT first_name FROM employees WHERE dept_id = &dept;
```

`&name` prompts each time, and `&&name` remembers the value. These are plain text replacement by the client, not server bind variables. `SET DEFINE OFF` stops text like `'AT&T'` from prompting you.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Write `col = NULL` or `col <> NULL` | It never matches | Use `IS NULL` or `IS NOT NULL` |
| Forget that `<>` and `NOT IN` drop NULLs | Rows vanish with no warning | Add `OR col IS NULL` when they should stay |
| Mix `AND` and `OR` with no parentheses | `AND` runs first, so too many rows match | Add parentheses |
| Think `DISTINCT` applies to one column | `DISTINCT(a), b` looks that way, but it covers the whole row | Remember it means the whole row |
| Use `BETWEEN` with a plain end date on a column with times | Everything after midnight that day is lost | Use `>= start AND < next_start` |
| Use a `SELECT` alias in `WHERE` | The alias does not exist yet | Repeat the expression, or use a subquery |
| Rely on the order rows happen to come back in | It can change at any time | Add a final `ORDER BY` |
| Sort a top-N query with no tie-breaker | Different runs give different rows | Add a unique column to the sort |
| Combine `ROWNUM <= 5` with `ORDER BY` at one level | Five arbitrary rows get sorted | Sort in an inner query first |
| Use `ROWNUM = 2` or `ROWNUM > 1` | No rows come back | Number the rows in an inner query |
| Use double quotes for text | The database looks for a column | Use single quotes |
| Write `FROM employees AS e` or `LIMIT 5` on Oracle | Neither is valid there | No `AS`, and use `FETCH FIRST` or `ROWNUM` |
| Search for a literal `%` or `_` with no `ESCAPE` | The wildcard matches anything | Use `ESCAPE` |
| Say `SELECT *` is always slow | That is not the real reason | Give the real reasons above |
| Recite the logical order as the actual plan | The optimizer may work differently | Call it the logical order |

## Interview questions

**Q1. What is the order of execution of a SQL query?**

Logically: `FROM` and joins, `WHERE`, `GROUP BY`, `HAVING`, window functions, `SELECT`, `DISTINCT`, set operators, `ORDER BY`, and finally `LIMIT` or `FETCH`. This is the logical order, which defines the result. The optimizer can actually run things in a different order as long as the result is the same.

**Q2. Why does `WHERE column = NULL` never match anything?**

NULL means unknown, so comparing anything to it gives UNKNOWN, not TRUE. `WHERE` keeps only rows where the test is TRUE. To test for NULL, use `IS NULL`.

**Q3. Why can you use a column alias in ORDER BY but not in WHERE?**

`WHERE` takes effect before `SELECT`, so the alias does not exist yet. `ORDER BY` takes effect after `SELECT`, so it does.

**Q4. Does BETWEEN include both end values, and why is it risky on timestamps?**

Yes, both ends are included. On a column with a time part, `BETWEEN` with a plain date as the upper bound stops at midnight at the start of that day, so the rest of the day is lost. Neighboring ranges also count the boundary twice. I use `>= start AND < next_start` instead.

**Q5. Can you rely on row order without ORDER BY?**

No. Only a final `ORDER BY` guarantees order, and even then, ties are undefined unless you add a unique tie-breaker. An index, a `GROUP BY`, or an `ORDER BY` in a subquery does not guarantee it.

**Q6. How do you return only the first N rows on Oracle, PostgreSQL, MySQL and SQL Server?**

The standard form is `FETCH FIRST n ROWS ONLY`, which works on PostgreSQL, on Oracle from 12c, and on SQL Server as part of `OFFSET ... FETCH`. PostgreSQL and MySQL also have `LIMIT`. SQL Server has `TOP`. Oracle before 12c uses `ROWNUM` around a sorted inner query. In every case I pair it with `ORDER BY`.

**Q7. Why does `WHERE ROWNUM = 2` return no rows in Oracle, and how do you get the top 5 earners?**

`ROWNUM` is assigned as a row passes the filter, starting at 1. The first row gets 1 and fails `= 2`, so the next row also gets 1, and no row ever reaches 2. For the top 5 earners, I sort in an inline view and put `ROWNUM <= 5` outside it. From 12c, I use `FETCH FIRST 5 ROWS ONLY`.

**Q8. What is the difference between ROWNUM, ROWID and ROW_NUMBER()?**

`ROWID` is the physical address of a row. `ROWNUM` is a temporary number given to rows of a result, before sorting. `ROW_NUMBER()` is a window function that numbers rows after sorting, and it can restart for each group.

**Q9. Is SELECT * bad, and why?**

It is not slow in itself, but it is a poor choice in application code. It stops an index from answering the query alone, it reads large columns nobody needs, it sends unused data over the network, and code can break when columns are added. For exploring by hand it is fine.

## Practice

**1. List customers in Dubai, with their signup date, newest first.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_name, signup_date
FROM customers
WHERE city = 'Dubai'
ORDER BY signup_date DESC;
```

```text output
 customer_name | signup_date
---------------+-------------
 Fatima Noor   | 2023-05-30
 Bilal Ahmed   | 2023-02-03
(2 rows)
```

</details>

**2. List products priced from 40 to 100, cheapest first.**

<details>
<summary>Show solution</summary>

```sql
SELECT product_name, price
FROM products
WHERE price BETWEEN 40 AND 100
ORDER BY price, product_id;
```

```text output
  product_name   | price
-----------------+-------
 Database Design | 45.00
 Blender         | 49.00
 Coffee Maker    | 89.50
(3 rows)
```

</details>

**3. Find customers whose city is not London. Include customers with no city.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_name, city
FROM customers
WHERE city <> 'London' OR city IS NULL
ORDER BY customer_id;
```

```text output
 customer_name |  city
---------------+---------
 Bilal Ahmed   | Dubai
 Chloe Martin  | Paris
 David Lee     | Toronto
 Fatima Noor   | Dubai
 Hana Sato     | Tokyo
 Ivan Novak    | NULL
(6 rows)
```

Without `OR city IS NULL`, Ivan Novak disappears.

</details>

**4. List the different job titles of employees hired from 2020 on, sorted by title.**

<details>
<summary>Show solution</summary>

```sql
SELECT DISTINCT job_title
FROM employees
WHERE hire_date >= DATE '2020-01-01'
ORDER BY job_title;
```

```text output
 job_title
------------
 Accountant
 Developer
 Intern
 Sales Rep
(4 rows)
```

</details>

**5. Show the three most expensive products that are in stock. Write it for Oracle 12c or later, and for your Oracle 11g.**

<details>
<summary>Show solution</summary>

**Oracle 12c and later, and PostgreSQL:**

```sql since=12c
SELECT product_name, price
FROM products
WHERE stock_qty > 0
ORDER BY price DESC, product_id
FETCH FIRST 3 ROWS ONLY;
```

```text output
 product_name |  price
--------------+---------
 Laptop Pro   | 1499.00
 Laptop Air   |  999.00
 Phone X      |  799.00
(3 rows)
```

**Oracle 11g:**

```sql oracle
SELECT product_name, price
FROM (SELECT product_name, price
      FROM products
      WHERE stock_qty > 0
      ORDER BY price DESC, product_id)
WHERE ROWNUM <= 3;
```

</details>

**6. Show the second page of employees, with 4 employees per page, sorted by `emp_id`.**

<details>
<summary>Show solution</summary>

```sql since=12c
SELECT emp_id, first_name
FROM employees
ORDER BY emp_id
OFFSET 4 ROWS FETCH NEXT 4 ROWS ONLY;
```

```text output
 emp_id | first_name
--------+------------
      5 | Lena
      6 | Diego
      7 | Mei
      8 | Arjun
(4 rows)
```

</details>

## Recap

- `WHERE` runs before `SELECT`, so aliases work in `ORDER BY` but not in `WHERE`.
- The logical order is `FROM`, `WHERE`, `GROUP BY`, `HAVING`, `SELECT`, `ORDER BY`, then the limit.
- Use `IS NULL`, never `= NULL`. `<>` and `NOT IN` silently lose NULL rows.
- `AND` runs before `OR`. Use parentheses.
- For date ranges, use `>= start AND < next_start`.
- Only a final `ORDER BY` guarantees order. Add a tie-breaker.
- On Oracle 11g, top-N means `ROWNUM` outside a sorted inner query. From 12c, use `FETCH FIRST`.

**Next:** [Chapter 9: Built-in functions](09-built-in-functions.md)
