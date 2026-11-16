# 44. Cursors: Reading Query Results Row by Row

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 43](43-control-structures.md)

> **In one line:** A cursor is a pointer to a query's result, so that PL/SQL can work through the rows.

## What you will learn

- What a cursor is, and the difference between implicit and explicit cursors
- How to tell if an `UPDATE` changed anything
- The four cursor attributes and what each returns at every stage
- Cursor FOR loops, and how they really fetch rows
- `FOR UPDATE` and `WHERE CURRENT OF`, and why a `COMMIT` breaks them
- REF CURSORs, and how to hand a result set to a calling application

All the code in this chapter is Oracle. Run `@setup/oracle/session.sql` first, so that you can see `DBMS_OUTPUT` text.

## What is a cursor?

When Oracle runs a SQL statement, it creates a private memory area to hold the statement's state and rows. A **cursor** is a pointer to that area. Think of a bookmark in the query's result: it marks which row you are on.

Every SQL statement runs through a cursor. The only question is who manages it.

| | Implicit cursor | Explicit cursor |
|---|---|---|
| Created by | PL/SQL, for every DML statement and every `SELECT INTO` | You, with a `CURSOR` declaration |
| Opened and closed by | PL/SQL, automatically | You, with `OPEN`, `FETCH` and `CLOSE` (or a FOR loop) |
| Rows | Works on any DML. `SELECT INTO` must return exactly one row | Any number of rows |
| Attributes | `SQL%FOUND`, `SQL%NOTFOUND`, `SQL%ROWCOUNT`, `SQL%ISOPEN` | `cursor_name%FOUND`, and so on |

## Implicit cursors and their attributes

You use an implicit cursor every time you run an `UPDATE`. Its attributes tell you what the statement just did.

**How do you check if an UPDATE changed anything?** An `UPDATE` that matches no rows is not an error. It raises nothing, so your code carries on as if all went well. You must look at `SQL%ROWCOUNT` or `SQL%NOTFOUND`.

```sql oracle
BEGIN
  UPDATE employees
  SET salary = salary + 1000
  WHERE emp_id = 999;   -- no such employee

  IF SQL%NOTFOUND THEN
    DBMS_OUTPUT.PUT_LINE('No employee found');
  ELSE
    DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' row(s) updated');
  END IF;

  ROLLBACK;
END;
/
```

```text output
No employee found
```

| Attribute | Value |
|---|---|
| `SQL%FOUND` | TRUE if the last statement touched at least one row |
| `SQL%NOTFOUND` | TRUE if it touched no rows |
| `SQL%ROWCOUNT` | How many rows it touched |
| `SQL%ISOPEN` | Always FALSE |

**Why is `SQL%ISOPEN` always FALSE?** PL/SQL closes the implicit cursor as soon as the statement ends, so by the time your next line runs, it is already closed.

Before any statement has run, the first three attributes are NULL.

### Save the value straight away

The attributes describe the most recent statement only. If another statement runs first, the value you wanted is gone. So copy it into a variable at once.

```sql oracle
DECLARE
  v_updated PLS_INTEGER;
BEGIN
  UPDATE employees
  SET salary = salary + 1000
  WHERE dept_id = 30;

  v_updated := SQL%ROWCOUNT;   -- save it before anything else runs

  DELETE FROM order_items WHERE order_id = 9999;   -- this overwrites SQL%ROWCOUNT

  DBMS_OUTPUT.PUT_LINE('Saved: ' || v_updated);
  DBMS_OUTPUT.PUT_LINE('Now: ' || SQL%ROWCOUNT);

  ROLLBACK;
END;
/
```

```text output
Saved: 4
Now: 0
```

Two more details to know:

- `ROLLBACK TO` a savepoint does not restore `SQL%ROWCOUNT`.
- A `SELECT INTO` that raises `TOO_MANY_ROWS` leaves `SQL%ROWCOUNT` at 1, not at the real number of rows. It stopped looking at the second row.

## Explicit cursors

Use an explicit cursor when a query returns many rows and you want to control how they are read. There are four steps.

```text
DECLARE   Name the query.
OPEN      Run the query and put the bookmark before the first row.
FETCH     Read the next row into variables. Repeat in a loop.
CLOSE     Release the memory.
```

Here they are together:

```sql oracle
DECLARE
  CURSOR c_emps IS
    SELECT first_name, salary
    FROM employees
    WHERE dept_id = 30
    ORDER BY salary DESC, emp_id;

  v_name   employees.first_name%TYPE;
  v_salary employees.salary%TYPE;
BEGIN
  OPEN c_emps;

  LOOP
    FETCH c_emps INTO v_name, v_salary;
    EXIT WHEN c_emps%NOTFOUND;     -- test right after FETCH

    DBMS_OUTPUT.PUT_LINE(v_name || ': ' || v_salary);
  END LOOP;

  CLOSE c_emps;
END;
/
```

```text output
Priya: 120000
Arjun: 105000
Emma: 82000
Yusuf: 82000
```

**Trap:** a `FETCH` past the last row raises no exception. It just sets `%NOTFOUND` to TRUE and leaves your variables holding the previous row. So test `%NOTFOUND` straight after `FETCH`, before you use the row. If you test it at the bottom of the loop instead, the last row is processed twice.

### Cursor attributes at every stage

Interviewers like this table. Learn it.

| Stage | `%ISOPEN` | `%FOUND` | `%NOTFOUND` | `%ROWCOUNT` |
|---|---|---|---|---|
| Before `OPEN` | FALSE | error | error | error |
| After `OPEN` | TRUE | NULL | NULL | 0 |
| After a `FETCH` that found a row | TRUE | TRUE | FALSE | rows so far |
| After the `FETCH` that found nothing | TRUE | FALSE | TRUE | unchanged |
| After `CLOSE` | FALSE | error | error | error |

"Error" means `INVALID_CURSOR`, which is `ORA-01001`. Note that `%ROWCOUNT` counts rows fetched so far, not the rows in the result.

Two exceptions exist just for cursors:

| Exception | Code | Cause |
|---|---|---|
| `INVALID_CURSOR` | `ORA-01001` | Using a cursor that is not open, such as a `FETCH` before `OPEN` or after `CLOSE` |
| `CURSOR_ALREADY_OPEN` | `ORA-06511` | Opening a cursor that is already open |

### Variables are read at OPEN

If a cursor's query uses a variable, its value is read when you `OPEN` the cursor. Changing the variable later does not change the rows.

```sql oracle
DECLARE
  v_dept employees.dept_id%TYPE := 40;
  CURSOR c_emps IS
    SELECT first_name FROM employees WHERE dept_id = v_dept ORDER BY emp_id;
  v_name employees.first_name%TYPE;
BEGIN
  OPEN c_emps;
  v_dept := 30;      -- too late, the query has already run

  LOOP
    FETCH c_emps INTO v_name;
    EXIT WHEN c_emps%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_name);
  END LOOP;

  CLOSE c_emps;
END;
/
```

```text output
Omar
Nina
```

### Fetching into a record

`%ROWTYPE` on a cursor gives you a record with exactly the cursor's columns, so you need not declare one variable per column. An expression in the query must have an alias, or the record has no field name to use for it.

```sql oracle
DECLARE
  CURSOR c_pay IS
    SELECT first_name, salary + NVL(commission, 0) AS total_pay
    FROM employees
    WHERE job_title = 'Sales Rep'
    ORDER BY emp_id;

  r_pay c_pay%ROWTYPE;
BEGIN
  OPEN c_pay;

  LOOP
    FETCH c_pay INTO r_pay;
    EXIT WHEN c_pay%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(r_pay.first_name || ': ' || r_pay.total_pay);
  END LOOP;

  CLOSE c_pay;
END;
/
```

```text output
Lena: 68000
Diego: 66500
Mei: 52000
```

## Parameterized cursors

A cursor can take parameters, like a procedure. This lets you reuse one query with different values.

```sql oracle
DECLARE
  CURSOR c_emps (p_dept_id NUMBER, p_min_salary NUMBER DEFAULT 0) IS
    SELECT first_name
    FROM employees
    WHERE dept_id = p_dept_id
      AND salary >= p_min_salary
    ORDER BY emp_id;

  v_name employees.first_name%TYPE;
BEGIN
  OPEN c_emps(20, 60000);

  LOOP
    FETCH c_emps INTO v_name;
    EXIT WHEN c_emps%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_name);
  END LOOP;

  CLOSE c_emps;
END;
/
```

```text output
James
Lena
Diego
```

You pass the actual values at `OPEN`. The parameters can be used only inside the cursor's query. `DEFAULT` lets you add a new parameter later without changing old `OPEN` calls.

## Cursor FOR loops

Most of the time you do not need `OPEN`, `FETCH` and `CLOSE` by hand. A cursor FOR loop does all three for you, and declares the record too.

```sql oracle
DECLARE
  CURSOR c_emps IS
    SELECT first_name, salary
    FROM employees
    WHERE dept_id = 40
    ORDER BY emp_id;
BEGIN
  FOR r IN c_emps LOOP
    DBMS_OUTPUT.PUT_LINE(r.first_name || ': ' || r.salary);
  END LOOP;
END;
/
```

```text output
Omar: 95000
Nina: 58000
```

You can also write the query inline, with no declaration:

```sql oracle
BEGIN
  FOR r IN (SELECT dept_name FROM departments WHERE location = 'London') LOOP
    DBMS_OUTPUT.PUT_LINE(r.dept_name);
  END LOOP;
END;
/
```

```text output
Sales
```

Things to remember:

- The record `r` exists only inside the loop. You do not declare it.
- The cursor closes by itself when the loop ends, and also when an exception leaves the loop. So cursor attributes are not available after the loop, or in an exception handler. If you need a row count, keep your own counter.
- This is the style to use for simple row-by-row reading, because you cannot forget to close the cursor.

### Does a FOR loop really fetch one row at a time?

No, and this is a good interview answer. At `PLSQL_OPTIMIZE_LEVEL` 2 or higher, which has been the default since Oracle 10g, a cursor FOR loop fetches 100 rows at a time into a hidden array, then hands them to your loop one by one. You cannot change the size.

Two limits apply:

- An explicit `OPEN`, `FETCH`, `CLOSE` loop does not get this.
- It only speeds up the reading. DML inside the loop body still runs one row at a time. For that, use `BULK COLLECT` and `FORALL` ([Chapter 50](50-bulk-processing.md)).

## FOR UPDATE and WHERE CURRENT OF

Sometimes you read rows in order to change them, and nobody else should change them in between. `FOR UPDATE` locks the rows.

```sql oracle
DECLARE
  CURSOR c_reps IS
    SELECT emp_id, salary
    FROM employees
    WHERE job_title = 'Sales Rep'
    FOR UPDATE OF salary;
BEGIN
  FOR r IN c_reps LOOP
    UPDATE employees
    SET salary = r.salary * 1.10
    WHERE CURRENT OF c_reps;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Done');
  ROLLBACK;
END;
/
```

```text output
Done
```

- **The locks are taken at `OPEN`,** not at each `FETCH`, and on all the matching rows. They last until `COMMIT` or `ROLLBACK`.
- **`WHERE CURRENT OF`** changes the row that was just fetched. It needs a `FOR UPDATE` cursor. It saves you from repeating the key, and it can avoid a second lookup.
- **`FOR UPDATE OF col`** matters in a join: it locks rows only in the table that owns that column.

You can also say what should happen if another session has already locked a row:

| Clause | What happens |
|---|---|
| (nothing) | Wait as long as it takes |
| `NOWAIT` | Fail at once with `ORA-00054` |
| `WAIT 5` | Wait up to 5 seconds, then fail with `ORA-30006` |
| `SKIP LOCKED` | Skip the locked rows and return the others. Documented since 11g, and useful for job queues |

**Why you must not commit inside this loop.** `COMMIT` releases all the locks. The next `FETCH` then fails with `ORA-01002: fetch out of sequence`. Commit after the loop. If you truly must commit in batches, one known workaround is to select `ROWID` and update by `ROWID`, with no `FOR UPDATE`. But then the rows are no longer locked, so you have given up the protection.

**Should you be using a loop at all?** The block above is a teaching example. In real code you would write one statement, which is simpler and much faster:

```sql oracle
UPDATE employees
SET salary = salary * 1.10
WHERE job_title = 'Sales Rep';
```

Keep the loop for when each row needs logic that SQL cannot express.

## Close what you open

Every open cursor uses memory. A session that leaks cursors eventually fails with `ORA-01000: maximum open cursors exceeded`, the limit being the `OPEN_CURSORS` setting. So close explicit cursors on the normal path and in exception handlers too. Test `%ISOPEN` first, because closing a closed cursor raises `INVALID_CURSOR`.

```sql oracle
DECLARE
  CURSOR c_emps IS SELECT first_name FROM employees;
  v_name employees.first_name%TYPE;
  v_num  NUMBER;
BEGIN
  OPEN c_emps;
  FETCH c_emps INTO v_name;
  v_num := TO_NUMBER(v_name);     -- fails: 'Sara' is not a number
  CLOSE c_emps;
EXCEPTION
  WHEN OTHERS THEN
    IF c_emps%ISOPEN THEN
      CLOSE c_emps;
    END IF;
    RAISE;
END;
/
```

This is one more reason to prefer a cursor FOR loop, which closes itself. Exceptions are the subject of [Chapter 45](45-exceptions.md).

## Cursor variables and REF CURSORs

A normal cursor is tied to one query, and you cannot pass it around. A **cursor variable** is a pointer you can assign, and pass to another program. It is not tied to any one query.

The type of a cursor variable is a **REF CURSOR**.

```sql oracle
DECLARE
  v_rc   SYS_REFCURSOR;
  v_name employees.first_name%TYPE;
BEGIN
  OPEN v_rc FOR
    SELECT first_name FROM employees WHERE dept_id = 40 ORDER BY emp_id;

  LOOP
    FETCH v_rc INTO v_name;
    EXIT WHEN v_rc%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_name);
  END LOOP;

  CLOSE v_rc;
END;
/
```

```text output
Omar
Nina
```

You open it with `OPEN ... FOR`, and the query is decided at that moment. The same variable can be reopened for a different query, and you need not close it first. A cursor variable takes no parameters, but its query can use ordinary variables.

### Strong, weak and SYS_REFCURSOR

```sql oracle
DECLARE
  TYPE t_emp_rc  IS REF CURSOR RETURN employees%ROWTYPE;   -- strong
  TYPE t_any_rc  IS REF CURSOR;                            -- weak
  v_strong  t_emp_rc;
  v_weak    t_any_rc;
  v_builtin SYS_REFCURSOR;                                 -- built-in weak
BEGIN
  NULL;
END;
/
```

| Type | Has `RETURN`? | When a mismatch is found |
|---|---|---|
| Strong REF CURSOR | Yes | At compile time |
| Weak REF CURSOR | No | At run time, before the first row is fetched, as `ROWTYPE_MISMATCH` |
| `SYS_REFCURSOR` | No, it is the built-in weak type | At run time |

Use `SYS_REFCURSOR` when you hand rows to a caller, because it is ready-made and any weak type works with it. Use a strong type when every use must return the same shape and you want the compiler to check it.

### The most common use: returning rows to an application

A Java, .NET or Python application cannot use a named PL/SQL cursor. But it can receive a REF CURSOR from a procedure, and read it like any result set.

```sql oracle
CREATE OR REPLACE PROCEDURE get_dept_employees (
  p_dept_id IN  employees.dept_id%TYPE,
  p_rows    OUT SYS_REFCURSOR
) AS
BEGIN
  OPEN p_rows FOR
    SELECT emp_id, first_name, salary
    FROM employees
    WHERE dept_id = p_dept_id
    ORDER BY emp_id;
END;
/
```

The procedure opens the cursor and leaves it open. The caller reads the rows and closes it. [Chapter 46](46-procedures-and-functions.md) goes deeper on passing parameters.

### Named cursor vs cursor variable

| | Named (explicit) cursor | Cursor variable |
|---|---|---|
| Tied to one query | Yes | No |
| Can be assigned or passed | No | Yes |
| Takes parameters | Yes | No |
| Works in a classic cursor FOR loop | Yes | No |
| Must close before reopening | Yes | No |

After `cv2 := cv1`, both variables point to the same work area. So closing one closes both, and using the other then raises `ORA-01001`.

## Which style should you pick?

| Situation | Use |
|---|---|
| Exactly one row | `SELECT INTO` |
| Simple reading, row by row | Cursor FOR loop |
| A large number of rows | Explicit cursor with `BULK COLLECT ... LIMIT` ([Chapter 50](50-bulk-processing.md)) |
| Handing rows to a caller or application | `SYS_REFCURSOR` |
| Changing many rows the same way | No cursor. One SQL statement |

## Newer features worth knowing

- **`SELECT ... INTO ... FOR UPDATE`** locks one row and reads it in a single statement. This is the usual way to do check-then-update safely ([Chapter 54](54-real-world-plsql-programs.md)).
- **Cursor expressions:** `CURSOR(subquery)` inside a select list gives a nested cursor for each row. [Chapter 52](52-advanced-plsql.md) uses this with pipelined functions.
- **Iteration controls (21c):** a FOR loop can run over a cursor or a cursor variable with the same syntax as a number range.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Test `%NOTFOUND` after processing the row | The last row is handled twice | Test right after `FETCH` |
| Read an attribute after a FOR loop or in its handler | The cursor is already closed | Keep your own counter |
| Read `SQL%ROWCOUNT` after another statement ran | You get the wrong statement's count | Save it in a variable at once |
| Expect a missing row in an `UPDATE` to raise `NO_DATA_FOUND` | Nothing is raised | Check `SQL%ROWCOUNT` |
| Change a variable after `OPEN` | The rows do not change | Close and reopen the cursor |
| Forget `CLOSE` on the error path | Cursors leak, and you end up at `ORA-01000` | Close in the handler, or use a FOR loop |
| Loop row by row where one statement would do | The code is slow and long | Use a single `UPDATE` or `INSERT ... SELECT` |
| Commit inside a `FOR UPDATE` loop | `ORA-01002` on the next fetch | Commit after the loop |
| Fetch into `%ROWTYPE` from a cursor with an unaliased expression | The field has no usable name | Give every expression an alias |

## Interview questions

**Q1. What is a cursor? What is the difference between implicit and explicit cursors?**

A cursor is a pointer to the memory area that holds a SQL statement's state and rows. Oracle creates an implicit cursor by itself for every DML statement and every `SELECT INTO`. I declare an explicit cursor myself, for a query that returns many rows, and control it with `OPEN`, `FETCH` and `CLOSE`, or with a cursor FOR loop.

**Q2. How do you check whether an UPDATE actually changed any rows?**

An `UPDATE` that matches nothing raises no error, so I read `SQL%ROWCOUNT` or `SQL%NOTFOUND` straight after it. I save the value at once, because the next statement overwrites it.

**Q3. Why is %ISOPEN always FALSE for an implicit cursor?**

PL/SQL closes the implicit cursor as soon as the statement ends. By the time my code can look at it, it is closed.

**Q4. Name the cursor attributes, and what each returns before OPEN, after OPEN, after FETCH and after CLOSE.**

`%ISOPEN` is FALSE before `OPEN` and after `CLOSE`, and TRUE between them. `%FOUND`, `%NOTFOUND` and `%ROWCOUNT` raise `INVALID_CURSOR` when the cursor is closed. Right after `OPEN`, `%FOUND` and `%NOTFOUND` are NULL and `%ROWCOUNT` is 0. After a successful `FETCH`, `%FOUND` is TRUE, `%NOTFOUND` is FALSE, and `%ROWCOUNT` is the number of rows fetched so far. After the `FETCH` that finds nothing, `%FOUND` is FALSE, `%NOTFOUND` is TRUE, and the count does not change.

**Q5. Which two exceptions are specific to cursors?**

`INVALID_CURSOR`, `ORA-01001`, from using a cursor that is not open. And `CURSOR_ALREADY_OPEN`, `ORA-06511`, from opening one twice.

**Q6. Can a cursor take parameters, and why would you want that?**

Yes. You declare them on the cursor and pass the values at `OPEN`. It lets you reuse one query for different values instead of writing several cursors, and the parameters are clearer than global variables.

**Q7. What is a cursor FOR loop? Does it really fetch one row at a time?**

It is a loop that opens the cursor, fetches each row into an implicit record, and closes the cursor by itself, even if an exception occurs. It looks like one row at a time, but from 10g on, at `PLSQL_OPTIMIZE_LEVEL` 2 or higher, it fetches 100 rows at a time behind the scenes. This does not help DML inside the loop, which still runs row by row.

**Q8. What do FOR UPDATE and WHERE CURRENT OF do, and what happens if you commit inside that loop?**

`FOR UPDATE` locks the selected rows when the cursor opens. `WHERE CURRENT OF` updates or deletes the row last fetched. A `COMMIT` inside the loop releases the locks, so the next `FETCH` fails with `ORA-01002: fetch out of sequence`. The commit belongs after the loop.

**Q9. What is the difference between a normal cursor and a REF CURSOR? When do you use SYS_REFCURSOR?**

A normal cursor is fixed to one query and cannot be passed around. A REF CURSOR is a variable that points to a cursor's work area, so the query can be chosen at run time, and it can be assigned or passed to another program. I use `SYS_REFCURSOR` mainly to return a result set from a procedure to an application.

**Q10. What is the difference between a strong and a weak REF CURSOR?**

A strong REF CURSOR has a `RETURN` clause that fixes the row shape, so mismatches fail at compile time. A weak one has no `RETURN`, so it can open any query, and a mismatch raises `ROWTYPE_MISMATCH` at run time. `SYS_REFCURSOR` is the built-in weak type.

## Practice

Try each one in SQL*Plus. Add `ROLLBACK;` after anything that changes data.

**1. Use an explicit cursor to print the name and price of every product that costs over 500, highest price first.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  CURSOR c_products IS
    SELECT product_name, price
    FROM products
    WHERE price > 500
    ORDER BY price DESC;

  v_name  products.product_name%TYPE;
  v_price products.price%TYPE;
BEGIN
  OPEN c_products;

  LOOP
    FETCH c_products INTO v_name, v_price;
    EXIT WHEN c_products%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_name || ': ' || v_price);
  END LOOP;

  CLOSE c_products;
END;
/
```

```text output
Laptop Pro: 1499
Laptop Air: 999
Phone X: 799
```

</details>

**2. Rewrite that as a cursor FOR loop with an inline query.**

<details>
<summary>Show solution</summary>

```sql oracle
BEGIN
  FOR r IN (SELECT product_name, price
            FROM products
            WHERE price > 500
            ORDER BY price DESC)
  LOOP
    DBMS_OUTPUT.PUT_LINE(r.product_name || ': ' || r.price);
  END LOOP;
END;
/
```

```text output
Laptop Pro: 1499
Laptop Air: 999
Phone X: 799
```

</details>

**3. Print how many orders each customer has, skipping customers with none. Use a parameterized cursor for the count.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  CURSOR c_count (p_customer_id NUMBER) IS
    SELECT COUNT(*) AS order_count
    FROM orders
    WHERE customer_id = p_customer_id;

  v_count NUMBER;
BEGIN
  FOR c IN (SELECT customer_id, customer_name FROM customers ORDER BY customer_id) LOOP
    OPEN c_count(c.customer_id);
    FETCH c_count INTO v_count;
    CLOSE c_count;

    IF v_count > 0 THEN
      DBMS_OUTPUT.PUT_LINE(c.customer_name || ': ' || v_count);
    END IF;
  END LOOP;
END;
/
```

```text output
Alice Morgan: 4
Bilal Ahmed: 3
Chloe Martin: 3
David Lee: 2
Fatima Noor: 2
George Hall: 2
```

In a real program, one query with a join and `GROUP BY` would do this. The point here is the parameter.

</details>

**4. Update the salary of employee 999, and print "Not found" if no row was changed.**

<details>
<summary>Show solution</summary>

```sql oracle
BEGIN
  UPDATE employees SET salary = 50000 WHERE emp_id = 999;

  IF SQL%ROWCOUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Not found');
  END IF;

  ROLLBACK;
END;
/
```

```text output
Not found
```

</details>

**5. Write a procedure `get_orders_by_status` that takes a status and returns those orders through a `SYS_REFCURSOR`. Then call it from an anonymous block and print the order ids.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE PROCEDURE get_orders_by_status (
  p_status IN  orders.status%TYPE,
  p_rows   OUT SYS_REFCURSOR
) AS
BEGIN
  OPEN p_rows FOR
    SELECT order_id
    FROM orders
    WHERE status = p_status
    ORDER BY order_id;
END;
/

DECLARE
  v_rows SYS_REFCURSOR;
  v_id   orders.order_id%TYPE;
BEGIN
  get_orders_by_status('SHIPPED', v_rows);

  LOOP
    FETCH v_rows INTO v_id;
    EXIT WHEN v_rows%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_id);
  END LOOP;

  CLOSE v_rows;
END;
/
```

```text output
1011
1012
1013
```

</details>

**6. Find the bug. What does this print, and why?**

```sql oracle
DECLARE
  CURSOR c IS SELECT first_name FROM employees WHERE dept_id = 40 ORDER BY emp_id;
  v_name employees.first_name%TYPE;
BEGIN
  OPEN c;
  LOOP
    FETCH c INTO v_name;
    DBMS_OUTPUT.PUT_LINE(v_name);
    EXIT WHEN c%NOTFOUND;
  END LOOP;
  CLOSE c;
END;
/
```

<details>
<summary>Show solution</summary>

```text output
Omar
Nina
Nina
```

The last row prints twice. The third `FETCH` finds nothing, but it raises no error and leaves `Nina` in the variable. The line then prints before `EXIT WHEN` runs. Move `EXIT WHEN` to the line right after `FETCH`.

</details>

## Recap

- A cursor is a pointer to a query's memory area. Every statement has one.
- Implicit cursors belong to PL/SQL. Read `SQL%ROWCOUNT` right after DML, because a missing row raises nothing.
- Explicit cursors follow `OPEN`, `FETCH`, `CLOSE`. Test `%NOTFOUND` right after `FETCH`.
- Attributes on a closed cursor raise `ORA-01001`, except `%ISOPEN`.
- A cursor FOR loop opens, fetches and closes for you, and it fetches 100 rows at a time from 10g on.
- `FOR UPDATE` locks rows at `OPEN`. A `COMMIT` in that loop gives `ORA-01002`.
- `SYS_REFCURSOR` is the way to return rows to an application.

**Next:** [Chapter 45: Exceptions](45-exceptions.md)
