# 47. Packages: Grouping Related Code

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 46](46-procedures-and-functions.md)

> **In one line:** A package is a named container for related code, with a public specification and a private body.

## What you will learn

- Spec vs body, and public vs private items
- Why packages are better than standalone procedures
- Overloading, and how Oracle chooses a version
- Package state, and the problems it causes
- `ORA-04068`, and how to handle it
- What gets invalidated when you change code

## What is a package?

A **package** groups related procedures, functions, types, variables, constants, cursors and exceptions, in two parts. The **spec** is the menu, and the **body** is the kitchen.

| | Specification | Body |
|---|---|---|
| Contains | Declarations | Code |
| Visible to | Everyone with `EXECUTE` | Only the package |
| Create it | First | Second |

**Benefits:**

- **Encapsulation:** private helpers stay hidden.
- **Overloading:** one name, different parameters.
- **Session state:** variables persist for the session.
- **Performance:** the whole package loads on first use.
- **Fewer recompiles:** callers depend on the spec, not the body.

## Building a package

```sql oracle
CREATE OR REPLACE PACKAGE emp_pkg IS
  c_max_raise CONSTANT NUMBER := 20;

  e_raise_too_big EXCEPTION;

  PROCEDURE give_raise (
    p_emp_id  IN employees.emp_id%TYPE,
    p_percent IN NUMBER
  );

  FUNCTION full_name (
    p_emp_id IN employees.emp_id%TYPE
  ) RETURN VARCHAR2;
END emp_pkg;
/

CREATE OR REPLACE PACKAGE BODY emp_pkg IS

  -- private: not in the spec, so callers cannot see it
  PROCEDURE check_percent (p_percent IN NUMBER) IS
  BEGIN
    IF p_percent > c_max_raise THEN
      RAISE e_raise_too_big;
    END IF;
  END check_percent;

  PROCEDURE give_raise (
    p_emp_id  IN employees.emp_id%TYPE,
    p_percent IN NUMBER
  ) IS
  BEGIN
    check_percent(p_percent);

    UPDATE employees
    SET salary = salary * (1 + p_percent / 100)
    WHERE emp_id = p_emp_id;
  END give_raise;

  FUNCTION full_name (
    p_emp_id IN employees.emp_id%TYPE
  ) RETURN VARCHAR2 IS
    v_name VARCHAR2(61);
  BEGIN
    SELECT first_name || ' ' || last_name
    INTO v_name
    FROM employees
    WHERE emp_id = p_emp_id;

    RETURN v_name;
  END full_name;

END emp_pkg;
/

BEGIN
  DBMS_OUTPUT.PUT_LINE(emp_pkg.full_name(3));
END;
/
```

```text output
Priya Sharma
```

Headings in the spec and body must match word for word (`PLS-00323`). A private subprogram must be declared before its first use, or be forward-declared.

**When is a body needed?** When the spec declares a subprogram, or a cursor with no query. A package of only constants, types and exceptions needs no body. This is a neat way to share names across a system:

```sql oracle
CREATE OR REPLACE PACKAGE app_const IS
  c_status_pending CONSTANT VARCHAR2(10) := 'PENDING';
  e_not_found      EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_not_found, -20100);
END app_const;
/
```

**Plain SQL cannot read a package constant directly,** so expose it through a function. Static SQL inside PL/SQL can use it.

`DROP PACKAGE` removes spec and body. `DROP PACKAGE BODY` removes only the body. `ALTER PACKAGE p COMPILE` recompiles.

## Overloading

**What is overloading, where is it allowed, and how does Oracle choose?** It means the same name with different parameters. It is allowed for nested, package and type subprograms, and **never for standalone ones**.

```sql oracle
CREATE OR REPLACE PACKAGE report_pkg IS
  PROCEDURE show (p_value IN NUMBER);
  PROCEDURE show (p_value IN VARCHAR2);
  PROCEDURE show (p_value IN DATE);
END report_pkg;
/
```

Oracle matches the number, order and types of the actuals.

**What does not count as overloading:** differences only in mode, subtype or return type. `PLS-00307` reports an ambiguous call.

## Package state

**Instantiation.** Each session gets its own copy of a package at first reference. Oracle assigns public constants, then public variables, then runs the initialization part once.

**Package state** is the values of a package's variables and cursors. It lasts for the session, and only that session sees it.

```sql oracle
CREATE OR REPLACE PACKAGE counter_pkg IS
  g_count NUMBER := 0;
  PROCEDURE add_one;
END counter_pkg;
/

CREATE OR REPLACE PACKAGE BODY counter_pkg IS
  PROCEDURE add_one IS
  BEGIN
    g_count := g_count + 1;
  END add_one;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Initialized once');
END counter_pkg;
/

BEGIN
  counter_pkg.add_one;
  counter_pkg.add_one;
  DBMS_OUTPUT.PUT_LINE(counter_pkg.g_count);
END;
/
```

```text output
Initialized once
2
```

**What is package state, and how can it cause problems?**

| Problem | Why |
|---|---|
| `ORA-04068` | Recompiling discards the state |
| Connection pools | Globals carry over between end users |
| Open cursors | They stay open across calls |
| Memory | Large collections stay in session memory |

**A cursor in a package spec vs one in a procedure.** A package cursor stays open across calls until closed, or until the session ends, which causes `CURSOR_ALREADY_OPEN`, and leaks. A local cursor closes when it goes out of scope.

### ORA-04068

**What does `ORA-04068` mean?** "Existing state of packages has been discarded." Recompiling the body of a stateful package that a session has already used discards that state. The next call raises the error, and the call after that re-instantiates the package.

**How do you deal with it in production?**

- **Keep packages stateless.** A package whose items are all compile-time constants counts as stateless, from 11.2.0.2.
- Move state to a context or a table.
- Deploy at quiet times, and have the application retry once.
- Use Edition-Based Redefinition for zero-downtime deployments.

### Connection pool hazard

Package globals carry over between pooled end users. So never store user-specific data in a package variable without resetting it. `DBMS_SESSION.RESET_PACKAGE` takes effect only after the current call.

### SERIALLY_REUSABLE

`PRAGMA SERIALLY_REUSABLE` limits state to one server call, and keeps it in a pool in the SGA. It goes in the spec, and in the body too when there is one. It reduces memory, at the cost of losing state between calls.

## Dependencies

**What happens to dependent objects when you change a package body compared with its specification?** Body changes do **not** invalidate dependents. Spec changes do. That is the great benefit of packages: you can fix logic in the body with no ripple effect.

Add new items at the end of the spec, to keep entry points stable.

**How do you find what depends on a table or package before changing it?**

```sql oracle
SELECT name, type
FROM user_dependencies
WHERE referenced_name = 'EMPLOYEES'
ORDER BY type, name;
```

**Fine-grained invalidation (11.1).** Only a change to the items a unit really uses invalidates it. `ALTER TABLE ... ADD` goes coarse for code with `SELECT *`, `%ROWTYPE`, or an `INSERT` with no column list.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Put private helpers in the spec | Callers depend on them | Keep them in the body |
| Change the spec for a logic fix | Dependents are invalidated | Change only the body |
| Use a private subprogram before declaring it | A compile error | Reorder, or forward-declare |
| Overload on return type alone | `PLS-00305` or ambiguous calls | Differ in parameters |
| Keep user data in globals behind a pool | It leaks between users | Stay stateless |
| Leave a package cursor open | `CURSOR_ALREADY_OPEN` | Use local cursors |
| Deploy stateful packages at peak time | `ORA-04068` for live sessions | Stay stateless, or use EBR |

## Interview questions

**Q1. What is a package, what are its parts, and what are the benefits of using one?**

A package groups related code. The spec is the public interface, and the body holds the code and private items. The benefits are encapsulation, overloading, session state, loading as one unit, and fewer recompiles, because callers depend only on the spec.

**Q2. What is overloading, where is it allowed, and how does Oracle choose which version to call?**

The same name with different parameters. It is allowed in packages, nested subprograms and object types, but not for standalone ones. Oracle matches the number, order and types of the arguments. Differences only in mode or return type do not count.

**Q3. What is package state, and how can it cause problems?**

It is the values of package variables and cursors, which last for the session. It can cause `ORA-04068` on recompile, leak between users behind a connection pool, and hold memory.

**Q4. How does a cursor declared in a package specification differ from one declared inside a procedure?**

A package cursor stays open across calls, until closed or the session ends. A local cursor closes when it goes out of scope.

**Q5. What does ORA-04068 mean, and how do you deal with it in production?**

The state of a package was discarded, usually by recompiling a stateful package that a session had already used. The next call fails, and the one after works. I keep packages stateless, deploy carefully, and let the application retry once. EBR helps for zero downtime.

**Q6. What happens to dependent objects when you change a package body compared with its specification?**

Changing the body does not invalidate them. Changing the spec can, though fine-grained invalidation limits it to units that use the changed items.

**Q7. How do you find what depends on a table or package before changing it?**

Query `USER_DEPENDENCIES` or `ALL_DEPENDENCIES`, where the referenced name is the object.

## Practice

**1. Write a package `order_pkg` with a public function `total(p_order_id)` and a private function that rounds a value to 2 decimals.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE OR REPLACE PACKAGE order_pkg IS
  FUNCTION total (p_order_id IN orders.order_id%TYPE) RETURN NUMBER;
END order_pkg;
/

CREATE OR REPLACE PACKAGE BODY order_pkg IS

  FUNCTION money (p_value IN NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN ROUND(p_value, 2);
  END money;

  FUNCTION total (p_order_id IN orders.order_id%TYPE) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT SUM(quantity * unit_price)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    RETURN money(v_total);
  END total;

END order_pkg;
/

BEGIN
  DBMS_OUTPUT.PUT_LINE(order_pkg.total(1005));
END;
/
```

```text output
1018.99
```

</details>

**2. You fix a bug inside a function in a package body. Which objects become invalid?**

<details>
<summary>Show solution</summary>

None of the dependents. They depend on the spec. Sessions that hold state in that package may get `ORA-04068` once.

</details>

**3. Why can't you overload a standalone procedure?**

<details>
<summary>Show solution</summary>

A standalone procedure is a schema object, and a name can belong to only one object in a schema. Overloading needs a scope that can hold several versions, such as a package.

</details>

## Recap

- A package has a public spec and a private body.
- Body changes do not invalidate dependents.
- Overloading works in packages, not for standalone units.
- State lasts for the session, and each session has its own.
- `ORA-04068` means state was discarded. Stay stateless.
- Package globals can leak through connection pools.
- `USER_DEPENDENCIES` shows what will be affected.

**Next:** [Chapter 48: Triggers](48-triggers.md)
