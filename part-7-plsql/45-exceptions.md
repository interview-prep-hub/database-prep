# 45. Exceptions: Handling Errors the Right Way

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 44](44-cursors.md)

> **In one line:** An exception stops normal flow and jumps to a handler, and good code decides on purpose which errors to catch and which to let through.

## What you will learn

- Predefined, internally defined and user-defined exceptions
- `RAISE`, `RAISE_APPLICATION_ERROR` and `PRAGMA EXCEPTION_INIT`
- How exceptions move through nested blocks
- Why `WHEN OTHERS THEN NULL` is dangerous
- How to find where an error started
- How rollback behaves with errors

## What is an exception?

A run-time error stops normal flow, and jumps to the `EXCEPTION` part.

```sql oracle
DECLARE
  v_result NUMBER;
BEGIN
  v_result := 10 / 0;
  DBMS_OUTPUT.PUT_LINE('Never printed');
EXCEPTION
  WHEN ZERO_DIVIDE THEN
    DBMS_OUTPUT.PUT_LINE('Cannot divide by zero');
END;
/
```

```text output
Cannot divide by zero
```

Several names can share a handler with `OR`, and only one handler runs.

**A block with no exception section:** the error moves to the enclosing block, or back to the caller as an unhandled error. You then see an `ORA-` line, and `ORA-06512` lines that show where it happened.

## The three categories

| Category | Has a code | Has a name | Raised |
|---|---|---|---|
| **Internally defined** | Yes | Only if you give one | Implicitly |
| **Predefined** | Yes | Yes | Implicitly |
| **User-defined** | Only if you give one | Yes | With `RAISE` |

### Predefined exceptions to know

| Exception | Code | Fires when |
|---|---|---|
| `NO_DATA_FOUND` | `ORA-01403` (SQLCODE +100) | `SELECT INTO` finds no row |
| `TOO_MANY_ROWS` | `ORA-01422` | `SELECT INTO` finds several |
| `ZERO_DIVIDE` | `ORA-01476` | Division by zero |
| `DUP_VAL_ON_INDEX` | `ORA-00001` | A unique key is duplicated |
| `VALUE_ERROR` | `ORA-06502` | A conversion or size error in procedural code |
| `INVALID_NUMBER` | `ORA-01722` | A bad conversion inside SQL |
| `INVALID_CURSOR` | `ORA-01001` | A cursor operation on a closed cursor |
| `CURSOR_ALREADY_OPEN` | `ORA-06511` | `OPEN` on an open cursor |
| `CASE_NOT_FOUND` | `ORA-06592` | No `CASE` branch matched |

**A bad conversion raises `INVALID_NUMBER` inside SQL, but `VALUE_ERROR` in procedural code.**

```sql oracle
DECLARE
  v_n NUMBER;
BEGIN
  v_n := TO_NUMBER('abc');        -- procedural: VALUE_ERROR
EXCEPTION
  WHEN VALUE_ERROR THEN
    DBMS_OUTPUT.PUT_LINE('VALUE_ERROR');
  WHEN INVALID_NUMBER THEN
    DBMS_OUTPUT.PUT_LINE('INVALID_NUMBER');
END;
/
```

```text output
VALUE_ERROR
```

## User-defined exceptions

Declare, `RAISE`, and handle.

```sql oracle
DECLARE
  e_low_stock EXCEPTION;
  v_qty products.stock_qty%TYPE;
BEGIN
  SELECT stock_qty INTO v_qty FROM products WHERE product_id = 7;

  IF v_qty = 0 THEN
    RAISE e_low_stock;
  END IF;

  DBMS_OUTPUT.PUT_LINE('In stock');
EXCEPTION
  WHEN e_low_stock THEN
    DBMS_OUTPUT.PUT_LINE('Out of stock');
    DBMS_OUTPUT.PUT_LINE(SQLCODE || ' ' || SQLERRM);
END;
/
```

```text output
Out of stock
1 User-Defined Exception
```

## PRAGMA EXCEPTION_INIT

**What does `PRAGMA EXCEPTION_INIT` do?** It ties your exception name to an error code, so that you can handle an internally defined error by name. It goes in the same declarative section as the exception.

Deleting a department that has employees raises `ORA-02292`, which has no predefined name.

```sql oracle
DECLARE
  e_has_children EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_has_children, -2292);
BEGIN
  DELETE FROM departments WHERE dept_id = 20;
EXCEPTION
  WHEN e_has_children THEN
    DBMS_OUTPUT.PUT_LINE('Department still has employees');
END;
/
```

```text output
Department still has employees
```

## RAISE_APPLICATION_ERROR

**What does it do, and which error numbers can you use?** It sends your own error number and message to the caller. The range is **-20000 to -20999**, and the message can be up to 2048 bytes.

```sql oracle
CREATE OR REPLACE PROCEDURE set_salary (
  p_emp_id IN employees.emp_id%TYPE,
  p_salary IN employees.salary%TYPE
) IS
BEGIN
  IF p_salary <= 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Salary must be positive');
  END IF;

  UPDATE employees SET salary = p_salary WHERE emp_id = p_emp_id;

  IF SQL%NOTFOUND THEN
    RAISE_APPLICATION_ERROR(-20002, 'No employee ' || p_emp_id);
  END IF;
END;
/
```

The caller can catch it by name:

```sql oracle
DECLARE
  e_bad_salary EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_bad_salary, -20001);
BEGIN
  set_salary(5, -1);
EXCEPTION
  WHEN e_bad_salary THEN
    DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
/
```

```text output
ORA-20001: Salary must be positive
```

## RAISE and re-raising

`RAISE name` raises a named exception. A bare `RAISE;` re-raises the current exception, and it works only inside a handler.

## How exceptions move

**How do exceptions behave in nested blocks?** With no matching handler, an exception moves to the enclosing block. **After a handler finishes, control goes to the next statement of the enclosing block, never back to the failed line.**

```sql oracle
BEGIN
  BEGIN
    RAISE NO_DATA_FOUND;
    DBMS_OUTPUT.PUT_LINE('A');     -- skipped
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('B');
  END;

  DBMS_OUTPUT.PUT_LINE('C');       -- runs next
END;
/
```

```text output
B
C
```

**If an exception occurs while initializing a variable in the `DECLARE` section, does that block's handler catch it?** No. It goes to the enclosing block. The same applies to an exception raised inside a handler.

```sql oracle
BEGIN
  DECLARE
    v_short VARCHAR2(2) := 'abc';    -- fails here
  BEGIN
    NULL;
  EXCEPTION
    WHEN VALUE_ERROR THEN
      DBMS_OUTPUT.PUT_LINE('Inner handler');
  END;
EXCEPTION
  WHEN VALUE_ERROR THEN
    DBMS_OUTPUT.PUT_LINE('Outer handler');
END;
/
```

```text output
Outer handler
```

**Scope of user exceptions.** Once one escapes the block that declared it, only `OTHERS` can catch it. If unhandled, it surfaces as `ORA-06510`.

## WHEN OTHERS

`WHEN OTHERS` must come last. Use it at the top level to log, and to re-raise.

**Why is `WHEN OTHERS THEN NULL` a problem?** It hides every failure, so the caller believes the work succeeded. Data can be silently wrong for months.

```sql norun
EXCEPTION
  WHEN OTHERS THEN
    log_error(SQLCODE, SQLERRM);    -- your own logging
    RAISE;                          -- never swallow it
```

**`SQLCODE` and `SQLERRM`.** `SQLCODE` is 0 outside a handler. `SQLERRM` caps at 512 bytes. **They cannot be used directly in a SQL statement,** so assign them to variables first.

```sql oracle
DECLARE
  v_code NUMBER;
  v_msg  VARCHAR2(512);
BEGIN
  RAISE ZERO_DIVIDE;
EXCEPTION
  WHEN OTHERS THEN
    v_code := SQLCODE;
    v_msg  := SQLERRM;
    DBMS_OUTPUT.PUT_LINE(v_code || ': ' || v_msg);
END;
/
```

```text output
-1476: ORA-01476: divisor is equal to zero
```

## Finding where an error started

**How do you find the line where an error originated after it has passed through several layers?**

| Function | Gives |
|---|---|
| `DBMS_UTILITY.FORMAT_ERROR_STACK` | The messages, up to 2000 bytes |
| `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` | The line where the error started |
| `DBMS_UTILITY.FORMAT_CALL_STACK` | The current call chain |
| `UTL_CALL_STACK` (12.1) | Structured access to the same |

```sql oracle
CREATE OR REPLACE PROCEDURE inner_proc IS
BEGIN
  RAISE ZERO_DIVIDE;
END;
/

CREATE OR REPLACE PROCEDURE outer_proc IS
BEGIN
  inner_proc;
END;
/

BEGIN
  outer_proc;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
```

The backtrace names `INNER_PROC` line 3 first, then `OUTER_PROC`.

**A handler that only re-raises makes the stack point at the `RAISE` line.** So capture the backtrace in the first handler, or do not catch the error at all.

## Rollback and errors

**Statement-level rollback.** An implicit savepoint comes before each `INSERT`, `UPDATE`, `DELETE` or `MERGE`, so a failed statement undoes only itself.

**Unhandled exceptions.** PL/SQL itself does no rollback when a stored subprogram exits with an unhandled exception. The caller or the host decides. A top-level call from a client acts as one statement, so if the error reaches the client, that call's uncommitted changes are undone.

**Why is a `ROLLBACK` in a low-level handler harmful?** It also discards the caller's earlier work. The transaction belongs to the top-level caller.

**What is the difference between `ROLLBACK` and `ROLLBACK TO`?** `ROLLBACK` ends the whole transaction. `SAVEPOINT` plus `ROLLBACK TO`, in a sub-block, undoes only your own part, and leaves the caller's work alone.

```sql oracle
CREATE OR REPLACE PROCEDURE add_note (p_ok IN BOOLEAN) IS
BEGIN
  SAVEPOINT before_note;
  UPDATE employees SET job_title = job_title WHERE emp_id = 1;

  IF NOT p_ok THEN
    RAISE_APPLICATION_ERROR(-20010, 'Note failed');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO before_note;
    RAISE;
END;
/
```

### Continuing after an error

Wrap the risky statement in its own sub-block, so that the loop can move on to the next row.

```sql oracle
BEGIN
  FOR r IN (SELECT product_id FROM products WHERE product_id <= 3 ORDER BY product_id) LOOP
    BEGIN
      IF r.product_id = 2 THEN
        RAISE VALUE_ERROR;
      END IF;
      DBMS_OUTPUT.PUT_LINE('Done ' || r.product_id);
    EXCEPTION
      WHEN VALUE_ERROR THEN
        DBMS_OUTPUT.PUT_LINE('Skipped ' || r.product_id);
    END;
  END LOOP;
END;
/
```

```text output
Done 1
Skipped 2
Done 3
```

### Retrying

Retry transient errors, such as `ORA-00060`, in a bounded loop. On a deadlock, Oracle rolls back only the current statement, so your code must decide what to redo.

### Logging in a handler

A plain `INSERT` into a log table is lost if the transaction later rolls back. [Chapter 52](52-advanced-plsql.md) solves this with an autonomous transaction.

## Compile-time warnings

`PLSQL_WARNINGS` turns on warnings, in the `SEVERE`, `PERFORMANCE` and `INFORMATIONAL` categories.

```sql oracle
ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL';
```

`PLW-06009` flags a `WHEN OTHERS` handler that does not re-raise.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Write `WHEN OTHERS THEN NULL` | Failures vanish | Log and re-raise |
| Put `WHEN OTHERS` first | A compile error | It must be last |
| Use `SQLERRM` directly in an `INSERT` | A compile error | Assign it to a variable |
| Use `ROLLBACK` in a low-level handler | The caller's work is lost | Use `ROLLBACK TO` |
| Expect control to return to the failed line | It goes to the enclosing block | Use a sub-block |
| Expect a handler to catch `DECLARE` errors | The outer block gets them | Initialize in `BEGIN` |
| Use error numbers outside -20000 to -20999 | `ORA-21000` | Stay in the range |
| Log with a plain `INSERT` before a rollback | The log is lost too | Use an autonomous transaction |
| Catch and re-raise everywhere | The backtrace points at `RAISE` | Capture it once |

## Interview questions

**Q1. What types of exceptions exist in PL/SQL? Name some predefined ones and when they fire.**

Predefined, internally defined and user-defined. Predefined ones include `NO_DATA_FOUND`, from a `SELECT INTO` with no row, `TOO_MANY_ROWS`, `ZERO_DIVIDE`, `DUP_VAL_ON_INDEX` and `VALUE_ERROR`.

**Q2. What happens if an error occurs in a block with no exception section?**

It moves to the enclosing block, or back to the caller as an unhandled error.

**Q3. What does PRAGMA EXCEPTION_INIT do?**

It ties a name to an Oracle error code, so that I can handle an error with no predefined name. For example, `-2292` for a child record found.

**Q4. What does RAISE_APPLICATION_ERROR do, and which error numbers can you use?**

It raises my own error, with a number from -20000 to -20999 and a message of up to 2048 bytes, and sends it to the caller.

**Q5. What do SQLCODE and SQLERRM return, and can you reference them directly in an INSERT statement?**

`SQLCODE` is the error number, and `SQLERRM` is the message. They cannot be used directly in SQL, so I assign them to variables first.

**Q6. How do exceptions behave in nested blocks, and where does control go after a handler finishes?**

With no matching handler, the exception moves outward. After a handler finishes, control goes to the next statement of the enclosing block, never back to the failed line.

**Q7. If an exception occurs while initializing a variable in the DECLARE section, does that block's handler catch it?**

No. It goes to the enclosing block.

**Q8. Why is WHEN OTHERS THEN NULL a problem?**

It hides every error, so the caller thinks all went well. Use `WHEN OTHERS` only to log and re-raise.

**Q9. How do you find the line where an error originated after it has passed through several layers of code?**

`DBMS_UTILITY.FORMAT_ERROR_BACKTRACE`, captured in the first handler.

**Q10. What is the difference between ROLLBACK and ROLLBACK TO, and how do you handle rollback across nested calls?**

`ROLLBACK` ends the whole transaction. `ROLLBACK TO` undoes only the work after a savepoint. In nested calls, each unit sets a savepoint and rolls back to it, and the top-level caller owns the commit.

## Practice

**1. Write a block that prints 'Not found' if customer 99 does not exist.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_name customers.customer_name%TYPE;
BEGIN
  SELECT customer_name INTO v_name FROM customers WHERE customer_id = 99;
  DBMS_OUTPUT.PUT_LINE(v_name);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Not found');
END;
/
```

```text output
Not found
```

</details>

**2. Insert a duplicate department id, and handle it by name.**

<details>
<summary>Show solution</summary>

```sql oracle
BEGIN
  INSERT INTO departments (dept_id, dept_name, location)
  VALUES (10, 'Copy', 'Oslo');
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    DBMS_OUTPUT.PUT_LINE('That id already exists');
END;
/
```

```text output
That id already exists
```

</details>

**3. What does this print?**

```sql oracle
BEGIN
  BEGIN
    RAISE TOO_MANY_ROWS;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('A');
  END;
  DBMS_OUTPUT.PUT_LINE('B');
EXCEPTION
  WHEN TOO_MANY_ROWS THEN
    DBMS_OUTPUT.PUT_LINE('C');
END;
/
```

<details>
<summary>Show solution</summary>

`C`. The inner handler does not match, so the exception moves out, and `B` is skipped.

</details>

## Recap

- An exception jumps to a handler, and never returns to the failed line.
- Predefined exceptions have names. Use `EXCEPTION_INIT` for the rest.
- `RAISE_APPLICATION_ERROR` uses -20000 to -20999.
- A `DECLARE` error goes to the enclosing block.
- `WHEN OTHERS` logs and re-raises. It never hides.
- `FORMAT_ERROR_BACKTRACE` finds the original line.
- The top-level caller owns the commit.

**Next:** [Chapter 46: Procedures and functions](46-procedures-and-functions.md)
