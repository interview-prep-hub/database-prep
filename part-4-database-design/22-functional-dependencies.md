# 22. Functional Dependencies: The Rules Behind Your Data

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 2](../part-1-foundations/02-relational-model-and-keys.md)

> **In one line:** A functional dependency says that one set of columns decides another, and these rules are what normalization is built on.

## What you will learn

- What a functional dependency is, and why data alone can never prove one
- Partial and transitive dependencies
- Armstrong's axioms
- How to compute attribute closure
- How to find all the candidate keys of a table
- What a canonical cover is

## The rule behind repetition

Look at this flat table:

```text
order_id | customer_id | city
---------+-------------+--------
1001     | 1           | London
1004     | 1           | London
1009     | 1           | London
1002     | 2           | Dubai
```

London repeats, because of a rule in the real world: **if you know the customer, you know the city.** Naming these rules is the first step of good design.

## What is a functional dependency?

A **functional dependency (FD)** `X -> Y` holds when any two rows that agree on every column of X also agree on every column of Y. Read it as "X determines Y".

- X is the **determinant**, the left side.
- Y is the **dependent**, the right side.

Picture it as a function: each X value maps to exactly one Y value.

**Direction matters.** `emp_id -> dept_id` holds, because each employee has one department. `dept_id -> emp_id` does not, because a department has many employees.

**One pair of rows is enough to break an FD.** Is `product_id -> unit_price` true? No. Product 1 sold at 799.00 in order 1001, and at 749.00 in order 1010. The price charged depends on the pair `(order_id, product_id)`.

### Where do FDs come from?

From **business rules**, not from the rows you can see.

| Business rule | FD |
|---|---|
| Each department has one location | `dept_id -> location` |
| A department has many employees | No FD from `dept_id` to `emp_id` |
| Each order has one customer | `order_id -> customer_id` |

**Can you prove an FD by looking at the data?** No. Data can refute an FD, but it can never prove one. One counterexample disproves it. Rows that satisfy it may do so by chance. The `customers` table shows `city -> country` today, but a customer in London, Ontario would break that.

### Testing a suspected FD with SQL

Group by the left side, and keep the groups with more than one right-side value.

```sql
SELECT product_id, COUNT(DISTINCT unit_price) AS different_prices
FROM order_items
GROUP BY product_id
HAVING COUNT(DISTINCT unit_price) > 1;
```

```text output
 product_id | different_prices
------------+------------------
          1 |                2
(1 row)
```

That row refutes `product_id -> unit_price`.

```sql
SELECT city, COUNT(DISTINCT country) AS countries
FROM customers
GROUP BY city
HAVING COUNT(DISTINCT country) > 1;
```

```text output
 city | countries
------+-----------
(0 rows)
```

Zero rows means "not refuted", not "proved". There is also a NULL blind spot: `COUNT(DISTINCT)` ignores NULLs, so a group holding one value and one NULL passes the test.

### Trivial FDs

`X -> Y` is **trivial** when Y is a subset of X, such as `AB -> A`. Trivial FDs always hold, and normal form tests look only at non-trivial ones.

### Keys are FDs

K is a superkey of a table exactly when K determines every attribute. A candidate key is a minimal superkey ([Chapter 2](../part-1-foundations/02-relational-model-and-keys.md)). The reverse fails: the left side of an FD is usually not a key.

**Why does this matter for design?** The database enforces a key FD for free, through `PRIMARY KEY` or `UNIQUE`. It has no way to declare a non-key FD, such as `zip_code -> city`. That rule needs a trigger or application code, or better, a design where the left side is a key. That is what normalization does.

## Splitting an FD

The **right** side can be split, but the **left** side cannot.

- `X -> YZ` means `X -> Y` and `X -> Z`.
- `AB -> C` does **not** give `A -> C` or `B -> C`.

`(order_id, product_id) -> quantity` is true, and `order_id -> quantity` is not. An order's quantity depends on which product you mean.

## Full, partial and transitive dependencies

These three words drive 2NF and 3NF.

| Type | Meaning | Example |
|---|---|---|
| **Full** | No proper part of the left side is enough | `(order_id, product_id) -> quantity` |
| **Partial** | Part of a composite key determines a non-key column | `product_id -> product_name` in a table keyed on `(order_id, product_id)` |
| **Transitive** | key -> Y and Y -> Z, where Y is not a key | `order_id -> customer_id -> city` |

## Armstrong's axioms

From a given set F, other FDs logically follow. The set of all of them is the **closure F+**. It can grow exponentially, so nobody writes it out.

Three rules derive everything:

| Axiom | Rule | Example |
|---|---|---|
| Reflexivity | If Y is a subset of X, then `X -> Y` | `AB -> A` |
| Augmentation | `X -> Y` gives `XZ -> YZ` | `A -> B` gives `AC -> BC` |
| Transitivity | `X -> Y` and `Y -> Z` give `X -> Z` | `A -> B`, `B -> C` give `A -> C` |

They are **sound** (they derive only true FDs) and **complete** (they derive every implied FD).

Three more rules follow from them:

| Rule | Statement |
|---|---|
| Union | `X -> Y` and `X -> Z` give `X -> YZ` |
| Decomposition | `X -> YZ` gives `X -> Y` and `X -> Z` |
| Pseudotransitivity | `X -> Y` and `WY -> Z` give `WX -> Z` |

**Proving the union rule** needs augmentation and transitivity:

```text
1. X -> Y              given
2. X -> XY             augment 1 with X (XX is just X)
3. X -> Z              given
4. XY -> YZ            augment 3 with Y
5. X -> YZ             transitivity on 2 and 4
```

## Attribute closure

The **closure X+** is every attribute that X determines.

**The algorithm:** start with X. Whenever an FD's left side is inside the result, add its right side. Keep looping over all the FDs until a full pass adds nothing.

Take R(A, B, C, D, E) with F = { `A -> B`, `B -> C`, `CD -> E` }.

```text
Find {A}+
  Start        {A}
  A -> B       {A, B}
  B -> C       {A, B, C}
  CD -> E      needs D, not in the result, so no change
  A full pass adds nothing. Stop.
  {A}+ = {A, B, C}

Find {A, D}+
  Start        {A, D}
  A -> B       {A, B, D}
  B -> C       {A, B, C, D}
  CD -> E      {A, B, C, D, E}
  {A, D}+ = every attribute, so AD is a superkey
```

### What closure can do

| Question | Test |
|---|---|
| Is X a superkey? | Does X+ hold every attribute? |
| Does `X -> Y` follow from F? | Is Y inside X+? |
| Are two FD sets equivalent? | Can each one derive every FD in the other? |

All of these avoid computing F+.

## Finding all candidate keys

Use this recipe:

1. Attributes on **no right side** are in every key.
2. Attributes **only on right sides** are in no key.
3. Take the closure of the must-have set.
4. If it is not everything, add the remaining attributes one at a time, then two at a time, keeping only minimal results.

**Worked example.** R(A, B, C, D, E, H), with `A -> B`, `BC -> D`, `E -> C` and `D -> A`.

```text
Right sides: B, D, C, A
On no right side: E, H, so every key contains E and H

{E, H}+ = {E, H, C}                                  not everything

Add A: {A, E, H}+ = A, E, H, B, C, D                 everything, so AEH is a key
Add B: {B, E, H}+ = B, E, H, C, D, A                 everything, so BEH is a key
Add D: {D, E, H}+ = D, E, H, A, B, C                 everything, so DEH is a key
Add C: {C, E, H}+ = C, E, H                          not everything

Candidate keys: AEH, BEH, DEH
```

Each one is minimal, because removing any attribute breaks it.

**Prime and non-prime attributes.** A **prime** attribute belongs to **any** candidate key, not just the chosen primary key. Here A, B, D, E and H are prime, and C is non-prime. This definition drives 2NF and 3NF, so always find every key first.

## Canonical cover

A **canonical cover** is a smaller set equivalent to F. The 3NF algorithm in [Chapter 23](23-normalization.md) needs it.

An attribute is **extraneous** if you can remove it from an FD without changing what F implies.

**The method:**

1. Merge FDs with the same left side.
2. Remove extraneous attributes from left and right sides, one at a time.
3. Repeat until nothing changes.

**Worked example.** F = { `A -> BC`, `B -> C`, `A -> B`, `AB -> C` }.

```text
1. Merge A -> BC and A -> B:          { A -> BC, B -> C, AB -> C }
2. In AB -> C, A is extraneous,
   because B -> C already holds:      { A -> BC, B -> C }
3. In A -> BC, C is extraneous,
   because A -> B and B -> C give it: { A -> B, B -> C }
```

**Two names, two conventions.** Silberschatz's canonical cover merges FDs with equal left sides. Elmasri's minimal cover keeps a single attribute on each right side. Neither result is unique, so two correct answers can look different.

## The sample database's FDs

| Table | FDs |
|---|---|
| `departments` | `dept_id -> dept_name, location`, and `dept_name -> dept_id` |
| `employees` | `emp_id ->` all, and `email ->` all |
| `orders` | `order_id ->` all |
| `order_items` | `(order_id, product_id) -> quantity, unit_price` |

Every left side is a key. That is why this schema is already normalized.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Decide FDs from the current rows | A chance pattern looks like a rule | Use business rules |
| Split the left side | `AB -> C` does not give `A -> C` | Only the right side splits |
| Read `X -> Y` as two-way | It is one direction | Test each direction |
| Stop closure after one pass | Later FDs may unlock earlier ones | Loop until a pass adds nothing |
| Find only one candidate key | 2NF and 3NF verdicts come out wrong | Find them all |
| Treat prime as "in the primary key" | Prime means in any candidate key | Use all the keys |

## Interview questions

**Q1. What is a functional dependency? Can you prove one holds by looking at the data in a table?**

`X -> Y` means that any two rows with the same X have the same Y. You cannot prove it from data. One bad pair disproves it, but rows that fit may fit by chance. FDs come from business rules.

**Q2. State Armstrong's axioms. Which of them do you need to prove the union rule?**

Reflexivity, augmentation and transitivity. The union rule needs augmentation and transitivity: `X -> Y` gives `X -> XY`, `X -> Z` gives `XY -> YZ`, and transitivity gives `X -> YZ`.

**Q3. Given R(A, B, C, D, E, H) with A -> B, BC -> D, E -> C and D -> A, find all the candidate keys.**

E and H are on no right side, so they are in every key. {E, H}+ is only E, H and C. Adding A, B or D each gives everything, and adding C does not. So the keys are AEH, BEH and DEH.

**Q4. What is the difference between a partial dependency and a transitive dependency?**

A partial dependency is a non-key column depending on part of a composite key, which breaks 2NF. A transitive dependency is a non-key column depending on another non-key column, which breaks 3NF.

**Q5. What is attribute closure, and what can you do with it?**

X+ is every attribute that X determines. You start with X, and keep applying FDs until nothing changes. It tests whether X is a superkey, whether an FD is implied, and whether two FD sets are equivalent, all without computing F+.

## Practice

**1. R(A, B, C, D) has `AB -> C`, `C -> D`, `D -> A`. Find all candidate keys.**

<details>
<summary>Show solution</summary>

```text
Right sides: C, D, A. B is on no right side, so B is in every key.
{B}+ = {B}
Add A: {A, B}+ = A, B, C, D   key
Add C: {B, C}+ = B, C, D, A   key
Add D: {B, D}+ = B, D, A, C   key

Keys: AB, BC, BD
Prime: A, B, C, D (all of them)
```

</details>

**2. Does `A -> C` follow from `A -> B`, `B -> C`? Does `B -> A` follow?**

<details>
<summary>Show solution</summary>

`{A}+ = {A, B, C}`, so `A -> C` follows. `{B}+ = {B, C}`, so `B -> A` does not.

</details>

**3. Test whether `order_date -> customer_id` holds in the sample data.**

<details>
<summary>Show solution</summary>

```sql
SELECT order_date, COUNT(DISTINCT customer_id) AS customers
FROM orders
GROUP BY order_date
HAVING COUNT(DISTINCT customer_id) > 1;
```

```text output
 order_date | customers
------------+-----------
(0 rows)
```

No rows comes back, so it is not refuted. But it is clearly not a rule: two customers can order on the same day. This is why data alone cannot prove an FD.

</details>

**4. Find a canonical cover of { `A -> B`, `AB -> C`, `A -> C` }.**

<details>
<summary>Show solution</summary>

```text
B is extraneous in AB -> C, because A -> B holds. That gives A -> C.
The two A -> C are the same. Merge: A -> BC.
Canonical cover: { A -> BC }
```

</details>

## Recap

- `X -> Y` means equal X forces equal Y.
- FDs come from business rules. Data can refute them, never prove them.
- The right side splits, the left does not.
- Partial means part of a composite key. Transitive means through a non-key column.
- Armstrong's axioms are reflexivity, augmentation and transitivity.
- X+ tests for superkeys and implied FDs.
- To find keys, start with the attributes on no right side.
- Prime means in **any** candidate key.

**Next:** [Chapter 23: Normalization](23-normalization.md)
