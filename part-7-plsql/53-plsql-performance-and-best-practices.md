# 53. Making PL/SQL Fast, Safe and Easy to Deploy

**Level:** Advanced | **Interview priority:** Should know | **Before this:** [Chapter 50](50-bulk-processing.md)

> **In one line:** Measure first, because most PL/SQL time is spent in the SQL it runs, then fix things in the right order.

## What you will learn

- How to trace, profile and debug PL/SQL
- Why a function in a `WHERE` clause is slow, and how to fix it
- Compiler settings and pragmas
- Coding standards and testing
- How to deploy a package with no downtime

## Measure before you tune

Find the slow part first. Most PL/SQL time is usually spent in its SQL.

**The tuning order:**

1. Set-based SQL.
2. `BULK COLLECT` with `LIMIT`, and `FORALL`.
3. Fewer context switches.
4. Compiler options.

## Tracing and debugging

**What are the ways to trace and debug PL/SQL?**

| Tool | Gives |
|---|---|
| `DBMS_OUTPUT`, log tables | Your own messages |
| SQL Trace with TKPROF | The SQL side |
| `DBMS_PROFILER` | Time per line, stored in tables |
| `DBMS_HPROF` (11.1) | A call tree, with SQL and PL/SQL time apart |
| SQL Developer debugger | Stepping through code |

**How do `DBMS_PROFILER` and `DBMS_HPROF` differ?** `DBMS_PROFILER` is line-level. `DBMS_HPROF` is the hierarchical profiler: it shows the call tree, separates SQL from PL/SQL time, and needs no special compile.

### Instrument your code

`DBMS_APPLICATION_INFO` sets module and action, so that a DBA can see what a session is doing.

```sql oracle
BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE('nightly_batch', 'load_orders');
  -- work happens here
  DBMS_APPLICATION_INFO.SET_ACTION('update_totals');
  -- more work
  DBMS_APPLICATION_INFO.SET_MODULE(NULL, NULL);
END;
/
```

## Functions called from SQL

They run once per row, and they hide their cost from the plan. Each query inside the function also gets its own read-consistent view, which can give inconsistent results within one statement.

**A PL/SQL function called in a `WHERE` clause makes a query slow. How do you diagnose and fix it?** Read the plan, compare with and without the function, and profile it. A function around a column also blocks a normal index.

**Fixes, in order:**

1. Replace the function with a join, or a plain SQL expression.
2. Wrap it as a scalar subquery, so that caching applies.
3. Use a function-based index, if it is deterministic.
4. Use `DETERMINISTIC` or the result cache.
5. Reduce the call overhead.

### Cutting call overhead

| Tool | Release | How |
|---|---|---|
| `PRAGMA UDF` | 12.1 | Compiles a function for calls from SQL |
| `WITH FUNCTION` | 12.1 | Declares a function inside the query |
| SQL macros | 19c and later | Folds logic into the SQL at parse time |
| SQL Transpiler | 23ai | Turns simple functions into SQL expressions. Off by default |

```sql oracle since=12c
WITH FUNCTION yearly (p_salary NUMBER) RETURN NUMBER IS
BEGIN
  RETURN p_salary * 12;
END;
SELECT first_name, yearly(salary) AS annual
FROM employees
WHERE dept_id = 40
/
```

## ORA-01555 from your own code

**What could cause `ORA-01555` in your own PL/SQL code?** Committing inside a cursor loop. The cursor needs undo that your own commits have released. Commit once at the end, or use a fresh cursor per batch.

## Compiler settings

**`PLSQL_OPTIMIZE_LEVEL`** is 0 to 3, the default is 2, and it is stored with the unit.

| Level | Effect |
|---|---|
| 0, 1 | Little or no optimization. 1 is for debugging |
| 2 | The default. Reorders code, and fetches in batches in FOR loops |
| 3 | Also inlines subprograms automatically |

**`PRAGMA INLINE`** (11.1) works at level 2, and `NO` overrides `YES`.

**What is native compilation, and how does it relate to `PLSQL_OPTIMIZE_LEVEL`?** `PLSQL_CODE_TYPE = NATIVE` compiles to machine code. It helps computation-heavy code, not SQL-heavy code. It needs no C compiler from 11.1, and it is ignored below optimization level 2.

```sql oracle
ALTER SESSION SET PLSQL_CODE_TYPE = 'NATIVE';
ALTER SESSION SET PLSQL_OPTIMIZE_LEVEL = 3;

ALTER PROCEDURE say_hello COMPILE;
```

Settings are stored per unit in `USER_PLSQL_OBJECT_SETTINGS`, and kept with `ALTER ... COMPILE REUSE SETTINGS`.

## Pragmas

**What are pragmas?** Instructions to the compiler.

| Pragma | Purpose | Chapter |
|---|---|---|
| `AUTONOMOUS_TRANSACTION` | An independent transaction | [52](52-advanced-plsql.md) |
| `EXCEPTION_INIT` | Name an error code | [45](45-exceptions.md) |
| `SERIALLY_REUSABLE` | State for one call | [47](47-packages.md) |
| `INLINE` | Inline a subprogram | Here |
| `UDF` (12.1) | Faster calls from SQL | Here |
| `DEPRECATE` (12.2) | Warn about old code | Here |

## Coding standards

- Anchor types with `%TYPE`.
- State `AUTHID` explicitly.
- Use explicit conversions.
- Keep units small.
- No `WHEN OTHERS THEN NULL`.
- No hard-coded values: use constants.
- Bind every value.
- Commit only at the top level.

**Testing.** Use **utPLSQL** for unit tests, and keep source in version control.

**Static analysis.** `PLSQL_WARNINGS` and PL/Scope find problems at compile time.

## Deployment

Use repeatable `CREATE OR REPLACE` scripts. Avoid `ORA-04068` with stateless packages, and body-only changes where possible.

**How do you deploy a changed PL/SQL package with no downtime?** Stateless packages plus **Edition-Based Redefinition** (11.2). An **edition** is a private copy of the code. You deploy the new version in a new edition, test it, and move sessions across. Old sessions keep running the old code. **Editioning views** and **crossedition triggers** handle table changes.

**Wrapping** hides source from `USER_SOURCE`, but it is not real security.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Tune PL/SQL before SQL | The real cost stays | Tune the SQL first |
| Call a function per row in a big query | Slow, and hidden from the plan | Use a join, or caching |
| Commit in a cursor loop | `ORA-01555` | Commit at the end |
| Set level 0 in production | Lost optimizations | Keep 2 or higher |
| Expect native compilation to speed up SQL | It helps only computation | Tune the SQL |
| Deploy stateful packages live | `ORA-04068` | Stay stateless, or use EBR |

## Interview questions

**Q1. What are the ways to trace and debug PL/SQL? How do DBMS_PROFILER and DBMS_HPROF differ?**

`DBMS_OUTPUT` and log tables, SQL Trace with TKPROF, the profilers, and a debugger. `DBMS_PROFILER` gives time per line. `DBMS_HPROF` gives a call tree, and separates SQL from PL/SQL time.

**Q2. A PL/SQL function called in a WHERE clause makes a query slow. How do you diagnose and fix it?**

I compare the plan and timing with and without it, then profile it. It runs per row, and it can block an index. I replace it with a join if I can. Otherwise I use a scalar subquery for caching, a function-based index, or `DETERMINISTIC`.

**Q3. What could cause ORA-01555 in your own PL/SQL code?**

Committing inside a cursor loop, because the cursor needs undo that those commits released.

**Q4. What is native compilation, and how does it relate to PLSQL_OPTIMIZE_LEVEL?**

It compiles PL/SQL to machine code, which helps computation-heavy code, not SQL. It needs optimization level 2 or higher to take effect.

**Q5. What are pragmas? Which ones have you used?**

They are compiler directives. Common ones are `EXCEPTION_INIT`, `AUTONOMOUS_TRANSACTION`, `SERIALLY_REUSABLE` and `INLINE`.

**Q6. How do you deploy a changed PL/SQL package with no downtime?**

I keep packages stateless, and prefer body-only changes. For larger changes, I use Edition-Based Redefinition: deploy in a new edition, and move sessions across.

## Practice

**1. Rewrite this to avoid a function call per row: `SELECT name, get_dept_name(dept_id) FROM staff`.**

<details>
<summary>Show solution</summary>

```sql norun
SELECT s.name, d.dept_name
FROM staff s
LEFT JOIN departments d ON d.dept_id = s.dept_id;
```

If the function must stay, use a scalar subquery: `(SELECT get_dept_name(s.dept_id) FROM dual)`.

</details>

**2. A loop commits every 1000 rows while fetching from a cursor, and fails with `ORA-01555`. Why?**

<details>
<summary>Show solution</summary>

The cursor must see the data as of its start. Each commit lets the undo it needs be overwritten. Commit after the loop, or restart the cursor for each batch.

</details>

## Recap

- Measure first. Most of the time is in the SQL.
- Set-based, then bulk, then compiler options.
- A function in SQL runs per row, and hides from the plan.
- Do not commit in a cursor loop.
- Native compilation helps computation, not SQL.
- Use EBR and stateless packages for zero downtime.

**Next:** [Chapter 54: Real-world PL/SQL programs](54-real-world-plsql-programs.md)
