# 51. Dynamic SQL and SQL Injection

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 46](46-procedures-and-functions.md)

> **In one line:** Dynamic SQL is a statement built as a string at run time, which is powerful, and dangerous if user input gets into the string.

## What you will learn

- When dynamic SQL is required, and when it is not
- `EXECUTE IMMEDIATE` with `INTO` and `USING`
- Why a table name cannot be a bind variable
- How SQL injection works, and how to stop it
- Native dynamic SQL vs `DBMS_SQL`

## Static vs dynamic SQL

**Static SQL** is written in the code. It is checked at compile time, and it records dependencies. **Dynamic SQL** is a string built at run time, so it is checked only when it runs, and records no dependency.

**When is dynamic SQL required?**

- DDL
- Table or column names unknown until run time
- A variable number of `WHERE` conditions

Otherwise, use static SQL.

## EXECUTE IMMEDIATE

```sql oracle
BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLE dyn_demo (id NUMBER)';
  EXECUTE IMMEDIATE 'DROP TABLE dyn_demo';
END;
/
```

**No trailing semicolon** in SQL text. A dynamic PL/SQL block string does need its own semicolons.

### INTO and USING

`INTO` receives one row. `USING` binds values.

```sql oracle
DECLARE
  v_name employees.first_name%TYPE;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT first_name FROM employees WHERE emp_id = :id'
    INTO v_name
    USING 3;

  DBMS_OUTPUT.PUT_LINE(v_name);
END;
/
```

```text output
Priya
```

**A trap:** a dynamic `SELECT` with no `INTO` never runs, and no error tells you.

### DML, RETURNING and BULK COLLECT

```sql oracle
DECLARE
  v_new employees.salary%TYPE;
  TYPE t_names IS TABLE OF employees.first_name%TYPE;
  v_names t_names;
BEGIN
  EXECUTE IMMEDIATE
    'UPDATE employees SET salary = salary + :amt WHERE emp_id = :id
     RETURNING salary INTO :out_val'
    USING 1000, 11, OUT v_new;

  EXECUTE IMMEDIATE
    'SELECT first_name FROM employees WHERE dept_id = :d ORDER BY emp_id'
    BULK COLLECT INTO v_names
    USING 40;

  DBMS_OUTPUT.PUT_LINE(v_new || ', ' || v_names.COUNT);
  ROLLBACK;
END;
/
```

```text output
59000, 2
```

### OPEN FOR with a string

```sql oracle
DECLARE
  v_rc   SYS_REFCURSOR;
  v_name employees.first_name%TYPE;
BEGIN
  OPEN v_rc FOR
    'SELECT first_name FROM employees WHERE dept_id = :d ORDER BY emp_id'
    USING 40;

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

## Binds replace values, never identifiers

**Can you pass a table name as a bind variable?** No. Binds replace **values**, never identifiers, because the statement must be parsed before binds are applied. Table and column names need validated concatenation.

```sql oracle
DECLARE
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM :t' INTO v_count USING 'EMPLOYEES';
END;
/
```

That fails with `ORA-00903: invalid table name`.

**Other details:**

- The literal NULL cannot be bound. Use an uninitialized variable.
- Repeated placeholders bind by position in a SQL statement, but by unique name in a dynamic PL/SQL block.
- Statements over 32K can be passed as a `CLOB` (11.1).

## Risks and benefits

| Benefits | Risks |
|---|---|
| DDL from code | SQL injection |
| Run-time table names | Errors only at run time |
| Optional filters | No dependency tracking |
| | Hard parses, if you concatenate values |

## SQL injection

**SQL injection** happens when concatenated user input changes the statement.

```sql oracle
CREATE OR REPLACE FUNCTION count_by_name (p_name IN VARCHAR2)
RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM employees WHERE last_name = ''' || p_name || ''''
    INTO v_count;
  RETURN v_count;
END count_by_name;
/
```

A normal input gives this statement:

```text
SELECT COUNT(*) FROM employees WHERE last_name = 'Khan'
```

An attacker passes `x' OR '1'='1`, which gives this:

```text
SELECT COUNT(*) FROM employees WHERE last_name = 'x' OR '1'='1'
```

The `WHERE` is now always true.

**Techniques:**

- **Statement modification:** adding `OR 1=1` to a `WHERE`.
- **Statement injection:** adding a whole new statement to a dynamic PL/SQL block.
- **Data type conversion:** using a session setting, such as `NLS_DATE_FORMAT`, to inject text through an implicit conversion.

## How do you prevent SQL injection?

### Defense 1: bind variables for every value

This is the fix, and it also helps performance.

```sql oracle
CREATE OR REPLACE FUNCTION count_by_name (p_name IN VARCHAR2)
RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM employees WHERE last_name = :n'
    INTO v_count
    USING p_name;
  RETURN v_count;
END count_by_name;
/
```

The input is now just a value. It can never change the SQL text.

### Defense 2: validate identifiers

Identifiers cannot be bound. Validate them against the data dictionary, or a white list.

```sql oracle
DECLARE
  v_table  VARCHAR2(128) := 'EMPLOYEES';
  v_exists NUMBER;
  v_count  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = v_table;

  IF v_exists = 0 THEN
    RAISE_APPLICATION_ERROR(-20050, 'Unknown table');
  END IF;

  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM ' || DBMS_ASSERT.ENQUOTE_NAME(v_table)
    INTO v_count;

  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

```text output
12
```

**`DBMS_ASSERT`** functions:

| Function | Use |
|---|---|
| `ENQUOTE_NAME` | Quote an identifier |
| `ENQUOTE_LITERAL` | Quote a string |
| `SIMPLE_SQL_NAME` | Check a simple name |
| `QUALIFIED_SQL_NAME` | Check a qualified name |
| `SCHEMA_NAME`, `SQL_OBJECT_NAME` | Check an object exists |
| `NOOP` | Validates nothing |

`DBMS_ASSERT` helps, but it is not complete on its own.

### Defense 3: explicit format models

Use an explicit format model in `TO_CHAR` and `TO_DATE`, so that a session `NLS_DATE_FORMAT` cannot change the statement.

### Keep the damage small

A stored unit normally runs with its owner's privileges, so injected SQL runs as the owner. Grant the owner only what it needs ([Chapter 52](52-advanced-plsql.md)).

### A safe optional-filter search

Build the `WHERE` text from fixed fragments, and bind every value.

```sql oracle
DECLARE
  v_dept  employees.dept_id%TYPE := 20;
  v_min   employees.salary%TYPE;           -- not supplied
  v_sql   VARCHAR2(500) := 'SELECT COUNT(*) FROM employees WHERE 1 = 1';
  v_count NUMBER;
BEGIN
  IF v_dept IS NOT NULL THEN
    v_sql := v_sql || ' AND dept_id = :d';
  END IF;

  IF v_min IS NOT NULL THEN
    v_sql := v_sql || ' AND salary >= :m';
  END IF;

  IF v_dept IS NOT NULL AND v_min IS NOT NULL THEN
    EXECUTE IMMEDIATE v_sql INTO v_count USING v_dept, v_min;
  ELSIF v_dept IS NOT NULL THEN
    EXECUTE IMMEDIATE v_sql INTO v_count USING v_dept;
  ELSIF v_min IS NOT NULL THEN
    EXECUTE IMMEDIATE v_sql INTO v_count USING v_min;
  ELSE
    EXECUTE IMMEDIATE v_sql INTO v_count;
  END IF;

  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

```text output
4
```

## Native dynamic SQL vs DBMS_SQL

| | Native (`EXECUTE IMMEDIATE`) | `DBMS_SQL` |
|---|---|---|
| Code | Short | Long |
| Speed | Usually faster | Slower |
| Unknown select list | No | **Yes** |
| Unknown number of binds | No | **Yes** |

**When do you need `DBMS_SQL`?** When the select list or the binds are unknown until run time. Otherwise, use native dynamic SQL.

**Switching between them:** `DBMS_SQL.TO_REFCURSOR` and `TO_CURSOR_NUMBER` (11.1).

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Concatenate user input | SQL injection | Bind it |
| Bind a table name | `ORA-00903` | Validate, then concatenate |
| End a SQL string with `;` | `ORA-00933` or `ORA-00911` | Leave it out |
| Forget `INTO` on a dynamic `SELECT` | It never runs, silently | Add `INTO` |
| Use dynamic SQL for fixed statements | Late errors, and no dependencies | Use static SQL |
| Trust `DBMS_ASSERT.NOOP` | It checks nothing | Use a real check |
| Concatenate values | Hard parses | Bind them |

## Interview questions

**Q1. What is dynamic SQL, and how does EXECUTE IMMEDIATE work?**

Dynamic SQL is a statement built as a string at run time. `EXECUTE IMMEDIATE` parses and runs it, with `INTO` for results and `USING` for bind values. I use it for DDL, and for names unknown until run time.

**Q2. Can you pass a table name as a bind variable in dynamic SQL?**

No. Binds replace values, and the statement must be parsed before binds are applied. I validate the name against the data dictionary or a white list, then concatenate it.

**Q3. What are the risks and benefits of using dynamic SQL?**

It gives flexibility: DDL, run-time names, and optional filters. The risks are SQL injection, errors found only at run time, no dependency tracking, and hard parses if values are concatenated.

**Q4. How do you prevent SQL injection in PL/SQL?**

Bind every value, so that input can never change the SQL text. Validate identifiers against the dictionary or with `DBMS_ASSERT`. Use explicit format models. And give the code's owner only the privileges it needs.

**Q5. Native dynamic SQL or DBMS_SQL: when do you need DBMS_SQL?**

Native is the default. I need `DBMS_SQL` when the select list or the number of binds is unknown until run time.

## Practice

**1. Rewrite this to be safe: `EXECUTE IMMEDIATE 'DELETE FROM orders WHERE status = ''' || p_status || '''';`**

<details>
<summary>Show solution</summary>

```sql norun
EXECUTE IMMEDIATE 'DELETE FROM orders WHERE status = :s' USING p_status;
```

Better still, use static SQL here, because nothing about the statement is dynamic.

</details>

**2. Use `EXECUTE IMMEDIATE` to count the rows in `products`, with the table name in a variable.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_table VARCHAR2(128) := 'PRODUCTS';
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(v_table)
    INTO v_count;

  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

```text output
10
```

</details>

**3. An input of `' OR 1=1 --` is passed to a concatenated query. What does the `--` do?**

<details>
<summary>Show solution</summary>

It comments out the rest of the statement, including the closing quote the code added, so the injected text stays valid SQL.

</details>

## Recap

- Use static SQL unless you need DDL, or run-time names, or optional filters.
- `INTO` receives results, and `USING` binds values.
- Binds replace values, never identifiers.
- Concatenating input invites SQL injection.
- Bind every value, and validate every identifier.
- `DBMS_SQL` is for an unknown select list or unknown binds.

**Next:** [Chapter 52: Advanced PL/SQL](52-advanced-plsql.md)
