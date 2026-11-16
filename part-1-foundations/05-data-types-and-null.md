# 5. Data Types and NULL: Storing Values Correctly

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 4](04-er-modeling.md)

> **In one line:** A column's type decides what it can hold and how it behaves, and NULL is the special marker for a value that is missing.

## What you will learn

- Which number, text and date types to pick, and why
- Why money must never be stored as `FLOAT`
- What NULL really means
- Three-valued logic, and why `= NULL` never matches
- How NULL behaves in expressions, and the design rules around it

## Why the column type matters

The type is the first constraint on a column. It decides:

- Which values are allowed. A date stored as text happily accepts `2024-13-45`.
- How values compare and sort. As text, `'10'` sorts before `'9'`.
- How much space they take.
- Whether an index can be used.

## Numbers

### Whole numbers

| Type | Range | Notes |
|---|---|---|
| `SMALLINT` | About +/- 32 thousand | |
| `INTEGER` | About +/- 2.1 billion | The usual choice |
| `BIGINT` | About +/- 9.2 quintillion | For very large ids and counters |
| Oracle `NUMBER(p)` | p digits | Oracle's `INTEGER` is `NUMBER(38)` |

Choose by the largest value you will ever store. A value out of range raises an error.

### Exact decimals

`NUMERIC(p, s)`, `DECIMAL(p, s)` and Oracle `NUMBER(p, s)` store exact values. `p` is the total number of digits, and `s` is the digits after the point. So `(10,2)` holds up to 99999999.99.

```sql
CREATE TABLE demo_numbers (amount NUMERIC(5,2));

INSERT INTO demo_numbers VALUES (12.345);

SELECT amount FROM demo_numbers;
```

```text output
CREATE TABLE
INSERT 0 1
 amount
--------
  12.35
(1 row)
```

Too many decimals are rounded. Too many whole digits raise an error:

```sql error=overflow
INSERT INTO demo_numbers VALUES (12345.67);
```

```text output
ERROR:  numeric field overflow
DETAIL:  A field with precision 5, scale 2 must round to an absolute value less than 10^3.
```

```sql
DROP TABLE demo_numbers;
```

### Approximate numbers

`REAL`, `DOUBLE PRECISION`, and Oracle `BINARY_FLOAT` and `BINARY_DOUBLE` store binary fractions. Many decimal values, including 0.1, have no exact binary form, so they are stored as a close approximation.

```sql postgres
-- PostgreSQL
SELECT 0.1::DOUBLE PRECISION + 0.2::DOUBLE PRECISION AS as_float,
       0.1::NUMERIC + 0.2::NUMERIC AS as_numeric;
```

```text output
      as_float       | as_numeric
---------------------+------------
 0.30000000000000004 |        0.3
(1 row)
```

Use these types for measurements and scientific values, where a tiny error does not matter and speed does.

### Money

**Use `NUMERIC` or `DECIMAL` with a fixed scale, or whole minor units such as cents. Never use `FLOAT`.** Totals drift, and equality checks fail. Keep a currency code beside the amount. Avoid PostgreSQL's `money` type, because its behavior depends on a locale setting.

## Text

| Type | Behavior |
|---|---|
| `CHAR(n)` | Fixed length, padded with blanks |
| `VARCHAR(n)` | Stores only what you give it, up to n |
| Oracle `VARCHAR2(n)` | The same, and the type to use on Oracle |
| `TEXT` (PostgreSQL) | Any length |

On Oracle, always use `VARCHAR2`, never `VARCHAR`. Oracle's documentation warns that `VARCHAR` may be redefined in future. Oracle's limits are 2000 bytes for `CHAR`, and 4000 bytes for `VARCHAR2` in a table, or 32767 with `MAX_STRING_SIZE = EXTENDED` from 12c. In PL/SQL, `VARCHAR2` goes up to 32767 bytes.

**Which should you pick?** `VARCHAR2` on Oracle, and `VARCHAR` or `TEXT` on PostgreSQL. Keep `CHAR` for truly fixed-length codes, such as a two-letter country code. On PostgreSQL, `CHAR` gives no speed gain.

### Bytes or characters?

Length can mean bytes or characters. Oracle's `VARCHAR2(10)` defaults to 10 **bytes**, so non-English text may fit fewer than 10 characters. Write `VARCHAR2(10 CHAR)` to be explicit. PostgreSQL's `varchar(n)` counts characters.

### Collation

**Collation** is the set of rules for comparing and sorting text. Is `'abc' = 'ABC'` true? It depends on the database.

| Engine | Default | `'abc' = 'ABC'` |
|---|---|---|
| Oracle | Binary | False |
| PostgreSQL | Case-sensitive | False |
| MySQL | `utf8mb4_0900_ai_ci`, case-insensitive | True |
| SQL Server | Usually case-insensitive | True |

### Trailing spaces

Oracle pads with blanks only when both sides are `CHAR` or text literals. If either side is `VARCHAR2`, it does not pad. So a `CHAR` column can fail to match a `VARCHAR2` variable, which is a classic PL/SQL bug.

## Dates and times

**DATE** is a calendar day on PostgreSQL, MySQL and SQL Server. **An Oracle `DATE` always holds a time as well**, to the second. So on Oracle, `WHERE d = DATE '2024-01-05'` misses any row that carries a time.

**TIMESTAMP** alone means without time zone: a wall-clock reading. A time-zone-aware type records an instant.

| Type | What it stores |
|---|---|
| `TIMESTAMP` | A wall-clock reading |
| PostgreSQL `timestamptz` | An instant. It converts input to UTC, and does not keep the original zone |
| Oracle `TIMESTAMP WITH TIME ZONE` | An instant, and keeps the zone |
| Oracle `TIMESTAMP WITH LOCAL TIME ZONE` | An instant, normalized, shown in the session's zone |
| SQL Server `DATETIMEOFFSET` | An instant, and keeps the offset |

**Which should you pick?**

| The value is | Use |
|---|---|
| An instant: order placed, payment taken | A time-zone-aware type |
| A calendar fact: birth date, hire date | `DATE` |
| A future local event: a 9:00 meeting in Dubai | Local time plus a zone name such as `Asia/Dubai` |

Why store a zone name for future events? Because governments change clock rules, and the meeting should still be at 9:00 local time.

`INTERVAL` stores a duration: `YEAR TO MONTH` or `DAY TO SECOND`. [Chapter 9](../part-2-sql-basics/09-built-in-functions.md) covers date arithmetic.

## Other types

- **Booleans:** PostgreSQL has `BOOLEAN`. Oracle has no `BOOLEAN` column before 23ai, so use `NUMBER(1)` or `CHAR(1)` with a `CHECK`. MySQL's `BOOLEAN` is a synonym for `TINYINT(1)`, and SQL Server uses `BIT`.
- **Large values:** `CLOB` and `BLOB` on Oracle, `TEXT` and `BYTEA` on PostgreSQL. Big files usually live in object storage, with only the path in the database.
- **UUID:** a 128-bit identifier ([Chapter 25](../part-4-database-design/25-schema-design-patterns.md)).
- **JSON and JSONB:** see [Chapter 20](../part-3-advanced-sql/20-modern-sql.md).
- **Arrays and ENUM:** see [Chapter 25](../part-4-database-design/25-schema-design-patterns.md).

## Implicit conversion

`CAST` says what you mean. If you leave it out, the database may convert for you, and that can hurt.

**Why might `WHERE phone = 5551234` fail to use an index on a `VARCHAR2` phone column?** When Oracle compares a character column with a number, it converts the **column**:

```text
WHERE phone = 5551234    becomes    WHERE TO_NUMBER(phone) = 5551234
```

A normal index on `phone` cannot be used, because it holds text. Worse, the query fails with `ORA-01722: invalid number` if any row holds a value like `555-1234`. The fix is to compare text with text: `WHERE phone = '5551234'`.

Two rules follow:

- Never store dates or numbers as text.
- Never store identifiers as numbers. A phone number loses its leading `0` or `+`.

## Choosing a type: the checklist

1. What is the largest value? What precision do you need?
2. Must it be exact? (Money: yes.)
3. Is it a calendar day, or an instant?
4. Can it be missing? If not, add `NOT NULL`.
5. Is it an identifier? Then treat it as text unless you do math on it.

Here is why the sample database uses its types:

| Column | Type | Why |
|---|---|---|
| Ids, `quantity`, `stock_qty` | `INTEGER` or `NUMBER(6)` | Whole numbers |
| `salary`, `commission` | `NUMERIC(10)` | Whole amounts, exact |
| `price`, `unit_price`, `amount` | `NUMERIC(10,2)` | Money: exact, with 2 decimals |
| `email`, names | `VARCHAR` or `VARCHAR2` | Length varies |
| `hire_date`, `order_date` | `DATE` | Calendar days |

## NULL

**NULL means a value is missing or unknown.** It is not zero. It is not an empty string. It is not a blank space.

```sql
SELECT first_name, commission
FROM employees
WHERE emp_id IN (1, 7)
ORDER BY emp_id;
```

```text output
 first_name | commission
------------+------------
 Sara       |       NULL
 Mei        |          0
(2 rows)
```

Mei Chen's commission is 0, a known amount. Sara Khan's is NULL: no amount is recorded.

NULL can stand for different things: unknown, not applicable, or not entered yet. The database cannot tell which.

### Oracle's exception: the empty string

Oracle treats a zero-length string as NULL. So `WHERE name = ''` returns nothing, and `LENGTH('')` is NULL. PostgreSQL keeps `''` as a real value of length 0. Oracle's manual warns that this may change, so do not rely on it.

```sql oracle
SELECT NVL(LENGTH(''), -1) AS length_of_empty FROM dual;
```

```text output
LENGTH_OF_EMPTY
---------------
             -1
```

**PostgreSQL:**

```sql postgres
SELECT LENGTH('') AS length_of_empty;
```

```text output
 length_of_empty
-----------------
               0
(1 row)
```

### Three-valued logic

In SQL, a condition has three possible results: TRUE, FALSE and UNKNOWN. A comparison with NULL gives UNKNOWN.

| AND | TRUE | FALSE | UNKNOWN |
|---|---|---|---|
| **TRUE** | TRUE | FALSE | UNKNOWN |
| **FALSE** | FALSE | FALSE | FALSE |
| **UNKNOWN** | UNKNOWN | FALSE | UNKNOWN |

| OR | TRUE | FALSE | UNKNOWN |
|---|---|---|---|
| **TRUE** | TRUE | TRUE | TRUE |
| **FALSE** | TRUE | FALSE | UNKNOWN |
| **UNKNOWN** | TRUE | UNKNOWN | UNKNOWN |

`NOT UNKNOWN` is UNKNOWN.

An easy way to think of it: UNKNOWN might be TRUE or might be FALSE. `FALSE AND anything` is FALSE, so the answer is known. `TRUE AND UNKNOWN` depends on the unknown, so it stays UNKNOWN.

### WHERE keeps only TRUE

`col = NULL` and `col <> NULL` never match, and `NULL = NULL` is not TRUE. Use `IS NULL` and `IS NOT NULL`.

```sql
SELECT COUNT(CASE WHEN commission = NULL THEN 1 END) AS equals_null,
       COUNT(CASE WHEN commission IS NULL THEN 1 END) AS is_null,
       COUNT(CASE WHEN commission IS NOT NULL THEN 1 END) AS is_not_null
FROM employees;
```

```text output
 equals_null | is_null | is_not_null
-------------+---------+-------------
           0 |       8 |           4
(1 row)
```

**The silent drop.** A filter also loses the NULL rows.

```sql
SELECT COUNT(*) AS matched
FROM employees
WHERE commission <> 0;
```

```text output
 matched
---------
       3
(1 row)
```

You might expect 11, since only one person has a commission of 0. But the 8 NULL rows give UNKNOWN, so they are dropped. `NOT (commission = 0)` also gives 3, because `NOT UNKNOWN` is still UNKNOWN.

### CHECK works the other way

A `CHECK` constraint rejects a row only when the condition is FALSE. UNKNOWN passes. That is why `CHECK (price > 0)` accepts NULL ([Chapter 2](02-relational-model-and-keys.md)). To block NULL, add `NOT NULL` too.

### NULL in expressions

Arithmetic with NULL gives NULL. So `salary + commission` is NULL for Sara Khan.

```sql
SELECT first_name, salary + commission AS total_pay
FROM employees
WHERE emp_id IN (1, 2)
ORDER BY emp_id;
```

```text output
 first_name | total_pay
------------+-----------
 Sara       |      NULL
 James      |    100000
(2 rows)
```

Use `COALESCE(commission, 0)` to treat NULL as 0.

Concatenation differs. On Oracle, `||` treats NULL as empty, so `'a' || NULL` is `'a'`. On PostgreSQL, the result is NULL.

### Where NULL behaves differently

| Place | Behavior | Chapter |
|---|---|---|
| Aggregates | They skip NULLs. `COUNT(*)` differs from `COUNT(col)` | [10](../part-2-sql-basics/10-aggregation-group-by-having.md) |
| `GROUP BY`, `DISTINCT` | NULLs form one group | [8](../part-2-sql-basics/08-select-filter-sort.md), [10](../part-2-sql-basics/10-aggregation-group-by-having.md) |
| `UNIQUE` | Usually allows many NULLs | [2](02-relational-model-and-keys.md) |
| `ORDER BY` | Last or first, depending on the engine | [8](../part-2-sql-basics/08-select-filter-sort.md) |
| Joins | NULL never matches NULL | [11](../part-2-sql-basics/11-joins.md) |
| `NOT IN` | One NULL makes it return nothing | [13](../part-2-sql-basics/13-subqueries.md) |
| Set operators | NULLs count as equal | [12](../part-2-sql-basics/12-set-operations.md) |
| Oracle B-tree index | Rows with all-NULL keys are not stored | [29](../part-5-internals-and-performance/29-indexes.md) |

### Comparing NULLs safely

When you want two NULLs to match: `IS NOT DISTINCT FROM` on PostgreSQL and SQL Server 2022, and `<=>` on MySQL. Oracle has no such operator, so write `(a = b OR (a IS NULL AND b IS NULL))`, or use `DECODE` ([Chapter 9](../part-2-sql-basics/09-built-in-functions.md)).

### Design rules

- **Make a column `NOT NULL` unless "no value" is a real state.**
- **Never invent sentinel values** such as 0, -1 or 1900-01-01. They pollute `SUM`, `AVG` and comparisons.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Store money in `FLOAT` | Totals drift | Use `NUMERIC` |
| Store dates or numbers as text | Bad values get in, and sorting is wrong | Use the real type |
| Store a phone number as a number | The leading `0` or `+` is lost | Use text |
| Use `CHAR` for everything | Blank padding causes bugs | Use `VARCHAR2` or `VARCHAR` |
| Use `VARCHAR` on Oracle | Oracle may redefine it | Use `VARCHAR2` |
| Assume an Oracle `DATE` is only a date | `=` misses rows with a time | Use a range, or `TRUNC` |
| Store instants with no time zone | Conversions go wrong | Use a time-zone-aware type |
| Write `col = NULL` | It never matches | Use `IS NULL` |
| Treat NULL as 0 | Arithmetic gives NULL | Use `COALESCE` |
| Compare with `''` on Oracle | `''` is NULL there | Use `IS NULL` |
| Use -1 or 1900-01-01 to mean "missing" | Reports are polluted | Use NULL |

## Interview questions

**Q1. What is the difference between CHAR and VARCHAR2?**

`CHAR(n)` is fixed length, and shorter values are padded with blanks. `VARCHAR2(n)` stores only what you give it. I use `VARCHAR2` by default, and `CHAR` only for truly fixed codes. Blank padding can also cause comparison bugs between the two types.

**Q2. What data type do you use for money, and why?**

An exact type: `NUMERIC` or `DECIMAL` with a fixed scale, or whole cents in an integer. Never `FLOAT`, because binary fractions cannot represent values like 0.1 exactly, so totals drift and equality checks fail. I would also store the currency code.

**Q3. When would you use a time-zone-aware timestamp instead of a plain TIMESTAMP?**

When the value is an instant, such as when an order was placed, especially with users or servers in several zones. A plain `TIMESTAMP` is only a wall-clock reading. For a calendar fact such as a birth date, I use `DATE`. For a future local event, I store local time plus the zone name.

**Q4. Is 'abc' = 'ABC' true? Does it depend on the database?**

Yes, it depends on the collation. It is false on Oracle and PostgreSQL by default, and usually true on MySQL and SQL Server, whose default collations ignore case.

**Q5. Why might `WHERE phone = 5551234` fail to use an index on a VARCHAR2 phone column?**

Oracle implicitly converts the column, so it becomes `TO_NUMBER(phone) = 5551234`. The index on the text value cannot be used, and the query can fail with `ORA-01722` on any non-numeric value. I would compare with a string instead.

**Q6. What is a NULL value, and how is it different from zero or a blank space?**

NULL means the value is missing or unknown. Zero is a known number, and a blank is a known character. Comparing anything with NULL gives UNKNOWN. On Oracle, an empty string is treated as NULL, which is an exception to keep in mind.

**Q7. Why does `WHERE column = NULL` never match anything?**

A comparison with NULL gives UNKNOWN, and `WHERE` keeps only TRUE. Even `NULL = NULL` is not TRUE. I use `IS NULL`.

## Practice

**1. Show each employee's total pay, treating a missing commission as 0, for department 20.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, salary + COALESCE(commission, 0) AS total_pay
FROM employees
WHERE dept_id = 20
ORDER BY emp_id;
```

```text output
 first_name | total_pay
------------+-----------
 James      |    100000
 Lena       |     68000
 Diego      |     66500
 Mei        |     52000
(4 rows)
```

</details>

**2. Count customers who have no email.**

<details>
<summary>Show solution</summary>

```sql
SELECT COUNT(*) AS without_email
FROM customers
WHERE email IS NULL;
```

```text output
 without_email
---------------
             1
(1 row)
```

</details>

**3. List employees whose commission is not 5000, including those with no commission.**

<details>
<summary>Show solution</summary>

```sql
SELECT first_name, commission
FROM employees
WHERE commission <> 5000 OR commission IS NULL
ORDER BY emp_id;
```

```text output
 first_name | commission
------------+------------
 Sara       |       NULL
 Priya      |       NULL
 Omar       |       NULL
 Lena       |       8000
 Diego      |       6500
 Mei        |          0
 Arjun      |       NULL
 Emma       |       NULL
 Yusuf      |       NULL
 Nina       |       NULL
 Tom        |       NULL
(11 rows)
```

</details>

**4. Design a table `transfers` with an id, an amount, a currency code and the exact moment of the transfer. Write it for Oracle.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE TABLE transfers (
  transfer_id  NUMBER(12) PRIMARY KEY,
  amount       NUMBER(14,2) NOT NULL,
  currency     CHAR(3) NOT NULL,
  created_at   TIMESTAMP WITH TIME ZONE NOT NULL
);
```

`NUMBER(14,2)` keeps money exact. `CHAR(3)` suits a fixed code such as `USD`. The time is an instant, so it needs a time zone.

</details>

## Recap

- Money goes in `NUMERIC`, never `FLOAT`.
- Use `VARCHAR2` on Oracle, and `VARCHAR` or `TEXT` on PostgreSQL.
- An Oracle `DATE` always holds a time.
- Use a time-zone-aware type for instants, and `DATE` for calendar facts.
- Implicit conversion can stop an index being used.
- NULL means missing. It is not 0, and it is not a blank.
- A comparison with NULL gives UNKNOWN, and `WHERE` keeps only TRUE. `CHECK` rejects only FALSE.
- Make columns `NOT NULL` unless "no value" is a real state.

**Next:** [Chapter 6: Creating tables and constraints](../part-2-sql-basics/06-ddl-and-constraints.md)
