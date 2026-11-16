# PL/SQL Cheat Sheet: Tables, Limits, Error Codes and Packages

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Part 7

> **In one line:** Every PL/SQL table you are expected to know, ready to look up.

Items marked 12.1 or later do not run on your 11g XE.

## Block skeleton ([Ch 42](../part-7-plsql/42-plsql-basics.md))

```sql oracle
DECLARE
  v_count PLS_INTEGER := 0;
BEGIN
  SELECT COUNT(*) INTO v_count FROM employees;
  DBMS_OUTPUT.PUT_LINE('Employees: ' || v_count);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(SQLERRM);
    RAISE;
END;
/
```

Run `SET SERVEROUTPUT ON` first, or `DBMS_OUTPUT` shows nothing. The client shows the text only after the block finishes.

## Declarations ([Ch 42](../part-7-plsql/42-plsql-basics.md))

| Form | Example | Note |
|---|---|---|
| Scalar | `v_name VARCHAR2(50);` | |
| Column type | `v_sal employees.salary%TYPE;` | Follows the column |
| Row type | `v_emp employees%ROWTYPE;` | Whole row |
| Constant | `c_rate CONSTANT NUMBER := 0.2;` | |
| Not null | `v_id NUMBER NOT NULL := 1;` | Needs an initial value (`PLS-00218`) |
| Record | `TYPE t_r IS RECORD (a NUMBER, b DATE);` | |
| Integers | `PLS_INTEGER` | Faster than `NUMBER` for counters |
| Boolean | `v_ok BOOLEAN := TRUE;` | Always in PL/SQL, in SQL only from 23ai |

**String sizes.** A `VARCHAR2` variable holds 32,767 bytes. A `VARCHAR2` column holds 4,000 bytes, unless `MAX_STRING_SIZE` is `EXTENDED` (12.1 and later).

## Control flow ([Ch 43](../part-7-plsql/43-control-structures.md))

- `IF ... ELSIF ... ELSE ... END IF;`. The spelling is `ELSIF`.
- A `CASE` statement with no match and no `ELSE` raises `CASE_NOT_FOUND` (`ORA-06592`). A `CASE` expression gives NULL.
- `LOOP ... EXIT WHEN x; END LOOP;`, `WHILE x LOOP`, `FOR i IN 1..10 LOOP`, `FOR i IN REVERSE 1..10 LOOP`.
- `CONTINUE` arrived in 11.1.

## SELECT INTO ([Ch 42](../part-7-plsql/42-plsql-basics.md), [Ch 44](../part-7-plsql/44-cursors.md))

| Case | Result |
|---|---|
| Exactly one row | Works |
| No rows | `NO_DATA_FOUND` |
| Many rows | `TOO_MANY_ROWS` |
| `SELECT COUNT(*) INTO` | Always one row, so it never raises `NO_DATA_FOUND` |
| `BULK COLLECT INTO`, no rows | Nothing raised, and the collection is empty |

## Cursors ([Ch 44](../part-7-plsql/44-cursors.md))

| Form | Use |
|---|---|
| Implicit | Single statements, `SQL%ROWCOUNT` |
| Explicit | `OPEN`, `FETCH`, `CLOSE` by hand |
| Cursor `FOR` loop | Opens, fetches and closes for you |
| Parameterized | `CURSOR c (p_dept NUMBER) IS ...` |
| `FOR UPDATE` | With `WHERE CURRENT OF c` |
| `SYS_REFCURSOR` | Returns a result set to the caller |

**Explicit cursor attributes:**

| Stage | `%ISOPEN` | `%FOUND` | `%NOTFOUND` | `%ROWCOUNT` |
|---|---|---|---|---|
| Before `OPEN` | FALSE | `ORA-01001` | `ORA-01001` | `ORA-01001` |
| After `OPEN` | TRUE | NULL | NULL | 0 |
| After a `FETCH` with a row | TRUE | TRUE | FALSE | Count so far |
| After a `FETCH` with no row | TRUE | FALSE | TRUE | Total count |
| After `CLOSE` | FALSE | `ORA-01001` | `ORA-01001` | `ORA-01001` |

**Implicit cursor attributes:**

| Stage | `SQL%ISOPEN` | `SQL%FOUND` | `SQL%NOTFOUND` | `SQL%ROWCOUNT` |
|---|---|---|---|---|
| Before any SQL | FALSE | NULL | NULL | NULL |
| DML touched rows | FALSE | TRUE | FALSE | n |
| DML touched none | FALSE | FALSE | TRUE | 0 |

When `SELECT INTO` raises `TOO_MANY_ROWS`, `SQL%ROWCOUNT` is 1, not the real count. Read these attributes right after the statement, because the next SQL statement replaces them.

## Collections ([Ch 49](../part-7-plsql/49-records-and-collections.md))

| | Associative array | Nested table | VARRAY |
|---|---|---|---|
| Declared with | `INDEX BY PLS_INTEGER` or `VARCHAR2` | `TABLE OF` | `VARRAY(n) OF` |
| Upper limit | None | None | Fixed |
| Constructor | Not needed | Needed | Needed |
| Sparse | Yes | After `DELETE` | Never |
| SQL type and column | No | Yes | Yes |
| Pick it for | Lookups | Sets and bulk work | Small ordered lists |

| Method | Associative array | Nested table | VARRAY |
|---|---|---|---|
| `EXISTS`, `COUNT`, `FIRST`, `LAST`, `PRIOR`, `NEXT` | Yes | Yes | Yes |
| `EXTEND`, `TRIM` | No | Yes | Yes |
| `DELETE` | Yes | Yes | Yes |
| `DELETE(n)`, `DELETE(m, n)` | Yes | Yes | No |
| `LIMIT` | NULL | NULL | The maximum |

| Problem | Error |
|---|---|
| Method on a NULL nested table or VARRAY (`EXISTS` returns FALSE) | `COLLECTION_IS_NULL`, `ORA-06531` |
| Index past `COUNT` | `SUBSCRIPT_BEYOND_COUNT`, `ORA-06533` |
| Index past the VARRAY limit | `SUBSCRIPT_OUTSIDE_LIMIT`, `ORA-06532` |
| Deleted element, or a missing associative array key | `NO_DATA_FOUND` |

## Procedures and functions ([Ch 46](../part-7-plsql/46-procedures-and-functions.md))

| | Procedure | Function |
|---|---|---|
| Returns | Through `OUT` parameters | One value with `RETURN` |
| Called from | PL/SQL, `EXEC` | PL/SQL and SQL |
| From a query | Not possible | No DML (`ORA-14551`), no DDL, `COMMIT` or `ROLLBACK` (`ORA-14552`) |
| No `RETURN` reached | Fine | `ORA-06503` |

| Mode | Behavior | Passed by |
|---|---|---|
| `IN` | Read-only | Reference |
| `OUT` | Starts NULL, sent back | Value, unless `NOCOPY` is honored |
| `IN OUT` | Read and sent back | Value, unless `NOCOPY` is honored |

`NOCOPY` is only a hint. Calls can use positional, named (`p_id => 5`) or mixed notation.

## Packages ([Ch 47](../part-7-plsql/47-packages.md))

- The specification is public. The body holds the code and private items.
- The initialization section runs once per session, on first use.
- Overloading: `PLS-00307` when a call is ambiguous.
- A forward declaration lets a private subprogram call a later one.
- Package variables live for the session. That is why recompiling a stateful package causes `ORA-04068` in other sessions.

## Triggers ([Ch 48](../part-7-plsql/48-triggers.md))

**Types:** row and statement, `BEFORE` and `AFTER`, `INSTEAD OF` on views (always row level), compound (11.1), DDL and system event.

**Inside:** `INSERTING`, `UPDATING` and `DELETING` tell you the operation. In the `WHEN` clause, write `NEW` and `OLD` with no colon.

**Firing order:** all `BEFORE STATEMENT` triggers, then all `BEFORE EACH ROW` and `AFTER EACH ROW` triggers around each row, then all `AFTER STATEMENT` triggers. `FOLLOWS` (11.1) orders triggers at the same timing point.

| Event | `:OLD` | `:NEW` |
|---|---|---|
| `INSERT` | NULL | New values |
| `UPDATE` | Old values | New values |
| `DELETE` | Old values | NULL |

| Rule | Error |
|---|---|
| `:OLD` or `:NEW` in a statement trigger | `ORA-04082` |
| Change `:NEW` in an `AFTER` row trigger | `ORA-04084` |
| Change `:OLD` anywhere | `ORA-04085` |
| `COMMIT` in a trigger, unless autonomous | `ORA-04092` |
| Row trigger touches its own table | `ORA-04091` |
| The wrapper around the trigger's real error | `ORA-04088` |
| The trigger is invalid | `ORA-04098` |

**Fix for `ORA-04091`:** a compound trigger, or a row trigger that collects keys plus a statement trigger that acts on them.

## Exceptions ([Ch 45](../part-7-plsql/45-exceptions.md))

```sql oracle
DECLARE
  e_child_rows EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_child_rows, -2292);
BEGIN
  DELETE FROM customers WHERE customer_id = 1;
EXCEPTION
  WHEN e_child_rows THEN
    RAISE_APPLICATION_ERROR(-20010, 'Customer has orders');
END;
/
```

- `WHEN OTHERS` goes last. A bare `RAISE` re-raises.
- `RAISE_APPLICATION_ERROR` takes -20000 to -20999 and up to 2,048 bytes.
- Assign `SQLCODE` and `SQLERRM` to variables, because they cannot appear in a SQL statement.
- `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` gives the failing line.

**Propagation.** An unhandled exception moves to the enclosing block, then to the caller. An exception raised in a declaration is not caught by that block's own handler. An exception raised inside a handler goes to the enclosing block.

**The 22 predefined exceptions:**

| Name | Oracle code | `SQLCODE` |
|---|---|---|
| `NO_DATA_FOUND` | `ORA-01403` | +100, the only positive one |
| `TOO_MANY_ROWS` | `ORA-01422` | -1422 |
| `DUP_VAL_ON_INDEX` | `ORA-00001` | -1 |
| `ZERO_DIVIDE` | `ORA-01476` | -1476 |
| `VALUE_ERROR` | `ORA-06502` | -6502 |
| `INVALID_NUMBER` | `ORA-01722` | -1722 |
| `CURSOR_ALREADY_OPEN` | `ORA-06511` | -6511 |
| `INVALID_CURSOR` | `ORA-01001` | -1001 |
| `COLLECTION_IS_NULL` | `ORA-06531` | -6531 |
| `ACCESS_INTO_NULL` | `ORA-06530` | -6530 |
| `CASE_NOT_FOUND` | `ORA-06592` | -6592 |
| `SUBSCRIPT_BEYOND_COUNT` | `ORA-06533` | -6533 |
| `SUBSCRIPT_OUTSIDE_LIMIT` | `ORA-06532` | -6532 |
| `ROWTYPE_MISMATCH` | `ORA-06504` | -6504 |
| `SYS_INVALID_ROWID` | `ORA-01410` | -1410 |
| `TIMEOUT_ON_RESOURCE` | `ORA-00051` | -51 |
| `LOGIN_DENIED` | `ORA-01017` | -1017 |
| `NOT_LOGGED_ON` | `ORA-01012` | -1012 |
| `PROGRAM_ERROR` | `ORA-06501` | -6501 |
| `STORAGE_ERROR` | `ORA-06500` | -6500 |
| `SELF_IS_NULL` | `ORA-30625` | -30625 |
| `NO_DATA_NEEDED` | `ORA-06548` | -6548 |

`VALUE_ERROR` vs `INVALID_NUMBER`: a bad conversion in a SQL statement raises `INVALID_NUMBER`, and in a procedural statement raises `VALUE_ERROR`.

## Bulk processing ([Ch 50](../part-7-plsql/50-bulk-processing.md))

```sql oracle
DECLARE
  CURSOR c IS SELECT emp_id FROM employees;
  TYPE t_ids IS TABLE OF employees.emp_id%TYPE;
  v_ids t_ids;
BEGIN
  OPEN c;
  LOOP
    FETCH c BULK COLLECT INTO v_ids LIMIT 100;
    EXIT WHEN v_ids.COUNT = 0;

    FORALL i IN 1..v_ids.COUNT SAVE EXCEPTIONS
      UPDATE employees SET salary = salary WHERE emp_id = v_ids(i);
  END LOOP;
  CLOSE c;
  ROLLBACK;
END;
/
```

- Exit on `COUNT = 0`. `%NOTFOUND` straight after the fetch loses the last partial batch.
- Use `INDICES OF` or `VALUES OF` for sparse collections. `1..n` over a gap gives `ORA-22160`.
- `SAVE EXCEPTIONS` raises `ORA-24381` at the end. Read `SQL%BULK_EXCEPTIONS.COUNT`, and `(i).ERROR_INDEX` and `(i).ERROR_CODE`.
- `SQL%BULK_ROWCOUNT(i)` gives the rows touched by element i.
- `RETURNING col BULK COLLECT INTO v` returns changed values.

## Dynamic SQL ([Ch 51](../part-7-plsql/51-dynamic-sql.md))

```sql oracle
DECLARE
  v_total NUMBER;
BEGIN
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM employees WHERE dept_id = :d'
    INTO v_total USING 30;
  DBMS_OUTPUT.PUT_LINE(v_total);
END;
/
```

- Bind values with `USING`. Never concatenate user input.
- Identifiers cannot be bound, so validate them with `DBMS_ASSERT`.
- DDL inside PL/SQL needs dynamic SQL.
- `OPEN c FOR 'select ...'` gives a dynamic cursor.
- `DBMS_SQL` is for a column list unknown until run time.

## Transactions and rights ([Ch 52](../part-7-plsql/52-advanced-plsql.md), [Ch 53](../part-7-plsql/53-plsql-performance-and-best-practices.md))

- `PRAGMA AUTONOMOUS_TRANSACTION` suits logging that must survive a rollback. The unit must finish its work, or `ORA-06519` is raised.
- `AUTHID DEFINER` is the default. `AUTHID CURRENT_USER` uses the caller's rights.
- Privileges through a role do not count inside a definer's rights unit, so grant directly.
- `ACCESSIBLE BY` (12.1) limits who may call a unit.

## Performance features ([Ch 53](../part-7-plsql/53-plsql-performance-and-best-practices.md))

| Feature | Use it when |
|---|---|
| `NOCOPY` | Passing large collections |
| `DETERMINISTIC` | Same input always gives the same output |
| `RESULT_CACHE` (11.1) | Repeated calls on rarely changing data. Not on XE 11g |
| `PIPELINED`, `PIPE ROW` | Streaming rows to a query |
| `PARALLEL_ENABLE` | A function that runs in parallel queries |
| `PRAGMA UDF`, `WITH FUNCTION` (12.1) | Reducing the SQL to PL/SQL context switch |
| `PLSQL_CODE_TYPE = NATIVE` | Compute-heavy code, not SQL-heavy code |

## Error map

**How to read a stack.** The first ORA line is the real error. `ORA-06512` lines are only the call path. `ORA-06550` is followed by the PLS code that explains it. Learn codes by number, because Oracle reworded some messages: `ORA-06502` reads "numeric or value error" on 11g.

| Area | Code | Meaning | First fix |
|---|---|---|---|
| Runtime | `ORA-06502` | Value too large, or bad conversion | Check sizes and types |
| | `ORA-06503` | Function ended with no `RETURN` | Return on every path |
| | `ORA-06508` | Program unit not found | Check it compiled |
| | `ORA-06510` | Unhandled user exception | Add a handler |
| | `ORA-06511` | Cursor already open | Check `%ISOPEN` |
| | `ORA-06512` | A line in the call path | Read the first line |
| | `ORA-06519` | Autonomous transaction left open | Commit or roll back |
| | `ORA-06592` | `CASE` not found | Add `ELSE` |
| Collections | `ORA-06530` | Uninitialized object | Initialize it |
| | `ORA-06531` | Uninitialized collection | Call the constructor |
| | `ORA-06532` | Outside the VARRAY limit | Check the limit |
| | `ORA-06533` | Beyond `COUNT` | `EXTEND` first |
| | `ORA-22160` | Gap in a `FORALL` | `INDICES OF` |
| Bulk | `ORA-24381` | Errors in array DML | Read `SQL%BULK_EXCEPTIONS` |
| Cursors | `ORA-01000` | Too many open cursors | Close them |
| | `ORA-01001` | Invalid cursor | Open it first |
| | `ORA-01002` | Fetch out of sequence | No commit in a `FOR UPDATE` loop |
| | `ORA-01555` | Snapshot too old | Shorten the query, stop fetching across commits |
| Compile | `ORA-06550` | Compile error at a line | Read the PLS line |
| State | `ORA-04061`, `ORA-04065` | Unit invalidated or changed | Recompile |
| | `ORA-04063` | Unit has errors | Fix and recompile |
| | `ORA-04068` | Package state discarded | Retry once, keep packages stateless |
| PLS | `PLS-00103` | Syntax error | Read the symbol it names |
| | `PLS-00201` | Identifier must be declared | Check the name and direct grants |
| | `PLS-00302` | Component must be declared | Check the member name |
| | `PLS-00306` | Wrong arguments | Check the signature |
| | `PLS-00307` | Ambiguous overload | Use named notation |
| | `PLS-00323` | In the specification, not the body | Add it to the body |
| | `PLS-00363` | Not an assignment target | Do not assign to an `IN` parameter |
| | `PLS-00382` | Wrong type | Convert it |
| | `PLS-00428` | `SELECT` with no `INTO` | Add `INTO` |
| | `PLS-00435` | Non-bulk DML in `FORALL` | One DML statement only |
| | `PLS-00904` | Insufficient privilege | Grant it. Not the same as `ORA-00904` |
| | `PLS-00905` | Object is invalid | Recompile it |

## Program limits

| Item | Limit |
|---|---|
| Block nesting | 255 |
| Subquery nesting | 254 |
| Label nesting | 98 |
| Record nesting | 32 |
| Identifiers | 128 bytes from 12.2, 30 before |
| `VARCHAR2`, `CHAR`, `RAW`, string literals | 32,767 bytes |
| `LONG` | 32,760 bytes |
| LOBs | 4G times `DB_BLOCK_SIZE` |
| Trigger size | 32K |
| Formal parameters | 65,536 |
| `PLS_INTEGER` | -2147483648 to 2147483647 |
| `NUMBER` precision | 38 digits |

`PLS-00123` means a unit is too large. `USER_OBJECT_SIZE` estimates size.

## Supplied packages

| Task | Package |
|---|---|
| Print | `DBMS_OUTPUT` |
| Error backtrace, call stack | `DBMS_UTILITY`, `UTL_CALL_STACK` (12.1) |
| Dynamic SQL | `DBMS_SQL` |
| Validate identifiers | `DBMS_ASSERT` |
| Jobs | `DBMS_SCHEDULER` (pick it over `DBMS_JOB`, for richer scheduling and logging) |
| Large objects | `DBMS_LOB` |
| User-defined locks | `DBMS_LOCK` |
| Session settings | `DBMS_SESSION` |
| Label work in `V$SESSION` | `DBMS_APPLICATION_INFO` |
| Get DDL | `DBMS_METADATA.GET_DDL` |
| Random values, not for security | `DBMS_RANDOM` |
| Encryption and hashing | `DBMS_CRYPTO` |
| Queues | `DBMS_AQ` |
| Messages between sessions | `DBMS_PIPE` |
| Server files | `UTL_FILE` |
| HTTP calls, email | `UTL_HTTP`, `UTL_SMTP` |
| Slow code | `DBMS_HPROF` |

## Dictionary views

`USER_` is what you own, `ALL_` is what you can see, `DBA_` is everything, and `V$` is live memory.

| Question | View |
|---|---|
| Source text | `USER_SOURCE` |
| Invalid units | `USER_OBJECTS` |
| Compile errors | `USER_ERRORS` |
| Subprogram properties | `USER_PROCEDURES` |
| Parameters | `USER_ARGUMENTS` |
| Who uses what | `USER_DEPENDENCIES` |
| Triggers | `USER_TRIGGERS` |
| Compile settings | `USER_PLSQL_OBJECT_SETTINGS` |
| Identifiers, with PL/Scope | `USER_IDENTIFIERS` |
| Job history | `USER_SCHEDULER_JOB_RUN_DETAILS` |
| Open cursors | `V$OPEN_CURSOR` |

## Compile and maintain

- `CREATE OR REPLACE`, `ALTER PROCEDURE p COMPILE;`, `ALTER PACKAGE p COMPILE BODY;`, `SHOW ERRORS`.
- `ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL';`.
- Changing a table or specification invalidates dependents, which recompile on next use.
- `$IF DBMS_DB_VERSION.VER_LE_11 $THEN ... $END` lets one source work across releases.
- Edition-based redefinition (11.2) patches PL/SQL with no downtime.

## Release timeline

| Release | PL/SQL features |
|---|---|
| 11.1 | Compound triggers, `CONTINUE`, function result cache |
| 11.2 | `DBMS_PARALLEL_EXECUTE`. Your 11g XE stops here |
| 12.1 | `ACCESSIBLE BY`, `PRAGMA UDF`, implicit statement results |
| 12.2 | `PRAGMA DEPRECATE`, 128-byte identifiers |
| 18c | Polymorphic table functions, qualified expressions |
| 19c | SQL table macros, from 19.7 |
| 21c | Extended iterators, scalar SQL macros |
| 23ai | SQL `BOOLEAN`, automatic SQL transpiler, `IF [NOT] EXISTS` on DDL |
| 26ai | `RESETTABLE` clause (23.26.0) to avoid `ORA-04068`, and SQL assertions (23.26.1), which are a SQL feature |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Read `ORA-06512` as the error | It is only the call path | Read the first ORA line |
| `WHEN OTHERS THEN NULL` | Hides every failure | Log and re-raise |
| Test `%FOUND` right after `OPEN` | It is NULL | Fetch first |
| Assume `NO_DATA_FOUND` is -1403 | It is +100 | Remember the exception |
| Silence `ORA-04091` with an autonomous transaction | The trigger cannot see the uncommitted changes | Use a compound trigger |
| Forget `EXTEND`, or the constructor | `ORA-06533`, `ORA-06531` | Initialize first |
| `DELETE(n)` on a VARRAY, `EXTEND` on an associative array | Not allowed | Check the method table |
| Treat `NOCOPY` as a guarantee | The compiler may ignore it | Do not depend on it |
| Identifiers over 30 bytes on 11g XE | The 128-byte limit starts at 12.2 | Keep names short |
| `DBMS_RANDOM` for tokens | Oracle says it is not for cryptography | `DBMS_CRYPTO` |

## Quick self-test

1. Walk through the cursor attributes at each stage of an explicit cursor.
2. What causes `ORA-06531`, `ORA-06532` and `ORA-06533`?
3. What is the difference between `RAISE` and `RAISE_APPLICATION_ERROR`?
4. A procedure fails with `PLS-00201`, but the same query works in SQL*Plus. Why?
5. Which package prints output, which gives the failing line, which schedules a job, and which reads a server file?
6. Which views show source code, compile errors, invalid objects and dependencies?

**Next:** [Dialect Differences](dialect-differences.md)
