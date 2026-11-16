# 50. Bulk Processing: BULK COLLECT and FORALL

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 49](49-records-and-collections.md)

> **In one line:** `BULK COLLECT` reads many rows in one trip, and `FORALL` writes many rows in one trip, which removes most of the cost of row-by-row PL/SQL.

## What you will learn

- The context switch, and why row-by-row loops are slow
- `BULK COLLECT`, with and without `LIMIT`
- `FORALL`, and what makes it not a loop
- `SAVE EXCEPTIONS`, and handling partial failures
- When to use DML error logging instead

## The context switch

The PL/SQL engine hands each SQL statement to the SQL engine, and back. Row-by-row DML in a loop pays that cost once per row. That is why it is slow.

```text
Row by row:   PL/SQL -> SQL -> PL/SQL -> SQL -> ...   one trip per row
Bulk:         PL/SQL -> SQL -> PL/SQL                 one trip, many rows
```

**Which tool should you pick?**

1. One set-based SQL statement.
2. Bulk binding, when you need procedural logic per row.
3. A plain row-by-row loop, last.

## BULK COLLECT

All rows land in a collection in one step.

```sql oracle
DECLARE
  TYPE t_names IS TABLE OF employees.first_name%TYPE;
  v_names t_names;
BEGIN
  SELECT first_name BULK COLLECT INTO v_names
  FROM employees
  WHERE dept_id = 30
  ORDER BY emp_id;

  DBMS_OUTPUT.PUT_LINE(v_names.COUNT || ' rows, first is ' || v_names(1));
END;
/
```

```text output
4 rows, first is Priya
```

**Zero rows raise no `NO_DATA_FOUND`,** so test `COUNT`. A loop `1..COUNT` then simply runs zero times.

### LIMIT

`FETCH ... BULK COLLECT INTO ... LIMIT n` reads in batches, so a huge result does not fill session memory. Each fetch **overwrites** the collection.

```sql oracle
DECLARE
  CURSOR c IS SELECT emp_id FROM employees ORDER BY emp_id;
  TYPE t_ids IS TABLE OF employees.emp_id%TYPE;
  v_ids   t_ids;
  v_total PLS_INTEGER := 0;
BEGIN
  OPEN c;

  LOOP
    FETCH c BULK COLLECT INTO v_ids LIMIT 5;
    EXIT WHEN v_ids.COUNT = 0;

    v_total := v_total + v_ids.COUNT;
    DBMS_OUTPUT.PUT_LINE('Batch of ' || v_ids.COUNT);
  END LOOP;

  CLOSE c;
  DBMS_OUTPUT.PUT_LINE('Total ' || v_total);
END;
/
```

```text output nocheck
Batch of 5
Batch of 5
Batch of 2
Total 12
```

**The loop exit trap.** `EXIT WHEN c%NOTFOUND` before processing **loses the last partial batch**. The final fetch of 2 rows sets `%NOTFOUND` to TRUE, because it found fewer rows than `LIMIT`. Exit on `COUNT = 0`, or test `%NOTFOUND` after processing.

`LIMIT` applies only to `FETCH`. A `SELECT BULK COLLECT` is capped with `ROWNUM`, or `FETCH FIRST` from 12.1.

**How do you use `BULK COLLECT` with `LIMIT` to avoid memory problems?** Open a cursor, fetch with `LIMIT 100` or `1000` in a loop, process each batch, and exit when `COUNT` is 0. Memory stays bounded by the batch size.

## RETURNING BULK COLLECT

```sql oracle
DECLARE
  TYPE t_ids IS TABLE OF employees.emp_id%TYPE;
  v_ids t_ids;
BEGIN
  UPDATE employees
  SET salary = salary + 1000
  WHERE dept_id = 40
  RETURNING emp_id BULK COLLECT INTO v_ids;

  DBMS_OUTPUT.PUT_LINE(v_ids.COUNT || ' rows changed');
  ROLLBACK;
END;
/
```

```text output
2 rows changed
```

## FORALL

`FORALL` runs one DML statement for a range of collection indexes.

```sql oracle
DECLARE
  TYPE t_ids IS TABLE OF products.product_id%TYPE;
  v_ids t_ids := t_ids(1, 2, 3);
BEGIN
  FORALL i IN 1..v_ids.COUNT
    UPDATE products
    SET stock_qty = stock_qty - 1
    WHERE product_id = v_ids(i);

  DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' rows updated');
  ROLLBACK;
END;
/
```

```text output
3 rows updated
```

**`FORALL` is not a loop.**

- It takes one DML statement only.
- The index is usable only as a subscript.
- Every referenced collection needs matching indexes.

**The standard batch pattern:** fetch with `LIMIT`, process, `FORALL`, repeat.

| | `BULK COLLECT` | `FORALL` |
|---|---|---|
| Direction | Reads into collections | Writes from collections |
| Works with | `SELECT`, `FETCH`, `RETURNING` | `INSERT`, `UPDATE`, `DELETE`, `MERGE` |

`SQL%ROWCOUNT` gives the total, and `SQL%BULK_ROWCOUNT(i)` gives the count for one iteration.

### When a FORALL fails

Without `SAVE EXCEPTIONS`, the first failure stops it. The failed iteration is undone. If the error is unhandled, all earlier iterations of that `FORALL` roll back. If handled, earlier iterations stay, and you must commit or roll back.

### SAVE EXCEPTIONS

**How does `FORALL` with `SAVE EXCEPTIONS` handle partial failures?** It continues past failures, then raises `ORA-24381` at the end. `SQL%BULK_EXCEPTIONS` lists what failed.

Here, the Blender has no stock, so the `CHECK` constraint rejects it.

```sql oracle
DECLARE
  TYPE t_ids IS TABLE OF products.product_id%TYPE;
  v_ids t_ids := t_ids(1, 7, 2);

  e_bulk EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_bulk, -24381);
BEGIN
  FORALL i IN 1..v_ids.COUNT SAVE EXCEPTIONS
    UPDATE products
    SET stock_qty = stock_qty - 1
    WHERE product_id = v_ids(i);
EXCEPTION
  WHEN e_bulk THEN
    DBMS_OUTPUT.PUT_LINE('Failed: ' || SQL%BULK_EXCEPTIONS.COUNT);

    FOR j IN 1..SQL%BULK_EXCEPTIONS.COUNT LOOP
      DBMS_OUTPUT.PUT_LINE(
        'Product ' || v_ids(SQL%BULK_EXCEPTIONS(j).ERROR_INDEX) || ': ' ||
        SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE));
    END LOOP;

    ROLLBACK;
END;
/
```

```text output
Failed: 1
Product 7: ORA-02290: check constraint (.) violated
```

`ERROR_CODE` is **positive**, so pass the negative to `SQLERRM`.

## Sparse collections

Sparse collections need `INDICES OF` or `VALUES OF` (10g). `ERROR_INDEX` is then the iteration number, not the sparse index, so you must map it back.

```sql oracle
DECLARE
  TYPE t_ids IS TABLE OF products.product_id%TYPE;
  v_ids t_ids := t_ids(1, 2, 3);
BEGIN
  v_ids.DELETE(2);

  FORALL i IN INDICES OF v_ids
    UPDATE products SET stock_qty = stock_qty WHERE product_id = v_ids(i);

  ROLLBACK;
END;
/
```

## How do these help performance?

**How do `BULK COLLECT` with `LIMIT` and `FORALL` with `SAVE EXCEPTIONS` help performance?** The fewer context switches come from the bulk work itself. `LIMIT` protects memory, and it does not add speed. `SAVE EXCEPTIONS` adds error handling, not speed. If one SQL statement can do the job, that still beats both.

**`FORALL` and triggers.** `FORALL INSERT` fires a statement trigger once, while `FORALL UPDATE` or `DELETE` fires it for each iteration.

## DML error logging

When one set-based statement can do the job, `LOG ERRORS` handles bad rows without any PL/SQL.

```sql oracle
BEGIN
  DBMS_ERRLOG.CREATE_ERROR_LOG('PRODUCTS');
END;
/

UPDATE products
SET stock_qty = stock_qty - 1
LOG ERRORS INTO err$_products ('nightly') REJECT LIMIT UNLIMITED;

ROLLBACK;
```

Bad rows go to the `ERR$_PRODUCTS` table, with `ORA_ERR_` columns.

| | `SAVE EXCEPTIONS` | `LOG ERRORS` |
|---|---|---|
| Needs PL/SQL | Yes | No |
| Works with a set-based statement | No, only `FORALL` | Yes |
| Errors go to | A pseudo-collection | A table |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use bulk binding where one statement would do | Extra code, and slower | Use set-based SQL |
| `BULK COLLECT` a huge table with no `LIMIT` | Memory runs out | Fetch with `LIMIT` |
| `EXIT WHEN c%NOTFOUND` before processing | The last batch is lost | Exit on `COUNT = 0` |
| Test `NO_DATA_FOUND` after `BULK COLLECT` | It is never raised | Test `COUNT` |
| Put two statements in `FORALL` | A compile error | One DML statement only |
| Use a sparse collection with `1..COUNT` in `FORALL` | `ORA-22160` | Use `INDICES OF` |
| Pass `ERROR_CODE` to `SQLERRM` unchanged | The wrong message | Negate it |
| Assume `ERROR_INDEX` is the sparse index | The wrong row | Map it back |

## Interview questions

**Q1. Explain the context switch between the SQL and PL/SQL engines, and how you reduce it.**

PL/SQL hands each SQL statement to the SQL engine, and each trip has a cost. A loop pays it once per row. I reduce it with a single set-based statement first, and otherwise with `BULK COLLECT` and `FORALL`, which pass many rows in one trip.

**Q2. What are BULK COLLECT and FORALL, and how do they differ?**

`BULK COLLECT` reads many rows into a collection in one trip. `FORALL` runs one DML statement for many collection elements in one trip. One reads, and the other writes.

**Q3. How do you use BULK COLLECT with LIMIT to avoid memory problems?**

Fetch from a cursor with `LIMIT` in a loop, process each batch, and exit when `COUNT` is 0. Exiting on `%NOTFOUND` before processing would lose the last partial batch.

**Q4. How does FORALL with SAVE EXCEPTIONS handle partial failures?**

It continues past failing rows, then raises `ORA-24381`. I handle that by name, and read `SQL%BULK_EXCEPTIONS` for `ERROR_INDEX` and `ERROR_CODE`.

**Q5. How do BULK COLLECT with LIMIT and FORALL with SAVE EXCEPTIONS help performance?**

The speed comes from fewer context switches. `LIMIT` bounds memory, and `SAVE EXCEPTIONS` handles errors, and neither adds speed by itself.

## Practice

**1. Read all customer names into a collection, and print the count.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  TYPE t_names IS TABLE OF customers.customer_name%TYPE;
  v_names t_names;
BEGIN
  SELECT customer_name BULK COLLECT INTO v_names FROM customers;
  DBMS_OUTPUT.PUT_LINE(v_names.COUNT);
END;
/
```

```text output
8
```

</details>

**2. Raise the price of products 8 and 9 by 10 percent, using `FORALL`.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  TYPE t_ids IS TABLE OF products.product_id%TYPE;
  v_ids t_ids := t_ids(8, 9);
BEGIN
  FORALL i IN 1..v_ids.COUNT
    UPDATE products SET price = price * 1.10 WHERE product_id = v_ids(i);

  DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT);
  ROLLBACK;
END;
/
```

```text output
2
```

In real code, one `UPDATE ... WHERE product_id IN (8, 9)` is simpler. `FORALL` earns its place when the ids come from logic.

</details>

**3. A loop does `FETCH c BULK COLLECT INTO v LIMIT 100; EXIT WHEN c%NOTFOUND;`, then processes `v`. The cursor has 250 rows. How many get processed?**

<details>
<summary>Show solution</summary>

200. The third fetch returns 50 rows and sets `%NOTFOUND`, so the loop exits before processing them.

</details>

## Recap

- Each trip between PL/SQL and SQL has a cost. Bulk binding reduces trips.
- One SQL statement beats bulk, and bulk beats row by row.
- Always use `LIMIT` on big results.
- Exit on `COUNT = 0`, not `%NOTFOUND`, before processing.
- `FORALL` takes one DML statement, and it is not a loop.
- `SAVE EXCEPTIONS` raises `ORA-24381` at the end.
- `ERROR_CODE` is positive.

**Next:** [Chapter 51: Dynamic SQL](51-dynamic-sql.md)
