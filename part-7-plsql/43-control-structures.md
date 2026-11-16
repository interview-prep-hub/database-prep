# 43. IF, CASE and Loops: Controlling the Flow

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 42](42-plsql-basics.md)

> **In one line:** `IF` and `CASE` choose what runs, and loops repeat it.

## What you will learn

- `IF`, and how NULL behaves in a condition
- The `CASE` statement vs the `CASE` expression
- Basic, `WHILE` and `FOR` loops
- `EXIT`, `CONTINUE` and labels

## IF

```sql oracle
DECLARE
  v_salary employees.salary%TYPE;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE emp_id = 5;

  IF v_salary >= 100000 THEN
    DBMS_OUTPUT.PUT_LINE('High');
  ELSIF v_salary >= 60000 THEN
    DBMS_OUTPUT.PUT_LINE('Medium');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Low');
  END IF;
END;
/
```

```text output
Medium
```

The keyword is `ELSIF`, not `ELSEIF`. `END IF` closes the statement, and only the first TRUE branch runs.

For a `BOOLEAN` variable, write `IF overdrawn`, not `IF overdrawn = TRUE`.

## NULL in conditions

**Only `IS NULL` and `IS NOT NULL` work.** `IF x = NULL` and `IF x = ''` are never true, because any zero-length string is NULL in PL/SQL.

**Is an empty string the same as NULL in PL/SQL? How should you test for it?** Yes. Test with `IS NULL`.

| Expression | Result |
|---|---|
| `TRUE AND NULL` | NULL |
| `FALSE AND NULL` | FALSE |
| `TRUE OR NULL` | TRUE |
| `FALSE OR NULL` | NULL |
| `NOT NULL` | NULL |

A NULL condition does not run `THEN`. This leads to two traps.

**Trap 1:** `IF x > y` and `IF NOT (x > y)` can both go to `ELSE` when x or y is NULL.

```sql oracle
DECLARE
  v_x NUMBER := 5;
  v_y NUMBER;          -- NULL
BEGIN
  IF v_x > v_y THEN
    DBMS_OUTPUT.PUT_LINE('Greater');
  ELSIF NOT (v_x > v_y) THEN
    DBMS_OUTPUT.PUT_LINE('Not greater');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Unknown');
  END IF;
END;
/
```

```text output
Unknown
```

**Trap 2:** `100 NOT IN (a, b)` is NULL when a member is NULL and no member equals 100, so its `THEN` never runs.

**Short-circuit.** `AND` and `OR` stop as soon as the result is known, so `IF n <> 0 AND x / n > 1` is safe.

## CASE

### The CASE statement

It ends with `END CASE`. With no match and no `ELSE`, it raises `CASE_NOT_FOUND` (`ORA-06592`).

```sql oracle
DECLARE
  v_status orders.status%TYPE;
BEGIN
  SELECT status INTO v_status FROM orders WHERE order_id = 1006;

  CASE v_status
    WHEN 'DELIVERED' THEN DBMS_OUTPUT.PUT_LINE('Done');
    WHEN 'CANCELLED' THEN DBMS_OUTPUT.PUT_LINE('Stopped');
    ELSE DBMS_OUTPUT.PUT_LINE('In progress');
  END CASE;
END;
/
```

```text output
Stopped
```

### The CASE expression

It gives a value, ends with `END`, and returns NULL with no match and no `ELSE`.

```sql oracle
DECLARE
  v_qty   products.stock_qty%TYPE;
  v_label VARCHAR2(20);
BEGIN
  SELECT stock_qty INTO v_qty FROM products WHERE product_id = 7;

  v_label := CASE WHEN v_qty = 0 THEN 'Out of stock'
                  WHEN v_qty < 20 THEN 'Low'
                  ELSE 'OK'
             END;

  DBMS_OUTPUT.PUT_LINE(v_label);
END;
/
```

```text output
Out of stock
```

| | `CASE` statement | `CASE` expression |
|---|---|---|
| Ends with | `END CASE;` | `END` |
| Used as | A statement | A value |
| No match, no `ELSE` | Raises `CASE_NOT_FOUND` | Returns NULL |

**`WHEN NULL` in a simple `CASE` never matches,** even for a NULL selector. Use a searched `CASE` with `IS NULL`.

**Which to pick?** `IF` for a few mixed conditions, and `CASE` when many branches test one value. Write an `ELSE` in every `CASE` statement, unless the error is what you want.

### Printing a BOOLEAN on 11g

`DBMS_OUTPUT.PUT_LINE` cannot print a `BOOLEAN`, so convert it:

```sql oracle
DECLARE
  v_flag BOOLEAN := TRUE;
BEGIN
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_flag THEN 'TRUE'
                            WHEN NOT v_flag THEN 'FALSE'
                            ELSE 'NULL'
                       END);
END;
/
```

```text output
TRUE
```

**SQL functions you cannot use in a PL/SQL expression:** `DECODE`, aggregates such as `COUNT`, and analytics such as `LAG`. Use a `CASE` expression, or `SELECT ... INTO`.

## Loops

### Basic LOOP

The body runs until an exit. A loop with no exit never stops. It always enters at least once.

```sql oracle
DECLARE
  v_i PLS_INTEGER := 1;
BEGIN
  LOOP
    DBMS_OUTPUT.PUT_LINE('Pass ' || v_i);
    v_i := v_i + 1;
    EXIT WHEN v_i > 3;
  END LOOP;
END;
/
```

```text output
Pass 1
Pass 2
Pass 3
```

### WHILE loop

The condition is tested before each pass, so it can run zero times. A NULL condition ends it, just like FALSE.

```sql oracle
DECLARE
  v_total NUMBER := 0;
  v_i     PLS_INTEGER := 1;
BEGIN
  WHILE v_total < 10 LOOP
    v_total := v_total + v_i;
    v_i := v_i + 1;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Total: ' || v_total);
END;
/
```

```text output
Total: 10
```

### Numeric FOR loop

```sql oracle
BEGIN
  FOR i IN 1..3 LOOP
    DBMS_OUTPUT.PUT_LINE(i);
  END LOOP;

  FOR i IN REVERSE 1..3 LOOP
    DBMS_OUTPUT.PUT_LINE(i);
  END LOOP;
END;
/
```

```text output
1
2
3
3
2
1
```

`REVERSE` still takes low..high, so write `REVERSE 1..3`, not `REVERSE 3..1`.

**FOR index rules:**

- It is an implicit `PLS_INTEGER`.
- It is local to the loop, and undefined afterward.
- It is read-only.
- Bounds are evaluated once.
- It runs zero times when low is above high.

### Which loop should you use?

| Loop | Minimum passes | Use when |
|---|---|---|
| Basic `LOOP` | 1 | You must enter at least once |
| `WHILE` | 0 | A condition decides |
| `FOR` | 0 | The count is known |

## EXIT, CONTINUE and labels

`CONTINUE` and `CONTINUE WHEN` (11.1) skip the rest of the current pass.

```sql oracle
BEGIN
  FOR i IN 1..5 LOOP
    CONTINUE WHEN MOD(i, 2) = 0;
    DBMS_OUTPUT.PUT_LINE(i);
  END LOOP;
END;
/
```

```text output
1
3
5
```

**How do you leave an outer loop from inside an inner one?** Put a label on the outer loop, then `EXIT outer`.

```sql oracle
BEGIN
  <<outer>>
  FOR i IN 1..3 LOOP
    FOR j IN 1..3 LOOP
      EXIT outer WHEN i * j = 4;
      DBMS_OUTPUT.PUT_LINE(i || ' x ' || j);
    END LOOP;
  END LOOP outer;
END;
/
```

```text output
1 x 1
1 x 2
1 x 3
2 x 1
```

## NULL and GOTO

**The `NULL` statement** (`NULL;`) does nothing, and it is not the NULL value. Use it for a branch that must stay empty.

**`GOTO` exists, but avoid it.** It cannot jump into an `IF`, a `LOOP` or a sub-block.

## Newer features

Number-range iteration controls in 21c add `BY step` and chained ranges, such as `FOR i IN 1..3, 10..12`. 23ai adds extended `CASE`, with predicates such as `WHEN < 0`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Write `ELSEIF` | A compile error | Write `ELSIF` |
| Write `IF x = NULL` | Never true | Use `IS NULL` |
| Assume a false `IF` means `NOT` is true | NULL reaches neither | Handle NULL |
| Leave out `ELSE` in a `CASE` statement | `CASE_NOT_FOUND` | Add `ELSE` |
| Write `END` for a `CASE` statement | A compile error | Write `END CASE` |
| Write `REVERSE 3..1` | It runs zero times | Write `REVERSE 1..3` |
| Assign to the `FOR` index | A compile error | Use another variable |
| Read the index after the loop | It is out of scope | Copy it inside the loop |
| Forget `EXIT` in a basic `LOOP` | An endless loop | Add `EXIT WHEN` |

## Interview questions

**Q1. Is an empty string the same as NULL in PL/SQL? How should you test for it?**

Yes. Any zero-length string is NULL, so `IF x = ''` is never true. I test with `IS NULL`.

**Q2. What is the difference between a CASE statement and a CASE expression when no branch matches?**

The statement raises `CASE_NOT_FOUND`, and the expression returns NULL. The statement ends with `END CASE`, and the expression with `END`.

**Q3. What is the minimum number of times each loop type runs, and how do you leave an outer loop from inside an inner one?**

A basic loop runs at least once. `WHILE` and `FOR` can run zero times. To leave an outer loop, I label it, and use `EXIT label`.

**Q4. Why can both branches of IF x > y ... ELSIF NOT (x > y) be skipped?**

When x or y is NULL, both conditions are NULL, and `THEN` runs only for TRUE. So control goes to `ELSE`.

## Practice

**1. Print the numbers from 1 to 10 that are divisible by 3.**

<details>
<summary>Show solution</summary>

```sql oracle
BEGIN
  FOR i IN 1..10 LOOP
    IF MOD(i, 3) = 0 THEN
      DBMS_OUTPUT.PUT_LINE(i);
    END IF;
  END LOOP;
END;
/
```

```text output
3
6
9
```

</details>

**2. Compute 5 factorial with a `WHILE` loop.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_n      PLS_INTEGER := 5;
  v_result NUMBER := 1;
BEGIN
  WHILE v_n > 1 LOOP
    v_result := v_result * v_n;
    v_n := v_n - 1;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(v_result);
END;
/
```

```text output
120
```

</details>

**3. For employee 12, print 'No department' if `dept_id` is NULL, and otherwise the department id.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_dept employees.dept_id%TYPE;
BEGIN
  SELECT dept_id INTO v_dept FROM employees WHERE emp_id = 12;

  IF v_dept IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('No department');
  ELSE
    DBMS_OUTPUT.PUT_LINE(v_dept);
  END IF;
END;
/
```

```text output
No department
```

</details>

**4. What does this print?**

```sql oracle
DECLARE
  v_x NUMBER;
BEGIN
  IF v_x = 1 OR TRUE THEN
    DBMS_OUTPUT.PUT_LINE('A');
  ELSE
    DBMS_OUTPUT.PUT_LINE('B');
  END IF;
END;
/
```

<details>
<summary>Show solution</summary>

`A`. `v_x = 1` is NULL, and `NULL OR TRUE` is TRUE.

</details>

## Recap

- It is `ELSIF`, and `END IF` closes it.
- Test NULL with `IS NULL`. A NULL condition does not run `THEN`.
- A `CASE` statement with no match raises an error. A `CASE` expression gives NULL.
- A basic loop runs at least once. `WHILE` and `FOR` can run zero times.
- `REVERSE` still takes low..high.
- Use labels to leave an outer loop.

**Next:** [Chapter 44: Cursors](44-cursors.md)
