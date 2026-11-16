# 23. Normalization: From 1NF to 5NF, Step by Step

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 22](22-functional-dependencies.md)

> **In one line:** Normalization splits a table so that each fact is stored once, and each rule is enforced by a key.

## What you will learn

- Insertion, update and deletion anomalies, on real statements
- 1NF, 2NF, 3NF, BCNF, 4NF and 5NF, with worked examples
- How to find the highest normal form of any table
- Lossless join and dependency preservation
- How to normalize a real table in SQL, and prove nothing was lost

## The problem: anomalies

Here is one big flat table, built from the sample data.

```sql
CREATE TABLE flat_orders AS
SELECT o.order_id, o.order_date, c.customer_id, c.customer_name, c.city,
       p.product_id, p.product_name, i.unit_price, i.quantity
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id;

SELECT order_id, customer_name, city, product_name
FROM flat_orders
WHERE customer_id = 1
ORDER BY order_id, product_id;
```

```text output
SELECT 22
 order_id | customer_name |  city  | product_name
----------+---------------+--------+--------------
     1001 | Alice Morgan  | London | Phone X
     1001 | Alice Morgan  | London | Phone Case
     1004 | Alice Morgan  | London | Coffee Maker
     1009 | Alice Morgan  | London | Blender
     1014 | Alice Morgan  | London | Phone Case
(5 rows)
```

Alice's name and city repeat on every line. That repetition causes three problems.

**Update anomaly.** A fact is stored many times, so changing it in one place leaves the copies wrong.

```sql postgres
-- PostgreSQL
BEGIN;
UPDATE flat_orders SET city = 'Leeds' WHERE order_id = 1001;

SELECT DISTINCT customer_name, city
FROM flat_orders
WHERE customer_id = 1
ORDER BY city;

ROLLBACK;
```

```text output
BEGIN
UPDATE 2
 customer_name |  city
---------------+--------
 Alice Morgan  | Leeds
 Alice Morgan  | London
(2 rows)

ROLLBACK
```

Now Alice lives in two cities at once.

**Insertion anomaly.** You cannot store a fact without an unrelated one. A new customer with no order has no row here, because each row needs an `order_id` and a `product_id`.

**Deletion anomaly.** Removing one fact destroys another. The Blender appears in only one order. Delete that order, and the shop forgets the Blender exists.

```sql postgres
-- PostgreSQL
BEGIN;
DELETE FROM flat_orders WHERE order_id = 1009;

SELECT COUNT(*) AS blender_rows
FROM flat_orders
WHERE product_name = 'Blender';

ROLLBACK;
```

```text output
BEGIN
DELETE 1
 blender_rows
--------------
            0
(1 row)

ROLLBACK
```

## What is normalization?

**Normalization** means splitting one table into smaller tables, called a **decomposition**, so that each fact is stored once and each dependency is enforced by a key. A join must be able to rebuild the original.

The normal forms nest like a ladder. Each form includes all the ones before it.

```text
1NF  >  2NF  >  3NF  >  BCNF  >  4NF  >  5NF
(fewer problems as you go to the right)
```

A normal form is a property of a schema and its dependencies, not of the rows that happen to be stored.

Here is the old memory aid for the first three: every non-key column must depend on **the key** (1NF), **the whole key** (2NF), and **nothing but the key** (3NF).

## First normal form (1NF)

**Every column holds one atomic value.** No repeating groups, and no lists in a column.

```text
Not in 1NF:                         In 1NF:

student | courses                   student | course
--------+-----------                --------+-------
Asha    | SQL, Java                 Asha    | SQL
                                    Asha    | Java
```

Atomic depends on use. A roll number is atomic until you start parsing its department prefix.

`flat_orders` is already in 1NF.

## Second normal form (2NF)

**In 1NF, and no non-prime attribute is partially dependent on any candidate key.**

Only composite keys can violate this. A table whose candidate keys all have one column is automatically in 2NF.

`flat_orders` has the key `(order_id, product_id)`. Its FDs are:

```text
(order_id, product_id) -> unit_price, quantity      full
order_id -> order_date, customer_id, customer_name, city      PARTIAL
product_id -> product_name                          PARTIAL
```

Move each partial dependency to its own table:

```text
orders_2nf   (order_id, order_date, customer_id, customer_name, city)
products     (product_id, product_name)
order_lines  (order_id, product_id, unit_price, quantity)
```

## Third normal form (3NF)

**In 2NF, and no non-prime attribute depends transitively on a candidate key.** In `orders_2nf`:

```text
order_id -> customer_id -> customer_name, city
```

Move the customer columns out:

```text
customers    (customer_id, customer_name, city)
orders       (order_id, order_date, customer_id)
products     (product_id, product_name)
order_lines  (order_id, product_id, unit_price, quantity)
```

That is the sample database's design.

### The exact 3NF test

The "no transitive dependency" wording covers non-prime attributes only. The exact test is:

> For every non-trivial `X -> A`, either **X is a superkey**, or **A is prime**.

Each A may sit in a different candidate key.

**Watch out:** many tutorials define 2NF and 3NF against the primary key only. The general definitions use **every** candidate key, and the two can give different verdicts.

## Boyce-Codd normal form (BCNF)

**For every non-trivial `X -> Y`, X is a superkey.**

It is simpler and stricter than 3NF, because the "A is prime" escape is gone. Any two-attribute table is in BCNF.

### 3NF but not BCNF

**A table is in 3NF but not BCNF when some non-trivial `X -> A` has X not a superkey, and A prime.** This requires overlapping composite candidate keys.

**The classic example:** `Registration(rollno, courseid, email)`, with `{rollno, courseid} -> email` and `email -> rollno`.

```text
Keys:   (rollno, courseid) and (email, courseid)
Prime:  rollno, courseid, email (all of them)

{rollno, courseid} -> email    left side is a superkey: fine
email -> rollno                left side is not a superkey, but rollno is prime

3NF: yes (rollno is prime)
BCNF: no (email is not a superkey)
Highest normal form: 3NF
```

The leftover redundancy shows up in the rows. A student's email and roll number pair repeats for every course:

```text
rollno | courseid | email
-------+----------+---------
7      | DB       | a@x.com
7      | OS       | a@x.com     the same pair stored again
```

## What is the highest normal form?

Use this recipe every time:

1. Find **all** candidate keys ([Chapter 22](22-functional-dependencies.md)).
2. Mark the prime attributes.
3. Test 2NF, then 3NF, then BCNF, and stop at the first failure.

Never test 3NF before you have every candidate key.

| Normal form | Test |
|---|---|
| 1NF | All values are atomic |
| 2NF | No non-prime attribute depends on part of a candidate key |
| 3NF | For each `X -> A`: X is a superkey, or A is prime |
| BCNF | For each `X -> A`: X is a superkey |

## What makes a decomposition good?

- **Lossless join:** joining the fragments returns exactly the original rows.
- **Dependency preservation:** every FD can be checked inside single fragments, with no join.

### Lossless join

A lossy split returns **more** rows, called **spurious tuples**. So what is lost is information, not rows.

Split `employees` badly, on a column that is not a key of either side:

```sql
SELECT COUNT(*) AS rows_after_join
FROM (SELECT DISTINCT emp_id, first_name, job_title FROM employees) a
JOIN (SELECT DISTINCT job_title, salary FROM employees) b
  ON a.job_title = b.job_title;
```

```text output
 rows_after_join
-----------------
              15
(1 row)
```

There are 12 employees, and 15 rows came back. Sales Reps earn 60000 or 52000, so the join invents a Mei earning 60000, and a Lena earning 52000.

**The binary test.** Splitting R into R1 and R2 is lossless when:

```text
R1 ∩ R2 -> R1   or   R1 ∩ R2 -> R2
```

In plain terms, the shared columns must be a key of at least one side. **Split along a key.** This condition is necessary and sufficient when only FDs apply.

### Three or more fragments: the chase

The pairwise test is not a general test for three or more fragments. Use the **chase** (matrix) method:

1. Make one row per fragment and one column per attribute.
2. Write `a` where a fragment has the attribute, and `b` where it does not.
3. Apply the FDs: if two rows agree on the left side, make their right sides equal, preferring `a`.
4. If a row becomes all `a`, the decomposition is lossless.

**Example.** R(A, B, C, D), with `A -> B`, `B -> C`, `C -> D`, split into (A, B), (B, C) and (C, D).

```text
Start:                After B -> C:         After C -> D:
     A  B  C  D            A  B  C  D            A  B  C  D
R1   a  a  b  b       R1   a  a  a  b       R1   a  a  a  a   all a: lossless
R2   b  a  a  b       R2   b  a  a  b       R2   b  a  a  a
R3   b  b  a  a       R3   b  b  a  a       R3   b  b  a  a
```

### Dependency preservation

Every FD should be checkable inside single fragments, with no join. Formally, the FDs restricted to the fragments must imply all of F. An FD can survive even if no fragment holds it directly, as long as the others imply it.

### The two properties are independent

For `A -> B`, `B -> C`:

| Split | Lossless? | Keeps `B -> C`? |
|---|---|---|
| (A, B), (A, C) | Yes, A is a key of both | No |
| (A, B), (B, C) | Yes, B is a key of (B, C) | Yes |

**Practice on a classic.** X(P, Q, R, S) has `QR -> S`, `R -> P` and `S -> Q`, and is split into Y(P, R) and Z(Q, R, S).

```text
Keys of X: QR and RS

Y(P, R): two attributes, so BCNF
Z(Q, R, S): S -> Q holds, and S is not a superkey of Z, so Z is NOT in BCNF
            (it is in 3NF, because Q is prime)

Lossless: Y and Z share R, and R -> P makes R a key of Y. Yes.
Preserved: R -> P is in Y. QR -> S and S -> Q are in Z. Yes.
```

### Checking a fragment

The given F is enough to test BCNF on the original schema, but **not on a fragment**, because implied FDs can hide.

R(A, B, C, D, E), F = { `A -> B`, `BC -> D` }. The fragment (A, C, D, E) contains no given FD. Yet `AC -> D` holds, through B. And AC is not a superkey of the fragment, so it is not in BCNF.

## BCNF decomposition

**The algorithm:** find a violating `X -> Y`. Replace R with `XY` and `R - (Y - X)`. Repeat on each fragment that still violates. The result is always lossless. Different choices of FD can give different results.

**Example.** Class(course, title, dept, building), with `course -> title, dept` and `dept -> building`.

```text
Key: course
dept -> building violates BCNF, because dept is not a superkey

Split into:  (dept, building)  and  (course, title, dept)
```

### BCNF and dependency preservation cannot always coexist

**Why can't you always get both?** Take `dept_advisor(s_ID, i_ID, dept_name)`, with `i_ID -> dept_name` and `s_ID, dept_name -> i_ID`.

```text
Keys: (s_ID, dept_name) and (s_ID, i_ID)
i_ID -> dept_name violates BCNF

Split: (i_ID, dept_name) and (s_ID, i_ID)
```

No single fragment now holds `s_ID`, `dept_name` and `i_ID` together, so `s_ID, dept_name -> i_ID` cannot be checked without a join. Any BCNF split loses it.

## 3NF synthesis

**The algorithm:** take a canonical cover ([Chapter 22](22-functional-dependencies.md)), make one schema per FD, add a schema holding a candidate key if no schema already has one, and drop any schema contained in another. The result is **always** lossless and dependency preserving.

**Example.** R(A, B, C, D), with `A -> B`, `B -> C`. The key is AD.

```text
A -> B    gives (A, B)
B -> C    gives (B, C)
No schema contains the key AD, so add (A, D)
Result: (A, B), (B, C), (A, D)
```

## 3NF or BCNF?

| | 3NF | BCNF |
|---|---|---|
| Removes redundancy | Most | More |
| Lossless | Always | Always |
| Preserves dependencies | Always | Not always |

**Default to BCNF.** Stop at 3NF when going further would lose a dependency you need to enforce with a simple key.

## Normalizing a real table in SQL

Create each fragment with `SELECT DISTINCT`.

```sql
CREATE TABLE n_customers AS
SELECT DISTINCT customer_id, customer_name, city FROM flat_orders;

CREATE TABLE n_orders AS
SELECT DISTINCT order_id, order_date, customer_id FROM flat_orders;

CREATE TABLE n_products AS
SELECT DISTINCT product_id, product_name FROM flat_orders;

CREATE TABLE n_order_lines AS
SELECT order_id, product_id, unit_price, quantity FROM flat_orders;

ALTER TABLE n_customers ADD CONSTRAINT n_cust_pk PRIMARY KEY (customer_id);
ALTER TABLE n_orders ADD CONSTRAINT n_ord_pk PRIMARY KEY (order_id);
ALTER TABLE n_products ADD CONSTRAINT n_prod_pk PRIMARY KEY (product_id);
ALTER TABLE n_order_lines ADD CONSTRAINT n_line_pk PRIMARY KEY (order_id, product_id);
ALTER TABLE n_orders ADD CONSTRAINT n_ord_cust_fk
  FOREIGN KEY (customer_id) REFERENCES n_customers (customer_id);
ALTER TABLE n_order_lines ADD CONSTRAINT n_line_ord_fk
  FOREIGN KEY (order_id) REFERENCES n_orders (order_id);
```

**Prove nothing changed.** Join back, and compare in both directions. Use `MINUS` on Oracle.

```sql postgres
-- PostgreSQL
WITH rebuilt AS (
  SELECT o.order_id, o.order_date, c.customer_id, c.customer_name, c.city,
         p.product_id, p.product_name, l.unit_price, l.quantity
  FROM n_order_lines l
  JOIN n_orders o ON o.order_id = l.order_id
  JOIN n_customers c ON c.customer_id = o.customer_id
  JOIN n_products p ON p.product_id = l.product_id
)
SELECT (SELECT COUNT(*) FROM (SELECT * FROM rebuilt EXCEPT SELECT * FROM flat_orders) x) AS only_in_rebuilt,
       (SELECT COUNT(*) FROM (SELECT * FROM flat_orders EXCEPT SELECT * FROM rebuilt) y) AS only_in_flat;
```

```text output
 only_in_rebuilt | only_in_flat
-----------------+--------------
               0 |            0
(1 row)
```

Zero and zero: the split was lossless.

```sql
DROP TABLE n_order_lines;
DROP TABLE n_orders;
DROP TABLE n_products;
DROP TABLE n_customers;
DROP TABLE flat_orders;
```

## Beyond BCNF

### Why FDs are not enough

`inst_info(ID, child_name, phone)` has no non-trivial FDs, so it is in BCNF. Yet every new phone repeats every child:

```text
ID | child_name | phone
---+------------+------
1  | Ali        | 111
1  | Sana       | 111
1  | Ali        | 222
1  | Sana       | 222
```

Two independent multi-valued facts share one table.

### 4NF and multivalued dependencies

A **multivalued dependency** `X ->> Y` means that for a given X, the set of Y values is independent of the other columns. Every FD is an MVD, but not every MVD is an FD.

**4NF:** for every non-trivial MVD `X ->> Y`, X is a superkey.

Fix: split into `(ID, child_name)` and `(ID, phone)`.

### 5NF

A **join dependency** means a table splits losslessly into three parts, but not into any two. **5NF** (also called PJNF) means every join dependency is implied by the candidate keys.

**Example.** `supplies(supplier, part, project)`, under the rule: if a supplier makes a part, and a project uses that part, and the supplier works with that project, then the supplier supplies that part to that project. Three two-column tables can rebuild it, and no two can. It is rare in practice.

### What normalization does not catch

`earnings_2024` and `earnings_2025` can both be in BCNF, and the design is still bad, because data is hiding in table names. Columns such as `sales_jan` and `sales_feb` are the same problem. The fix is one table with a year or month column.

### Normalization as a check on an ER design

A careful ER design ([Chapter 4](../part-1-foundations/04-er-modeling.md)) should already be normalized. An FD from a non-key attribute, such as `dept_name -> building` on an instructor table, signals a missing entity.

## Summary

| Form | Test | Violation | The fix removes |
|---|---|---|---|
| 1NF | Atomic values | Lists in a column | Repeating groups |
| 2NF | No partial dependency | Column depends on part of a key | Partial dependencies |
| 3NF | `X -> A`: X superkey, or A prime | Non-key depends on non-key | Transitive dependencies |
| BCNF | `X -> A`: X superkey | A non-key determinant | All FD redundancy |
| 4NF | `X ->> Y`: X superkey | Independent multi-valued facts | MVD redundancy |
| 5NF | Join dependencies implied by keys | Splits only into three or more | Join dependency redundancy |

**Beyond this:** temporal data breaks some FDs, since `ID -> address` stops holding once history is stored. DKNF and 6NF exist, but they are rarely used in practice.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Test 3NF with only the primary key | The verdict can be wrong | Use every candidate key |
| Test 2NF on a single-column key | It cannot fail | Skip to 3NF |
| Say a lossy split loses rows | It adds spurious rows | Say it loses information |
| Test a fragment with only the given FDs | Implied FDs hide | Project the FDs |
| Say BCNF is always better | It can lose a dependency | Check preservation |
| Decide normal forms from sample rows | They are about dependencies | Start from the FDs |
| Split without a key in common | The join is lossy | Split along a key |
| Think BCNF means the design is good | Data can hide in table names | Check for that too |

## Interview questions

**Q1. What are insertion, update and deletion anomalies?**

They are problems caused by redundancy. An update anomaly: a fact stored many times gets changed in only some places. An insertion anomaly: you cannot store a fact without an unrelated one, such as a customer with no order. A deletion anomaly: removing one fact destroys another, such as deleting a product's only order.

**Q2. What is normalization and why is it needed?**

It is splitting tables so that each fact is stored once and each dependency is enforced by a key. It removes those anomalies and makes the data consistent, and a lossless join can still rebuild the original.

**Q3. Explain 1NF, 2NF, 3NF and BCNF with examples.**

1NF: atomic values, so no list of courses in a column. 2NF: no non-key column depends on part of a composite key, so `product_name` does not belong in a table keyed on `(order_id, product_id)`. 3NF: no non-key column depends on another non-key column, so `city` does not belong in `orders`. BCNF: every determinant is a superkey.

**Q4. What is the difference between 3NF and BCNF? Give a relation that is in 3NF but not in BCNF.**

3NF allows `X -> A` when A is prime, and BCNF does not. `Registration(rollno, courseid, email)` with `{rollno, courseid} -> email` and `email -> rollno`. Its keys are `(rollno, courseid)` and `(email, courseid)`, so all columns are prime and it is in 3NF, but `email` is not a superkey, so it is not in BCNF.

**Q5. A table is in 3NF but not in BCNF. What must be true?**

It has a non-trivial `X -> A` where X is not a superkey, and A is prime. That requires overlapping composite candidate keys.

**Q6. What does lossless join mean? Does a lossy decomposition lose rows?**

Lossless means the join of the fragments returns exactly the original rows. A lossy split does not lose rows. It adds spurious rows, so what is lost is the information about which rows were real.

**Q7. How do you test whether a decomposition into two relations is lossless? What changes with three?**

For two, the shared columns must be a superkey of at least one fragment. For three or more, the pairwise test is not general, so I use the chase method.

**Q8. What is dependency preservation? Can a decomposition be lossless but not dependency preserving?**

It means each FD can be checked inside single fragments, with no join. Yes: for `A -> B`, `B -> C`, the split (A, B), (A, C) is lossless, but `B -> C` cannot be checked in one fragment.

**Q9. Why can't you always get BCNF together with dependency preservation?**

Take `dept_advisor(s_ID, i_ID, dept_name)` with `i_ID -> dept_name` and `s_ID, dept_name -> i_ID`. Any BCNF split separates those columns, so the second FD can no longer be checked in one table.

**Q10. Why might you stop at 3NF instead of going to BCNF in a real system?**

Because 3NF always preserves dependencies. If BCNF would lose a rule that a simple key could otherwise enforce, I may keep 3NF, and accept a little redundancy.

**Q11. A relation has no non-trivial functional dependencies, yet it still has redundancy. How?**

Through a multivalued dependency. Two independent multi-valued facts share a table, such as children and phones for one person. It can be in BCNF and still not be in 4NF.

**Q12. What are 4NF and 5NF?**

4NF removes multivalued dependencies: for every non-trivial `X ->> Y`, X is a superkey. 5NF removes join dependencies not implied by keys, for a table that splits losslessly into three parts but not two. It is rare.

**Q13. The tables earnings_2024 and earnings_2025 are both in BCNF. What is wrong?**

Data is hiding in the table names. Normal forms do not catch that. It should be one table with a year column.

## Practice

**1. R(A, B, C) has `A -> B`, `B -> C`. What is its highest normal form?**

<details>
<summary>Show solution</summary>

```text
Key: A
All keys have one column, so 2NF holds.
B -> C: B is not a superkey, and C is not prime. So 3NF fails.
Highest: 2NF
Fix: (A, B) and (B, C)
```

</details>

**2. R(A, B, C, D) has key AB, with `AB -> CD` and `B -> D`. What is its highest normal form?**

<details>
<summary>Show solution</summary>

```text
B -> D: B is part of the key, and D is non-prime. Partial dependency.
Highest: 1NF
Fix: (A, B, C) and (B, D)
```

</details>

**3. Is splitting R(A, B, C) with `A -> B` into (A, B) and (B, C) lossless?**

<details>
<summary>Show solution</summary>

The shared column is B. Is B a key of either side? `B -> A` is not given, and `B -> C` is not given. So no, the split is lossy. Splitting into (A, B) and (A, C) is lossless, since A is a key of (A, B).

</details>

**4. An orders spreadsheet has `order_id, customer_email, customer_phone, items`, where `items` holds "pen x2, book x1". Normalize it to 3NF.**

<details>
<summary>Show solution</summary>

```text
1NF: items is a list, so split it into lines.
customers    (customer_id, email, phone)
orders       (order_id, customer_id)
products     (product_id, name)
order_lines  (order_id, product_id, quantity)
```

Add a surrogate `customer_id`, because email and phone can change.

</details>

## Recap

- Redundancy causes update, insertion and deletion anomalies.
- 1NF is atomic values. 2NF removes partial dependencies. 3NF removes transitive ones.
- BCNF: every determinant is a superkey.
- 3NF but not BCNF needs overlapping composite candidate keys.
- For the highest normal form, find all keys first, then test upward.
- Lossy means extra rows. Split along a key.
- 3NF always preserves dependencies. BCNF may not.
- 4NF handles independent multi-valued facts.

**Next:** [Chapter 24: Denormalization](24-denormalization-and-trade-offs.md)
