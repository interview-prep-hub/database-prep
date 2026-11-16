# 46. Procedures and Functions: Reusable Stored Code

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 45](45-exceptions.md)

> **In one line:** A procedure does work, a function computes a value, and both are compiled code stored in the database.

## What you will learn

- Procedure vs function, and when to use each
- `IN`, `OUT` and `IN OUT` parameters
- Positional and named notation, and default values
- What a function may not do when called from SQL
- `NOCOPY` and `DETERMINISTIC`
- How to return several values, or whole result sets

## Why stored subprograms?

One place for a rule, reuse, code compiled once, less network traffic, and a grant on the code instead of on the tables.

## Procedures

A procedure is called as a statement. A bare `RETURN;` leaves early.

```sql oracle
CREATE OR REPLACE PROCEDURE give_raise (
  p_emp_id  IN employees.emp_id%TYPE,
  p_percent IN NUMBER DEFAULT 5
) IS
BEGIN
  UPDATE employees
  SET salary = salary * (1 + p_percent / 100)
  WHERE emp_id = p_emp_id;

  IF SQL%NOTFOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'No employee ' || p_emp_id);
  END IF;
END give_raise;
/

EXEC give_raise(7, 10)
ROLLBACK;
```

## Functions

A function has a `RETURN` type in its header, and a `RETURN value` in its body. Reaching the end without `RETURN` raises `ORA-06503`.

```sql oracle
CREATE OR REPLACE FUNCTION annual_pay (
  p_emp_id IN employees.emp_id%TYPE
) RETURN NUMBER IS
  v_total NUMBER;
BEGIN
  SELECT salary * 12 + NVL(commission, 0)
  INTO v_total
  FROM employees
  WHERE emp_id = p_emp_id;

  RETURN v_total;
END annual_pay;
/

SELECT first_name, annual_pay(emp_id) AS yearly
FROM employees
WHERE dept_id = 40
ORDER BY emp_id;
```

```text output
FIRST_NAME     YEARLY
---------- ----------
Omar          1140000
Nina           696000
```

A function can be used in any PL/SQL expression, or from SQL. A procedure cannot be called from SQL.

| | Procedure | Function |
|---|---|---|
| Returns a value | Through `OUT` parameters | Yes, with `RETURN` |
| Called as | A statement | Part of an expression |
| Used in SQL | No | Yes, within limits |
| Purpose | Do work | Compute one value |

**Which to pick?** A function to compute one value, and a procedure to do work.

## Parameter modes

| Mode | Direction | Details |
|---|---|---|
| `IN` | Into the subprogram | The default. Read-only: assigning to it gives `PLS-00363` |
| `OUT` | Back to the caller | Starts as NULL, even if the actual held a value |
| `IN OUT` | Both | Keeps the incoming value |

`OUT` and `IN OUT` actuals must be variables, not literals.

**Why have `OUT` parameters when a function can `RETURN` a value?** Because a procedure can hand back several values. Oracle's advice is not to use `OUT` or `IN OUT` on functions.

```sql oracle
CREATE OR REPLACE PROCEDURE dept_stats (
  p_dept_id IN  employees.dept_id%TYPE,
  p_count   OUT NUMBER,
  p_total   OUT NUMBER
) IS
BEGIN
  SELECT COUNT(*), NVL(SUM(salary), 0)
  INTO p_count, p_total
  FROM employees
  WHERE dept_id = p_dept_id;
END dept_stats;
/

DECLARE
  v_count NUMBER;
  v_total NUMBER;
BEGIN
  dept_stats(20, v_count, v_total);
  DBMS_OUTPUT.PUT_LINE(v_count || ' staff, total ' || v_total);
END;
/
```

```text output
4 staff, total 267000
```

**Formal vs actual parameters.** A formal parameter is in the header, and an actual is what you pass. A formal cannot carry a size, so `VARCHAR2(20)` in a parameter list is a compile error.

## Notation and defaults

```sql oracle
BEGIN
  give_raise(7, 10);                          -- positional
  give_raise(p_percent => 10, p_emp_id => 7); -- named
  give_raise(7, p_percent => 10);             -- mixed: positional first
  give_raise(7);                              -- uses the default
  ROLLBACK;
END;
/
```

An omitted actual gets the default, not NULL. Adding a trailing optional parameter keeps old calls working. Named notation also works in SQL calls from 11.1.

## Functions called from SQL

**Can a PL/SQL function perform DML? What restrictions apply when a function is called from a SQL statement?** It can perform DML when called from PL/SQL. When called from SQL, these limits apply:

| Not allowed | Error |
|---|---|
| `OUT` or `IN OUT` parameters | `ORA-06572` |
| DML, when called from a `SELECT` | `ORA-14551` |
| `COMMIT`, or DDL, unless autonomous | `ORA-14552` |

**A trap:** `NO_DATA_FOUND` escaping a function called from SQL does not fail the query. The row just gets NULL. So a function used from both SQL and PL/SQL must handle it explicitly.

## Returning several values

**Can a function return more than one value?** Directly, one. But that one value can be a record, a collection or an object.

```sql oracle
CREATE OR REPLACE FUNCTION get_emp (
  p_emp_id IN employees.emp_id%TYPE
) RETURN employees%ROWTYPE IS
  v_emp employees%ROWTYPE;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE emp_id = p_emp_id;
  RETURN v_emp;
END get_emp;
/

DECLARE
  v_emp employees%ROWTYPE;
BEGIN
  v_emp := get_emp(4);
  DBMS_OUTPUT.PUT_LINE(v_emp.first_name || ', ' || v_emp.job_title);
END;
/
```

```text output
Omar, Finance Manager
```

A function returning a record cannot be used directly in plain SQL. A schema-level object or collection type can ([Chapter 49](49-records-and-collections.md)).

## Returning rows to a client

**How can a PL/SQL procedure return multiple result sets to a client?**

- A `SYS_REFCURSOR` `OUT` parameter per result set ([Chapter 44](44-cursors.md))
- Implicit results with `DBMS_SQL.RETURN_RESULT` (12.1)
- A pipelined function ([Chapter 52](52-advanced-plsql.md))

## Local subprograms and recursion

A **local subprogram** is declared inside a block or subprogram, after all other declarations, and is visible only there.

A **forward declaration** gives a heading first and the body later, which is needed when two subprograms call each other.

**Recursion** needs a base case. This walks the manager chain from Emma to Sara:

```sql oracle
DECLARE
  FUNCTION chain (p_emp_id NUMBER) RETURN VARCHAR2 IS
    v_name    employees.first_name%TYPE;
    v_manager employees.manager_id%TYPE;
  BEGIN
    SELECT first_name, manager_id
    INTO v_name, v_manager
    FROM employees
    WHERE emp_id = p_emp_id;

    IF v_manager IS NULL THEN
      RETURN v_name;
    END IF;

    RETURN v_name || ' > ' || chain(v_manager);
  END chain;
BEGIN
  DBMS_OUTPUT.PUT_LINE(chain(9));
END;
/
```

```text output
Emma > Arjun > Priya > Sara
```

## NOCOPY

By default, `OUT` and `IN OUT` values are copied. `NOCOPY` asks to pass by reference, which avoids copying large values such as collections.

```sql oracle
CREATE OR REPLACE PROCEDURE clean_list (
  p_list IN OUT NOCOPY DBMS_SQL.VARCHAR2_TABLE
) IS
BEGIN
  NULL;
END clean_list;
/
```

**What does `NOCOPY` do, and when does it have no effect?** It is only a hint, and the compiler silently ignores it in some cases, such as when a parameter needs an implicit conversion, or has a `NOT NULL` constraint.

**The risk:** if the subprogram fails partway, the caller may see partly changed values, because there is no copy to fall back on.

## DETERMINISTIC

`DETERMINISTIC` is your **unverified promise** that the same inputs always give the same result. It is required for function-based indexes and virtual columns.

```sql oracle
CREATE OR REPLACE FUNCTION net_price (p_price NUMBER) RETURN NUMBER
DETERMINISTIC IS
BEGIN
  RETURN ROUND(p_price * 1.2, 2);
END net_price;
/
```

**What happens if the claim is false?** You get wrong results with no error. After changing the function, you must rebuild dependent indexes yourself.

## Managing units

- `CREATE OR REPLACE` keeps grants, while `DROP` loses them.
- `ALTER PROCEDURE p COMPILE` recompiles.
- `USER_SOURCE`, `USER_PROCEDURES`, `USER_ARGUMENTS` and `USER_ERRORS` show your code.

`GRANT EXECUTE` lets another user run your code without table privileges.

A privilege received through a **role** works in SQL*Plus, but can fail inside a stored procedure ([Chapter 52](52-advanced-plsql.md) explains why).

## Autonomous transactions: a first look

`PRAGMA AUTONOMOUS_TRANSACTION` makes a subprogram run in its own independent transaction, which it must commit or roll back itself. The main use is logging ([Chapter 52](52-advanced-plsql.md)).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Give a formal parameter a size | A compile error | Use the bare type or `%TYPE` |
| Forget `RETURN` in a function | `ORA-06503` | Return on every path |
| Assign to an `IN` parameter | `PLS-00363` | Use a local variable |
| Pass a literal to `OUT` | A compile error | Pass a variable |
| Do DML in a function called from `SELECT` | `ORA-14551` | Use a procedure |
| Let `NO_DATA_FOUND` escape in SQL | The row silently gets NULL | Handle it |
| Claim `DETERMINISTIC` falsely | Wrong results, with no error | Claim it only when true |
| Rely on `NOCOPY` | It is only a hint | Do not depend on it |
| `DROP` and recreate | Grants are lost | Use `CREATE OR REPLACE` |

## Interview questions

**Q1. What is the difference between a procedure and a function?**

A function returns a value, and can be used in expressions and SQL. A procedure is called as a statement, and does work, returning values through `OUT` parameters. I use a function to compute one value, and a procedure to act.

**Q2. Can a function return more than one value?**

It returns one value, but that can be a record, a collection or an object. A procedure can return several through `OUT` parameters.

**Q3. Can a PL/SQL function perform DML? What restrictions apply when a function is called from a SQL statement?**

Yes, when called from PL/SQL. When called from SQL, it cannot have `OUT` parameters, cannot do DML from a `SELECT`, and cannot commit or run DDL unless it is autonomous.

**Q4. Explain IN, OUT and IN OUT parameters. Why have OUT parameters when a function can RETURN a value?**

`IN` passes a read-only value in. `OUT` sends a value back, and starts as NULL. `IN OUT` does both. `OUT` lets a procedure return several values.

**Q5. What does the NOCOPY hint do, and when does it have no effect?**

It asks to pass `OUT` and `IN OUT` parameters by reference, which avoids copying large values. It is only a hint, so it is ignored in some cases, such as when a conversion is needed. If the unit fails, the caller may see partial changes.

**Q6. What does DETERMINISTIC mean on a function, and what happens if the claim is false?**

It promises that the same inputs always give the same result. Oracle does not verify it, so a false claim gives wrong results with no error.

**Q7. How can a PL/SQL procedure return multiple result sets to a client?**

With one `SYS_REFCURSOR` `OUT` parameter per result set, or with `DBMS_SQL.RETURN_RESULT` from 12.1.

## Practice

**1. Write a function `calc_order_total(p_order_id)` that returns the total of an order.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE FUNCTION calc_order_total (
  p_order_id IN orders.order_id%TYPE
) RETURN NUMBER IS
  v_total NUMBER;
BEGIN
  SELECT NVL(SUM(quantity * unit_price), 0)
  INTO v_total
  FROM order_items
  WHERE order_id = p_order_id;

  RETURN v_total;
END calc_order_total;
/

SELECT calc_order_total(1001) AS total FROM dual;
```

```text output
     TOTAL
----------
    838.98
```

</details>

**2. Write a procedure `swap_values` that swaps two numbers, using `IN OUT` parameters.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE PROCEDURE swap_values (
  p_a IN OUT NUMBER,
  p_b IN OUT NUMBER
) IS
  v_temp NUMBER := p_a;
BEGIN
  p_a := p_b;
  p_b := v_temp;
END swap_values;
/

DECLARE
  v_x NUMBER := 1;
  v_y NUMBER := 2;
BEGIN
  swap_values(v_x, v_y);
  DBMS_OUTPUT.PUT_LINE(v_x || ', ' || v_y);
END;
/
```

```text output
2, 1
```

</details>

**3. Why does this fail?**

```sql oracle
CREATE OR REPLACE FUNCTION log_it RETURN NUMBER IS
BEGIN
  INSERT INTO departments (dept_id, dept_name, location)
  VALUES (99, 'Log', 'Oslo');
  RETURN 1;
END log_it;
/

SELECT log_it FROM dual;
```

<details>
<summary>Show solution</summary>

It compiles, but the `SELECT` raises `ORA-14551: cannot perform a DML operation inside a query`.

</details>

## Recap

- A function returns a value, and works in SQL. A procedure does work.
- `IN` is read-only, `OUT` starts as NULL, and `IN OUT` does both.
- A function called from SQL cannot do DML from a `SELECT`, or have `OUT` parameters.
- `NO_DATA_FOUND` from a function in SQL just gives NULL.
- `NOCOPY` is only a hint.
- `DETERMINISTIC` is an unchecked promise.
- `SYS_REFCURSOR` returns rows to clients.

**Next:** [Chapter 47: Packages](47-packages.md)
