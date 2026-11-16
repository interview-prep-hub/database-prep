# 6. Creating Tables and Constraints

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 5](../part-1-foundations/05-data-types-and-null.md)

> **In one line:** DDL statements define the structure of the database, and constraints are the rules that keep its data correct.

## What you will learn

- `CREATE TABLE`, and how to write every kind of constraint
- Why you should name your constraints
- Column-level vs table-level syntax
- `ALTER TABLE` and `DROP TABLE`, with the Oracle and PostgreSQL differences
- How to copy a table, and what the copy leaves behind

**DDL** (Data Definition Language) means `CREATE`, `ALTER`, `DROP`, `RENAME` and `TRUNCATE`. These define or remove objects. **DML** ([Chapter 7](07-dml-insert-update-delete.md)) changes rows. [Chapter 2](../part-1-foundations/02-relational-model-and-keys.md) explains what each constraint means. This chapter shows how to write them.

## CREATE TABLE

Each column gets a name, a data type and optional rules.

```sql
CREATE TABLE courses (
  course_id   INTEGER,
  title       VARCHAR(100),
  fee         NUMERIC(8,2),
  start_date  DATE
);

INSERT INTO courses (course_id, title, fee, start_date)
VALUES (1, 'SQL Basics', 150.00, DATE '2024-09-01');

SELECT course_id, title, fee, start_date FROM courses;
```

```text output
CREATE TABLE
INSERT 0 1
 course_id |   title    |  fee   | start_date
-----------+------------+--------+------------
         1 | SQL Basics | 150.00 | 2024-09-01
(1 row)
```

These types run on both engines. Real Oracle code uses `VARCHAR2` ([Chapter 5](../part-1-foundations/05-data-types-and-null.md)).

**Naming rules:** start with a letter, and use letters, digits and underscores. Avoid reserved words such as `order`, `group`, `user` and `date`. Unquoted names fold to upper case on Oracle and to lower case on PostgreSQL, so `emp_id` and `EMP_ID` are the same name. Quoted names are case-sensitive, which causes endless trouble, so avoid quotes.

**`DEFAULT`** supplies a value when an `INSERT` leaves the column out. An explicit NULL stays NULL. Write `DEFAULT` before `NOT NULL`, because Oracle rejects the other order.

```sql
DROP TABLE courses;

CREATE TABLE courses (
  course_id  INTEGER,
  title      VARCHAR(100),
  seats      INTEGER DEFAULT 30 NOT NULL
);

INSERT INTO courses (course_id, title) VALUES (1, 'SQL Basics');

SELECT course_id, seats FROM courses;
```

```text output
DROP TABLE
CREATE TABLE
INSERT 0 1
 course_id | seats
-----------+-------
         1 |    30
(1 row)
```

```sql
DROP TABLE courses;
```

## Naming constraints

Give every constraint a name, with the word `CONSTRAINT`, as the sample schema does (`emp_salary_ck`, `ord_cust_fk`).

Why?

- The error message then names the rule that broke.
- You need the name to drop or disable the constraint.
- Unnamed constraints get names like `SYS_C0012345` on Oracle, which tell you nothing.

## Column-level vs table-level constraints

A **column-level** constraint sits on the column's line. A **table-level** constraint sits after all the columns. Composite keys, and `CHECK` rules across several columns, must be table-level.

```sql
CREATE TABLE enrollments (
  student_id   INTEGER NOT NULL,                       -- column level
  course_id    INTEGER NOT NULL,
  start_date   DATE,
  end_date     DATE,
  CONSTRAINT enroll_pk PRIMARY KEY (student_id, course_id),   -- table level
  CONSTRAINT enroll_dates_ck CHECK (end_date >= start_date)   -- table level
);
```

## PRIMARY KEY

A primary key is unique and never NULL. The database creates a unique index for it automatically.

```sql
CREATE TABLE students (
  student_id  INTEGER CONSTRAINT stu_pk PRIMARY KEY,
  email       VARCHAR(100) CONSTRAINT stu_email_uk UNIQUE,
  age         INTEGER CONSTRAINT stu_age_ck CHECK (age >= 16)
);

INSERT INTO students VALUES (1, 'a@example.com', 20);
```

A duplicate key fails. Oracle gives `ORA-00001: unique constraint violated`.

```sql error=duplicate
INSERT INTO students VALUES (1, 'b@example.com', 21);
```

```text output
ERROR:  duplicate key value violates unique constraint "stu_pk"
DETAIL:  Key (student_id)=(1) already exists.
```

So does a NULL key. Oracle gives `ORA-01400: cannot insert NULL`.

```sql error=null
INSERT INTO students VALUES (NULL, 'c@example.com', 22);
```

```text output
ERROR:  null value in column "student_id" of relation "students" violates not-null constraint
DETAIL:  Failing row contains (null, c@example.com, 22).
```

## UNIQUE

`UNIQUE` allows no duplicates, but unlike a primary key it allows NULLs, and a table can have many unique constraints.

```sql error=stu_email_uk
INSERT INTO students VALUES (2, 'a@example.com', 22);
```

```text output
ERROR:  duplicate key value violates unique constraint "stu_email_uk"
DETAIL:  Key (email)=(a@example.com) already exists.
```

Most engines allow many NULLs in a unique column. PostgreSQL 15 added `UNIQUE NULLS NOT DISTINCT`, which allows only one. On Oracle, in a multi-column unique key, two rows with a NULL and the same values in the other columns do conflict. SQL Server allows only one NULL.

## CHECK

`CHECK` enforces a rule on a row.

```sql error=stu_age_ck
INSERT INTO students VALUES (3, 'd@example.com', 12);
```

```text output
ERROR:  new row for relation "students" violates check constraint "stu_age_ck"
DETAIL:  Failing row contains (3, d@example.com, 12).
```

A NULL passes a `CHECK`, because the test is UNKNOWN, not FALSE. So pair it with `NOT NULL` when a value is required.

```sql
INSERT INTO students VALUES (3, 'd@example.com', NULL);
```

A `CHECK` cannot contain a subquery, or read another table.

## FOREIGN KEY

A foreign key says a value must exist in a parent table. The parent must exist first, and the target must be a `PRIMARY KEY` or `UNIQUE` column. Oracle gives `ORA-02270` otherwise.

```sql
CREATE TABLE results (
  result_id   INTEGER CONSTRAINT res_pk PRIMARY KEY,
  student_id  INTEGER NOT NULL,
  score       INTEGER,
  CONSTRAINT res_student_fk FOREIGN KEY (student_id)
    REFERENCES students (student_id) ON DELETE CASCADE
);

INSERT INTO results VALUES (1, 1, 90);
```

A value with no parent fails. Oracle gives `ORA-02291`.

```sql error=foreign
INSERT INTO results VALUES (2, 99, 80);
```

```text output
ERROR:  insert or update on table "results" violates foreign key constraint "res_student_fk"
DETAIL:  Key (student_id)=(99) is not present in table "students".
```

### ON DELETE options

| Option | When a parent row is deleted | Use it when |
|---|---|---|
| (none) | The delete fails | The default, and the safest |
| `ON DELETE CASCADE` | Child rows are deleted too | Children mean nothing without the parent, such as order lines |
| `ON DELETE SET NULL` | The child's key becomes NULL | The child can live on without a parent |

Oracle offers only `CASCADE` and `SET NULL`, and has no `ON UPDATE` action. PostgreSQL also has `RESTRICT`, `SET DEFAULT` and `ON UPDATE` actions.

```sql
DELETE FROM students WHERE student_id = 1;

SELECT COUNT(*) AS results_left FROM results;
```

```text output
DELETE 1
 results_left
--------------
            0
(1 row)
```

**Note:** a foreign key does not get an index automatically on Oracle or PostgreSQL. You usually want one ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)).

## ALTER TABLE

The syntax differs by engine.

| Task | Oracle | PostgreSQL |
|---|---|---|
| Add a column | `ADD phone VARCHAR2(20)` | `ADD COLUMN phone VARCHAR(20)` |
| Change a type | `MODIFY phone VARCHAR2(30)` | `ALTER COLUMN phone TYPE VARCHAR(30)` |
| Add NOT NULL | `MODIFY phone NOT NULL` | `ALTER COLUMN phone SET NOT NULL` |

These are the same on both: `RENAME COLUMN a TO b`, `DROP COLUMN c`, and `RENAME TO new_name`.

**PostgreSQL:**

```sql postgres
ALTER TABLE students ADD COLUMN phone VARCHAR(20);
ALTER TABLE students ALTER COLUMN phone TYPE VARCHAR(30);
```

**Oracle:**

```sql oracle
ALTER TABLE students ADD phone VARCHAR2(20);
ALTER TABLE students MODIFY phone VARCHAR2(30);
```

**Both:**

```sql
ALTER TABLE students RENAME COLUMN phone TO mobile;
ALTER TABLE students DROP COLUMN mobile;
```

### Adding a constraint later

Adding a constraint checks the rows already there, so old bad data makes it fail.

```sql
ALTER TABLE students ADD CONSTRAINT stu_age_min CHECK (age >= 18);
ALTER TABLE students DROP CONSTRAINT stu_age_min;
```

On a large table, you can skip the check of old rows: `ENABLE NOVALIDATE` on Oracle, or `NOT VALID` on PostgreSQL.

### Adding a NOT NULL column to a table with rows

**What happens?** It fails without a `DEFAULT`, because the existing rows would hold NULL. Oracle gives `ORA-01758`.

```sql postgres error=contains
ALTER TABLE students ADD COLUMN city VARCHAR(30) NOT NULL;
```

```text output
ERROR:  column "city" of relation "students" contains null values
```

With a `DEFAULT`, it works, and the existing rows get that value.

```sql postgres
ALTER TABLE students ADD COLUMN city VARCHAR(30) DEFAULT 'Unknown' NOT NULL;

SELECT student_id, city FROM students ORDER BY student_id;
```

```text output
ALTER TABLE
 student_id |  city
------------+---------
          3 | Unknown
(1 row)
```

## DROP TABLE

`DROP TABLE` removes the rows and the structure. It fails while another table's foreign key points at it. Oracle gives `ORA-02449`.

```sql error=depend
DROP TABLE students;
```

```text output
ERROR:  cannot drop table students because other objects depend on it
DETAIL:  constraint res_student_fk on table results depends on table students
HINT:  Use DROP ... CASCADE to drop the dependent objects too.
```

The fix is `CASCADE CONSTRAINTS` on Oracle, or `CASCADE` on PostgreSQL. Both remove the foreign key, and not the child table. Or you can drop the child first.

```sql
DROP TABLE results;
DROP TABLE students;
DROP TABLE enrollments;
```

**How do you get back a table you dropped by mistake on Oracle?** Oracle keeps dropped tables in the recycle bin:

```sql oracle
FLASHBACK TABLE employees_copy TO BEFORE DROP;
```

`DROP TABLE t PURGE` skips the recycle bin, and then the table cannot be recovered this way. PostgreSQL has no recycle bin.

## Copying a table

**With its data:**

```sql
CREATE TABLE dept_copy AS
SELECT dept_id, dept_name, location FROM departments;

SELECT COUNT(*) AS copied FROM dept_copy;
```

```text output
SELECT 5
 copied
--------
      5
(1 row)
```

**Structure only:** add a condition that is never true, so the `SELECT` returns no rows.

```sql
CREATE TABLE dept_empty AS
SELECT dept_id, dept_name, location FROM departments WHERE 1 = 0;

SELECT COUNT(*) AS copied FROM dept_empty;
```

```text output
SELECT 0
 copied
--------
      0
(1 row)
```

PostgreSQL also has `WITH NO DATA`.

### What a copy leaves behind

`CREATE TABLE AS` copies data and column types. It **does not** copy primary keys, unique constraints, foreign keys, `CHECK` constraints, defaults or indexes.

Oracle carries over only `NOT NULL` constraints explicitly declared on columns selected as they are. So the `NOT NULL` implied by a primary key is lost.

```sql postgres
SELECT COUNT(*) AS constraints_on_copy
FROM pg_constraint
WHERE conrelid = 'dept_copy'::regclass;
```

```text output
 constraints_on_copy
---------------------
                   0
(1 row)
```

**Closer clones:** PostgreSQL's `CREATE TABLE new (LIKE old INCLUDING ALL)` copies defaults, `CHECK` and `NOT NULL` constraints and indexes, but never foreign keys. MySQL's `CREATE TABLE new LIKE old` copies the definition and indexes.

```sql
DROP TABLE dept_copy;
DROP TABLE dept_empty;
```

## Other things you should know

**Auto-numbered keys.** A sequence hands out numbers, and an identity column (`GENERATED ALWAYS AS IDENTITY`, Oracle 12c and later, PostgreSQL 10 and later) uses one for you ([Chapter 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md)).

**Generated columns** compute their value from other columns: Oracle virtual columns from 11g, and PostgreSQL generated columns.

**Deferrable constraints.** `DEFERRABLE INITIALLY DEFERRED` waits until `COMMIT` to check, which helps when two tables reference each other.

**Looking at what you built.** `DESCRIBE t` in SQL*Plus, or `\d t` in psql. On Oracle, the views `USER_TABLES`, `USER_TAB_COLUMNS` and `USER_CONSTRAINTS` list everything.

**What is a schema?** On Oracle, a schema is a user and the objects it owns. On PostgreSQL, a schema is a named folder inside a database.

**`IF [NOT] EXISTS`** on `CREATE` and `DROP` works on PostgreSQL, and on Oracle from 23ai.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Leave constraints unnamed | Errors show `SYS_C0012345` | Name every constraint |
| Write `NOT NULL DEFAULT 0` on Oracle | A syntax error | Write `DEFAULT 0 NOT NULL` |
| Use reserved words as names | Errors, or forced quoting | Choose other names |
| Quote names | They become case-sensitive | Do not quote |
| Add `NOT NULL` with no `DEFAULT` to a filled table | It fails | Add a `DEFAULT`, or backfill first |
| Forget that NULL passes a `CHECK` | Missing values get in | Add `NOT NULL` too |
| Assume `CREATE TABLE AS` copies constraints | The copy has no rules | Add them afterward |
| Forget to index foreign keys | Slow joins and locking issues | Add an index |
| Use `ON DELETE CASCADE` everywhere | One delete can remove far too much | Use it only for true child rows |

## Interview questions

**Q1. Write a query to copy one table into another, first with its data and then without its data.**

With data: `CREATE TABLE new AS SELECT * FROM old`. Without data: add `WHERE 1 = 0`, so that no rows come back but the columns are still created. On PostgreSQL, `WITH NO DATA` also works.

**Q2. Which constraints does CREATE TABLE AS SELECT copy to the new table?**

Almost none. It copies the data and column types. Primary keys, unique constraints, foreign keys, checks, defaults and indexes are not copied. Oracle keeps only explicitly declared `NOT NULL` constraints on columns selected as they are.

**Q3. What is the difference between a column-level and a table-level constraint?**

A column-level constraint is written on the column's line and applies to that column. A table-level constraint is written after the columns. Composite keys and `CHECK` rules across several columns must be table-level. `NOT NULL` is written at column level.

**Q4. What happens when you add a NOT NULL column to a table that already has rows?**

It fails without a `DEFAULT`, because the existing rows would hold NULL. With a `DEFAULT`, it works, and existing rows get that value.

**Q5. How do you add a constraint to a table that already holds data, and what can go wrong?**

`ALTER TABLE ... ADD CONSTRAINT`. It checks the existing rows, so bad old data makes it fail, and on a large table the check takes time. I would fix the data first, or add it without checking old rows: `NOVALIDATE` on Oracle, or `NOT VALID` on PostgreSQL, then validate later.

**Q6. How do you get back a table you dropped by mistake on Oracle?**

`FLASHBACK TABLE t TO BEFORE DROP`, using the recycle bin. It does not work if the table was dropped with `PURGE`. Otherwise you restore from a backup.

## Practice

**1. Create a table `suppliers` with an id primary key, a required name, a unique email, and a rating from 1 to 5. Name all the constraints.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE suppliers (
  supplier_id  INTEGER CONSTRAINT sup_pk PRIMARY KEY,
  name         VARCHAR(60) NOT NULL,
  email        VARCHAR(60) CONSTRAINT sup_email_uk UNIQUE,
  rating       INTEGER CONSTRAINT sup_rating_ck CHECK (rating BETWEEN 1 AND 5)
);
```

</details>

**2. Add a foreign key from a new table `supplies` to `suppliers` and `products`, with a composite primary key.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE supplies (
  supplier_id  INTEGER NOT NULL,
  product_id   INTEGER NOT NULL,
  CONSTRAINT supplies_pk PRIMARY KEY (supplier_id, product_id),
  CONSTRAINT supplies_sup_fk FOREIGN KEY (supplier_id) REFERENCES suppliers (supplier_id),
  CONSTRAINT supplies_prod_fk FOREIGN KEY (product_id) REFERENCES products (product_id)
);
```

</details>

**3. Try to insert a supplier with a rating of 9. What error do you get?**

<details>
<summary>Show solution</summary>

```sql error=sup_rating_ck
INSERT INTO suppliers VALUES (1, 'Acme', 'acme@example.com', 9);
```

```text output
ERROR:  new row for relation "suppliers" violates check constraint "sup_rating_ck"
DETAIL:  Failing row contains (1, Acme, acme@example.com, 9).
```

On Oracle this is `ORA-02290: check constraint violated`.

</details>

**4. Copy `products` into `products_backup` with its data, then remove both new tables and the backup.**

<details>
<summary>Show solution</summary>

```sql
CREATE TABLE products_backup AS
SELECT product_id, product_name, price FROM products;

DROP TABLE products_backup;
DROP TABLE supplies;
DROP TABLE suppliers;
```

Drop `supplies` before `suppliers`, because `supplies` has a foreign key to it.

</details>

## Recap

- `CREATE TABLE` defines columns, types and rules.
- Name every constraint, so that errors explain themselves.
- Composite keys and multi-column checks must be table-level.
- `DEFAULT` goes before `NOT NULL`.
- A NULL passes a `CHECK`.
- `ALTER` syntax differs: `MODIFY` on Oracle, `ALTER COLUMN` on PostgreSQL.
- `CREATE TABLE AS` does not copy constraints or indexes.
- On Oracle, `FLASHBACK TABLE ... TO BEFORE DROP` undoes a drop.

**Next:** [Chapter 7: Changing data](07-dml-insert-update-delete.md)
