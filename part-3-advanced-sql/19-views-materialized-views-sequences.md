# 19. Views, Materialized Views, Sequences and Temporary Tables

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 18](18-advanced-dml.md)

> **In one line:** A view is a saved query, a materialized view is a saved result, a sequence hands out numbers, and a temporary table holds rows for a short time.

## What you will learn

- What a view is, and when you can update through one
- Materialized views and their trade-offs
- Why sequences leave gaps, and what to do about it
- Identity columns, synonyms and temporary tables
- How to choose between a subquery, CTE, temp table, view and materialized view
- `GRANT` basics, and views as a security layer

## Views

A **view** is a named, stored query. It holds no rows of its own. Each use runs the query against current data.

```sql
CREATE VIEW staff_directory AS
SELECT e.emp_id, e.first_name, e.last_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON d.dept_id = e.dept_id;

SELECT first_name, dept_name
FROM staff_directory
WHERE emp_id IN (1, 12)
ORDER BY emp_id;
```

```text output
CREATE VIEW
 first_name | dept_name
------------+-----------
 Sara       | Executive
 Tom        | NULL
(2 rows)
```

**How does a view run?** The engine usually merges the view's text into the calling query. So a plain view is **not** a performance feature. Views stacked on views hide their cost, and can make plans worse.

**Why use views?**

- To hide a complex join
- To keep a stable interface while tables change
- To show only some rows and columns ([below](#views-as-a-security-layer))

### Updating through a view

A simple single-table view is usually updatable.

```sql
CREATE VIEW sales_staff AS
SELECT emp_id, first_name, salary, dept_id
FROM employees
WHERE dept_id = 20
WITH CHECK OPTION;

UPDATE sales_staff SET salary = salary + 100 WHERE emp_id = 7;

SELECT salary FROM employees WHERE emp_id = 7;
```

```text output
CREATE VIEW
UPDATE 1
 salary
--------
  52100
(1 row)
```

`WITH CHECK OPTION` refuses a change that would move the row out of the view:

```sql error=check
UPDATE sales_staff SET dept_id = 30 WHERE emp_id = 7;
```

```text output
ERROR:  new row violates check option for view "sales_staff"
DETAIL:  Failing row contains (7, Mei, Chen, mei.chen@shop.example, Sales Rep, 52100, 0, 2022-01-17, 2, 30).
```

Aggregates, `DISTINCT`, `GROUP BY` and set operators make a view read-only:

```sql
CREATE VIEW dept_pay AS
SELECT dept_id, SUM(salary) AS total_pay
FROM employees
GROUP BY dept_id;
```

```sql error=updatable
UPDATE dept_pay SET total_pay = 0 WHERE dept_id = 20;
```

```text output
ERROR:  cannot update view "dept_pay"
DETAIL:  Views containing GROUP BY are not automatically updatable.
HINT:  To enable updating the view, provide an INSTEAD OF UPDATE trigger or an unconditional ON UPDATE DO INSTEAD rule.
```

A join view can be updated on Oracle only through a key-preserved table ([Chapter 18](18-advanced-dml.md)).

### What breaks a view

On Oracle, dropping or changing a base table leaves the view **INVALID** until the table returns. It recompiles on next use. On PostgreSQL, `DROP TABLE` is refused unless you add `CASCADE`, which also drops the view.

```sql
DROP VIEW dept_pay;
DROP VIEW sales_staff;
DROP VIEW staff_directory;
```

## Materialized views

A **materialized view** is a query whose result is physically stored, and which must be refreshed.

| | View | Materialized view |
|---|---|---|
| Stores rows | No | Yes |
| Read speed | Same as the query | Fast |
| Data | Always current | Can be stale |
| Can be indexed | No | Yes |
| Costs | Nothing extra | Storage and refresh work |

### On PostgreSQL

```sql postgres
CREATE MATERIALIZED VIEW dept_totals AS
SELECT dept_id, SUM(salary) AS total_pay
FROM employees
GROUP BY dept_id;

UPDATE employees SET salary = salary + 1000 WHERE dept_id = 40;

SELECT total_pay FROM dept_totals WHERE dept_id = 40;
```

```text output
SELECT 5
UPDATE 2
 total_pay
-----------
    153000
(1 row)
```

The change is not visible yet. Nothing refreshes automatically.

```sql postgres
REFRESH MATERIALIZED VIEW dept_totals;

SELECT total_pay FROM dept_totals WHERE dept_id = 40;
```

```text output
REFRESH MATERIALIZED VIEW
 total_pay
-----------
    155000
(1 row)
```

`REFRESH` recomputes everything and blocks readers. `REFRESH ... CONCURRENTLY` does not block them, but it needs a unique index on the materialized view.

```sql postgres
DROP MATERIALIZED VIEW dept_totals;
```

### On Oracle

Oracle has far more options.

| Option | Choices |
|---|---|
| Refresh method | `COMPLETE`, `FAST` (only the changes), `FORCE` (fast if possible) |
| Refresh timing | `ON DEMAND`, `ON COMMIT` |
| Materialized view logs | Tables that record changes, which `FAST` needs |
| Query rewrite | The optimizer silently uses the materialized view for a matching query |

```sql oracle
CREATE MATERIALIZED VIEW dept_totals
REFRESH COMPLETE ON DEMAND
AS
SELECT dept_id, SUM(salary) AS total_pay
FROM employees
GROUP BY dept_id;

EXEC DBMS_MVIEW.REFRESH('DEPT_TOTALS');
```

**Other engines.** SQL Server indexed views stay in step with every change. MySQL has no materialized views, so people build summary tables.

**When is it a good fit?** An expensive aggregate, read often, on data that changes slowly, where some staleness is fine. A bad fit is data that must be current to the second, or a busy table with `ON COMMIT` refresh, which slows every commit.

## Sequences

A **sequence** is an object that hands out numbers.

**PostgreSQL:**

```sql postgres
CREATE SEQUENCE invoice_seq START WITH 100 INCREMENT BY 1;

SELECT nextval('invoice_seq') AS next_number;
```

```text output
CREATE SEQUENCE
 next_number
-------------
         100
(1 row)
```

**Oracle:**

```sql oracle
CREATE SEQUENCE invoice_seq START WITH 100 INCREMENT BY 1 CACHE 20;

SELECT invoice_seq.NEXTVAL FROM dual;
SELECT invoice_seq.CURRVAL FROM dual;
```

`CURRVAL` works only after `NEXTVAL` in the same session, and it is `ORA-08002` otherwise.

### Why do sequences leave gaps?

Sequences are **not transactional**. `ROLLBACK` does not return a number.

```sql postgres
BEGIN;
SELECT nextval('invoice_seq') AS used_then_rolled_back;
ROLLBACK;

SELECT nextval('invoice_seq') AS next_number;
```

```text output
BEGIN
 used_then_rolled_back
-----------------------
                   101
(1 row)

ROLLBACK
 next_number
-------------
         102
(1 row)
```

Number 101 is gone. Why design it this way? If rollback returned numbers, every session would have to wait for others to finish. Not waiting is the point. Cached numbers can also be lost in a crash. `CACHE` trades gaps for speed. **Gaps are normal.**

**How would you produce gapless invoice numbers?** Where the law requires it, use a counter row, locked in the same transaction:

```sql postgres
CREATE TABLE counters (name VARCHAR(20) PRIMARY KEY, value INTEGER NOT NULL);
INSERT INTO counters VALUES ('invoice', 500);

BEGIN;
UPDATE counters SET value = value + 1 WHERE name = 'invoice' RETURNING value;
COMMIT;
```

```text output
CREATE TABLE
INSERT 0 1
BEGIN
 value
-------
   501
(1 row)

UPDATE 1
COMMIT
```

The row lock makes every invoice wait for the one before it, so a rollback leaves no gap. The cost is that invoice creation runs one at a time. Use this only where it is really required.

```sql postgres
DROP TABLE counters;
DROP SEQUENCE invoice_seq;
```

## Identity columns

An identity column numbers rows by itself, using a sequence behind the scenes.

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
CREATE TABLE tickets (
  ticket_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  subject    VARCHAR(100) NOT NULL
);

INSERT INTO tickets (subject) VALUES ('Login fails');
INSERT INTO tickets (subject) VALUES ('Printer jam');

SELECT ticket_id, subject FROM tickets ORDER BY ticket_id;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
 ticket_id |   subject
-----------+-------------
         1 | Login fails
         2 | Printer jam
(2 rows)
```

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
DROP TABLE tickets;
```

`GENERATED ALWAYS` rejects a value you supply. `GENERATED BY DEFAULT` accepts one.

| Engine | Syntax |
|---|---|
| Oracle 12c and later, PostgreSQL 10 and later | `GENERATED ... AS IDENTITY` |
| Older PostgreSQL | `SERIAL` |
| MySQL | `AUTO_INCREMENT` |
| SQL Server | `IDENTITY` |

On your Oracle 11g, use a sequence in the `INSERT`, or in a trigger:

```sql oracle
CREATE OR REPLACE TRIGGER tickets_bi
BEFORE INSERT ON tickets
FOR EACH ROW
BEGIN
  IF :NEW.ticket_id IS NULL THEN
    :NEW.ticket_id := ticket_seq.NEXTVAL;
  END IF;
END;
/
```

## Synonyms

A **synonym** is an alias for an object, private or public on Oracle. It hides the owner or a database link, so that code does not change when the object moves. A synonym grants no privileges.

```sql oracle
CREATE SYNONYM emp FOR employees;
```

SQL Server has synonyms. PostgreSQL and MySQL do not.

## Temporary tables

| | Oracle global temporary table | PostgreSQL temporary table |
|---|---|---|
| Definition | Permanent and shared | Private to the session, gone when it ends |
| Rows | Private to each session | Private to the session |
| Created | Once, by a DBA or a script | In each session |

```sql oracle
CREATE GLOBAL TEMPORARY TABLE gtt_totals (
  dept_id    NUMBER,
  total_pay  NUMBER
) ON COMMIT PRESERVE ROWS;
```

`ON COMMIT DELETE ROWS` clears the rows at commit, and `ON COMMIT PRESERVE ROWS` keeps them until the session ends. Oracle 18c added private temporary tables, whose definition is private too.

```sql postgres
CREATE TEMPORARY TABLE temp_totals AS
SELECT dept_id, SUM(salary) AS total_pay
FROM employees
GROUP BY dept_id;

SELECT COUNT(*) AS row_count FROM temp_totals;
```

```text output
SELECT 5
 row_count
-----------
         5
(1 row)
```

**When does a temp table beat a CTE?** When several statements need the result, when it needs an index or statistics, or when it is large and would otherwise be recomputed. On PostgreSQL, autovacuum does not analyze temp tables, so run `ANALYZE` yourself.

## How to choose

| Tool | Scope | Stores rows | Use it for |
|---|---|---|---|
| Subquery | One statement | No | A one-off filter |
| CTE | One statement | Usually no | Naming steps, recursion |
| Temp table | One session | Yes | A result that several statements need |
| View | Permanent | No | Reuse, hiding joins, security |
| Materialized view | Permanent | Yes | Expensive reports that can be stale |

## GRANT, and views as a security layer

**System privileges** allow an action, such as `CREATE TABLE`. **Object privileges** allow access to one object, such as `SELECT ON employees`. A **role** is a named bundle of privileges.

```sql norun
GRANT SELECT ON staff_directory TO reporting_role;
REVOKE SELECT ON staff_directory FROM reporting_role;
```

`WITH GRANT OPTION` lets the grantee pass on an object privilege. Revoking it cascades to the people they granted it to.

### Views as a security layer

**How do you let a user see only some rows and columns of a table?** Grant `SELECT` on a view, and not on the table. A staff directory view with no salary or commission hides those columns. A view with a `WHERE` hides rows. [Chapter 40](../part-6-architecture-and-scale/40-database-security.md) continues with row-level security.

On Oracle, a view's owner needs direct grants on the base tables, because privileges received through a role do not count inside a definer's view.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Expect a view to speed up a query | It just runs the query | Use a materialized view, or tune the query |
| Stack views on views | Plans get slow and hard to read | Keep view layers shallow |
| Forget to refresh a materialized view | Users see stale data | Schedule the refresh |
| Use `ON COMMIT` refresh on a busy table | Every commit slows down | Use `ON DEMAND` |
| Promise gapless numbers from a sequence | Rollbacks and crashes leave gaps | Use a locked counter row, if truly needed |
| Use `CURRVAL` before `NEXTVAL` | `ORA-08002` | Call `NEXTVAL` first |
| Assume a synonym grants access | It does not | Grant on the object |
| Use a temp table for one simple step | Extra work | Use a CTE |

## Interview questions

**Q1. What is a materialized view and what are its trade-offs?**

It is a query whose result is stored physically and refreshed. Reads are fast, and it can be indexed. The costs are that data can be stale, it takes storage, and refreshing takes work. It suits expensive aggregates read often, on data that changes slowly.

**Q2. CTE, temporary table, view or materialized view: how do you choose?**

A CTE is for naming steps in one statement. A temp table is for a result several statements need, especially if it needs an index. A view is a permanent, reusable query with no stored rows. A materialized view stores the result, for expensive reports that can be a little stale.

**Q3. Can you update data through a view?**

Yes, for a simple single-table view. Aggregates, `DISTINCT`, `GROUP BY` and set operators make it read-only. On Oracle, a join view can be updated only through a key-preserved table. `WITH CHECK OPTION` stops changes that would move a row out of the view.

**Q4. Why do sequences leave gaps, and how would you produce gapless invoice numbers?**

Sequences are not transactional. `ROLLBACK` does not return a number, because that would force sessions to wait for each other, and cached numbers can be lost in a crash. For legally gapless numbers, I use a counter row, updated and locked in the same transaction. That makes invoice creation serial, so I only do it when required.

**Q5. What is the difference between an Oracle global temporary table and a PostgreSQL temporary table?**

An Oracle global temporary table has a permanent, shared definition, and rows private to each session. A PostgreSQL temp table is created in a session, and both its definition and rows vanish when the session ends.

**Q6. How do you let a user see only some rows and columns of a table?**

Create a view with those rows and columns, and grant `SELECT` on the view, not on the table. For per-user row filtering, I would use row-level security: VPD on Oracle, or RLS policies on PostgreSQL.

## Practice

**1. Create a view showing each order with its customer name and total value. Query it for customer 1, then drop it.**

<details>
<summary>Show solution</summary>

```sql
CREATE VIEW order_summary AS
SELECT o.order_id, c.customer_id, c.customer_name,
       SUM(i.quantity * i.unit_price) AS order_total
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items i ON i.order_id = o.order_id
GROUP BY o.order_id, c.customer_id, c.customer_name;

SELECT order_id, order_total
FROM order_summary
WHERE customer_id = 1
ORDER BY order_id;
```

```text output
CREATE VIEW
 order_id | order_total
----------+-------------
     1001 |      838.98
     1004 |       89.50
     1009 |       49.00
     1014 |       59.97
(4 rows)
```

```sql
DROP VIEW order_summary;
```

</details>

**2. Create a view that shows only products in stock, and stop anyone setting `stock_qty` to 0 through it.**

<details>
<summary>Show solution</summary>

```sql
CREATE VIEW in_stock AS
SELECT product_id, product_name, stock_qty
FROM products
WHERE stock_qty > 0
WITH CHECK OPTION;
```

```sql error=check
UPDATE in_stock SET stock_qty = 0 WHERE product_id = 1;
```

```text output
ERROR:  new row violates check option for view "in_stock"
DETAIL:  Failing row contains (1, Phone X, 2, 799.00, 0).
```

```sql
DROP VIEW in_stock;
```

</details>

## Recap

- A view stores a query, not rows. It is not a performance feature.
- Simple views are updatable. Aggregates make them read-only.
- A materialized view stores the result. It is fast, but can be stale.
- Sequences are not transactional, so gaps are normal.
- For gapless numbers, lock a counter row, and accept that this makes writes serial.
- Oracle temp tables have a permanent definition and private rows.
- Grant on a view, not on the table, to show only some data.

**Next:** [Chapter 20: Modern SQL](20-modern-sql.md)
