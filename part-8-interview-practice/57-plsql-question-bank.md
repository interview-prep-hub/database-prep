# 57. PL/SQL Questions: Theory, Coding Drills and Production Scenarios

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Part 7

> **In one line:** A PL/SQL round is rapid theory, code written with no compiler, and "what does this print".

## Rapid-fire banks

Cover the right column.

### Basics (Chapters 42, 43)

| Question | One-line answer |
|---|---|
| PL/SQL vs SQL? | Procedural logic around set-based SQL |
| Block parts? | `DECLARE`, `BEGIN`, `EXCEPTION`, `END` |
| `%TYPE` vs `%ROWTYPE`? | One column, vs a whole row |
| `SELECT INTO` rule? | Exactly one row |
| `SQL%ROWCOUNT`? | Rows touched by the last statement |
| `ELSIF` or `ELSEIF`? | `ELSIF` |
| Minimum loop passes? | Basic 1, `WHILE` and `FOR` 0 |

### Cursors (Chapter 44)

| Question | One-line answer |
|---|---|
| Implicit vs explicit? | Managed by PL/SQL, vs by you |
| Cursor attributes? | `%FOUND`, `%NOTFOUND`, `%ROWCOUNT`, `%ISOPEN` |
| Does a FOR loop fetch one row at a time? | No, 100 at a time from 10g |
| `WHERE CURRENT OF`? | Changes the last fetched row of a `FOR UPDATE` cursor |
| Commit in a `FOR UPDATE` loop? | `ORA-01002` on the next fetch |
| `SYS_REFCURSOR`? | The built-in weak REF CURSOR |

### Exceptions (Chapter 45)

| Question | One-line answer |
|---|---|
| Kinds? | Predefined, internally defined, user-defined |
| `RAISE_APPLICATION_ERROR` range? | -20000 to -20999 |
| `EXCEPTION_INIT`? | Names an error code |
| `WHEN OTHERS THEN NULL`? | Hides failures |
| Where does control go after a handler? | The enclosing block's next statement |
| Finding the origin line? | `FORMAT_ERROR_BACKTRACE` |

### Subprograms and packages (Chapters 46, 47)

| Question | One-line answer |
|---|---|
| Procedure vs function? | Does work, vs returns a value |
| `IN`, `OUT`, `IN OUT`? | Read-only, sends back, both |
| `NOCOPY`? | A by-reference hint |
| `DETERMINISTIC`? | An unchecked promise |
| Function from SQL may not? | Do DML from a `SELECT`, or commit |
| Why packages? | Encapsulation, overloading, state, fewer recompiles |
| `ORA-04068`? | Package state discarded |
| Body change invalidates dependents? | No |

### Triggers (Chapter 48)

| Question | One-line answer |
|---|---|
| Firing order? | `BEFORE` statement, row pair, `AFTER` statement |
| `:OLD` on insert? | NULL |
| Change `:NEW` where? | `BEFORE` row only |
| Commit in a trigger? | `ORA-04092` |
| `ORA-04091`? | A row trigger touched its own table |
| Compound trigger? | One trigger, four timing points, shared state |
| `INSTEAD OF`? | Makes a view writable |

### Collections and bulk (Chapters 49, 50)

| Question | One-line answer |
|---|---|
| Three collection types? | Associative array, nested table, VARRAY |
| Which needs no constructor? | Associative array |
| Which has a maximum? | VARRAY |
| Sparse loop? | `FIRST` and `NEXT` |
| `BULK COLLECT`? | Many rows into a collection, in one trip |
| `FORALL`? | One DML for many elements, in one trip |
| `SAVE EXCEPTIONS`? | Keep going, then `ORA-24381` |

### Dynamic SQL and more (Chapters 51 to 53)

| Question | One-line answer |
|---|---|
| Bind a table name? | No |
| Stop injection? | Bind values, validate names |
| `DBMS_SQL` when? | Unknown select list or binds |
| Autonomous transaction use? | Logging |
| Definer vs invoker? | Owner's rights, vs caller's |
| Roles in definer units? | Off |
| Pipelined function? | Streams rows, read with `TABLE()` |
| `DBMS_JOB` vs `DBMS_SCHEDULER`? | Older and transactional, vs richer |

## Coding drills

Write these on paper first.

**1. Print the series 99, 96, ... 3.**

<details>
<summary>Show solution</summary>

```sql oracle
BEGIN
  FOR i IN REVERSE 1..33 LOOP
    DBMS_OUTPUT.PUT_LINE(i * 3);
  END LOOP;
END;
/
```

On 11g, `FOR` has no step, so multiply the index.

</details>

**2. Count the vowels in a string, without a loop.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_text VARCHAR2(30) := 'DATABASE';
BEGIN
  DBMS_OUTPUT.PUT_LINE(
    LENGTH(v_text) - NVL(LENGTH(TRANSLATE(v_text, 'xAEIOU', 'x')), 0));
END;
/
```

```text output
4
```

`TRANSLATE` removes the vowels. The `x` is there because the third argument cannot be empty.

</details>

**3. Write a function that returns the Nth highest salary.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE FUNCTION nth_salary (p_n IN PLS_INTEGER) RETURN NUMBER IS
  v_salary employees.salary%TYPE;
BEGIN
  SELECT salary INTO v_salary
  FROM (SELECT DISTINCT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS rnk
        FROM employees)
  WHERE rnk = p_n;

  RETURN v_salary;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END nth_salary;
/

SELECT nth_salary(3) AS third FROM dual;
```

```text output
     THIRD
----------
    105000
```

</details>

**4. Block deletes on weekends.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE TRIGGER no_weekend_delete
BEFORE DELETE ON employees
BEGIN
  IF TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN') THEN
    RAISE_APPLICATION_ERROR(-20060, 'No deletes on weekends');
  END IF;
END;
/
```

A statement-level trigger is enough, because the rule is about the statement, not each row. The `NLS_DATE_LANGUAGE` argument keeps it independent of session settings.

</details>

**5. Mask an email: `s***@shop.example`.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE FUNCTION mask_email (p_email IN VARCHAR2) RETURN VARCHAR2 IS
BEGIN
  RETURN SUBSTR(p_email, 1, 1) || '***' || SUBSTR(p_email, INSTR(p_email, '@'));
END mask_email;
/

SELECT mask_email(email) AS masked FROM employees WHERE emp_id = 1;
```

```text output
MASKED
-----------------
s***@shop.example
```

</details>

**6. Retry on deadlock, up to 3 times.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  e_deadlock EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_deadlock, -60);
BEGIN
  FOR attempt IN 1..3 LOOP
    BEGIN
      SAVEPOINT before_try;

      UPDATE products SET stock_qty = stock_qty WHERE product_id = 1;

      EXIT;
    EXCEPTION
      WHEN e_deadlock THEN
        ROLLBACK TO before_try;

        IF attempt = 3 THEN
          RAISE;
        END IF;
    END;
  END LOOP;

  ROLLBACK;
END;
/
```

</details>

## Predict the output

**7. What does this print?**

```sql oracle
DECLARE
  x NUMBER;
BEGIN
  IF x = 1 THEN
    DBMS_OUTPUT.PUT_LINE('one');
  ELSIF NOT (x = 1) THEN
    DBMS_OUTPUT.PUT_LINE('not one');
  ELSE
    DBMS_OUTPUT.PUT_LINE('neither');
  END IF;
END;
/
```

<details>
<summary>Show solution</summary>

`neither`. With x NULL, both conditions are NULL.

</details>

**8. What does this print?**

```sql oracle
DECLARE
  v NUMBER := 1;
BEGIN
  DECLARE
    v NUMBER := 2;
  BEGIN
    v := v + 1;
  END;
  DBMS_OUTPUT.PUT_LINE(v);
END;
/
```

<details>
<summary>Show solution</summary>

`1`. The inner `v` hides the outer one, and goes away with its block.

</details>

**9. After a `FORALL` of 100 rows fails on row 50, with no `SAVE EXCEPTIONS` and no handler, how many rows stay changed?**

<details>
<summary>Show solution</summary>

None. An unhandled failure rolls back every iteration of that `FORALL`. With a handler, the first 49 stay.

</details>

**10. A procedure with an `OUT` parameter sets it, then raises an unhandled exception. What does the caller's variable hold?**

<details>
<summary>Show solution</summary>

Its old value, because `OUT` parameters are passed by value by default, and copied back only on success. With `NOCOPY`, the new value may be visible.

</details>

## Production scenarios

**A nightly PL/SQL job runs for 8 hours. What do you do?** Find where the time goes, with SQL Trace or `DBMS_HPROF`. It is usually row-by-row SQL. Replace it with set-based SQL, or `BULK COLLECT` and `FORALL`.

**A deployment fails with `ORA-04068` for live users.** A stateful package was recompiled. Make packages stateless, deploy at quiet times, and let the application retry once. EBR handles the larger cases.

**A batch fails halfway, and you need to restart it.** Commit per batch, record progress in a control table, and make each batch idempotent.

**`ORA-01555` in a long job.** It is usually from committing inside a cursor loop. Commit after the loop, or restart the cursor per batch.

## Recap

- Know each `ORA-` code in this chapter by heart.
- Write code on paper, with no compiler.
- Say the trap out loud as you predict an output.

**Next:** [Chapter 58: Design and architecture questions](58-design-and-architecture-question-bank.md)
