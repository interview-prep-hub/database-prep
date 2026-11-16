# 48. Triggers: Code That Runs Automatically

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 47](47-packages.md)

> **In one line:** A trigger is named PL/SQL that the database runs automatically when an event happens.

## What you will learn

- The kinds of trigger, and their firing order
- `:OLD`, `:NEW` and the `WHEN` clause
- Why you cannot commit in a trigger
- The mutating table error, and how to fix it
- Compound triggers and `INSTEAD OF` triggers

## What is a trigger?

A **trigger** runs automatically on an event. You can enable or disable it, but you cannot call it.

**The kinds:** simple DML, compound, `INSTEAD OF`, and system triggers.

**Where to do what.** Use a constraint when a constraint can do the job. Use a trigger only for actions that must happen whoever changes the data, such as an audit row. Keep business logic out of triggers ([Chapter 41](../part-6-architecture-and-scale/41-where-to-do-what.md)).

## Statement vs row level

A **statement** trigger fires once, even for zero rows. A **row** trigger (`FOR EACH ROW`) fires once per changed row.

```sql oracle
CREATE OR REPLACE TRIGGER emp_stmt_trg
AFTER UPDATE ON employees
BEGIN
  DBMS_OUTPUT.PUT_LINE('Statement fired');
END;
/

CREATE OR REPLACE TRIGGER emp_row_trg
AFTER UPDATE ON employees
FOR EACH ROW
BEGIN
  DBMS_OUTPUT.PUT_LINE('Row fired for ' || :OLD.emp_id);
END;
/

UPDATE employees SET salary = salary WHERE dept_id = 40;
ROLLBACK;

DROP TRIGGER emp_stmt_trg;
DROP TRIGGER emp_row_trg;
```

```text output
Row fired for 4
Row fired for 11
Statement fired
```

### Firing order

```text
1. BEFORE statement
2. For each row:
     BEFORE row
     the row change, with constraint checks
     AFTER row
3. AFTER statement
```

**Several triggers at the same point:** the order is not defined unless you use `FOLLOWS` (11.1).

## :OLD and :NEW

| Event | `:OLD` | `:NEW` |
|---|---|---|
| `INSERT` | NULL | The new values |
| `UPDATE` | The old values | The new values |
| `DELETE` | The old values | NULL |

Neither exists in statement triggers.

**Writing them.** Changing `:OLD` raises `ORA-04085`. Changing `:NEW` is allowed only in a `BEFORE` row trigger, and elsewhere raises `ORA-04084`.

```sql oracle
CREATE OR REPLACE TRIGGER emp_email_lower
BEFORE INSERT OR UPDATE OF email ON employees
FOR EACH ROW
BEGIN
  :NEW.email := LOWER(:NEW.email);
END;
/
```

### The WHEN clause

`WHEN` needs `FOR EACH ROW`, uses **no colon** before `NEW` or `OLD`, and allows no subquery. False skips only the trigger body, and the statement still runs.

### Conditional predicates

`INSERTING`, `UPDATING`, `UPDATING('col')` and `DELETING` tell a trigger on several events what fired it.

```sql oracle
CREATE OR REPLACE TRIGGER emp_change_log
BEFORE INSERT OR UPDATE OR DELETE ON employees
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    DBMS_OUTPUT.PUT_LINE('New: ' || :NEW.emp_id);
  ELSIF DELETING THEN
    DBMS_OUTPUT.PUT_LINE('Gone: ' || :OLD.emp_id);
  ELSIF UPDATING('SALARY') THEN
    DBMS_OUTPUT.PUT_LINE('Pay change: ' || :OLD.emp_id);
  END IF;
END;
/
```

`UPDATE OF col` fires when the column is in the `SET` list, even if the value does not change.

### What fires what

- `TRUNCATE` fires DDL triggers, but not `DELETE` triggers.
- `MERGE` fires the `INSERT`, `UPDATE` and `DELETE` triggers of the actions it performs.

## An audit trigger

```sql oracle
CREATE TABLE salary_audit (
  emp_id      NUMBER(6),
  old_salary  NUMBER(10),
  new_salary  NUMBER(10),
  changed_by  VARCHAR2(30),
  changed_at  DATE
);

CREATE OR REPLACE TRIGGER emp_salary_audit
AFTER UPDATE OF salary ON employees
FOR EACH ROW
WHEN (NEW.salary <> OLD.salary)
BEGIN
  INSERT INTO salary_audit (emp_id, old_salary, new_salary, changed_by, changed_at)
  VALUES (:OLD.emp_id, :OLD.salary, :NEW.salary, USER, SYSDATE);
END;
/
```

The audit row shares the transaction, so it rolls back with the change. An **autonomous** audit trigger survives rollback, and so it records attempts that never committed.

**Side effects that cannot roll back.** `UTL_HTTP`, or sending mail from a trigger, is not transactional. A `BEFORE` row trigger can also fire again when its statement restarts, so keep triggers free of outside effects.

## Exceptions in triggers

An unhandled exception undoes the trigger and the statement. A handled one lets the statement proceed. Use `RAISE_APPLICATION_ERROR` to block DML.

**Can you commit in a trigger?** Not in a normal one. `COMMIT` raises `ORA-04092`, and so does calling a subprogram that commits. A trigger runs inside the statement's transaction. Only an **autonomous** trigger can run TCL or DDL.

## The mutating table error

**A row-level trigger cannot query or modify the table being changed.** That gives `ORA-04091`.

```sql oracle
CREATE OR REPLACE TRIGGER emp_check_avg
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
DECLARE
  v_avg NUMBER;
BEGIN
  SELECT AVG(salary) INTO v_avg FROM employees;   -- ORA-04091 at run time

  IF :NEW.salary > v_avg * 5 THEN
    RAISE_APPLICATION_ERROR(-20020, 'Salary too high');
  END IF;
END;
/
```

**Why does this rule exist?** During a multi-row update, the table is halfway changed, so a query would see an inconsistent mix of old and new rows.

Statement-level triggers are not affected. A single-row `INSERT ... VALUES` is a special case: a `BEFORE` row trigger can read the table.

**What is the difference between a mutating table and a constraining table?** A mutating table is being changed by the statement, possibly through `ON DELETE CASCADE`. A constraining table is one the statement may need to read to check a foreign key.

**How do you fix `ORA-04091`?**

| Fix | When |
|---|---|
| A statement-level trigger | The check can run once |
| A compound trigger | You need row data and a table read |
| An autonomous transaction | Rarely. It reads committed data only, so it can be wrong |

## Compound triggers

**What is a compound trigger, and what problem does it solve?** It is one trigger (11.1) with sections for each timing point, sharing variables. It solves the mutating table error: read in `BEFORE STATEMENT`, then check each row.

```sql oracle
CREATE OR REPLACE TRIGGER emp_salary_check
FOR UPDATE OF salary ON employees
COMPOUND TRIGGER

  g_avg NUMBER;

  BEFORE STATEMENT IS
  BEGIN
    SELECT AVG(salary) INTO g_avg FROM employees;
  END BEFORE STATEMENT;

  BEFORE EACH ROW IS
  BEGIN
    IF :NEW.salary > g_avg * 5 THEN
      RAISE_APPLICATION_ERROR(-20020, 'Salary too high');
    END IF;
  END BEFORE EACH ROW;

END emp_salary_check;
/
```

**Rules:** no initialization section, it cannot be autonomous, `:OLD` and `:NEW` work only in row sections, and only `BEFORE EACH ROW` can change `:NEW`.

## INSTEAD OF triggers

**What is an `INSTEAD OF` trigger? How can you update a complex view?** It runs instead of the DML, on a view that cannot be updated directly. It is always row level, and it is the only way to make such a view writable.

```sql oracle
CREATE OR REPLACE VIEW emp_dept_v AS
SELECT e.emp_id, e.first_name, d.dept_name
FROM employees e
JOIN departments d ON d.dept_id = e.dept_id;

CREATE OR REPLACE TRIGGER emp_dept_v_upd
INSTEAD OF UPDATE ON emp_dept_v
FOR EACH ROW
BEGIN
  UPDATE employees
  SET first_name = :NEW.first_name
  WHERE emp_id = :OLD.emp_id;
END;
/
```

## System triggers

These fire on events at `SCHEMA` or `DATABASE` level.

```sql oracle
CREATE OR REPLACE TRIGGER no_drop_tables
BEFORE DROP ON SCHEMA
BEGIN
  IF ORA_DICT_OBJ_TYPE = 'TABLE' THEN
    RAISE_APPLICATION_ERROR(-20030, 'Dropping tables is not allowed');
  END IF;
END;
/
```

**A warning:** a failing `AFTER LOGON ON DATABASE` trigger blocks logins, except for users with `ADMINISTER DATABASE TRIGGER`.

## Cross-row rules

A rule such as "at most 3 open orders per customer" cannot be safely enforced by a trigger alone. A trigger cannot see other sessions' uncommitted rows, so it races unless it serializes, for example with `SELECT ... FOR UPDATE` on the customer row.

## Managing triggers

- Enabled by default. `CREATE ... DISABLE` (11.1) compiles first.
- `ALTER TRIGGER t DISABLE`, and `ALTER TABLE t DISABLE ALL TRIGGERS`.
- `USER_TRIGGERS` lists them.
- The owner needs direct grants, because roles do not count.

**How many triggers can you define on one table?** There is no fixed limit. The old answer of 12 only counts the timing combinations: `BEFORE` or `AFTER`, row or statement, `INSERT`, `UPDATE` or `DELETE`. Keep it to as few as possible.

**Guidelines:** do not duplicate constraints, do not depend on row order, avoid self-updating recursive triggers, and call a procedure rather than writing long trigger bodies.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use a trigger where a constraint works | Slower, and it can race | Use the constraint |
| Query the same table in a row trigger | `ORA-04091` | Use a compound trigger |
| `COMMIT` in a trigger | `ORA-04092` | Do not. Use an autonomous transaction if truly needed |
| Use `:NEW` with a colon in `WHEN` | A compile error | No colon in `WHEN` |
| Change `:NEW` in an `AFTER` trigger | `ORA-04084` | Use `BEFORE` |
| Send email from a trigger | It cannot roll back | Queue it |
| Depend on the order of triggers | It is not guaranteed | Use `FOLLOWS`, or merge them |
| Expect delete triggers on `TRUNCATE` | They do not fire | Use `DELETE` if they must |
| Hide business logic in triggers | Nobody can follow it | Keep it in procedures |

## Interview questions

**Q1. What types of triggers are there, and what is their firing order?**

DML triggers, at statement or row level, plus compound, `INSTEAD OF` and system triggers. The order is `BEFORE` statement, then per row `BEFORE` row and `AFTER` row, then `AFTER` statement.

**Q2. What are :OLD and :NEW, and where can each be read or written?**

They are the row before and after the change. `:OLD` is NULL on insert, and `:NEW` is NULL on delete. `:OLD` can never be written. `:NEW` can be written only in a `BEFORE` row trigger. Neither exists in statement triggers.

**Q3. Can you commit inside a trigger?**

Not in a normal trigger: it raises `ORA-04092`, because the trigger runs inside the statement's transaction. Only an autonomous trigger can.

**Q4. What is a mutating table error, and how do you resolve it?**

`ORA-04091` is raised when a row-level trigger queries or changes the table being modified, because the table is in a mid-change state. I fix it with a statement-level trigger, or a compound trigger that reads in `BEFORE STATEMENT`.

**Q5. What is the difference between a mutating table and a constraining table?**

A mutating table is being changed by the statement. A constraining table is read to check a foreign key.

**Q6. What is a compound trigger, and what problem does it solve?**

One trigger with sections for each timing point, sharing state. It avoids the mutating error, and lets me collect row data and act once at the end.

**Q7. What is an INSTEAD OF trigger? How can you update a complex view?**

A trigger on a view that runs instead of the DML. It lets me define how an update on a join view changes the base tables.

**Q8. How many triggers can you define on one table?**

There is no fixed limit. The answer 12 counts the timing combinations. I keep them few, because order and hidden effects get hard to manage.

## Practice

**1. Write a trigger that stops salaries being reduced.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE TRIGGER no_pay_cut
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
WHEN (NEW.salary < OLD.salary)
BEGIN
  RAISE_APPLICATION_ERROR(-20040, 'Salaries cannot be reduced');
END;
/
```

</details>

**2. On Oracle 11g, write a trigger that fills `ticket_id` from a sequence.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE TRIGGER tickets_bi
BEFORE INSERT ON tickets
FOR EACH ROW
WHEN (NEW.ticket_id IS NULL)
BEGIN
  :NEW.ticket_id := ticket_seq.NEXTVAL;
END;
/
```

From 12c, an identity column replaces this.

</details>

**3. A row trigger on `orders` updates `customers`. Is that a mutating table problem?**

<details>
<summary>Show solution</summary>

No. Only `orders` is mutating. Updating a different table is fine, unless a cascade or another trigger brings it back to `orders`.

</details>

## Recap

- Row triggers fire per row, and statement triggers once.
- `BEFORE` row can change `:NEW`. `:OLD` is read-only.
- `WHEN` uses no colon.
- You cannot `COMMIT` in a normal trigger.
- `ORA-04091`: a row trigger touched its own table. Use a compound trigger.
- `INSTEAD OF` makes complex views writable.
- Prefer constraints, and keep triggers small.

**Next:** [Chapter 49: Records and collections](49-records-and-collections.md)
