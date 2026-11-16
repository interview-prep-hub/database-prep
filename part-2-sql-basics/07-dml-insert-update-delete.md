# 7. Changing Data: INSERT, UPDATE, DELETE and TRUNCATE

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 6](06-ddl-and-constraints.md)

> **In one line:** `INSERT` adds rows, `UPDATE` changes them, `DELETE` removes them, and `TRUNCATE` empties a table all at once.

## What you will learn

- How to write safe `INSERT`, `UPDATE` and `DELETE` statements
- `COMMIT`, `ROLLBACK` and `SAVEPOINT`, just enough to practice safely
- The difference between `DELETE`, `TRUNCATE` and `DROP`
- Whether `TRUNCATE` can be rolled back (the honest answer depends on the engine)

**DML** (Data Manipulation Language) changes rows. The table's structure stays the same, and the constraints from [Chapter 6](06-ddl-and-constraints.md) check every change.

## Practice safely: COMMIT and ROLLBACK

A change stays private until `COMMIT` makes it permanent. `ROLLBACK` undoes it.

- **SQL*Plus** holds your changes until you `COMMIT`.
- **psql** commits each statement by itself, unless you start with `BEGIN`.

So here is the safe way to experiment on each:

**Oracle:**

```sql oracle
UPDATE employees SET salary = 1 WHERE emp_id = 12;
SELECT salary FROM employees WHERE emp_id = 12;
ROLLBACK;
```

**PostgreSQL:**

```sql postgres
BEGIN;
UPDATE employees SET salary = 1 WHERE emp_id = 12;
SELECT salary FROM employees WHERE emp_id = 12;
ROLLBACK;
```

```text output
BEGIN
UPDATE 1
 salary
--------
      1
(1 row)

ROLLBACK
```

And you can always reload the original rows ([setup guide](../setup/README.md)).

## INSERT

```sql
INSERT INTO departments (dept_id, dept_name, location)
VALUES (60, 'Support', 'Oslo');
```

Always write the column list. An `INSERT` without one depends on the column order, and breaks when someone adds a column. Values match the list by position.

**Columns left out** get their `DEFAULT`, or NULL if there is none. The `DEFAULT` keyword asks for it explicitly. Inserting NULL into a column that has a default stores NULL.

```sql
INSERT INTO products (product_id, product_name, category_id, price)
VALUES (11, 'Mouse', 1, 15.00);

SELECT product_name, stock_qty FROM products WHERE product_id = 11;
```

```text output
INSERT 0 1
 product_name | stock_qty
--------------+-----------
 Mouse        |         0
(1 row)
```

`stock_qty` was left out, so it got its default of 0.

### Constraint failures

Each failed `INSERT` names the rule it broke.

| Problem | Oracle | PostgreSQL says |
|---|---|---|
| Duplicate key | `ORA-00001` | `duplicate key value violates unique constraint` |
| NULL in a `NOT NULL` column | `ORA-01400` | `null value in column ... violates not-null constraint` |
| Missing parent | `ORA-02291` | `violates foreign key constraint` |
| Failed `CHECK` | `ORA-02290` | `violates check constraint` |

```sql error=ord_status_ck
INSERT INTO orders (order_id, customer_id, order_date, status)
VALUES (2000, 1, DATE '2024-07-01', 'LOST');
```

```text output
ERROR:  new row for relation "orders" violates check constraint "ord_status_ck"
DETAIL:  Failing row contains (2000, 1, null, 2024-07-01, LOST).
```

### Several rows at once

Multi-row `VALUES` works on PostgreSQL, MySQL and SQL Server, and on Oracle only from 23ai.

```sql postgres
INSERT INTO departments (dept_id, dept_name, location)
VALUES (70, 'Research', 'Berlin'),
       (80, 'Design', 'Milan');
```

On your Oracle 11g, write one `INSERT` per row.

### INSERT ... SELECT

This copies rows into a table that already exists. Columns match by position, not by name. `CREATE TABLE AS` ([Chapter 6](06-ddl-and-constraints.md)) creates the table, and this fills an existing one.

```sql
CREATE TABLE high_earners (
  emp_id      INTEGER,
  first_name  VARCHAR(30),
  salary      NUMERIC(10)
);

INSERT INTO high_earners (emp_id, first_name, salary)
SELECT emp_id, first_name, salary
FROM employees
WHERE salary >= 100000;

SELECT COUNT(*) AS copied FROM high_earners;
```

```text output
CREATE TABLE
INSERT 0 3
 copied
--------
      3
(1 row)
```

```sql
DROP TABLE high_earners;
```

## UPDATE

`SET` gives a new value, for the rows picked by `WHERE`. The new value can use the old one, and commas set several columns.

```sql
UPDATE employees
SET salary = salary * 1.10,
    job_title = 'Senior Sales Rep'
WHERE emp_id = 5;

SELECT first_name, job_title, salary FROM employees WHERE emp_id = 5;
```

```text output
UPDATE 1
 first_name |    job_title     | salary
------------+------------------+--------
 Lena       | Senior Sales Rep |  66000
(1 row)
```

`SET col = NULL` is legal, because this `=` assigns a value. It is not a comparison.

### No WHERE means every row

A forgotten `WHERE` changes the whole table. Here is the safe routine:

1. Run a `SELECT` with the same `WHERE`, and look at the rows.
2. Run the change inside a transaction.
3. Read the rows-affected count. Does it match?
4. Then `COMMIT`, or `ROLLBACK`.

### Swapping two columns

All right-hand sides read the row as it was **before** the statement. So `SET a = b, b = a` swaps two columns on Oracle, PostgreSQL and SQL Server. MySQL assigns left to right in a single-table `UPDATE`, so there both columns end up equal.

## DELETE

`DELETE` removes rows and leaves the table.

```sql
DELETE FROM payments WHERE payment_id = 13;
```

Deleting a parent that has children fails. Oracle gives `ORA-02292`.

```sql error=foreign
DELETE FROM customers WHERE customer_id = 1;
```

```text output
ERROR:  update or delete on table "customers" violates foreign key constraint "ord_cust_fk" on table "orders"
DETAIL:  Key (customer_id)=(1) is still referenced from table "orders".
```

To allow it, the foreign key needs `ON DELETE CASCADE` or `ON DELETE SET NULL` ([Chapter 6](06-ddl-and-constraints.md)), or you delete the children first.

## SAVEPOINT

`SAVEPOINT name` marks a spot. `ROLLBACK TO name` undoes the work after it, and keeps the rest.

```sql postgres
-- PostgreSQL
BEGIN;
UPDATE employees SET salary = 40000 WHERE emp_id = 12;
SAVEPOINT after_raise;
UPDATE employees SET salary = 1 WHERE emp_id = 12;
ROLLBACK TO after_raise;
SELECT salary FROM employees WHERE emp_id = 12;
ROLLBACK;
```

```text output
BEGIN
UPDATE 1
SAVEPOINT
UPDATE 1
ROLLBACK
 salary
--------
  40000
(1 row)

ROLLBACK
```

## DDL and transactions

**What happens to your uncommitted changes when you run a DDL statement?**

- On **Oracle and MySQL**, DDL commits implicitly, before and after it runs. So your pending changes are committed too, and cannot be rolled back.
- On **PostgreSQL and SQL Server**, most DDL can be rolled back inside a transaction.

This one fact explains the `TRUNCATE` difference below.

## TRUNCATE

`TRUNCATE TABLE t` removes every row at once, and keeps the table, its columns, constraints and indexes. It has no `WHERE`, and it is classed as DDL. Always write the word `TABLE`, because Oracle requires it.

**Why is it fast?** `DELETE` writes **undo** (old values kept for rollback) and **redo** (the change log) for every row, so it is slow on big tables, and the space stays with the table. `TRUNCATE` removes the storage in one operation, with very little logging.

**Can `TRUNCATE` be rolled back?** "No" is wrong as a blanket answer.

| Engine | Can it be rolled back? |
|---|---|
| Oracle, MySQL | No. It commits implicitly |
| PostgreSQL, SQL Server | Yes, inside a transaction |

```sql postgres
BEGIN;
TRUNCATE TABLE payments;
SELECT COUNT(*) AS rows_after_truncate FROM payments;
ROLLBACK;
SELECT COUNT(*) AS rows_after_rollback FROM payments;
```

```text output
BEGIN
TRUNCATE TABLE
 rows_after_truncate
---------------------
                   0
(1 row)

ROLLBACK
 rows_after_rollback
---------------------
                  13
(1 row)
```

**Why does `TRUNCATE` fail on a table with an empty child?** A table referenced by a foreign key generally cannot be truncated, even if the child is empty, because `TRUNCATE` does not check rows one by one. Oracle gives `ORA-02266`.

```sql error=truncate
TRUNCATE TABLE orders;
```

```text output
ERROR:  cannot truncate a table referenced in a foreign key constraint
DETAIL:  Table "order_items" references "orders".
HINT:  Truncate table "order_items" at the same time, or use TRUNCATE ... CASCADE.
```

From 12c, Oracle has `TRUNCATE ... CASCADE` when the foreign key is `ON DELETE CASCADE`. PostgreSQL also has `TRUNCATE ... CASCADE`.

**Triggers.** Row-level `ON DELETE` triggers do not fire for `TRUNCATE` ([Chapter 48](../part-7-plsql/48-triggers.md)).

**Identity columns.** SQL Server and MySQL reset the counter on `TRUNCATE`. PostgreSQL keeps counting unless you write `RESTART IDENTITY`. Oracle keeps counting.

## DELETE vs TRUNCATE vs DROP

This is one of the most asked questions in SQL interviews.

| | `DELETE` | `TRUNCATE` | `DROP` |
|---|---|---|---|
| Removes | Some or all rows | All rows | The whole table |
| Structure survives | Yes | Yes | No |
| `WHERE` | Yes | No | No |
| Class | DML | DDL | DDL |
| Logging | Every row | Minimal | Minimal |
| Speed on big tables | Slow | Fast | Fast |
| Rollback on Oracle, MySQL | Yes | No | No (Oracle: recycle bin) |
| Rollback on PostgreSQL, SQL Server | Yes | Yes | Yes |
| Row-level delete triggers fire | Yes | No | No |
| Blocked by a foreign key | Only if children exist | Yes, even if the child is empty | Yes |
| Space | Stays with the table | Released | Released |

**Which should you pick?** `DELETE` to remove some rows, or when triggers must fire. `TRUNCATE` to empty a table quickly. `DROP` when the table itself should go.

## Other things worth knowing

- **A failed statement.** On Oracle, only that statement is undone, and the transaction continues. On PostgreSQL, an error aborts the whole transaction until you `ROLLBACK`.
- **Leaving SQL*Plus.** `EXIT` commits pending work by default, which surprises people who expect a rollback.
- **Sequences are not transactional.** A value used by a rolled-back transaction is gone, so gaps are normal ([Chapter 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md)).
- **`MERGE`** updates matching rows and inserts the rest, and **`RETURNING`** gets generated keys back ([Chapter 18](../part-3-advanced-sql/18-advanced-dml.md)).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Forget `WHERE` on `UPDATE` or `DELETE` | Every row changes | Run a `SELECT` first, and use a transaction |
| Leave out the `INSERT` column list | It breaks when a column is added | Always list the columns |
| Assume psql waits for `COMMIT` | Each statement is permanent at once | Start with `BEGIN` |
| Run DDL with pending work on Oracle | The work is committed too | Commit or roll back first |
| Say `TRUNCATE` can never be rolled back | It can on PostgreSQL and SQL Server | Say it depends on the engine |
| Use `DELETE` to empty a huge table | It is slow, and space is not freed | Use `TRUNCATE` |
| Expect delete triggers to fire on `TRUNCATE` | They do not | Use `DELETE` if they must fire |
| Write `TRUNCATE t` on Oracle | A syntax error | Write `TRUNCATE TABLE t` |

## Interview questions

**Q1. What is the difference between DELETE, TRUNCATE and DROP?**

`DELETE` is DML. It removes chosen rows, logs each one, and fires triggers. `TRUNCATE` is DDL. It removes all rows quickly and keeps the table. `DROP` removes the table itself. `DELETE` can always be rolled back. `TRUNCATE` and `DROP` depend on the engine: no on Oracle and MySQL, and yes on PostgreSQL and SQL Server inside a transaction.

**Q2. Can TRUNCATE be rolled back?**

It depends on the engine. On Oracle and MySQL, no, because it commits implicitly. On PostgreSQL and SQL Server, yes, if it runs inside a transaction.

**Q3. What happens to space and undo in each case?**

`DELETE` writes undo and redo for every row, and the space stays with the table for reuse. `TRUNCATE` writes very little, and releases the space. `DROP` releases everything, and on Oracle the table goes to the recycle bin unless you use `PURGE`.

**Q4. What happens to your uncommitted changes when you run a DDL statement on Oracle, and on PostgreSQL?**

On Oracle, DDL commits implicitly, so they become permanent. On PostgreSQL, DDL takes part in the transaction, so it can all be rolled back together.

**Q5. Why can deleting all rows be slow while TRUNCATE is fast?**

`DELETE` processes each row: it writes undo and redo, updates every index, and fires triggers. `TRUNCATE` deallocates the storage in one step.

**Q6. Why does TRUNCATE fail on a table that has no rows in its child table?**

Because the check is on the foreign key definition, not the rows. `TRUNCATE` does not look at rows one by one. I would disable the constraint, use `DELETE`, or use `CASCADE` where the engine supports it.

**Q7. How do you make sure an UPDATE or DELETE changes only the rows you intended?**

I run a `SELECT` with the same `WHERE` first. Then I make the change in a transaction, check the rows-affected count, and only then commit.

## Practice

Use a transaction, and reload the data afterward if you need to.

**1. Add a new customer with only the required columns.**

<details>
<summary>Show solution</summary>

```sql
INSERT INTO customers (customer_id, customer_name, signup_date)
VALUES (9, 'Lina Costa', DATE '2024-07-01');
```

</details>

**2. Raise the price of all Books products by 10 percent.**

<details>
<summary>Show solution</summary>

```sql
UPDATE products
SET price = price * 1.10
WHERE category_id = 6;

SELECT product_name, price FROM products WHERE category_id = 6 ORDER BY product_id;
```

```text output
UPDATE 2
  product_name   | price
-----------------+-------
 SQL Basics      | 31.90
 Database Design | 49.50
(2 rows)
```

</details>

**3. Delete the customer you just added.**

<details>
<summary>Show solution</summary>

```sql
DELETE FROM customers WHERE customer_id = 9;
```

</details>

**4. Copy all CANCELLED orders into a new table `cancelled_orders`, then remove that table.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE cancelled_orders AS
SELECT order_id, customer_id, order_date
FROM orders
WHERE status = 'CANCELLED';

SELECT order_id, customer_id FROM cancelled_orders;
```

```text output
SELECT 1
 order_id | customer_id
----------+-------------
     1006 |           2
(1 row)
```

```sql
DROP TABLE cancelled_orders;
```

</details>

## Recap

- Always write the `INSERT` column list.
- Run a `SELECT` with the same `WHERE` before any `UPDATE` or `DELETE`.
- SQL*Plus holds changes until `COMMIT`. psql commits each statement unless you use `BEGIN`.
- DDL commits implicitly on Oracle and MySQL.
- `TRUNCATE` is DDL. It is fast, has no `WHERE`, and needs no row logging.
- `TRUNCATE` can be rolled back on PostgreSQL and SQL Server, but not on Oracle and MySQL.
- `DELETE` keeps the structure and fires triggers. `DROP` removes the table.

**Next:** [Chapter 8: SELECT](08-select-filter-sort.md)
