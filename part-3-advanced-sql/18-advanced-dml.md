# 18. Advanced Data Changes: Upsert, MERGE, RETURNING and Removing Duplicates

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 7](../part-2-sql-basics/07-dml-insert-update-delete.md) and [Chapter 15](15-window-functions-ranking-and-offset.md)

> **In one line:** These tools change data based on other data, safely, in one statement.

## What you will learn

- How to update one table from another on each engine
- Why "SELECT, then INSERT" is unsafe, and what to write instead
- `MERGE`, and its rules
- `RETURNING`, and Oracle's multi-table `INSERT`
- How to find duplicates, and delete them while keeping one

## Updating from another table

The portable way uses a correlated subquery. The `WHERE EXISTS` matters: without it, every row with no match is set to NULL.

```sql
CREATE TABLE price_updates (
  product_id  INTEGER PRIMARY KEY,
  new_price   NUMERIC(10,2) NOT NULL
);

INSERT INTO price_updates VALUES (1, 749.00);
INSERT INTO price_updates VALUES (2, 379.00);
```

```sql
UPDATE products p
SET price = (SELECT u.new_price FROM price_updates u WHERE u.product_id = p.product_id)
WHERE EXISTS (SELECT 1 FROM price_updates u WHERE u.product_id = p.product_id);

SELECT product_id, price FROM products WHERE product_id <= 3 ORDER BY product_id;
```

```text output
UPDATE 2
 product_id | price
------------+--------
          1 | 749.00
          2 | 379.00
          3 |  19.99
(3 rows)
```

Each engine also has a shorter form:

| Engine | Update with a join | Delete with a join |
|---|---|---|
| PostgreSQL | `UPDATE t SET ... FROM s WHERE ...` | `DELETE FROM t USING s WHERE ...` |
| SQL Server | `UPDATE t SET ... FROM t JOIN s ...` | `DELETE t FROM t JOIN s ...` |
| MySQL | `UPDATE t JOIN s ON ... SET ...` | `DELETE t FROM t JOIN s ...` |
| Oracle before 23ai | `MERGE`, a correlated subquery, or an updatable inline view | A subquery |

**PostgreSQL:**

```sql postgres
UPDATE products p
SET price = u.new_price
FROM price_updates u
WHERE u.product_id = p.product_id;
```

**One target row, two source rows.** If the join gives a target row two matches, Oracle raises `ORA-30926`, while PostgreSQL's `UPDATE ... FROM` silently uses just one of them, with no error. So make sure the join gives each target row one source row.

### Updatable inline view on Oracle

Oracle can update through a join in an inline view, if the table being changed is **key-preserved**: each of its rows appears at most once in the join. Otherwise you get `ORA-01779`.

```sql oracle
UPDATE (SELECT p.price, u.new_price
        FROM products p
        JOIN price_updates u ON u.product_id = p.product_id)
SET price = new_price;
```

This works because `u.product_id` is the primary key of `price_updates`, so each product appears at most once.

## Why SELECT, then INSERT is unsafe

An **upsert** means "insert, or update if it already exists". The tempting way is to check first:

```text
Session A: SELECT ... -> no row
Session B: SELECT ... -> no row
Session A: INSERT     -> ok
Session B: INSERT     -> unique violation, or a duplicate if there is no constraint
```

The gap between the check and the write is a **race condition**. The fix is one atomic statement, backed by a unique constraint.

### PostgreSQL: ON CONFLICT

```sql postgres
INSERT INTO departments (dept_id, dept_name, location)
VALUES (20, 'Sales', 'Paris')
ON CONFLICT (dept_id) DO UPDATE SET location = EXCLUDED.location;

SELECT dept_name, location FROM departments WHERE dept_id = 20;
```

```text output
INSERT 0 1
 dept_name | location
-----------+----------
 Sales     | Paris
(1 row)
```

`EXCLUDED` is the row you tried to insert. `DO NOTHING` skips the row instead. It needs a unique index or constraint on the key.

### MySQL

`INSERT ... ON DUPLICATE KEY UPDATE`, `INSERT IGNORE`, and `REPLACE`. `REPLACE` deletes and re-inserts the row, so it can change an auto-increment id and fire delete triggers. It is not a true update.

## MERGE

`MERGE` matches source rows to target rows, updates the matches, and inserts the rest. It exists on Oracle, SQL Server, and PostgreSQL from 15.

```sql
MERGE INTO products p
USING price_updates u
ON (p.product_id = u.product_id)
WHEN MATCHED THEN
  UPDATE SET price = u.new_price
WHEN NOT MATCHED THEN
  INSERT (product_id, product_name, category_id, price)
  VALUES (u.product_id, 'New product', 1, u.new_price);

SELECT product_id, price FROM products WHERE product_id <= 2 ORDER BY product_id;
```

```text output
MERGE 2
 product_id | price
------------+--------
          1 | 749.00
          2 | 379.00
(2 rows)
```

Oracle's `USING` can be `SELECT ... FROM dual` for a one-row upsert:

```sql oracle
MERGE INTO departments d
USING (SELECT 60 AS dept_id, 'Support' AS dept_name, 'Oslo' AS location FROM dual) s
ON (d.dept_id = s.dept_id)
WHEN MATCHED THEN UPDATE SET d.location = s.location
WHEN NOT MATCHED THEN INSERT (dept_id, dept_name, location)
                      VALUES (s.dept_id, s.dept_name, s.location);
```

### MERGE rules

- A target row matched by two source rows is an error: `ORA-30926` on Oracle, and `MERGE command cannot affect row a second time` on PostgreSQL. Make the source unique on the key first.
- Oracle cannot update a column used in the `ON` clause (`ORA-38104`).
- `MERGE` is **not** automatically safe under concurrency. Two sessions inserting the same key can still get a unique violation. Keep the constraint, and be ready to retry.

**Oracle extras:** a `MERGE` can have only an update branch or only an insert branch, which is a common way to update from a join on 11g. Inserts and updates each fire their own triggers.

## RETURNING

`RETURNING` gets back the rows you just changed, with no second query.

**PostgreSQL** returns them as a result. Version 18 adds `old.col` and `new.col`.

```sql postgres
UPDATE employees
SET salary = salary + 1000
WHERE emp_id = 11
RETURNING emp_id, salary;
```

```text output
 emp_id | salary
--------+--------
     11 |  59000
(1 row)

UPDATE 1
```

**Oracle** fills variables, using `RETURNING ... INTO`:

```sql oracle
DECLARE
  v_salary employees.salary%TYPE;
BEGIN
  UPDATE employees
  SET salary = salary + 1000
  WHERE emp_id = 11
  RETURNING salary INTO v_salary;

  DBMS_OUTPUT.PUT_LINE('New salary: ' || v_salary);
  ROLLBACK;
END;
/
```

```text output
New salary: 59000
```

**How would you tell which rows a MERGE inserted and which it updated?** PostgreSQL 17 and later has `RETURNING merge_action()`. SQL Server has `OUTPUT $action`. Oracle has no such function. A common Oracle trick is to count: compare the rows that existed before with the total merged, or set a flag column in each branch.

## Multi-table INSERT on Oracle

One source row can feed several tables.

| Form | Behavior |
|---|---|
| `INSERT ALL` (no `WHEN`) | Every `INTO` runs for every source row |
| `INSERT ALL` with `WHEN` | Every true `WHEN` runs |
| `INSERT FIRST` | Only the first true `WHEN` runs |

```sql oracle
INSERT ALL
  WHEN salary >= 100000 THEN INTO high_paid (emp_id, salary) VALUES (emp_id, salary)
  WHEN dept_id = 20     THEN INTO sales_staff (emp_id) VALUES (emp_id)
SELECT emp_id, salary, dept_id FROM employees;
```

### PostgreSQL's alternative

A data-modifying CTE. Each part runs exactly once, and they all see one snapshot, so they cannot see each other's changes.

```sql postgres
CREATE TABLE archived_payments AS SELECT * FROM payments WHERE 1 = 0;

WITH moved AS (
  DELETE FROM payments
  WHERE payment_date < DATE '2024-02-01'
  RETURNING *
)
INSERT INTO archived_payments
SELECT * FROM moved;

SELECT COUNT(*) AS archived FROM archived_payments;
```

```text output
SELECT 0
INSERT 0 3
 archived
----------
        3
(1 row)
```

```sql postgres
DROP TABLE archived_payments;
```

## Finding and removing duplicates

**First, decide what "duplicate" means.** The same whole row, or the same business key?

```sql
CREATE TABLE contacts (
  contact_id  INTEGER PRIMARY KEY,
  email       VARCHAR(60) NOT NULL,
  name        VARCHAR(60),
  updated_at  DATE NOT NULL
);

INSERT INTO contacts VALUES (1, 'a@example.com', 'Asha', DATE '2024-01-01');
INSERT INTO contacts VALUES (2, 'a@example.com', 'Asha K', DATE '2024-03-01');
INSERT INTO contacts VALUES (3, 'b@example.com', 'Ben', DATE '2024-02-01');
INSERT INTO contacts VALUES (4, 'a@example.com', 'A Khan', DATE '2024-02-01');
```

**Find the duplicate keys:**

```sql
SELECT email, COUNT(*) AS copies
FROM contacts
GROUP BY email
HAVING COUNT(*) > 1;
```

```text output
     email     | copies
---------------+--------
 a@example.com |      3
(1 row)
```

**See the full rows, and pick one to keep.** `ROW_NUMBER` partitions by the business key, and the sort decides which row wins.

```sql
SELECT contact_id, email, name, updated_at,
       ROW_NUMBER() OVER (PARTITION BY email ORDER BY updated_at DESC, contact_id DESC) AS rn
FROM contacts
ORDER BY email, rn;
```

```text output
 contact_id |     email     |  name  | updated_at | rn
------------+---------------+--------+------------+----
          2 | a@example.com | Asha K | 2024-03-01 |  1
          4 | a@example.com | A Khan | 2024-02-01 |  2
          1 | a@example.com | Asha   | 2024-01-01 |  3
          3 | b@example.com | Ben    | 2024-02-01 |  1
(4 rows)
```

`SELECT DISTINCT` is not enough here. It removes only rows equal in every selected column, so rows that differ in `name` all stay.

**Handling duplicates without DISTINCT:** `GROUP BY`, `ROW_NUMBER`, `UNION` (which removes duplicates), or `EXISTS` instead of a join that fans out. Often the real fix is the join that created them.

### Delete duplicates, keep one copy

With a primary key, delete everything ranked after the first:

```sql
DELETE FROM contacts
WHERE contact_id IN (
  SELECT t.contact_id
  FROM (SELECT contact_id,
               ROW_NUMBER() OVER (PARTITION BY email
                                  ORDER BY updated_at DESC, contact_id DESC) AS rn
        FROM contacts) t
  WHERE t.rn > 1
);

SELECT contact_id, email FROM contacts ORDER BY contact_id;
```

```text output
DELETE 2
 contact_id |     email
------------+---------------
          2 | a@example.com
          3 | b@example.com
(2 rows)
```

If rows are exact copies with no key, use the row's physical address.

**Oracle:**

```sql oracle
DELETE FROM contacts
WHERE ROWID NOT IN (SELECT MIN(ROWID) FROM contacts GROUP BY email);
```

**PostgreSQL:** the same with `ctid`.

```sql postgres
DELETE FROM contacts c
USING contacts d
WHERE c.email = d.email
  AND c.ctid > d.ctid;
```

**After cleaning, add the unique constraint,** so that the duplicates cannot come back.

```sql
ALTER TABLE contacts ADD CONSTRAINT contacts_email_uk UNIQUE (email);
DROP TABLE contacts;
DROP TABLE price_updates;
```

On a very large table, one huge `DELETE` writes a lot of undo and log, and holds locks for a long time. Delete in batches by key range, or copy the rows to keep into a new table and swap.

### Oracle DML error logging

`LOG ERRORS INTO err_table` lets a big `INSERT` or `UPDATE` carry on past bad rows, and records them. Create the table with `DBMS_ERRLOG.CREATE_ERROR_LOG`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Update from a subquery with no `WHERE EXISTS` | Unmatched rows become NULL | Add `WHERE EXISTS` |
| Join to a source with duplicate keys | `ORA-30926`, or a silently wrong value on PostgreSQL | Make the source unique |
| Use SELECT then INSERT for an upsert | A race condition | Use `ON CONFLICT` or `MERGE`, with a unique constraint |
| Think `MERGE` is concurrency-safe | Unique violations can still happen | Keep the constraint, and retry |
| Use `REPLACE` on MySQL as an update | The row is deleted and re-inserted | Use `ON DUPLICATE KEY UPDATE` |
| Use `DISTINCT` to deduplicate on a business key | Rows that differ in other columns stay | Use `ROW_NUMBER` |
| Delete duplicates and stop there | They come back | Add a unique constraint |
| Run one huge `DELETE` | Long locks, and heavy logging | Delete in batches |

## Interview questions

**Q1. Delete duplicate rows but keep one copy.**

If there is a primary key, I number rows with `ROW_NUMBER() OVER (PARTITION BY key ORDER BY ...)` and delete those with `rn > 1`. For exact copies with no key, I use `ROWID` on Oracle: `DELETE ... WHERE ROWID NOT IN (SELECT MIN(ROWID) ... GROUP BY key)`, or `ctid` on PostgreSQL. Then I add a unique constraint.

**Q2. How can you handle duplicates in a query without using DISTINCT?**

`GROUP BY` the columns, or use `ROW_NUMBER` and keep `rn = 1`, or `UNION`, which removes duplicates. If a join caused them, I fix the join: use `EXISTS` instead, or aggregate the child table first.

**Q3. How do you write an upsert, and why not SELECT-then-INSERT?**

On PostgreSQL, `INSERT ... ON CONFLICT DO UPDATE`. On Oracle and SQL Server, `MERGE`. On MySQL, `ON DUPLICATE KEY UPDATE`. SELECT-then-INSERT has a race: two sessions can both see no row, and both insert. I still keep a unique constraint, because that is what truly guarantees it.

**Q4. How would you tell which rows a MERGE inserted and which it updated?**

PostgreSQL 17 and later has `RETURNING merge_action()`, and SQL Server has `OUTPUT $action`. On Oracle there is no direct function, so I would compare counts, or set a marker column in each branch.

**Q5. What is a key-preserved table?**

In an Oracle join view, a table is key-preserved when each of its rows appears at most once in the join, usually because the other table is joined on its primary key. Only such a table can be updated through the join. Otherwise you get `ORA-01779`.

## Practice

**1. Set each product's stock to 0 if it has a row in a table of discontinued products. Create a small table and write the update.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE discontinued (product_id INTEGER PRIMARY KEY);
INSERT INTO discontinued VALUES (10);

UPDATE products
SET stock_qty = 0
WHERE product_id IN (SELECT d.product_id FROM discontinued d);

SELECT product_name, stock_qty FROM products WHERE product_id = 10;
```

```text output
CREATE TABLE
INSERT 0 1
UPDATE 1
 product_name | stock_qty
--------------+-----------
 Desk Lamp    |         0
(1 row)
```

```sql
DROP TABLE discontinued;
```

</details>

**2. Find customers who share a country, showing each country once with the number of customers, only where there are duplicates.**

<details>
<summary>Show solution</summary>

```sql
SELECT country, COUNT(*) AS customers
FROM customers
WHERE country IS NOT NULL
GROUP BY country
HAVING COUNT(*) > 1
ORDER BY country;
```

```text output
 country | customers
---------+-----------
 UAE     |         2
 UK      |         2
(2 rows)
```

</details>

**3. Show one row per city, keeping the customer who signed up first.**

<details>
<summary>Show solution</summary>

```sql
WITH ranked AS (
  SELECT customer_name, city, signup_date,
         ROW_NUMBER() OVER (PARTITION BY city ORDER BY signup_date, customer_id) AS rn
  FROM customers
  WHERE city IS NOT NULL
)
SELECT city, customer_name, signup_date
FROM ranked
WHERE rn = 1
ORDER BY city;
```

```text output
  city   | customer_name | signup_date
---------+---------------+-------------
 Dubai   | Bilal Ahmed   | 2023-02-03
 London  | Alice Morgan  | 2023-01-15
 Paris   | Chloe Martin  | 2023-02-20
 Tokyo   | Hana Sato     | 2023-09-14
 Toronto | David Lee     | 2023-04-11
(5 rows)
```

</details>

## Recap

- Update from another table with a correlated subquery plus `WHERE EXISTS`.
- SELECT then INSERT is a race. Use `ON CONFLICT` or `MERGE`, with a unique constraint.
- In `MERGE`, each target row may match only one source row.
- `RETURNING` gets changed rows back. Oracle needs `INTO`.
- `INSERT ALL` and `INSERT FIRST` feed several tables on Oracle.
- Delete duplicates with `ROW_NUMBER`, or `ROWID` or `ctid` for exact copies.
- Afterward, add a unique constraint.

**Next:** [Chapter 19: Views, materialized views and sequences](19-views-materialized-views-sequences.md)
