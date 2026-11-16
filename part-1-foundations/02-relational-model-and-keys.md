# 2. The Relational Model: Tables, Keys and Rules

**Level:** Basic | **Interview priority:** Must know | **Before this:** [Chapter 1](01-what-is-a-database.md)

> **In one line:** The relational model stores all data in tables linked by values, and keys and constraints keep those tables correct.

## What you will learn

- The formal terms: relation, tuple, attribute, domain, degree, cardinality
- Every kind of key, and how to tell them apart
- Primary key vs unique key
- Foreign keys and referential integrity
- The families of integrity constraints

## Why the relational model exists

In 1970, E. F. Codd proposed that all data should live in **relations**, linked by values, so that programs never follow storage pointers.

## The core terms

| Theory | Physical | On `departments` |
|---|---|---|
| Relation | Table | `departments` |
| Tuple | Row | `(20, 'Sales', 'London')` |
| Attribute | Column | `dept_name` |
| Domain | Allowed values | Text up to 50 characters |

```sql
SELECT dept_id, dept_name, location
FROM departments
ORDER BY dept_id;
```

```text output
 dept_id |  dept_name  | location
---------+-------------+-----------
      10 | Executive   | New York
      20 | Sales       | London
      30 | Engineering | Toronto
      40 | Finance     | Dubai
      50 | Legal       | Singapore
(5 rows)
```

The **relation schema** is written `departments(dept_id, dept_name, location)`, with the key underlined. The rows are the **relation instance**.

**Degree** (or arity) counts columns, and **cardinality** counts rows. `departments` has degree 3 and cardinality 5. ER diagrams use "cardinality" to mean something different ([Chapter 4](04-er-modeling.md)).

### Properties of a relation

- Row order means nothing.
- Column order means nothing, because columns are reached by name.
- No two rows are identical.
- Each cell holds one atomic value.

**Relations are sets, but SQL tables are multisets.** SQL lets a table exist with no key, and then nothing stops duplicates.

```sql
CREATE TABLE no_key (x INTEGER);
INSERT INTO no_key VALUES (1);
INSERT INTO no_key VALUES (1);
SELECT x FROM no_key ORDER BY x;
DROP TABLE no_key;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
 x
---
 1
 1
(2 rows)

DROP TABLE
```

**NULL** is a marker for a missing value, not a member of any domain. [Chapter 5](05-data-types-and-null.md) covers it fully.

## Keys

A row must be identifiable from its values alone.

| Key | Meaning | Example |
|---|---|---|
| **Superkey** | Any set of attributes that can never repeat | `{emp_id}`, `{emp_id, email}` |
| **Candidate key** | A minimal superkey: no strict subset still works | `{emp_id}`, `{email}` |
| **Primary key** | The candidate key you choose. Unique, never NULL, one per table | `emp_id` |
| **Alternate key** | A candidate key you did not choose | `email` |
| **Composite key** | A key of two or more columns | `(order_id, product_id)` |
| **Foreign key** | Matches a key in a parent table | `employees.dept_id` |
| **Natural key** | Comes from the real world | `email` |
| **Surrogate key** | Generated, with no business meaning | `emp_id` |

**Check every strict subset,** not only single columns. If AD is a key, neither A nor D alone may be one.

**A key is a rule about every legal row, not a fact about today's rows.** `departments.location` happens to be unique right now, but nothing makes it a key. Two departments may share a city tomorrow.

**A composite key** is unique only as a combination. Order 1001 appears twice in `order_items`, and product 3 appears many times, but each pair appears once.

**A prime attribute** belongs to any candidate key, not only the primary key. [Chapters 22](../part-4-database-design/22-functional-dependencies.md) and [23](../part-4-database-design/23-normalization.md) depend on this.

### Counting superkeys

One candidate key of k attributes among n gives 2^(n-k) superkeys, because every other attribute is free to be in or out. With two or more candidate keys, use inclusion-exclusion.

**R(A, B, C, D) has exactly two candidate keys, {A, B} and {A, C}. How many superkeys?**

```text
Contain AB:             2^2 = 4   (AB, ABC, ABD, ABCD)
Contain AC:             2^2 = 4   (AC, ABC, ACD, ABCD)
Contain both (ABC):     2^1 = 2   (ABC, ABCD)

Total: 4 + 4 - 2 = 6
```

## Primary key vs UNIQUE

| | Primary key | `UNIQUE` |
|---|---|---|
| How many per table | One | Many |
| NULL | Never | Allowed |
| Composite | Can be | Can be |
| Foreign key target | Yes | Yes |
| Index | Created automatically | Created automatically |

**NULL rules for `UNIQUE` differ.** SQL Server allows one NULL per unique column, while PostgreSQL, Oracle and MySQL allow many. `customers.email` is unique, and Ivan's is NULL, so another NULL is fine here:

```sql
INSERT INTO customers (customer_id, customer_name, signup_date)
VALUES (9, 'New Person', DATE '2024-07-01');

SELECT COUNT(*) AS null_emails FROM customers WHERE email IS NULL;
```

```text output
INSERT 0 1
 null_emails
-------------
           2
(1 row)
```

**Can a table have more than one primary key?** No, only one. But it can span several columns.

## Foreign keys

A **foreign key** is a column, or set of columns, in a child table whose values must match a primary or unique key in a parent table.

- It **may be NULL.** Tom Baker has no department, and website orders have no `emp_id`.
- It **may reference its own table:** `employees.manager_id`.
- The types must be compatible.

### What referential integrity blocks

A child pointing at a parent that does not exist:

```sql error=foreign
INSERT INTO orders (order_id, customer_id, order_date, status)
VALUES (2000, 99, DATE '2024-07-01', 'PENDING');
```

```text output
ERROR:  insert or update on table "orders" violates foreign key constraint "ord_cust_fk"
DETAIL:  Key (customer_id)=(99) is not present in table "customers".
```

And deleting a parent that has children:

```sql error=foreign
DELETE FROM departments WHERE dept_id = 20;
```

```text output
ERROR:  update or delete on table "departments" violates foreign key constraint "emp_dept_fk" on table "employees"
DETAIL:  Key (dept_id)=(20) is still referenced from table "employees".
```

### ON DELETE options

| Option | What happens to the children |
|---|---|
| (none, `NO ACTION`) | The delete is rejected |
| `CASCADE` | They are deleted too |
| `SET NULL` | Their foreign key is cleared |

**Tracing it by hand.** With a self-referencing table where each row points to its parent, `ON DELETE CASCADE` removes everything below the deleted row, level by level. Delete the top of a three-level chain, and all three levels go.

## Integrity constraints

| Family | Rule | SQL |
|---|---|---|
| **Domain** | Values fit the type and rules | Type, `NOT NULL`, `CHECK` |
| **Key** | No two rows share a candidate key | `UNIQUE`, `PRIMARY KEY` |
| **Entity** | No NULL in a primary key | `PRIMARY KEY` |
| **Referential** | A foreign key matches a parent, or is NULL | `FOREIGN KEY` |

**Does `CHECK (price > 0)` reject NULL?** No. A `CHECK` rejects a row only when the condition is FALSE, and with NULL it is UNKNOWN. Pair it with `NOT NULL`.

**Why do constraints belong in the database?** They hold for every client, script and future service, unlike checks in one application.

**Why name constraints?** `emp_email_uk` in an error message tells you which rule failed.

## Codd's rules

Codd gave 13 rules, numbered 0 to 12, usually called the twelve rules. Know that they exist, and a few of them: the **information rule** (all data is in tables), **guaranteed access** (table, key and column reach any value), **systematic treatment of NULL**, an **online catalog**, and **physical and logical data independence**.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Treat today's unique column as a key | Tomorrow's row breaks it | Use business rules |
| Confuse superkey and candidate key | Candidates must be minimal | Check every subset |
| Say a table can have two primary keys | It has one, perhaps composite | Say alternate key |
| Assume a foreign key cannot be NULL | It can | Add `NOT NULL` if required |
| Expect `CHECK` to reject NULL | UNKNOWN passes | Add `NOT NULL` |
| Assume foreign keys are indexed | Not on Oracle or PostgreSQL | Add an index |

## Interview questions

**Q1. What is the difference between the degree and the cardinality of a relation?**

Degree is the number of columns. Cardinality is the number of rows.

**Q2. What is the difference between a super key, a candidate key and a primary key?**

A superkey is any set of columns that identifies a row. A candidate key is a minimal superkey. A primary key is the candidate key you choose.

**Q3. A relation R(A, B, C, D) has exactly two candidate keys, {A, B} and {A, C}. How many superkeys does it have?**

Six. Four contain AB, four contain AC, and two contain both, so 4 + 4 - 2 = 6.

**Q4. Can a table have more than one primary key? Can a primary key span several columns?**

No to the first, and yes to the second. There is one primary key, and it can be composite.

**Q5. What is the difference between a primary key and a unique key?**

A table has one primary key, which can never be NULL. It can have many unique keys, which usually allow NULL. Both can be foreign key targets, and both create an index.

**Q6. Can a foreign key be NULL? Can it reference a column in the same table?**

Yes to both. NULL means no parent. A self-reference models hierarchies, like `manager_id`.

**Q7. What do ON DELETE CASCADE and ON DELETE SET NULL do, and what happens if you specify neither?**

`CASCADE` deletes the child rows too. `SET NULL` clears their foreign key. With neither, the delete is rejected while children exist.

**Q8. What are the types of integrity constraints?**

Domain, key, entity and referential integrity. In SQL: `NOT NULL`, `CHECK`, `UNIQUE`, `PRIMARY KEY` and `FOREIGN KEY`.

**Q9. Does CHECK (price > 0) reject NULL?**

No. NULL makes it UNKNOWN, and `CHECK` rejects only FALSE.

## Practice

**1. Name the degree and cardinality of `order_items`.**

<details>
<summary>Show solution</summary>

Degree 4, cardinality 22.

```sql
SELECT COUNT(*) AS cardinality FROM order_items;
```

```text output
 cardinality
-------------
          22
(1 row)
```

</details>

**2. List the candidate keys of `employees`.**

<details>
<summary>Show solution</summary>

`emp_id` and `email`. `emp_id` is the primary key, and `email` is an alternate key.

</details>

**3. R(A, B, C) has one candidate key, {A}. How many superkeys?**

<details>
<summary>Show solution</summary>

`2^(3-1) = 4`: A, AB, AC, ABC.

</details>

**4. Why can `orders.emp_id` be NULL, but `orders.customer_id` cannot?**

<details>
<summary>Show solution</summary>

A website order has no sales rep, so `emp_id` may be missing. Every order must have a customer, so `customer_id` is `NOT NULL`.

</details>

## Recap

- Relation, tuple, attribute and domain are table, row, column and allowed values.
- Degree is columns, and cardinality is rows.
- A candidate key is a minimal superkey. The primary key is the chosen one.
- A prime attribute is in **any** candidate key.
- A foreign key can be NULL, and can reference its own table.
- `CHECK` passes NULL.

**Next:** [Chapter 3: Relational algebra](03-relational-algebra.md)
