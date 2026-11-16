# 49. Records and Collections: Holding Rows and Lists in Memory

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 44](44-cursors.md)

> **In one line:** A record groups different fields for one thing, like a row, and a collection holds many items of one type, like a list.

## What you will learn

- Records, and `%ROWTYPE` vs `TYPE ... IS RECORD`
- Associative arrays, nested tables and VARRAYs, and how to choose
- Collection methods, and which apply to which type
- Sparse collections, and how to loop over them safely
- How to query a collection from SQL

## Records

```sql oracle
DECLARE
  TYPE t_pay IS RECORD (
    name   employees.first_name%TYPE,
    salary employees.salary%TYPE,
    bonus  NUMBER := 0
  );

  v_pay t_pay;
BEGIN
  SELECT first_name, salary
  INTO v_pay.name, v_pay.salary
  FROM employees
  WHERE emp_id = 5;

  v_pay.bonus := v_pay.salary * 0.10;
  DBMS_OUTPUT.PUT_LINE(v_pay.name || ': ' || v_pay.bonus);
END;
/
```

```text output
Lena: 6000
```

`RECORD` types cannot be created at schema level, only in PL/SQL.

**`%ROWTYPE` vs `TYPE ... IS RECORD`.** `%ROWTYPE` gives a full table row or a cursor row, and all fields start NULL. Pick it when the shape matches a row. Use `TYPE ... IS RECORD` for a custom shape, or for defaults.

**Working with records.** Whole-record assignment works between the same type. There is no native equality or NULL test, so compare field by field.

**Record DML:**

```sql oracle
DECLARE
  v_dept departments%ROWTYPE;
BEGIN
  v_dept.dept_id   := 60;
  v_dept.dept_name := 'Support';
  v_dept.location  := 'Oslo';

  INSERT INTO departments VALUES v_dept;

  v_dept.location := 'Bergen';
  UPDATE departments SET ROW = v_dept WHERE dept_id = 60;

  ROLLBACK;
END;
/
```

## The three collection types

| | Associative array | Nested table | VARRAY |
|---|---|---|---|
| Size | Unbounded | Unbounded | A declared maximum |
| Index | `PLS_INTEGER` or string | Integer from 1 | Integer from 1 |
| Density | Sparse | Dense at first, can get gaps | Always dense |
| Before use | Empty, ready | Atomically null | Atomically null |
| Constructor needed | No | Yes | Yes |
| `EXTEND` | No | Yes | Yes |
| Schema-level type | No | Yes | Yes |
| Can be a column | No | Yes | Yes |

**Think of them this way:** an associative array is a hash map, a nested table is a set or list, and a VARRAY is a small fixed array.

### Associative arrays

Key-value pairs. They are ready to use when declared, and have no constructor.

```sql oracle
DECLARE
  TYPE t_map IS TABLE OF NUMBER INDEX BY VARCHAR2(20);
  v_rates t_map;
  v_key   VARCHAR2(20);
BEGIN
  v_rates('UK')  := 0.20;
  v_rates('UAE') := 0.05;

  v_key := v_rates.FIRST;
  WHILE v_key IS NOT NULL LOOP
    DBMS_OUTPUT.PUT_LINE(v_key || ': ' || v_rates(v_key));
    v_key := v_rates.NEXT(v_key);
  END LOOP;
END;
/
```

```text output
UAE: .05
UK: .2
```

String keys sort by the session's sort order, so `UAE` comes first here.

### Nested tables

A constructor is required. `EXTEND` adds slots.

```sql oracle
DECLARE
  TYPE t_names IS TABLE OF VARCHAR2(30);
  v_names t_names := t_names('Asha', 'Ben');
BEGIN
  v_names.EXTEND;
  v_names(3) := 'Chen';

  FOR i IN 1..v_names.COUNT LOOP
    DBMS_OUTPUT.PUT_LINE(v_names(i));
  END LOOP;
END;
/
```

```text output
Asha
Ben
Chen
```

### VARRAYs

A declared maximum size, and always dense.

```sql oracle
DECLARE
  TYPE t_top3 IS VARRAY(3) OF NUMBER;
  v_top t_top3 := t_top3(10, 20);
BEGIN
  v_top.EXTEND;
  v_top(3) := 30;
  DBMS_OUTPUT.PUT_LINE(v_top.COUNT || ' of ' || v_top.LIMIT);
END;
/
```

```text output
3 of 3
```

### Null vs empty

An uninitialized VARRAY or nested table is **atomically null**, and every method except `EXISTS` raises `COLLECTION_IS_NULL`. `EXTEND` cannot initialize it, so call the constructor. `t_names()` makes an empty one.

### Subscript errors

| Exception | Code | Cause |
|---|---|---|
| `COLLECTION_IS_NULL` | `ORA-06531` | Using an uninitialized collection |
| `SUBSCRIPT_BEYOND_COUNT` | `ORA-06533` | Index past `COUNT` |
| `SUBSCRIPT_OUTSIDE_LIMIT` | `ORA-06532` | Index out of the legal range |
| `NO_DATA_FOUND` | `ORA-01403` | Reading a missing or deleted element |

## Collection methods

| Method | Meaning | Associative | Nested table | VARRAY |
|---|---|---|---|---|
| `COUNT` | How many elements | Yes | Yes | Yes |
| `EXISTS(n)` | Is element n there? | Yes | Yes | Yes |
| `FIRST`, `LAST` | Lowest and highest index | Yes | Yes | Yes |
| `PRIOR(n)`, `NEXT(n)` | Previous or next index | Yes | Yes | Yes |
| `LIMIT` | Maximum size | NULL | NULL | Yes |
| `DELETE` | Remove all | Yes | Yes | Yes |
| `DELETE(n)` | Remove one | Yes | Yes | **No** |
| `EXTEND` | Add slots | **No** | Yes | Yes |
| `TRIM` | Remove from the end | **No** | Yes | Yes |

Methods cannot be used in SQL statements.

**Details:** `FIRST` and `LAST` are NULL when empty. `COUNT` is below `LAST` when sparse. `DELETE(n)` keeps a placeholder, and `TRIM` does not.

## Sparse collections

**What is a sparse collection, and how do you loop over one safely?** It has gaps in its index, after `DELETE(n)`. Use `FIRST` and `NEXT`, because a `1..COUNT` loop hits the gaps, and misses the high elements.

```sql oracle
DECLARE
  TYPE t_nums IS TABLE OF NUMBER;
  v_nums t_nums := t_nums(10, 20, 30, 40);
  v_i    PLS_INTEGER;
BEGIN
  v_nums.DELETE(2);

  v_i := v_nums.FIRST;
  WHILE v_i IS NOT NULL LOOP
    DBMS_OUTPUT.PUT_LINE(v_i || ' = ' || v_nums(v_i));
    v_i := v_nums.NEXT(v_i);
  END LOOP;
END;
/
```

```text output
1 = 10
3 = 30
4 = 40
```

**A trap:** `FOR i IN c.FIRST..c.LAST` on an empty collection raises `VALUE_ERROR`, because the bounds are NULL. `1..c.COUNT` simply runs zero times.

## Comparing and assigning

- Nested tables of the same type support `=` and `<>`, regardless of order.
- VARRAYs and nested tables take `IS NULL`.
- Assignment needs the **same type**, not just the same element type. A package type is not compatible with an identically defined local type.

## Collections of records

```sql oracle
DECLARE
  TYPE t_emps IS TABLE OF employees%ROWTYPE;
  v_emps t_emps;
BEGIN
  SELECT * BULK COLLECT INTO v_emps
  FROM employees
  WHERE dept_id = 40
  ORDER BY emp_id;

  FOR i IN 1..v_emps.COUNT LOOP
    DBMS_OUTPUT.PUT_LINE(v_emps(i).first_name);
  END LOOP;
END;
/
```

```text output
Omar
Nina
```

## Using a collection in SQL

Create the type at schema level, then use `TABLE()`.

```sql oracle
CREATE TYPE id_list AS TABLE OF NUMBER;
/

DECLARE
  v_ids   id_list := id_list(1, 3);
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM employees
  WHERE emp_id IN (SELECT column_value FROM TABLE(v_ids));

  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

```text output
2
```

This is the bridge to pipelined functions in [Chapter 52](52-advanced-plsql.md). From 12.1, a collection declared in a package spec can also be used with `TABLE()`.

## Which collection should you pick?

| Need | Pick |
|---|---|
| In-memory lookup inside PL/SQL | Associative array |
| List passed to SQL, or stored as a set | Nested table |
| Short list with a fixed maximum | VARRAY |
| Rows for bulk processing | Associative array or nested table of records |

Collections live in session memory (PGA), so a huge collection costs real memory. [Chapter 50](50-bulk-processing.md) shows `LIMIT`.

## Newer features

- **Qualified expressions (18c):** `aa_t(1 => 'a', 2 => 'b')`.
- **Iteration controls (21c):** `VALUES OF`, `INDICES OF` and `PAIRS OF` in a `FOR` loop.
- **Set operators on nested tables:** `MULTISET UNION`, `MEMBER OF`, `SUBMULTISET`, `CARDINALITY` and `SET`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use a nested table with no constructor | `COLLECTION_IS_NULL` | Call the constructor |
| Assign past the end with no `EXTEND` | `SUBSCRIPT_BEYOND_COUNT` | Call `EXTEND` first |
| Loop `1..COUNT` on a sparse collection | `NO_DATA_FOUND` | Use `FIRST` and `NEXT` |
| Loop `FIRST..LAST` on an empty collection | `VALUE_ERROR` | Use `1..COUNT` |
| Use `DELETE(n)` on a VARRAY | A compile error | VARRAYs stay dense |
| Use a local type in `TABLE()` on 11g | An error | Use a schema-level type |
| Load a huge table into a collection | Memory runs out | Use `LIMIT` |
| Compare two records with `=` | A compile error | Compare field by field |

## Interview questions

**Q1. What collection types does PL/SQL have, and how do you choose between them?**

Associative arrays, nested tables and VARRAYs. I use an associative array for lookups in memory, a nested table for lists passed to SQL, and a VARRAY for short lists with a known maximum.

**Q2. How do nested tables differ from VARRAYs?**

A nested table is unbounded, and can become sparse. A VARRAY has a declared maximum, and is always dense. Both need a constructor, and both can be column types. As columns, a nested table is stored in a separate table, and a VARRAY usually inline.

**Q3. How do associative arrays differ from nested tables, including their state before initialization?**

An associative array has any integer or string key, is empty and usable when declared, and needs no constructor or `EXTEND`. It is PL/SQL only. A nested table is atomically null until constructed, and needs `EXTEND`, but it can be used in SQL.

**Q4. Which collection methods do you use most, and which do not apply to which collection types?**

`COUNT`, `FIRST`, `LAST`, `NEXT`, `EXISTS` and `DELETE`. `EXTEND` and `TRIM` do not apply to associative arrays. `DELETE(n)` does not apply to VARRAYs. `LIMIT` is NULL unless it is a VARRAY.

**Q5. What is a sparse collection, and how do you loop over one safely?**

It has gaps in its index. I loop with `FIRST` and `NEXT` in a `WHILE` loop, or with `INDICES OF` from 21c.

## Practice

**1. Build an associative array of product id to price for category 2, then print the price of product 1.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  TYPE t_prices IS TABLE OF products.price%TYPE INDEX BY PLS_INTEGER;
  v_prices t_prices;
BEGIN
  FOR r IN (SELECT product_id, price FROM products WHERE category_id = 2) LOOP
    v_prices(r.product_id) := r.price;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(v_prices(1));
END;
/
```

```text output
799
```

</details>

**2. What does this print?**

```sql oracle
DECLARE
  TYPE t_nums IS TABLE OF NUMBER;
  v t_nums := t_nums(1, 2, 3);
BEGIN
  v.DELETE(3);
  DBMS_OUTPUT.PUT_LINE(v.COUNT || ' ' || v.LAST);
END;
/
```

<details>
<summary>Show solution</summary>

`2 2`. Deleting the last element lowers both `COUNT` and `LAST`. If you deleted element 2 instead, it would print `2 3`.

</details>

**3. Why does this fail?**

```sql oracle
DECLARE
  TYPE t_nums IS TABLE OF NUMBER;
  v t_nums;
BEGIN
  v(1) := 10;
END;
/
```

<details>
<summary>Show solution</summary>

`v` is atomically null, so it raises `COLLECTION_IS_NULL`. Initialize it with `t_nums()`, then `EXTEND`.

</details>

## Recap

- A record is one row-like thing, and a collection is a list.
- Associative arrays need no constructor. Nested tables and VARRAYs do.
- Only VARRAYs have a maximum size, and they stay dense.
- `EXTEND` and `TRIM` do not apply to associative arrays.
- Loop sparse collections with `FIRST` and `NEXT`.
- `TABLE()` queries a collection from SQL.

**Next:** [Chapter 50: Bulk processing](50-bulk-processing.md)
