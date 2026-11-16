# 42. PL/SQL Basics: Blocks, Variables and Data Types

**Level:** Basic | **Interview priority:** Must know | **Before this:** Parts 2 and 3

> **In one line:** PL/SQL is Oracle's procedural language built around SQL, adding variables, logic, error handling and stored code.

## What you will learn

- The structure of a PL/SQL block
- How to run a block and see its output
- Variables, constants, `%TYPE` and `%ROWTYPE`
- `SELECT INTO`, and what can go wrong with it
- DML and transactions inside a block
- The column name trap

All the code in this part is Oracle. Run `@setup/oracle/session.sql` first, which turns on `DBMS_OUTPUT`.

## What is PL/SQL?

SQL is set-based: one statement says what you want. **PL/SQL** adds variables, `IF` and loops, error handling, and named stored code.

**How a block runs.** The PL/SQL engine runs the procedural statements, and sends each SQL statement to the SQL engine. Every trip between the two is a **context switch**, and each one has a cost.

```text
+------------------+     SQL statement    +-------------+
| PL/SQL engine    | -------------------> | SQL engine  |
| IF, loops,       | <------------------- |             |
| variables        |     rows, status     |             |
+------------------+                      +-------------+
```

**Where to do what.** If one SQL statement can do the job, write that statement. Reach for PL/SQL when you need step-by-step logic, error handling, or one API around several statements.

## Your first block

```sql oracle
BEGIN
  DBMS_OUTPUT.PUT_LINE('Hello from PL/SQL');
END;
/
```

```text output
Hello from PL/SQL
```

The final `/` on its own line sends the block to the database. Without it, SQL*Plus just waits.

`SET SERVEROUTPUT ON` shows the output, and `session.sql` does that for you.

**How `DBMS_OUTPUT` works.** It writes to a buffer, so nothing appears until the block returns to its caller. There is no flush. It is a debugging tool, not a logging system.

## Block anatomy

```sql norun
DECLARE      -- optional: variables, constants, cursors
  ...
BEGIN        -- mandatory: at least one statement
  ...
EXCEPTION    -- optional: error handlers
  ...
END;         -- mandatory
/
```

`BEGIN` needs at least one statement, and `NULL;` counts as one. You write the word `DECLARE` only for an anonymous block.

### Kinds of PL/SQL unit

Anonymous block, `PROCEDURE`, `FUNCTION`, `PACKAGE`, `PACKAGE BODY`, `TRIGGER`, `TYPE` and `TYPE BODY`. Only the anonymous block is not stored in the database.

### A first stored procedure

A stored unit uses `IS` or `AS`, never `DECLARE`.

```sql oracle
CREATE OR REPLACE PROCEDURE say_hello IS
  v_message VARCHAR2(30) := 'Hello';
BEGIN
  DBMS_OUTPUT.PUT_LINE(v_message);
END;
/

EXEC say_hello
```

```text output
Hello
```

| | Anonymous block | Stored subprogram |
|---|---|---|
| Name | None | Yes |
| Stored in the database | No | Yes, compiled |
| Reusable | No | Yes |
| Takes parameters | No | Yes |

### Compile errors

A stored unit with a mistake is still saved, but as **INVALID**. `SHOW ERRORS` lists the `PLS-` messages.

```sql oracle
CREATE OR REPLACE PROCEDURE broken IS
BEGIN
  no_such_thing := 1;
END;
/

SHOW ERRORS
```

The message is `PLS-00201: identifier 'NO_SUCH_THING' must be declared`. You can also query `USER_ERRORS`.

## Variables and constants

```sql oracle
DECLARE
  v_name    VARCHAR2(30) := 'Sara';
  v_count   PLS_INTEGER  DEFAULT 0;
  v_rate    CONSTANT NUMBER := 0.10;
  v_active  BOOLEAN := TRUE;
  v_today   DATE := DATE '2024-07-01';
BEGIN
  v_count := v_count + 1;
  DBMS_OUTPUT.PUT_LINE(v_name || ': ' || v_count);
END;
/
```

```text output
Sara: 1
```

Rules:

- One name per declaration.
- Every variable starts as NULL.
- `NOT NULL` and `CONSTANT` require an initial value.
- `:=` and `DEFAULT` mean the same thing in a declaration.
- An unquoted name is not case-sensitive. The length limit rose from 30 to 128 bytes in 12.2.

A common naming convention is `v_` for variables, `c_` for constants and cursors, and `p_` for parameters.

## Data types

| Type | Use |
|---|---|
| `NUMBER` | General numbers |
| `PLS_INTEGER` | Whole numbers in loops and counters |
| `VARCHAR2(n)` | Text |
| `CHAR(n)` | Fixed-length text, padded with blanks |
| `DATE`, `TIMESTAMP` | Dates and times |
| `BOOLEAN` | TRUE, FALSE or NULL |

**`CHAR` vs `VARCHAR2`.** `CHAR` pads with blanks. A comparison is blank-padded only when neither side is `VARCHAR2`, so a `CHAR` variable can fail to match a `VARCHAR2` one. Use `VARCHAR2` unless you have a reason.

**Limits differ between PL/SQL and SQL.**

| | PL/SQL variable | Table column |
|---|---|---|
| `VARCHAR2` | 32,767 bytes | 4,000 bytes (32,767 with `MAX_STRING_SIZE = EXTENDED`) |
| `CHAR` | 32,767 bytes | 2,000 bytes |

**When would you use `PLS_INTEGER` instead of `NUMBER`?** For whole-number counters and loop work. It is a 32-bit type that uses machine arithmetic, so it is faster and smaller. Overflow raises `ORA-01426`.

**`BOOLEAN`** holds TRUE, FALSE or NULL. Before 23ai, it is a PL/SQL-only type, so there are no `BOOLEAN` columns, and `DBMS_OUTPUT.PUT_LINE` cannot print one ([Chapter 43](43-control-structures.md) shows the workaround).

## %TYPE and %ROWTYPE

**`%TYPE`** gives a variable the type and size of a column or another variable, so your code survives a column change.

**`%ROWTYPE`** declares a **record**, one variable with a field for every column of a table.

```sql oracle
DECLARE
  v_salary  employees.salary%TYPE;
  v_emp     employees%ROWTYPE;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE emp_id = 2;
  SELECT * INTO v_emp FROM employees WHERE emp_id = 3;

  DBMS_OUTPUT.PUT_LINE('Salary: ' || v_salary);
  DBMS_OUTPUT.PUT_LINE(v_emp.first_name || ' is a ' || v_emp.job_title);
END;
/
```

```text output
Salary: 95000
Priya is a Engineering Manager
```

**If a column is declared `NOT NULL`, does a variable anchored to it with `%TYPE` inherit that?** No. From a table column it takes the type and size only. From another variable, it does inherit `NOT NULL`.

## Expressions and NULL

Most SQL functions (`UPPER`, `NVL`, `ROUND`, `TO_CHAR`) work directly in PL/SQL, and `||` joins text.

**NULL in expressions.** `||` ignores NULL, but arithmetic stays NULL. An uninitialized counter is the classic bug:

```sql oracle
DECLARE
  v_count NUMBER;           -- starts as NULL
BEGIN
  v_count := v_count + 1;   -- stays NULL, with no error
  DBMS_OUTPUT.PUT_LINE('Count: [' || v_count || ']');
END;
/
```

```text output
Count: []
```

**Any zero-length string is NULL in PL/SQL.** After `v := ''`, the variable is NULL.

**Conversions.** Prefer explicit `TO_CHAR`, `TO_DATE` and `TO_NUMBER`, with a format model.

**Sequences** work directly in an expression from 11.1: `v_id := my_seq.NEXTVAL;`.

## Scope in nested blocks

An inner block sees outer names, and an inner name hides an outer one. A label reaches the hidden variable.

```sql oracle
<<outer>>
DECLARE
  v_x NUMBER := 1;
BEGIN
  DECLARE
    v_x NUMBER := 2;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Inner: ' || v_x);
    DBMS_OUTPUT.PUT_LINE('Outer: ' || outer.v_x);
  END;
END;
/
```

```text output
Inner: 2
Outer: 1
```

## Host and substitution variables

A **host variable** lives in the tool, and a PL/SQL variable lives in the block.

```sql oracle
VARIABLE g_total NUMBER

BEGIN
  SELECT SUM(salary) INTO :g_total FROM employees WHERE dept_id = 40;
END;
/

PRINT g_total
```

```text output
   G_TOTAL
----------
    153000
```

A **substitution variable** (`&name`) is plain text that SQL*Plus pastes in before sending the code.

## SELECT INTO

`SELECT ... INTO` copies one row into variables or a record. The select list and the `INTO` list must match in number and type.

**The exactly-one-row rule:**

| Rows found | What happens |
|---|---|
| Exactly one | It works |
| None | `NO_DATA_FOUND` (`ORA-01403`) |
| More than one | `TOO_MANY_ROWS` (`ORA-01422`) |

```sql oracle
DECLARE
  v_name employees.first_name%TYPE;
BEGIN
  SELECT first_name INTO v_name FROM employees WHERE emp_id = 99;
  DBMS_OUTPUT.PUT_LINE(v_name);      -- never reached
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('No such employee');
END;
/
```

```text output
No such employee
```

Control jumps to `EXCEPTION`, so a test on the next line, such as `IF v_name IS NULL`, is never reached.

**Can `SELECT COUNT(*) INTO` ever raise `NO_DATA_FOUND`?** Not with no `GROUP BY`, because an aggregate with no `GROUP BY` always returns one row. Legal, with no employees, gives 0. With `GROUP BY`, it can return no rows, and then it does raise it.

```sql oracle
DECLARE
  v_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM employees WHERE dept_id = 50;
  DBMS_OUTPUT.PUT_LINE('Legal staff: ' || v_count);
END;
/
```

```text output
Legal staff: 0
```

A `SELECT` with no `INTO` is a compile error (`PLS-00428`). A query that can return many rows needs a cursor ([Chapter 44](44-cursors.md)) or `BULK COLLECT` ([Chapter 50](50-bulk-processing.md)).

## DML in a block

`INSERT`, `UPDATE`, `DELETE` and `MERGE` run unchanged, and variables can stand in for values.

```sql oracle
DECLARE
  v_raise employees.salary%TYPE := 1000;
BEGIN
  UPDATE employees SET salary = salary + v_raise WHERE emp_id = 11;
  DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' row updated');
  ROLLBACK;
END;
/
```

```text output
1 row updated
```

### The column name trap

The column wins over a local variable with the same name.

```sql oracle
DECLARE
  last_name employees.last_name%TYPE := 'Khan';
BEGIN
  DELETE FROM employees WHERE last_name = last_name;   -- deletes every row!
  ROLLBACK;
END;
/
```

`last_name = last_name` compares the column with itself. Use a prefix: `v_last_name`.

**Which SQL statements can you not write directly in a block?** DDL (`CREATE`, `ALTER`, `DROP`) and session control (`ALTER SESSION`), because they are not static SQL. Use `EXECUTE IMMEDIATE` with the statement in a string ([Chapter 51](51-dynamic-sql.md)). DDL also commits implicitly.

### RETURNING INTO

This reads values back from the row you just changed, in the same statement. Many rows need `BULK COLLECT`.

```sql oracle
DECLARE
  v_new employees.salary%TYPE;
BEGIN
  UPDATE employees SET salary = salary * 1.10
  WHERE emp_id = 12
  RETURNING salary INTO v_new;

  DBMS_OUTPUT.PUT_LINE('New salary: ' || v_new);
  ROLLBACK;
END;
/
```

```text output
New salary: 33000
```

## Transactions and blocks

**A block is not a transaction.** `BEGIN` does not start one, and `END` does not commit. One block can hold several transactions, and one transaction can span several blocks.

`COMMIT`, `ROLLBACK`, `SAVEPOINT` and `ROLLBACK TO` work as you saw in [Chapter 32](../part-5-internals-and-performance/32-transactions-and-isolation.md). Leave `COMMIT` to the top-level caller, so that callers can combine your work with theirs.

## PL/SQL vs other engines

PL/pgSQL in PostgreSQL, T-SQL in SQL Server and stored programs in MySQL fill the same role. The ideas carry over, but the syntax and many details do not.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Forget the final `/` | SQL*Plus just waits | Add a line with only `/` |
| Forget `SET SERVEROUTPUT ON` | No output appears | Run `session.sql` |
| Expect `DBMS_OUTPUT` to print as it runs | It prints at the end | Treat it as a buffer |
| Use `SELECT` with no `INTO` | `PLS-00428` | Add `INTO`, or use a cursor |
| Expect a missing row to give NULL | `NO_DATA_FOUND` is raised | Handle the exception |
| Name a variable like a column | The column wins | Use `v_` prefixes |
| Add 1 to an uninitialized counter | It stays NULL | Initialize it |
| Think a block is a transaction | Work stays uncommitted | Commit explicitly |
| Run DDL directly in a block | A compile error | Use `EXECUTE IMMEDIATE` |

## Interview questions

**Q1. What is PL/SQL, and what does it add on top of SQL?**

It is Oracle's procedural extension to SQL. It adds variables, conditions, loops, error handling, and stored named code such as procedures, functions, packages and triggers.

**Q2. Describe the structure of a PL/SQL block. Which parts are mandatory?**

`DECLARE` is optional, `BEGIN` is mandatory, `EXCEPTION` is optional, and `END;` is mandatory. `BEGIN` needs at least one statement, and `NULL;` counts. The word `DECLARE` is needed only in anonymous blocks.

**Q3. What is the difference between an anonymous block and a stored subprogram?**

An anonymous block has no name, is not stored, and takes no parameters. A stored subprogram is named, compiled and kept in the database, takes parameters, and can be reused and granted to others.

**Q4. What is the difference between %TYPE and %ROWTYPE, and why would you use them?**

`%TYPE` copies the type of one column or variable. `%ROWTYPE` declares a record with a field for each column of a table. Both keep your code working when the table changes.

**Q5. If a column is declared NOT NULL, does a variable anchored to it with %TYPE inherit that constraint?**

No. It takes the type and size only. A variable anchored to another variable does inherit `NOT NULL`.

**Q6. When would you use PLS_INTEGER instead of NUMBER?**

For whole-number counters and loops. It is faster and smaller, because it uses machine arithmetic. It overflows at about 2.1 billion.

**Q7. How does SELECT INTO work, and what can go wrong with it?**

It copies exactly one row into variables. No rows raises `NO_DATA_FOUND`, and several rows raises `TOO_MANY_ROWS`.

**Q8. Can SELECT COUNT(*) INTO ever raise NO_DATA_FOUND?**

Not without `GROUP BY`, because an aggregate always returns one row. With `GROUP BY`, it can.

**Q9. Which kinds of SQL statements can you not write directly in a PL/SQL block, and how do you run them?**

DDL and session control. I run them with `EXECUTE IMMEDIATE`.

## Practice

**1. Print the name of the department with id 30.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_name departments.dept_name%TYPE;
BEGIN
  SELECT dept_name INTO v_name FROM departments WHERE dept_id = 30;
  DBMS_OUTPUT.PUT_LINE(v_name);
END;
/
```

```text output
Engineering
```

</details>

**2. Using `%ROWTYPE`, print the name and price of product 4.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_p products%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM products WHERE product_id = 4;
  DBMS_OUTPUT.PUT_LINE(v_p.product_name || ': ' || v_p.price);
END;
/
```

```text output
Laptop Pro: 1499
```

</details>

**3. Count the orders of customer 1, and print whether the customer is a repeat buyer.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM orders WHERE customer_id = 1;

  IF v_count > 1 THEN
    DBMS_OUTPUT.PUT_LINE('Repeat buyer: ' || v_count);
  ELSE
    DBMS_OUTPUT.PUT_LINE('New buyer');
  END IF;
END;
/
```

```text output
Repeat buyer: 4
```

</details>

**4. Find the bug.**

```sql oracle
DECLARE
  dept_id NUMBER := 20;
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM employees WHERE dept_id = dept_id;
  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

<details>
<summary>Show solution</summary>

The column wins over the variable, so `dept_id = dept_id` compares the column with itself. It counts every row with a non-NULL `dept_id`, which is 11, not 4. Rename the variable to `v_dept_id`.

</details>

## Recap

- `BEGIN` and `END;` are mandatory, and `DECLARE` and `EXCEPTION` are optional.
- End each unit with a line holding only `/`.
- `%TYPE` and `%ROWTYPE` keep code in step with the table.
- `SELECT INTO` needs exactly one row.
- A column name wins over a variable of the same name.
- DDL needs `EXECUTE IMMEDIATE`.
- A block is not a transaction.

**Next:** [Chapter 43: IF, CASE and loops](43-control-structures.md)
