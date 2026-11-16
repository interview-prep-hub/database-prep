# 52. Advanced PL/SQL Features

**Level:** Advanced | **Interview priority:** Should know | **Before this:** [Chapter 51](51-dynamic-sql.md)

> **In one line:** These features solve specific problems: independent transactions, security contexts, caching, streaming results, and scheduled work.

## What you will learn

- Autonomous transactions, with a good use and a bad use
- Definer's rights vs invoker's rights, and why roles disappear
- The function result cache
- Object types
- Pipelined table functions
- Conditional compilation, LOBs, the scheduler and the main built-in packages

## Autonomous transactions

**What is an autonomous transaction?** A transaction that is independent of the main one. It shares no locks, and its commit is visible at once. The main transaction suspends until it finishes.

```sql oracle
CREATE TABLE app_log (
  logged_at  TIMESTAMP DEFAULT SYSTIMESTAMP,
  message    VARCHAR2(400)
);

CREATE OR REPLACE PROCEDURE log_msg (p_message IN VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO app_log (message) VALUES (p_message);
  COMMIT;
END log_msg;
/

BEGIN
  UPDATE employees SET salary = 1 WHERE emp_id = 12;
  log_msg('Tried to change salary');
  ROLLBACK;
END;
/

SELECT message FROM app_log;
```

```text output
MESSAGE
----------------------
Tried to change salary
```

The update rolled back, and the log row stayed.

**Where it is allowed:** a top-level anonymous block, any subprogram, an object method, or a noncompound DML trigger. Never a whole package.

**How it fails:**

- Leaving with pending work raises `ORA-06519`, and rolls back.
- Needing a lock the main transaction holds is a **deadlock**.
- Main-transaction savepoints do not apply inside it.

**A good use and a bad use.** Logging is the valid use. Using it to hide `ORA-04091`, or `ORA-14551`, is the bad use: it reads only committed data, and it breaks atomicity.

## Definer's rights vs invoker's rights

**What is the difference?**

| | `AUTHID DEFINER` (default) | `AUTHID CURRENT_USER` |
|---|---|---|
| Names and privileges at run time | The owner's | The caller's |
| Use for | A controlled API over tables | A utility that acts on the caller's objects |

Anonymous blocks run with invoker's rights, and triggers run with definer's rights.

```sql oracle
CREATE OR REPLACE PROCEDURE count_my_rows (p_table IN VARCHAR2)
AUTHID CURRENT_USER IS
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_table)
    INTO v_count;
  DBMS_OUTPUT.PUT_LINE(v_count);
END count_my_rows;
/
```

**A stored procedure fails on a table you can query in SQL*Plus, and your access comes through a role. Why?** Roles are off inside definer's rights units. Only `PUBLIC` stays enabled. So the privilege must be granted directly, or the unit must use invoker's rights.

**Injection** in a definer's rights unit runs with the owner's privileges, which is why such code must bind and validate.

**`ACCESSIBLE BY`** (12.1) is a white list of units that may call this one. Others get `PLS-00904` at compile time.

## Result cache

**What is the PL/SQL function result cache?** The `RESULT_CACHE` keyword (11.1) keeps results in the SGA, shared by all sessions.

```sql oracle
CREATE OR REPLACE FUNCTION dept_name_of (
  p_dept_id IN departments.dept_id%TYPE
) RETURN VARCHAR2 RESULT_CACHE IS
  v_name departments.dept_name%TYPE;
BEGIN
  SELECT dept_name INTO v_name FROM departments WHERE dept_id = p_dept_id;
  RETURN v_name;
END dept_name_of;
/
```

Hits need identical arguments, with NULL matching NULL. Committed changes to dependent tables invalidate it. It suits small, read-mostly lookups. It is not included in the 11g XE edition.

| | Function result cache | SQL query result cache |
|---|---|---|
| Stores | A return value per argument set | A query's rows |
| Enabled with | `RESULT_CACHE` on the function | The `/*+ RESULT_CACHE */` hint |

## Object types

```sql oracle
CREATE OR REPLACE TYPE money_t AS OBJECT (
  amount   NUMBER,
  currency CHAR(3),
  MEMBER FUNCTION show RETURN VARCHAR2
);
/

CREATE OR REPLACE TYPE BODY money_t AS
  MEMBER FUNCTION show RETURN VARCHAR2 IS
  BEGIN
    RETURN currency || ' ' || amount;
  END show;
END;
/

DECLARE
  v_price money_t := money_t(799, 'USD');
BEGIN
  DBMS_OUTPUT.PUT_LINE(v_price.show);
END;
/
```

```text output
USD 799
```

- A `MEMBER` method works on one object, and a `STATIC` method does not.
- The default constructor takes one value per attribute.
- `NOT FINAL` and `UNDER` give inheritance.
- An object can have at most one `MAP` or `ORDER` method, for comparison.
- Using an uninitialized object raises `ACCESS_INTO_NULL`.

## Pipelined table functions

**What is a pipelined table function, and when would you use one?** A function that streams rows to the caller as they are produced, instead of building a whole collection first. It is declared `PIPELINED`, uses `PIPE ROW` for each row, and a bare `RETURN` at the end.

The return type must be a schema or package collection of SQL-compatible elements, never an associative array.

```sql oracle
CREATE OR REPLACE TYPE month_row AS OBJECT (
  order_month VARCHAR2(11),
  revenue     NUMBER
);
/

CREATE OR REPLACE TYPE month_tab AS TABLE OF month_row;
/

CREATE OR REPLACE FUNCTION monthly_sales RETURN month_tab PIPELINED IS
BEGIN
  FOR r IN (SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
                   SUM(i.quantity * i.unit_price) AS revenue
            FROM orders o
            JOIN order_items i ON i.order_id = o.order_id
            WHERE o.status <> 'CANCELLED'
            GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
            ORDER BY order_month)
  LOOP
    PIPE ROW(month_row(r.order_month, r.revenue));
  END LOOP;

  RETURN;
END monthly_sales;
/

SELECT order_month, revenue FROM TABLE(monthly_sales);
```

```text output
ORDER_MONTH    REVENUE
----------- ----------
2024-01        2411.98
2024-02        1108.49
2024-03         973.98
2024-04            868
2024-05           1178
2024-06        2047.47
```

**Use one when** a transformation is too complex for one query, when huge results must stream, or when a report should be read as a table.

## Conditional compilation

`$IF`, `$ELSIF`, `$ELSE`, `$END` and `$ERROR` choose code at compile time.

```sql oracle
CREATE OR REPLACE PROCEDURE show_mode IS
BEGIN
  $IF DBMS_DB_VERSION.VER_LE_11_2 $THEN
    DBMS_OUTPUT.PUT_LINE('Old release code path');
  $ELSE
    DBMS_OUTPUT.PUT_LINE('New release code path');
  $END
END show_mode;
/
```

`$$PLSQL_UNIT` and `$$PLSQL_LINE` give the unit name and line. `PLSQL_CCFLAGS` sets your own flags.

## LOBs

- A LOB variable holds a **locator**, not the data.
- Lock the row before writing.
- Offsets start at 1.
- Amounts are bytes for `BLOB`, and characters for `CLOB`.

```sql oracle
DECLARE
  v_doc CLOB;
BEGIN
  DBMS_LOB.CREATETEMPORARY(v_doc, TRUE);
  DBMS_LOB.WRITEAPPEND(v_doc, 5, 'Hello');
  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.GETLENGTH(v_doc));
  DBMS_LOB.FREETEMPORARY(v_doc);
END;
/
```

```text output
5
```

## Scheduling

**What is the difference between `DBMS_JOB` and `DBMS_SCHEDULER`?** `DBMS_JOB` is superseded, and its `SUBMIT` joins the caller's transaction, so the job runs only after your `COMMIT`. `DBMS_SCHEDULER` is richer, with named programs, schedules, chains, and logging, and `CREATE_JOB` commits by itself.

```sql oracle
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'NIGHTLY_REPORT',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'SAY_HELLO',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=2',
    enabled         => TRUE);
END;
/
```

## UTL_FILE

`UTL_FILE` reads and writes server files. It uses directory objects in uppercase, with `READ` and `WRITE` grants. It handles no subdirectories, and files live on the database server.

## Built-in packages

| Package | Purpose |
|---|---|
| `DBMS_OUTPUT` | Debug text |
| `DBMS_LOB` | LOB work |
| `DBMS_SQL` | Fully dynamic SQL |
| `DBMS_ASSERT` | Input checks |
| `DBMS_UTILITY` | Error stacks, compile helpers |
| `DBMS_SCHEDULER` | Jobs |
| `DBMS_METADATA` | Get DDL |
| `DBMS_APPLICATION_INFO` | Label a session's work |
| `DBMS_STATS` | Statistics |
| `DBMS_LOCK` | Custom locks |
| `DBMS_RLS` | Row-level security |
| `DBMS_CRYPTO` | Encryption and hashing |
| `UTL_FILE`, `UTL_HTTP`, `UTL_MAIL` | Files, HTTP and mail |

## Recent releases

Oracle 26ai is release update 23.26.0 and later of the same code line. Worth recognizing are lock-free reservations (23ai), JSON Relational Duality views (23ai), True Cache (23ai) and polymorphic table functions (18c).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use autonomous transactions to dodge errors | Atomicity is broken | Fix the design |
| Leave an autonomous unit uncommitted | `ORA-06519` | Commit or roll back |
| Update the main transaction's row autonomously | A deadlock | Do not |
| Rely on role privileges in stored code | It fails at compile or run time | Grant directly |
| Forget `RETURN` in a pipelined function | `ORA-06503` risk | End with a bare `RETURN;` |
| Return an associative array from `TABLE()` | A compile error | Use a schema type |
| Use `DBMS_JOB` in new code | It is superseded | Use `DBMS_SCHEDULER` |

## Interview questions

**Q1. What is an autonomous transaction? Give a good use and a bad use.**

An independent transaction started from within another, with its own commit. A good use is error logging that must survive a rollback. A bad use is hiding the mutating table error, because it breaks atomicity, and reads only committed data.

**Q2. What is the difference between definer's rights and invoker's rights?**

Definer's rights run with the owner's privileges and name resolution, and this is the default. Invoker's rights, `AUTHID CURRENT_USER`, run with the caller's. I use definer's for an API over tables, and invoker's for utilities acting on the caller's objects.

**Q3. A stored procedure fails on a table you can query in SQL*Plus, and your access comes through a role. Why?**

Roles are off inside definer's rights units. The privilege must be granted directly.

**Q4. What is the PL/SQL function result cache, and how does it differ from the SQL query result cache?**

It stores a function's return value per argument set, in the SGA, shared by sessions, and invalidated when dependent tables change. The SQL query result cache stores a query's rows.

**Q5. What is a pipelined table function, and when would you use one?**

A function that returns rows as they are produced, read with `TABLE()`. I use it for complex transformations, large results that must stream, and chaining steps in a pipeline.

**Q6. What is the difference between DBMS_JOB and DBMS_SCHEDULER?**

`DBMS_JOB` is older and transactional: the job runs only after you commit. `DBMS_SCHEDULER` has named schedules, chains and logging, and `CREATE_JOB` commits by itself.

## Practice

**1. Write an autonomous procedure `log_error(p_msg)`. Why must it commit?**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE PROCEDURE log_error (p_msg IN VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO app_log (message) VALUES (p_msg);
  COMMIT;
END log_error;
/
```

Leaving an autonomous unit with pending work raises `ORA-06519`.

</details>

**2. Write a pipelined function that returns the numbers from 1 to n.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE TYPE num_tab AS TABLE OF NUMBER;
/

CREATE OR REPLACE FUNCTION gen_numbers (p_n IN NUMBER) RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1..p_n LOOP
    PIPE ROW(i);
  END LOOP;
  RETURN;
END gen_numbers;
/

SELECT column_value AS n FROM TABLE(gen_numbers(3));
```

```text output
         N
----------
         1
         2
         3
```

</details>

## Recap

- Autonomous transactions are for logging, not for dodging errors.
- Definer's rights use the owner's privileges, and roles are off.
- The result cache is for small, read-mostly lookups.
- Pipelined functions stream rows, read with `TABLE()`.
- Use `DBMS_SCHEDULER`, not `DBMS_JOB`.

**Next:** [Chapter 53: Making PL/SQL fast, safe and easy to deploy](53-plsql-performance-and-best-practices.md)
