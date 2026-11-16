# 9. Built-in Functions: Text, Numbers, Dates, NULLs and CASE

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 8](08-select-filter-sort.md)

> **In one line:** A single-row function takes values from one row and returns one value, and every database has its own names for them.

## What you will learn

- The most used text, number and date functions on each engine
- Integer division, division by zero, and how to guard against them
- `NVL`, `NVL2` and `COALESCE`
- `CASE`, and how it compares with `DECODE`

A **single-row function** returns one value for each row. **Aggregates** such as `SUM` take many rows, and they come in [Chapter 10](10-aggregation-group-by-having.md). Functions can be nested, and they work in `SELECT`, `WHERE` and `ORDER BY`.

To try an expression on both Oracle and PostgreSQL, this chapter selects it from one row of `employees`, since `dual` exists only on Oracle.

## Text functions

### Case and length

```sql
SELECT UPPER(first_name) AS upper_name,
       LOWER(job_title) AS lower_title,
       INITCAP('hello world') AS title_case,
       LENGTH(first_name) AS name_length
FROM employees
WHERE emp_id = 1;
```

```text output
 upper_name | lower_title | title_case  | name_length
------------+-------------+-------------+-------------
 SARA       | ceo         | Hello World |           4
(1 row)
```

- `INITCAP` exists on Oracle and PostgreSQL. MySQL and SQL Server have no `INITCAP`.
- For a case-insensitive search, write `UPPER(city) = 'LONDON'`. A function around a column stops a normal index being used, so a function-based index may be needed ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)).
- `LENGTH` counts characters on Oracle and PostgreSQL. On MySQL it counts bytes, and `CHAR_LENGTH` counts characters. SQL Server's `LEN` ignores trailing spaces.

### Cutting and finding text

`SUBSTR(s, start, length)` counts from 1.

```sql
SELECT SUBSTR(email, 1, 4) AS first_four
FROM employees
WHERE emp_id = 1;
```

```text output
 first_four
------------
 sara
(1 row)
```

To find text inside text, the name differs by engine. All of them count from 1, and return 0 when nothing is found.

| Engine | Function |
|---|---|
| Oracle, MySQL | `INSTR(s, sub)` |
| PostgreSQL | `POSITION(sub IN s)` or `STRPOS(s, sub)` |
| SQL Server | `CHARINDEX(sub, s)` |

Combine them to take the part of an email before the `@`:

**Oracle:**

```sql oracle
SELECT SUBSTR(email, 1, INSTR(email, '@') - 1) AS user_part
FROM employees
WHERE emp_id = 1;
```

**PostgreSQL:**

```sql postgres
SELECT SUBSTR(email, 1, POSITION('@' IN email) - 1) AS user_part
FROM employees
WHERE emp_id = 1;
```

```text output
 user_part
-----------
 sara.khan
(1 row)
```

A negative start counts from the end on Oracle and MySQL, but not on PostgreSQL.

### Editing text

```sql
SELECT REPLACE('2024-01-05', '-', '/') AS replaced,
       TRANSLATE('abc', 'ab', 'xy') AS translated,
       TRIM('  hi  ') AS trimmed,
       LPAD('7', 3, '0') AS padded
FROM employees
WHERE emp_id = 1;
```

```text output
  replaced  | translated | trimmed | padded
------------+------------+---------+--------
 2024/01/05 | xyc        | hi      | 007
(1 row)
```

- `REPLACE` swaps a whole substring.
- `TRANSLATE` swaps character by character.
- `TRIM`, `LTRIM` and `RTRIM` remove spaces, or other characters you name.
- `LPAD` and `RPAD` fill to a given width.

**Counting a character:** `LENGTH(s) - LENGTH(REPLACE(s, 'a', ''))`. There is an Oracle trap here: if `REPLACE` leaves an empty string, that is NULL on Oracle ([Chapter 5](../part-1-foundations/05-data-types-and-null.md)), so wrap it in `NVL(LENGTH(...), 0)`.

### Joining text

`||` works on Oracle and PostgreSQL. SQL Server uses `+`. `CONCAT` exists on all four, but Oracle's takes exactly two arguments before 23ai. On MySQL, `||` means OR unless you change a setting.

```sql
SELECT first_name || ' ' || last_name AS full_name
FROM employees
WHERE emp_id = 2;
```

```text output
  full_name
--------------
 James Wilson
(1 row)
```

## Number functions

```sql
SELECT ROUND(-2.5) AS rounded,
       TRUNC(-2.5) AS truncated,
       FLOOR(-2.5) AS floored,
       CEIL(-2.5) AS ceiled,
       ROUND(1234.567, 2) AS two_places,
       MOD(7, 2) AS remainder
FROM employees
WHERE emp_id = 1;
```

```text output
 rounded | truncated | floored | ceiled | two_places | remainder
---------+-----------+---------+--------+------------+-----------
      -3 |        -2 |      -3 |     -2 |    1234.57 |         1
(1 row)
```

- `ROUND` goes to the nearest value.
- `TRUNC` cuts off the decimals, toward zero.
- `FLOOR` goes down, and `CEIL` goes up. SQL Server writes `CEILING`.
- `MOD(a, b)` is the remainder. Its sign follows `a` on Oracle and PostgreSQL: `MOD(-7, 2)` is -1. SQL Server has only the `%` operator.

### Integer division

**Why does `5 / 2` return 2 on PostgreSQL, and 2.5 on Oracle?** PostgreSQL and SQL Server divide two integers as integers, and drop the fraction. Oracle and MySQL return a fraction.

```sql postgres
SELECT 5 / 2 AS integer_division,
       5.0 / 2 AS decimal_division,
       ROUND(1.0 * 9 / 16, 4) AS safe_rate;
```

```text output
 integer_division |  decimal_division  | safe_rate
------------------+--------------------+-----------
                2 | 2.5000000000000000 |    0.5625
(1 row)
```

`COUNT(*)` is an integer too, so a rate such as 9 / 16 gives 0 on PostgreSQL. Fix it with `1.0 *` at the front, or with a `CAST` to `NUMERIC`.

### Division by zero

It is an error on Oracle (`ORA-01476`), PostgreSQL and SQL Server, and it gives NULL in a MySQL `SELECT`.

**How do you avoid a division-by-zero error?** `NULLIF(a, b)` returns NULL when a equals b, and otherwise returns a. So `x / NULLIF(y, 0)` gives NULL instead of an error.

```sql
SELECT salary / NULLIF(0, 0) AS safe_result
FROM employees
WHERE emp_id = 1;
```

```text output
 safe_result
-------------
        NULL
(1 row)
```

## Date functions

### Current date and time

| Engine | Date and time now |
|---|---|
| Standard | `CURRENT_DATE`, `CURRENT_TIMESTAMP` |
| Oracle | `SYSDATE`, `SYSTIMESTAMP` |
| PostgreSQL, MySQL | `NOW()` |
| SQL Server | `GETDATE()` |

Oracle's `CURRENT_DATE` includes a time, and PostgreSQL's does not. Oracle's `SYSDATE` uses the database server's clock, while `CURRENT_DATE` uses the session's time zone.

### The Oracle DATE trap

An Oracle `DATE` always holds a time. So `WHERE order_date = DATE '2024-01-05'` misses a row stored at 14:30. `TRUNC(order_date) = DATE '2024-01-05'` fixes the test, but a range is better, because it can still use an index:

```sql norun
WHERE order_date >= DATE '2024-01-05' AND order_date < DATE '2024-01-06'
```

### Text to date and back

`TO_DATE` and `TO_CHAR` use a format mask, on both Oracle and PostgreSQL.

```sql
SELECT TO_CHAR(hire_date, 'YYYY-MM-DD') AS iso,
       TO_CHAR(hire_date, 'DD Mon YYYY') AS readable,
       TO_CHAR(hire_date, 'FMMonth') AS month_name
FROM employees
WHERE emp_id = 1;
```

```text output
    iso     |  readable   | month_name
------------+-------------+------------
 2015-01-12 | 12 Jan 2015 | January
(1 row)
```

`MM` is the month and `MI` is the minute, so a time is `'YYYY-MM-DD HH24:MI:SS'`. `FM` removes the padding. MySQL uses `STR_TO_DATE` and `DATE_FORMAT`, and SQL Server uses `CONVERT` and `FORMAT`.

### Pulling out parts

```sql
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year,
       EXTRACT(MONTH FROM hire_date) AS hire_month
FROM employees
WHERE emp_id = 1;
```

```text output
 hire_year | hire_month
-----------+------------
      2015 |          1
(1 row)
```

SQL Server uses `DATEPART`, `YEAR()` and `MONTH()`.

### First and last day of a month

**Oracle:**

```sql oracle
SELECT TRUNC(DATE '2024-02-14', 'MM') AS first_day,
       LAST_DAY(DATE '2024-02-14') AS last_day
FROM dual;
```

**PostgreSQL:**

```sql postgres
SELECT DATE_TRUNC('month', DATE '2024-02-14')::DATE AS first_day,
       (DATE_TRUNC('month', DATE '2024-02-14') + INTERVAL '1 month - 1 day')::DATE AS last_day;
```

```text output
 first_day  |  last_day
------------+------------
 2024-02-01 | 2024-02-29
(1 row)
```

MySQL has `LAST_DAY` and `DATE_FORMAT(d, '%Y-%m-01')`, and SQL Server has `EOMONTH` and, from 2022, `DATETRUNC`.

### Date arithmetic

`date - date` gives days on Oracle and PostgreSQL, and `date + 7` adds days on both.

```sql
SELECT DATE '2024-03-01' - DATE '2024-02-01' AS days_apart,
       DATE '2024-01-31' + 7 AS one_week_later
FROM employees
WHERE emp_id = 1;
```

```text output
 days_apart | one_week_later
------------+----------------
         29 | 2024-02-07
(1 row)
```

For months, Oracle has `ADD_MONTHS` and `MONTHS_BETWEEN`. PostgreSQL uses `+ INTERVAL '1 month'` and `AGE`. Month ends differ:

```sql oracle
SELECT ADD_MONTHS(DATE '2024-02-29', 1) AS next_month FROM dual;
```

```text output
NEXT_MONTH
----------
2024-03-31
```

```sql postgres
SELECT (DATE '2024-02-29' + INTERVAL '1 month')::DATE AS next_month;
```

```text output
 next_month
------------
 2024-03-29
(1 row)
```

Oracle treats the last day of a month as "the last day", and PostgreSQL keeps the day number.

**`DATEDIFF` is a portability trap.** MySQL's `DATEDIFF(end, start)` returns days. SQL Server's `DATEDIFF(unit, start, end)` has the dates the other way round, and it counts boundaries crossed.

### Last-N-period filters

**How do you find the employees hired in the last 90 days?** Write a range on the raw column, not a function around it, so that an index can be used. With a fixed "today" of 2024-06-30:

```sql
SELECT order_id, order_date
FROM orders
WHERE order_date >= DATE '2024-06-30' - 30
ORDER BY order_date;
```

```text output
 order_id | order_date
----------+------------
     1014 | 2024-06-01
     1015 | 2024-06-11
     1016 | 2024-06-18
(3 rows)
```

In real code, use `SYSDATE - 90` on Oracle, or `CURRENT_DATE - 90` on PostgreSQL.

**A worked interview question: the top 5 earners with more than 3 years of service.** As of 2024-06-30, they were hired on or before 2021-06-30.

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
SELECT first_name, salary, hire_date
FROM employees
WHERE hire_date <= DATE '2021-06-30'
ORDER BY salary DESC, emp_id
FETCH FIRST 5 ROWS ONLY;
```

```text output
 first_name | salary | hire_date
------------+--------+------------
 Sara       | 180000 | 2015-01-12
 Priya      | 120000 | 2016-06-15
 Arjun      | 105000 | 2018-04-23
 James      |  95000 | 2016-03-01
 Omar       |  95000 | 2017-02-20
(5 rows)
```

On your Oracle 11g, use the `ROWNUM` recipe from [Chapter 8](08-select-filter-sort.md).

## Conversion functions

`CAST(x AS type)` is standard. Oracle and PostgreSQL also have `TO_CHAR`, `TO_NUMBER` and `TO_DATE`, and PostgreSQL has `x::type`.

```sql
SELECT CAST(salary AS VARCHAR(10)) AS as_text,
       CAST('2024-01-05' AS DATE) AS as_date
FROM employees
WHERE emp_id = 1;
```

```text output
 as_text |  as_date
---------+------------
 180000  | 2024-01-05
(1 row)
```

Explicit is better than implicit ([Chapter 5](../part-1-foundations/05-data-types-and-null.md)). On Oracle, `WHERE text_col = 123` converts the column to a number, and it fails on any non-numeric row.

For safe conversion, Oracle 12.2 has `TO_NUMBER(x DEFAULT 0 ON CONVERSION ERROR)`, and SQL Server has `TRY_CAST`.

## Handling NULL

**What does `salary + commission` return when commission is NULL?** NULL, because arithmetic with NULL gives NULL. That is true for 8 of the 12 employees here. Concatenation differs: Oracle's `||` ignores NULL, while PostgreSQL's `||` returns NULL.

| Function | Engine | Meaning |
|---|---|---|
| `COALESCE(a, b, c)` | Standard, all engines | The first non-NULL, with two or more arguments |
| `NVL(a, b)` | Oracle | `b` if `a` is NULL. Exactly two arguments |
| `NVL2(a, b, c)` | Oracle | `b` if `a` is not NULL, otherwise `c` |
| `IFNULL(a, b)` | MySQL | Like `NVL` |
| `ISNULL(a, b)` | SQL Server | Like `NVL` |
| `NULLIF(a, b)` | Standard | NULL if `a = b`, otherwise `a` |

```sql
SELECT first_name,
       salary + COALESCE(commission, 0) AS total_pay,
       COALESCE(commission, 0) AS commission_or_zero
FROM employees
WHERE emp_id IN (1, 2)
ORDER BY emp_id;
```

```text output
 first_name | total_pay | commission_or_zero
------------+-----------+--------------------
 Sara       |    180000 |                  0
 James      |    100000 |               5000
(2 rows)
```

**Oracle:**

```sql oracle
SELECT first_name,
       NVL(commission, 0) AS with_nvl,
       NVL2(commission, 'Has commission', 'No commission') AS with_nvl2
FROM employees
WHERE emp_id IN (1, 2)
ORDER BY emp_id;
```

```text output
FIRST_NAME   WITH_NVL WITH_NVL2
---------- ---------- --------------
Sara                0 No commission
James            5000 Has commission
```

**`NVL` vs `COALESCE`, the differences interviewers want:**

- `COALESCE` takes many arguments. `NVL` takes two.
- `COALESCE` stops at the first non-NULL. `NVL` always evaluates both arguments, so an expensive function in the second slot still runs.
- `COALESCE` is standard, so it works everywhere.
- `COALESCE` needs compatible types. `NVL` converts the second to the first's type.

### GREATEST and LEAST

These compare values across columns in one row. A NULL argument makes the result NULL on Oracle and MySQL. PostgreSQL ignores NULLs, which its documentation calls a deviation from the standard.

## CASE

`CASE` is standard SQL, and it is an expression, so it works anywhere a value does. It has two forms.

**Searched:** any condition.

```sql
SELECT first_name, salary,
       CASE WHEN salary >= 100000 THEN 'High'
            WHEN salary >= 60000 THEN 'Medium'
            ELSE 'Low'
       END AS band
FROM employees
WHERE dept_id = 20
ORDER BY emp_id;
```

```text output
 first_name | salary |  band
------------+--------+--------
 James      |  95000 | Medium
 Lena       |  60000 | Medium
 Diego      |  60000 | Medium
 Mei        |  52000 | Low
(4 rows)
```

**Simple:** equality with one value.

```sql
SELECT order_id,
       CASE status WHEN 'DELIVERED' THEN 'Done'
                   WHEN 'CANCELLED' THEN 'Stopped'
                   ELSE 'In progress'
       END AS progress
FROM orders
WHERE order_id IN (1001, 1006, 1011)
ORDER BY order_id;
```

```text output
 order_id |  progress
----------+-------------
     1001 | Done
     1006 | Stopped
     1011 | In progress
(3 rows)
```

The rules:

- The first true `WHEN` wins, so order matters. Check `>= 100000` before `>= 60000`.
- With no `ELSE`, a row that matches nothing gets NULL.
- All results must have compatible types.
- The simple form cannot match NULL, because `x = NULL` is not TRUE. Use `CASE WHEN x IS NULL THEN ...`.

### CASE at work

**Custom sort order:** PENDING first, then SHIPPED, then the rest.

```sql
SELECT order_id, status
FROM orders
WHERE order_id > 1012
ORDER BY CASE status WHEN 'PENDING' THEN 1
                     WHEN 'SHIPPED' THEN 2
                     ELSE 3
         END,
         order_id;
```

```text output
 order_id | status
----------+---------
     1014 | PENDING
     1015 | PENDING
     1016 | PENDING
     1013 | SHIPPED
(4 rows)
```

**Swap the values of a column in one `UPDATE`.** No temporary value is needed, because each row is read as it was before the statement.

```sql
CREATE TABLE people (id INTEGER PRIMARY KEY, gender CHAR(1));

INSERT INTO people VALUES (1, 'M');
INSERT INTO people VALUES (2, 'F');
INSERT INTO people VALUES (3, 'M');

UPDATE people
SET gender = CASE gender WHEN 'M' THEN 'F' WHEN 'F' THEN 'M' ELSE gender END;

SELECT id, gender FROM people ORDER BY id;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
INSERT 0 1
UPDATE 3
 id | gender
----+--------
  1 | F
  2 | M
  3 | F
(3 rows)
```

```sql
DROP TABLE people;
```

### DECODE

`DECODE(expr, search1, result1, ..., default)` is Oracle only.

```sql oracle
SELECT order_id,
       DECODE(status, 'DELIVERED', 'Done', 'CANCELLED', 'Stopped', 'In progress') AS progress
FROM orders
WHERE order_id IN (1001, 1006, 1011)
ORDER BY order_id;
```

```text output
  ORDER_ID PROGRESS
---------- -----------
      1001 Done
      1006 Stopped
      1011 In progress
```

| | `CASE` | `DECODE` |
|---|---|---|
| Standard | Yes | No, Oracle only |
| Conditions | Any | Equality only |
| Two NULLs | Not equal in the simple form | **Treated as equal** |
| Result type | All must be compatible | Converted to the first result's type |
| Where it works | SQL and PL/SQL | Only inside SQL statements |

Prefer `CASE`. One useful `DECODE` trick: since Oracle has no `IS NOT DISTINCT FROM`, `DECODE(a, b, 1, 0) = 1` is a NULL-safe comparison.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Divide integers on PostgreSQL | The fraction is lost | Use `1.0 *` or `CAST` |
| Divide without a guard | A division-by-zero error | Use `NULLIF(y, 0)` |
| Add a nullable column | The result is NULL | Use `COALESCE` |
| Use `=` on an Oracle `DATE` | Rows with a time are missed | Use a range |
| Wrap a filtered column in a function | The index cannot be used | Write a range on the raw column |
| Mix up `MM` and `MI` | Months appear as minutes | `MM` is month, `MI` is minute |
| Put `CASE WHEN x >= 60` before `>= 100` | The first true branch wins | Order from most specific |
| Use the simple `CASE` to match NULL | It never matches | Use `WHEN x IS NULL` |
| Assume `NVL` stops early | Both arguments are evaluated | Use `COALESCE` |
| Trust `MOD(id, 2)` for odd rows | Gaps in ids break it | Use `ROW_NUMBER` ([Chapter 13](13-subqueries.md)) |

## Interview questions

**Q1. What do NVL, NVL2 and COALESCE do, and how do they differ?**

`NVL(a, b)` returns `b` when `a` is NULL. `NVL2(a, b, c)` returns `b` when `a` is not NULL, otherwise `c`. `COALESCE` returns the first non-NULL of any number of arguments. `COALESCE` is standard and stops at the first non-NULL, while `NVL` is Oracle-only and always evaluates both arguments.

**Q2. What is the difference between DECODE and CASE?**

`CASE` is standard, handles any condition, and works in SQL and PL/SQL. `DECODE` is Oracle-only, does equality only, treats two NULLs as equal, and works only inside SQL statements. I prefer `CASE`.

**Q3. Swap the values of a gender column ('M' to 'F' and 'F' to 'M') in one UPDATE.**

`UPDATE t SET gender = CASE gender WHEN 'M' THEN 'F' WHEN 'F' THEN 'M' ELSE gender END`. No temporary value is needed, since each row is read as it was before the statement.

**Q4. Write a query to get the top 5 highest-earning employees who have worked for more than 3 years.**

Filter on `hire_date` being more than 3 years ago, sort by salary descending with a unique tie-breaker, and use `FETCH FIRST 5 ROWS ONLY`. On Oracle 11g, I use `ROWNUM` outside a sorted inline view.

**Q5. What does salary + commission return when commission is NULL, and how do you fix it?**

It returns NULL, because arithmetic with NULL gives NULL. I write `salary + COALESCE(commission, 0)`.

**Q6. Why does 5 / 2 return 2 on PostgreSQL and 2.5 on Oracle?**

PostgreSQL divides two integers as integers and drops the fraction. Oracle's numbers have no integer division. On PostgreSQL I write `5.0 / 2`, or `CAST` one side to `NUMERIC`. This also catches out people dividing two `COUNT`s.

**Q7. How do you avoid a division-by-zero error in a query?**

`x / NULLIF(y, 0)`. `NULLIF` turns a zero into NULL, and dividing by NULL gives NULL instead of an error. `CASE` also works.

**Q8. How do you find the first and last day of a month?**

On Oracle, `TRUNC(d, 'MM')` and `LAST_DAY(d)`. On PostgreSQL, `DATE_TRUNC('month', d)`, and then add one month and subtract one day.

**Q9. How do you find the employees hired in the last 90 days?**

`WHERE hire_date >= SYSDATE - 90` on Oracle, or `CURRENT_DATE - 90` on PostgreSQL. I keep the column bare, so that an index can be used.

## Practice

**1. Show each employee's full name in upper case, with the length of the full name, for department 40.**

<details>
<summary>Show solution</summary>

```sql
SELECT UPPER(first_name || ' ' || last_name) AS full_name,
       LENGTH(first_name || ' ' || last_name) AS name_length
FROM employees
WHERE dept_id = 40
ORDER BY emp_id;
```

```text output
  full_name   | name_length
--------------+-------------
 OMAR FAROOQ  |          11
 NINA PETROVA |          12
(2 rows)
```

</details>

**2. Show how many days each order took to get its first payment, for orders 1001 to 1003.**

<details>
<summary>Show solution</summary>

```sql
SELECT o.order_id,
       MIN(p.payment_date) - o.order_date AS days_to_pay
FROM orders o
JOIN payments p ON p.order_id = o.order_id
WHERE o.order_id <= 1003
GROUP BY o.order_id, o.order_date
ORDER BY o.order_id;
```

```text output
 order_id | days_to_pay
----------+-------------
     1001 |           0
     1002 |           0
     1003 |           1
(3 rows)
```

</details>

**3. Label each product 'Out of stock', 'Low' (under 20) or 'OK', and sort with the most urgent first.**

<details>
<summary>Show solution</summary>

```sql
SELECT product_name, stock_qty,
       CASE WHEN stock_qty = 0 THEN 'Out of stock'
            WHEN stock_qty < 20 THEN 'Low'
            ELSE 'OK'
       END AS stock_status
FROM products
ORDER BY stock_qty, product_id;
```

```text output
  product_name   | stock_qty | stock_status
-----------------+-----------+--------------
 Blender         |         0 | Out of stock
 Laptop Pro      |        10 | Low
 Desk Lamp       |        12 | Low
 Laptop Air      |        15 | Low
 Phone X         |        25 | OK
 Coffee Maker    |        30 | OK
 Phone Lite      |        40 | OK
 Database Design |        60 | OK
 SQL Basics      |       100 | OK
 Phone Case      |       200 | OK
(10 rows)
```

</details>

**4. Show each customer's name and city, with 'Unknown' where the city is missing.**

<details>
<summary>Show solution</summary>

```sql
SELECT customer_name, COALESCE(city, 'Unknown') AS city
FROM customers
ORDER BY customer_id;
```

```text output
 customer_name |  city
---------------+---------
 Alice Morgan  | London
 Bilal Ahmed   | Dubai
 Chloe Martin  | Paris
 David Lee     | Toronto
 Fatima Noor   | Dubai
 George Hall   | London
 Hana Sato     | Tokyo
 Ivan Novak    | Unknown
(8 rows)
```

</details>

**5. Show employees hired in the first three months of any year.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, hire_date
FROM employees
WHERE EXTRACT(MONTH FROM hire_date) <= 3
ORDER BY hire_date;
```

```text output
 first_name | hire_date
------------+------------
 Sara       | 2015-01-12
 James      | 2016-03-01
 Omar       | 2017-02-20
 Mei        | 2022-01-17
(4 rows)
```

</details>

## Recap

- `||` joins text on Oracle and PostgreSQL. `CONCAT` takes two arguments on older Oracle.
- `ROUND`, `TRUNC`, `FLOOR` and `CEIL` differ on negative numbers.
- `5 / 2` is 2 on PostgreSQL. Use `1.0 *`.
- `x / NULLIF(y, 0)` avoids division by zero.
- An Oracle `DATE` holds a time, so filter with a range.
- `COALESCE` is standard and stops early. `NVL` is Oracle-only and evaluates both.
- In `CASE`, the first true `WHEN` wins, and with no `ELSE` the result is NULL.
- Prefer `CASE` to `DECODE`.

**Next:** [Chapter 10: Grouping and totals](10-aggregation-group-by-having.md)
