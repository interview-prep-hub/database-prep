# 3. Relational Algebra: The Math Under SQL

**Level:** Intermediate | **Interview priority:** Should know | **Before this:** [Chapter 2](02-relational-model-and-keys.md)

> **In one line:** Relational algebra is a small set of operators that take relations and return a relation, and SQL is built on top of it.

## What you will learn

- The basic operators, and how each maps to SQL
- Why the algebra's "select" is not SQL's `SELECT`
- Joins, semi-joins and division
- What relational algebra cannot do
- Relational calculus, in brief

This chapter matters most for theory rounds and exams such as GATE. If your interview is purely practical, skim it, and come back to division.

## What is relational algebra?

It is a set of operators that take relations and return a relation. This is called **closure**: the output of one operator can feed the next.

| Symbol | Read as | SQL |
|---|---|---|
| σ | select | `WHERE` |
| π | project | `SELECT DISTINCT` |
| ρ | rename | `AS` |
| ∪ | union | `UNION` |
| - | difference | `EXCEPT` or `MINUS` |
| × | product | `CROSS JOIN` |
| ⋈ | join | `JOIN` |
| ∩ | intersection | `INTERSECT` |
| ÷ | divide | Double `NOT EXISTS` |

## Selection and projection

**Selection σ** keeps rows that meet a condition. `σ_salary>90000(employees)`:

```sql
SELECT COUNT(*) AS row_count
FROM employees
WHERE salary > 90000;
```

```text output
 row_count
-----------
         5
(1 row)
```

**Projection π** keeps named columns, and removes duplicates, so it can shrink the row count. `π_job_title(employees)`:

```sql
SELECT COUNT(*) AS row_count
FROM (SELECT DISTINCT job_title FROM employees) t;
```

```text output
 row_count
-----------
         9
(1 row)
```

**The naming trap.** **Why is the algebra's select not the same as SQL's `SELECT`?** The operator called select is SQL's `WHERE`. SQL's `SELECT` clause is a projection, and it keeps duplicates.

### Composing operators

Read inside out, and draw a small tree:

```text
π_first_name(σ_dept_id=30(employees))

        π first_name
             |
        σ dept_id = 30
             |
         employees
```

A selection cannot use a column that an earlier projection removed.

**Rename ρ** gives a relation or column a new name, so that a table can be compared with itself.

## Set operators

**Union** and **difference** need **union-compatible** inputs: the same number of columns, and compatible domains. `r - s` is not `s - r`.

**Intersection** is derived: `r ∩ s = r - (r - s)`.

## Cartesian product

`r × s` pairs every row of r with every row of s, so m × n rows, and the columns add up. `departments × customers` gives 40 rows.

```sql
SELECT COUNT(*) AS row_count
FROM departments CROSS JOIN customers;
```

```text output
 row_count
-----------
        40
(1 row)
```

## Basic vs derived operators

**Which operators are basic?** Six: select, project, union, set difference, Cartesian product and rename. **Join, intersection, division and assignment are derived.**

## Joins

| Join | Meaning |
|---|---|
| **Theta join** | `r ⋈_θ s = σ_θ(r × s)`, any condition |
| **Equijoin** | Theta with only equality. Keeps both copies of the join column |
| **Natural join** | Matches every same-named column, and keeps one copy |

**What happens in a natural join when the two tables share no column name?** It becomes a Cartesian product.

**How many rows can a join of an m-row table and an n-row table return?** From 0 to m × n. A foreign key to a primary key caps the result at the child's row count.

**Outer joins** keep unmatched rows, and pad the other side with NULL.

**Semi-join and anti-join** return rows of r that have, or do not have, a match in s, with no columns added and no row repeated. These are `EXISTS` and `NOT EXISTS`.

## Division

**Division `r ÷ s` answers "for all" questions:** which A values are paired with **every** row of s.

```text
r (customer, product)       s (product)      r ÷ s
Bilal   8                   8                Bilal
Bilal   9                   9                David
David   8
David   9
Chloe   8
```

**From basic operators:**

```text
r ÷ s = π_A(r) - π_A((π_A(r) × s) - r)

1. π_A(r)                  all candidates
2. π_A(r) × s              every pairing they would need
3. (step 2) - r            the pairings that are missing
4. π_A(step 3)             candidates with something missing
5. Step 1 minus step 4     candidates with nothing missing
```

**How would you express "employees who own all brands"?** With `Own(eid, brand_id)` and `Brand(brand_id, name)`:

```text
Own ÷ π_brand_id(Brand)
```

[Chapter 13](../part-2-sql-basics/13-subqueries.md) writes this in SQL.

**The empty-divisor trap.** If s is empty, every candidate qualifies, by vacuous truth.

## Tricks with only basic operators

**The highest value, without aggregates:** all salaries, minus every salary lower than some other salary.

```text
π_salary(E) - π_E.salary(σ_E.salary < F.salary(E × ρ_F(E)))
```

**Counting to a fixed number.** "At least k" needs k copies of the relation, so k - 1 cross products, with conditions that force the rows to differ.

## What relational algebra cannot do

Basic relational algebra has **no aggregation** and **no recursion**. So `SUM`, and transitive closure ("everyone under this manager"), are inexpressible.

**Extended algebra** adds generalized projection (computed columns), aggregation γ, and duplicate elimination δ over bags. SQL is really a bag language.

**Algebra laws that optimizers use:** selections can be split and reordered, and a selection can move below a join. Pushing σ down means fewer rows reach the join ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).

## Relational calculus

Calculus describes the result with a logic formula, and gives no steps. **Algebra is procedural, and calculus is declarative.**

**Tuple relational calculus:** t stands for a row.

```text
{ t | t ∈ employees ∧ t.salary > 90000 }
```

**Domain relational calculus:** variables stand for attribute values.

```text
{ <n> | ∃i ∃l (<i, n, l> ∈ departments ∧ l = 'London') }
```

**Safety.** An expression is **safe** when every value in its result comes from the values in the formula and its relations. `{ t | ¬(t ∈ employees) }` is unsafe, because the result is infinite.

**Expressive power.** Basic relational algebra, safe tuple calculus and safe domain calculus express exactly the same queries. The word "safe" is essential.

**Translating.** `∀x P(x)` is `¬∃x ¬P(x)`, and `P ⇒ Q` is `¬P ∨ Q`. This turns "for all" into two nested `NOT EXISTS`.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Equate algebra's select with SQL's `SELECT` | They are different operators | select is `WHERE` |
| Forget that π removes duplicates | Row counts are wrong | SQL needs `DISTINCT` |
| Use a column removed by π | The expression is invalid | Project last |
| Treat intersection as basic | It is derived | Learn the six basic ones |
| Forget that natural join needs shared names | It becomes a product | Check the columns |
| Ignore an empty divisor | Everyone qualifies | Handle it |

## Interview questions

**Q1. Which relational algebra operators are basic, and which are derived?**

Select, project, union, set difference, Cartesian product and rename are basic. Join, intersection, division and assignment are derived.

**Q2. Why is the relational algebra select operator not the same thing as the SQL SELECT clause?**

The algebra's select filters rows, which is SQL's `WHERE`. SQL's `SELECT` clause chooses columns, which is projection, and it keeps duplicates.

**Q3. What is the difference between a theta join, an equijoin and a natural join?**

A theta join uses any condition. An equijoin uses only equality, and keeps both join columns. A natural join matches every same-named column, and keeps one copy.

**Q4. How would you express "employees who own all brands" in relational algebra?**

`Own ÷ π_brand_id(Brand)`. From basic operators, take all candidates, form every pairing they would need, subtract the real pairings, and remove candidates with anything missing.

**Q5. Using only selection, projection, cross product and rename, how many cross products do you need to find cities with at least 3 hotels?**

Two. Three copies of the relation need two cross products, with conditions that the city is the same and the three hotel ids differ.

**Q6. What is the difference between relational algebra and relational calculus? Are they equally powerful?**

Algebra lists the steps, and calculus states the result. Basic algebra and safe calculus have the same expressive power.

**Q7. What makes a tuple relational calculus expression unsafe? Give an example.**

Its result can include values from outside the database, so it may be infinite. `{ t | ¬(t ∈ employees) }` is unsafe.

## Practice

**1. Write in algebra: names of employees in department 30.**

<details>
<summary>Show solution</summary>

`π_first_name(σ_dept_id=30(employees))`

</details>

**2. Write in algebra: customers who have an order. Then customers with none.**

<details>
<summary>Show solution</summary>

```text
Have an order:  π_customer_id(orders)
Have none:      π_customer_id(customers) - π_customer_id(orders)
```

</details>

**3. r has 4 rows, s has 3. What are the minimum and maximum rows of `r ⋈ s`?**

<details>
<summary>Show solution</summary>

From 0 to 12.

</details>

**4. Express "products ordered by every customer" using division.**

<details>
<summary>Show solution</summary>

`π_product_id,customer_id(order_items ⋈ orders) ÷ π_customer_id(customers)`, then keep `product_id`. On the sample data, the result is empty.

</details>

## Recap

- Six basic operators: select, project, union, difference, product, rename.
- select is `WHERE`, and project is `SELECT DISTINCT`.
- Division answers "for all" questions.
- A natural join with no shared columns is a product.
- Basic algebra has no aggregation and no recursion.
- Algebra is procedural, and calculus is declarative. Safe forms are equally powerful.

**Next:** [Chapter 4: ER modeling](04-er-modeling.md)
