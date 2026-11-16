# 20. Modern SQL: Regular Expressions, Date Series, LATERAL and JSON

**Level:** Advanced | **Interview priority:** Should know | **Before this:** [Chapter 19](19-views-materialized-views-sequences.md)

> **In one line:** These are the tools for messy text, missing dates, per-row subqueries and semi-structured data.

## What you will learn

- When to use regular expressions, and what they cost
- How to split a delimited string into rows
- How to show days with no sales as zero
- What `LATERAL` can do that a normal join cannot
- When JSON in a relational table is a good idea

## Regular expressions

**When to use what:** `LIKE` for simple prefixes and wildcards, regular expressions for real patterns, and neither when the column should have been split into proper columns.

### The building blocks

| Symbol | Means |
|---|---|
| `.` | Any one character |
| `^` and `$` | The start and end of the string |
| `[abc]` and `[^abc]` | One of these, or none of these |
| `*`, `+`, `?` | Zero or more, one or more, zero or one |
| `{n,m}` | Between n and m times |
| `a\|b` | a or b |
| `( )` | A group |
| `[[:digit:]]` or `\d` | A digit |

### Regex functions by engine

| Task | Oracle (10g and later) | PostgreSQL |
|---|---|---|
| Does it match? | `REGEXP_LIKE(s, p)` | `s ~ p`, or `s ~* p` to ignore case |
| Extract | `REGEXP_SUBSTR(s, p)` | `SUBSTRING(s FROM p)`, `regexp_match` |
| Replace | `REGEXP_REPLACE(s, p, r)` | `regexp_replace(s, p, r)` |
| Count | `REGEXP_COUNT` (11g and later) | `regexp_count` (15 and later) |

**Trap:** Oracle's `REGEXP_REPLACE` replaces every match by default. PostgreSQL's replaces only the first, unless you add the `'g'` flag.

**Validate an email's shape, and pull out the domain.**

**PostgreSQL:**

```sql postgres
SELECT customer_name,
       email ~ '^[^@ ]+@[^@ ]+\.[a-z]+$' AS looks_valid,
       SUBSTRING(email FROM '@(.*)$') AS domain
FROM customers
WHERE customer_id = 1;
```

```text output
 customer_name | looks_valid |   domain
---------------+-------------+-------------
 Alice Morgan  | t           | example.com
(1 row)
```

**Oracle:**

```sql oracle
SELECT customer_name,
       REGEXP_SUBSTR(email, '@(.*)$', 1, 1, NULL, 1) AS domain
FROM customers
WHERE customer_id = 1
  AND REGEXP_LIKE(email, '^[^@ ]+@[^@ ]+\.[a-z]+$');
```

**Strip everything except digits:**

```sql postgres
SELECT regexp_replace('+1 (555) 010-7788', '[^0-9]', '', 'g') AS digits;
```

```text output
   digits
-------------
 15550107788
(1 row)
```

**Cost.** A normal B-tree index cannot serve most regex filters, so they scan the table. Prefer a validated stored column. On PostgreSQL, a trigram index (`pg_trgm`) can help.

## Splitting a delimited string into rows

**How would you split a comma-separated string into rows?** This is the reverse of `LISTAGG`.

**PostgreSQL 14 and later:**

```sql postgres
SELECT t.color
FROM string_to_table('red,green,blue', ',') WITH ORDINALITY AS t (color, position)
ORDER BY t.position;
```

```text output
 color
-------
 red
 green
 blue
(3 rows)
```

**Oracle,** with the row generator from [Chapter 14](14-cte-and-recursive-queries.md):

```sql oracle
SELECT REGEXP_SUBSTR('red,green,blue', '[^,]+', 1, LEVEL) AS color
FROM dual
CONNECT BY LEVEL <= REGEXP_COUNT('red,green,blue', ',') + 1;
```

```text output
COLOR
-----
red
green
blue
```

## Date series

`GROUP BY` shows only the days that have rows, so empty days vanish, and averages come out wrong.

**PostgreSQL:**

```sql postgres
SELECT d::DATE AS day
FROM generate_series(DATE '2024-01-01', DATE '2024-01-03', INTERVAL '1 day') AS d
ORDER BY day;
```

```text output
    day
------------
 2024-01-01
 2024-01-02
 2024-01-03
(3 rows)
```

**Oracle (works on 11g):**

```sql oracle
SELECT DATE '2024-01-01' + LEVEL - 1 AS day
FROM dual
CONNECT BY LEVEL <= 3;
```

A recursive CTE works anywhere ([Chapter 14](14-cte-and-recursive-queries.md)).

A permanent **calendar table** is the usual production answer: one row per date, with columns for weekends, holidays and fiscal periods. Pick it when reports use business calendars, and a generated series for one-off queries.

### Zero-filling a daily report

**How do you show days with no sales as zero?** `LEFT JOIN` from the date list to the facts, then `COALESCE`.

```sql postgres
SELECT d::DATE AS day,
       COUNT(o.order_id) AS orders,
       COALESCE(SUM(p.amount), 0) AS paid
FROM generate_series(DATE '2024-01-04', DATE '2024-01-09', INTERVAL '1 day') AS d
LEFT JOIN orders o ON o.order_date = d::DATE
LEFT JOIN payments p ON p.order_id = o.order_id
GROUP BY d
ORDER BY day;
```

```text output
    day     | orders |  paid
------------+--------+--------
 2024-01-04 |      0 |      0
 2024-01-05 |      1 | 838.98
 2024-01-06 |      0 |      0
 2024-01-07 |      0 |      0
 2024-01-08 |      0 |      0
 2024-01-09 |      1 |  74.00
(6 rows)
```

Two traps:

- Put filters on the fact table in the `ON` clause, not in `WHERE`, or the `LEFT JOIN` turns back into an inner join ([Chapter 11](../part-2-sql-basics/11-joins.md)).
- Count a fact column, not `*`, or empty days count as 1.

**A zero day differs from a missing row.** Zero means you measured and nothing happened. Missing means there is no data, perhaps because a pipeline failed. Fill with 0 only when zero is true.

## LATERAL

**What can LATERAL do that a normal join cannot?** A normal derived table cannot see the tables to its left. A `LATERAL` subquery can, so it logically runs once per left row. A scalar subquery can too, but it returns one value, while `LATERAL` can return several columns and rows.

**The top 2 earners per department:**

```sql postgres
-- PostgreSQL
SELECT d.dept_name, t.first_name, t.salary
FROM departments d
CROSS JOIN LATERAL (
  SELECT e.first_name, e.salary
  FROM employees e
  WHERE e.dept_id = d.dept_id
  ORDER BY e.salary DESC, e.emp_id
  FETCH FIRST 2 ROWS ONLY
) t
ORDER BY d.dept_id, t.salary DESC;
```

```text output
  dept_name  | first_name | salary
-------------+------------+--------
 Executive   | Sara       | 180000
 Sales       | James      |  95000
 Sales       | Lena       |  60000
 Engineering | Priya      | 120000
 Engineering | Arjun      | 105000
 Finance     | Omar       |  95000
 Finance     | Nina       |  58000
(7 rows)
```

With an index on `(dept_id, salary DESC)`, this reads only a few rows per group, which is why it can beat a window function on a large table.

| Form | Works on |
|---|---|
| `CROSS JOIN LATERAL`, `LEFT JOIN LATERAL ... ON TRUE` | PostgreSQL 9.3, MySQL 8.0.14 |
| `LATERAL`, `CROSS APPLY`, `OUTER APPLY` | Oracle 12c and later (not your 11g) |
| `CROSS APPLY`, `OUTER APPLY` | SQL Server |

`CROSS` drops left rows with no result, like an inner join. `LEFT` or `OUTER` keeps them.

**LATERAL as an unpivot:**

```sql postgres
SELECT p.product_id, v.attribute, v.attr_value
FROM products p
CROSS JOIN LATERAL (VALUES ('price', p.price), ('stock', p.stock_qty)) AS v (attribute, attr_value)
WHERE p.product_id = 1
ORDER BY v.attribute;
```

```text output
 product_id | attribute | attr_value
------------+-----------+------------
          1 | price     |     799.00
          1 | stock     |         25
(2 rows)
```

PostgreSQL treats functions in `FROM` as lateral automatically.

## JSON

**When would you store JSON in a relational table?** For attributes that vary by row and are read as a whole, such as extra product attributes or an API payload. **When would you avoid it?** For anything you filter, join or constrain regularly, which should be a real column ([Chapter 25](../part-4-database-design/25-schema-design-patterns.md)).

### Storage by engine

| Engine | Support |
|---|---|
| Oracle 11g | None |
| Oracle 12.1.0.2 and later | `IS JSON`, `JSON_VALUE`, `JSON_QUERY`, `JSON_EXISTS`, `JSON_TABLE`, over `VARCHAR2`, `CLOB` or `BLOB` |
| Oracle 21c and later | A native `JSON` type |
| PostgreSQL | `json` (text) and `jsonb` (binary, indexable, the usual choice) |

### Reading JSON on PostgreSQL

```sql postgres
CREATE TABLE product_specs (
  product_id  INTEGER PRIMARY KEY,
  specs       JSONB NOT NULL
);

INSERT INTO product_specs VALUES
  (1, '{"color": "black", "storage": 256, "tags": ["5g", "dual-sim"]}'),
  (4, '{"color": "silver", "storage": 1024}');

SELECT product_id,
       specs ->> 'color' AS color,
       (specs ->> 'storage')::INTEGER AS storage,
       specs -> 'tags' AS tags
FROM product_specs
ORDER BY product_id;
```

```text output
CREATE TABLE
INSERT 0 2
 product_id | color  | storage |        tags
------------+--------+---------+--------------------
          1 | black  |     256 | ["5g", "dual-sim"]
          4 | silver |    1024 | NULL
(2 rows)
```

- `->` returns JSON, and `->>` returns text.
- `#>` and `#>>` take a path.
- `@>` tests containment, and `?` tests for a key.

Cast `->>` before comparing numbers, because as text, `'10'` sorts before `'9'`.

```sql postgres
SELECT product_id
FROM product_specs
WHERE specs @> '{"color": "black"}';
```

```text output
 product_id
------------
          1
(1 row)
```

### Standard SQL/JSON functions

`JSON_VALUE` returns a scalar, `JSON_QUERY` returns an object or array, and `JSON_EXISTS` tests a path. These work on Oracle 12c and later, and PostgreSQL 17 and later. A missing path gives NULL by default.

```sql postgres
SELECT product_id,
       JSON_VALUE(specs, '$.color') AS color,
       JSON_EXISTS(specs, '$.tags') AS has_tags
FROM product_specs
ORDER BY product_id;
```

```text output
 product_id | color  | has_tags
------------+--------+----------
          1 | black  | t
          4 | silver | f
(2 rows)
```

**`JSON_TABLE`** turns a JSON array into rows and columns that you can join. It works on Oracle 12c, PostgreSQL 17 and MySQL 8.0.4.

```sql postgres
SELECT s.product_id, t.tag
FROM product_specs s,
     JSON_TABLE(s.specs, '$.tags[*]' COLUMNS (tag VARCHAR(20) PATH '$')) t
ORDER BY t.tag;
```

```text output
 product_id |   tag
------------+----------
          1 | 5g
          1 | dual-sim
(2 rows)
```

```sql oracle since=12c
SELECT s.product_id, t.tag
FROM product_specs s,
     JSON_TABLE(s.specs, '$.tags[*]' COLUMNS (tag VARCHAR2(20) PATH '$')) t;
```

### Building JSON from rows

**One order with its items as a nested document,** which avoids a query per order:

```sql postgres
SELECT JSONB_BUILD_OBJECT(
         'order_id', o.order_id,
         'items', JSONB_AGG(JSONB_BUILD_OBJECT('product', i.product_id, 'qty', i.quantity)
                            ORDER BY i.product_id)
       ) AS doc
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.order_id = 1001
GROUP BY o.order_id;
```

```text output
                                        doc
-----------------------------------------------------------------------------------
 {"items": [{"qty": 1, "product": 1}, {"qty": 2, "product": 3}], "order_id": 1001}
(1 row)
```

Oracle 12.2 and PostgreSQL 16 have the standard `JSON_OBJECT` and `JSON_ARRAYAGG`.

### Indexing JSON

Without an index, every JSON filter is a full scan ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)).

```sql postgres
CREATE INDEX specs_gin ON product_specs USING GIN (specs);
CREATE INDEX specs_color ON product_specs ((specs ->> 'color'));
DROP TABLE product_specs;
```

A GIN index serves containment, and an expression index serves one path. On Oracle, use a function-based index on `JSON_VALUE`.

To update JSON, use `jsonb_set` on PostgreSQL, and `JSON_MERGEPATCH` or `JSON_TRANSFORM` on Oracle.

## Querying a collection from SQL

**How do you query a PL/SQL collection from SQL?** A collection is an array-like value. The type must be created at schema level, and then `TABLE()` turns it into rows.

```sql oracle
CREATE TYPE num_list AS TABLE OF NUMBER;
/

SELECT column_value AS n
FROM TABLE(num_list(10, 20, 30));
```

```text output
         N
----------
        10
        20
        30
```

[Chapter 49](../part-7-plsql/49-records-and-collections.md) covers collections in full.

## Newer Oracle features to recognize

- **`MATCH_RECOGNIZE`** (12c): row pattern matching in plain SQL, which can solve gaps and islands.
- **PL/SQL functions in the `WITH` clause** (12.1).
- **SQL macros:** a function that returns SQL text, which the database folds into the query when it is parsed. They are like a parameterized view, and they avoid the cost of switching between SQL and PL/SQL at run time, which a normal table function pays. See [Chapter 53](../part-7-plsql/53-plsql-performance-and-best-practices.md).
- **JSON Relational Duality views** (23ai): JSON documents over normalized tables.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use regex where `LIKE` would do | It is slower | Use `LIKE` for simple patterns |
| Assume `regexp_replace` works the same everywhere | PostgreSQL replaces only the first match | Add `'g'` |
| Filter on regex on a big table | A full scan | Store a validated column |
| Report only days with rows | Empty days vanish | `LEFT JOIN` from a date list |
| Filter facts in `WHERE` after that `LEFT JOIN` | Empty days vanish again | Filter in `ON` |
| Fill a missing day with 0 when no data arrived | A pipeline failure looks like a quiet day | Report missing as missing |
| Compare `->>` values as numbers without a cast | `'10'` sorts before `'9'` | Cast first |
| Put filtered fields in JSON | Every query is a slow scan | Use real columns |

## Interview questions

**Q1. How would you split a comma-separated string into rows?**

On PostgreSQL, `string_to_table`, or `regexp_split_to_table`. On Oracle, `REGEXP_SUBSTR` with `CONNECT BY LEVEL <= REGEXP_COUNT(...) + 1`. If that string is stored in a column, it is also a design smell, because it breaks first normal form.

**Q2. How do you show days with no sales as zero in a daily report?**

I generate the list of dates, or use a calendar table, then `LEFT JOIN` the sales and use `COALESCE(SUM(x), 0)`. Filters on the sales table go in `ON`, and I count a sales column, not `*`.

**Q3. What can LATERAL do that a normal join cannot?**

A `LATERAL` subquery can refer to tables on its left, so it can return a different set of rows for each left row. That makes top-N per group easy, with `ORDER BY` and `FETCH FIRST` inside. With the right index, it reads only a few rows per group.

**Q4. When would you store JSON in a relational table, and when would you avoid it?**

I store JSON for attributes that vary by row and are read as a whole. I avoid it for anything I filter, join or constrain regularly, which should be a real column, because JSON gives up types, constraints and easy indexing.

**Q5. How do you query a PL/SQL collection from SQL?**

Create the collection type at schema level, then use the `TABLE()` operator in `FROM`: `SELECT column_value FROM TABLE(my_list)`. From 12c, package-level types also work in many cases.

**Q6. What are SQL macros, and how do they compare with views and table functions?**

A SQL macro is a function that returns SQL text, and the text is folded into the query at parse time. Like a view, it is optimized as part of the query. Unlike a view, it takes parameters. Unlike a normal table function, it has no run-time switch to PL/SQL.

## Practice

**1. Find customers whose email starts with a vowel. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
SELECT customer_name, email
FROM customers
WHERE email ~ '^[aeiou]'
ORDER BY customer_id;
```

```text output
 customer_name |       email
---------------+-------------------
 Alice Morgan  | alice@example.com
(1 row)
```

</details>

**2. Show every month from January to June 2024, with the number of orders by employee 7, including months with none. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
SELECT TO_CHAR(m, 'YYYY-MM') AS order_month,
       COUNT(o.order_id) AS orders
FROM generate_series(DATE '2024-01-01', DATE '2024-06-01', INTERVAL '1 month') AS m
LEFT JOIN orders o
       ON o.emp_id = 7
      AND o.order_date >= m::DATE
      AND o.order_date < (m + INTERVAL '1 month')::DATE
GROUP BY m
ORDER BY m;
```

```text output
 order_month | orders
-------------+--------
 2024-01     |      0
 2024-02     |      1
 2024-03     |      1
 2024-04     |      0
 2024-05     |      1
 2024-06     |      1
(6 rows)
```

The employee filter is in `ON`, so that empty months stay. This fixes the missing month trap from [Chapter 15](15-window-functions-ranking-and-offset.md).

</details>

**3. For each customer, show their most recent order and its date, using `LATERAL`. Keep customers with no orders.**

<details>
<summary>Show solution</summary>

```sql postgres
SELECT c.customer_name, t.order_id, t.order_date
FROM customers c
LEFT JOIN LATERAL (
  SELECT o.order_id, o.order_date
  FROM orders o
  WHERE o.customer_id = c.customer_id
  ORDER BY o.order_date DESC, o.order_id DESC
  FETCH FIRST 1 ROW ONLY
) t ON TRUE
ORDER BY c.customer_id;
```

```text output
 customer_name | order_id | order_date
---------------+----------+------------
 Alice Morgan  |     1014 | 2024-06-01
 Bilal Ahmed   |     1013 | 2024-05-19
 Chloe Martin  |     1016 | 2024-06-18
 David Lee     |     1011 | 2024-04-21
 Fatima Noor   |     1012 | 2024-05-02
 George Hall   |     1015 | 2024-06-11
 Hana Sato     |     NULL | NULL
 Ivan Novak    |     NULL | NULL
(8 rows)
```

</details>

## Recap

- Use `LIKE` for simple patterns, and regex for real ones. Regex usually means a scan.
- Oracle's `REGEXP_REPLACE` replaces all matches. PostgreSQL's needs `'g'`.
- Generate a date list, and `LEFT JOIN` from it, to show empty days.
- Zero and missing are different things.
- `LATERAL` lets a subquery in `FROM` see tables to its left.
- Store JSON for what you read whole. Use columns for what you filter.
- Index JSON, or every filter is a full scan.

**Next:** [Chapter 21: Classic query patterns](21-classic-query-patterns.md)
