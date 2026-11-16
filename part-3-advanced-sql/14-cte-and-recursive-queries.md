# 14. CTEs and Recursive Queries: Naming Steps and Walking Trees

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 13](../part-2-sql-basics/13-subqueries.md)

> **In one line:** A CTE gives a query step a name, and a recursive CTE repeats a step until a whole tree has been walked.

## What you will learn

- What a CTE is, and when to use one instead of a subquery
- Why self-joins cannot walk a hierarchy of unknown depth
- How a recursive CTE works, step by step
- Oracle's `CONNECT BY`, which still appears in many interviews
- How to generate rows, handle cycles and classify tree nodes

## What is a CTE?

A **CTE** (common table expression) is a named result that exists for one statement only. You write it with `WITH`, above the main query.

This derived table from [Chapter 13](../part-2-sql-basics/13-subqueries.md):

```sql
SELECT t.dept_id, t.total_pay
FROM (SELECT dept_id, SUM(salary) AS total_pay
      FROM employees
      GROUP BY dept_id) t
WHERE t.total_pay > 200000
ORDER BY t.dept_id;
```

becomes this CTE:

```sql
WITH dept_pay AS (
  SELECT dept_id, SUM(salary) AS total_pay
  FROM employees
  GROUP BY dept_id
)
SELECT dept_id, total_pay
FROM dept_pay
WHERE total_pay > 200000
ORDER BY dept_id;
```

```text output
 dept_id | total_pay
---------+-----------
      20 |    267000
      30 |    389000
(2 rows)
```

The result is the same. The difference is that it now reads from top to bottom, like a recipe.

### CTE rules

- One `WITH` can define several CTEs, separated by commas.
- A later CTE can read an earlier one, but not the reverse.
- One CTE can be used many times in the statement.
- It disappears when the statement ends.
- You can name its columns: `WITH dept_pay (dept_id, total_pay) AS (...)`.

```sql
WITH dept_pay AS (
  SELECT dept_id, SUM(salary) AS total_pay
  FROM employees
  WHERE dept_id IS NOT NULL
  GROUP BY dept_id
),
company AS (
  SELECT AVG(total_pay) AS avg_dept_pay
  FROM dept_pay
)
SELECT d.dept_id, d.total_pay
FROM dept_pay d, company c
WHERE d.total_pay > c.avg_dept_pay
ORDER BY d.dept_id;
```

```text output
 dept_id | total_pay
---------+-----------
      20 |    267000
      30 |    389000
(2 rows)
```

### CTE or subquery?

For non-recursive queries they have the same power, so choose for readability.

| Use a CTE when | Use a subquery when |
|---|---|
| You want to name the steps | The logic is one small line |
| You want it to read top to bottom | It is a simple `IN` or `EXISTS` test |
| You use the same result twice | |
| You need recursion | |

A derived table used twice must be written twice. The last practice question of [Chapter 13](../part-2-sql-basics/13-subqueries.md) shows that pain.

### Are CTEs faster?

Do not say so. It depends on the engine. PostgreSQL 12 and later folds a simple CTE used once into the main query, and it computes one used more than once a single time. You can force either with `MATERIALIZED` or `NOT MATERIALIZED`. Oracle's optimizer makes a similar choice by itself. Computing a heavy result once helps. Losing the use of an index on an outer filter hurts. Check the plan.

## The problem recursion solves

A hierarchy is often stored as a parent id in each row. This is called an **adjacency list**, and `employees.manager_id` and `categories.parent_id` are examples.

```text
Sara (1)
  +-- James (2)
  |     +-- Lena (5), Diego (6), Mei (7)
  +-- Priya (3)
  |     +-- Arjun (8)
  |     |     +-- Emma (9), Yusuf (10)
  |     +-- Tom (12)
  +-- Omar (4)
        +-- Nina (11)
```

One self-join reaches one level. Two joins reach two levels. To reach N levels you need N joins, and you do not know N in advance. That is why recursion exists.

## Recursive CTE anatomy

A recursive CTE has three parts:

```sql norun
WITH RECURSIVE reports (emp_id, first_name, depth) AS (
  -- 1. Anchor: the starting rows
  SELECT ...
  UNION ALL
  -- 2. Recursive member: joins the CTE back to the table to get the next level
  SELECT ... FROM employees e JOIN reports r ON e.manager_id = r.emp_id
)
-- 3. It stops by itself when the recursive member returns no rows
SELECT * FROM reports;
```

**Find everyone under Priya (emp_id 3), directly or indirectly.**

**PostgreSQL:**

```sql postgres
WITH RECURSIVE reports (emp_id, first_name, depth) AS (
  SELECT emp_id, first_name, 0
  FROM employees
  WHERE emp_id = 3

  UNION ALL

  SELECT e.emp_id, e.first_name, r.depth + 1
  FROM employees e
  JOIN reports r ON e.manager_id = r.emp_id
)
SELECT emp_id, first_name, depth
FROM reports
WHERE emp_id <> 3
ORDER BY depth, emp_id;
```

```text output
 emp_id | first_name | depth
--------+------------+-------
      8 | Arjun      |     1
     12 | Tom        |     1
      9 | Emma       |     2
     10 | Yusuf      |     2
(4 rows)
```

**Oracle (11.2 and later, so it runs on your XE):** the same query with plain `WITH`.

```sql oracle
WITH reports (emp_id, first_name, depth) AS (
  SELECT emp_id, first_name, 0
  FROM employees
  WHERE emp_id = 3

  UNION ALL

  SELECT e.emp_id, e.first_name, r.depth + 1
  FROM employees e
  JOIN reports r ON e.manager_id = r.emp_id
)
SELECT emp_id, first_name, depth
FROM reports
WHERE emp_id <> 3
ORDER BY depth, emp_id;
```

Syntax rules by engine:

| | Keyword | Notes |
|---|---|---|
| PostgreSQL, MySQL 8.0 | `WITH RECURSIVE` | |
| Oracle 11.2 and later | `WITH` | The column list is required (`ORA-32039` without it), and it must be `UNION ALL` |
| SQL Server | `WITH` | It must be `UNION ALL` |

The rest of this chapter's PostgreSQL recursive queries work on Oracle if you delete the word `RECURSIVE`.

### How it runs

It is a loop, not a real function call. The engine runs the anchor, then repeats the recursive member using **only the rows from the previous step**.

```text
Step 0 (anchor)    Priya
Step 1             rows whose manager is in {Priya}          ->  Arjun, Tom
Step 2             rows whose manager is in {Arjun, Tom}     ->  Emma, Yusuf
Step 3             rows whose manager is in {Emma, Yusuf}    ->  none, so stop

Result: everything collected
```

### Walking up

To find every manager above someone, reverse the join. Here we follow Emma upward.

```sql postgres
WITH RECURSIVE chain (emp_id, first_name, manager_id) AS (
  SELECT emp_id, first_name, manager_id
  FROM employees
  WHERE emp_id = 9

  UNION ALL

  SELECT m.emp_id, m.first_name, m.manager_id
  FROM employees m
  JOIN chain c ON m.emp_id = c.manager_id
)
SELECT emp_id, first_name
FROM chain
WHERE emp_id <> 9
ORDER BY emp_id DESC;
```

```text output
 emp_id | first_name
--------+------------
      8 | Arjun
      3 | Priya
      1 | Sara
(3 rows)
```

**Why is this impossible in plain relational algebra?** Finding all reachable pairs is called **transitive closure**. A relational algebra expression has a fixed number of joins, so it reaches a fixed depth. The depth of a hierarchy depends on the data. Recursion adds real power.

### Paths and tree order

Build a path column, then sort by it to print a tree. The anchor's column must be wide enough for the grown value, so cast it. Without the cast, PostgreSQL rejects the query with a type error, and Oracle can fail when the value outgrows the column.

```sql postgres
WITH RECURSIVE tree (emp_id, first_name, depth, path) AS (
  SELECT emp_id, first_name, 0, CAST(first_name AS VARCHAR(200))
  FROM employees
  WHERE manager_id IS NULL

  UNION ALL

  SELECT e.emp_id, e.first_name, t.depth + 1,
         CAST(t.path || '/' || e.first_name AS VARCHAR(200))
  FROM employees e
  JOIN tree t ON e.manager_id = t.emp_id
)
SELECT LPAD(' ', depth * 2) || first_name AS org_chart, path
FROM tree
ORDER BY path;
```

```text output
  org_chart  |          path
-------------+------------------------
 Sara        | Sara
   James     | Sara/James
     Diego   | Sara/James/Diego
     Lena    | Sara/James/Lena
     Mei     | Sara/James/Mei
   Omar      | Sara/Omar
     Nina    | Sara/Omar/Nina
   Priya     | Sara/Priya
     Arjun   | Sara/Priya/Arjun
       Emma  | Sara/Priya/Arjun/Emma
       Yusuf | Sara/Priya/Arjun/Yusuf
     Tom     | Sara/Priya/Tom
(12 rows)
```

### Rollups through a tree

**What is the total stock value under each top-level category, including all subcategories?** Electronics has no products of its own, only its children do.

Keep a root column, so that every descendant remembers where it started. `categories` has three top-level rows, so the anchor returns a forest, not one tree.

```sql postgres
WITH RECURSIVE tree (root_name, category_id) AS (
  SELECT category_name, category_id
  FROM categories
  WHERE parent_id IS NULL

  UNION ALL

  SELECT t.root_name, c.category_id
  FROM categories c
  JOIN tree t ON c.parent_id = t.category_id
)
SELECT t.root_name,
       COUNT(p.product_id) AS products,
       SUM(p.price * p.stock_qty) AS stock_value
FROM tree t
LEFT JOIN products p ON p.category_id = t.category_id
GROUP BY t.root_name
ORDER BY t.root_name;
```

```text output
  root_name  | products | stock_value
-------------+----------+-------------
 Books       |        2 |     5600.00
 Electronics |        5 |    69908.00
 Home        |        3 |     3105.00
(3 rows)
```

## Cycles

Bad data can make a hierarchy loop: A reports to B, and B reports to A. Recursion then runs forever, or until a limit stops it.

```sql
CREATE TABLE staff_bad (id INTEGER PRIMARY KEY, boss_id INTEGER);

INSERT INTO staff_bad VALUES (1, 2);
INSERT INTO staff_bad VALUES (2, 1);
```

The portable guard is to track the path, and refuse to step onto a node already on it:

```sql postgres
WITH RECURSIVE chain (id, boss_id, path) AS (
  SELECT id, boss_id, CAST('/' || id || '/' AS VARCHAR(200))
  FROM staff_bad
  WHERE id = 1

  UNION ALL

  SELECT s.id, s.boss_id, CAST(c.path || s.id || '/' AS VARCHAR(200))
  FROM staff_bad s
  JOIN chain c ON s.id = c.boss_id
  WHERE c.path NOT LIKE '%/' || s.id || '/%'
)
SELECT id, path
FROM chain
ORDER BY path;
```

```text output
 id | path
----+-------
  1 | /1/
  2 | /1/2/
(2 rows)
```

Built-in clauses exist too:

**Oracle:** add `CYCLE id SET is_cycle TO 'Y' DEFAULT 'N'` after the CTE.

**PostgreSQL 14 and later:** add `CYCLE id SET is_cycle USING cycle_path` after the CTE.

```sql
DROP TABLE staff_bad;
```

**Limits.** SQL Server stops at 100 levels unless you set `OPTION (MAXRECURSION n)`, where 0 means no limit. MySQL stops at `cte_max_recursion_depth`, which defaults to 1000. Inside the recursive member, most engines restrict aggregates, `DISTINCT` and outer joins on the CTE.

## Oracle CONNECT BY

This older syntax is Oracle-only, and it still appears in many Oracle interviews.

- `START WITH` picks the root rows.
- `CONNECT BY` defines the link.
- `PRIOR` marks the parent side, and its position sets the direction.

```text
CONNECT BY PRIOR emp_id = manager_id    walks DOWN: the prior row's id is this row's manager
CONNECT BY PRIOR manager_id = emp_id    walks UP
```

```sql oracle
SELECT LEVEL AS depth,
       SYS_CONNECT_BY_PATH(first_name, '/') AS path,
       CONNECT_BY_ISLEAF AS is_leaf
FROM employees
START WITH emp_id = 3
CONNECT BY PRIOR emp_id = manager_id
ORDER SIBLINGS BY first_name;
```

```text output
DEPTH PATH                    IS_LEAF
----- ----------------------- -------
    1 /Priya                        0
    2 /Priya/Arjun                  0
    3 /Priya/Arjun/Emma             1
    3 /Priya/Arjun/Yusuf            1
    2 /Priya/Tom                    1
```

The helpers:

| Helper | Gives |
|---|---|
| `LEVEL` | The depth, starting at 1 |
| `SYS_CONNECT_BY_PATH(col, '/')` | The path from the root |
| `CONNECT_BY_ROOT col` | The value from the root row |
| `CONNECT_BY_ISLEAF` | 1 if the row has no children |
| `ORDER SIBLINGS BY` | Sorts within each level and keeps the tree shape |

A plain `ORDER BY` or `GROUP BY` destroys the tree order.

### WHERE vs CONNECT BY

Oracle runs joins first, then `CONNECT BY`, then the remaining `WHERE`. This creates a classic trap.

A `WHERE` condition removes that one row, and keeps its children:

```sql oracle
SELECT first_name
FROM employees
WHERE first_name <> 'Arjun'
START WITH emp_id = 3
CONNECT BY PRIOR emp_id = manager_id
ORDER SIBLINGS BY first_name;
```

```text output
FIRST_NAME
----------
Priya
Emma
Yusuf
Tom
```

The same condition inside `CONNECT BY` prunes the whole branch:

```sql oracle
SELECT first_name
FROM employees
START WITH emp_id = 3
CONNECT BY PRIOR emp_id = manager_id AND first_name <> 'Arjun'
ORDER SIBLINGS BY first_name;
```

```text output
FIRST_NAME
----------
Priya
Tom
```

### Cycles in CONNECT BY

A loop raises `ORA-01436: CONNECT BY loop in user data`. Write `CONNECT BY NOCYCLE` to keep going, and use `CONNECT_BY_ISCYCLE` to find the row that closes the loop.

### Recursive CTE or CONNECT BY?

| | Recursive CTE | `CONNECT BY` |
|---|---|---|
| Standard SQL | Yes | No, Oracle only |
| Works on other engines | Yes | No |
| Reads easily | Longer | Very short for one table |
| Built-in helpers | You build path and depth yourself | `LEVEL`, `SYS_CONNECT_BY_PATH` and more |

**Use a recursive CTE for new code**, because it is standard. Use `CONNECT BY` when you maintain Oracle code, or want a short one-table hierarchy.

## Generating rows

Recursion can also produce rows from nothing. This is how you make a list of numbers or dates.

**PostgreSQL:**

```sql postgres
WITH RECURSIVE nums (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM nums WHERE n < 5
)
SELECT n FROM nums ORDER BY n;
```

```text output
 n
---
 1
 2
 3
 4
 5
(5 rows)
```

**Oracle,** using the well-known idiom:

```sql oracle
SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5;
```

PostgreSQL also has `generate_series`, which is simpler ([Chapter 20](20-modern-sql.md)).

Use this to find what is **missing**. Which order numbers from 1001 to 1016 have no payment?

```sql postgres
WITH RECURSIVE nums (n) AS (
  SELECT 1001
  UNION ALL
  SELECT n + 1 FROM nums WHERE n < 1016
)
SELECT n.n AS order_id
FROM nums n
WHERE NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = n.n)
ORDER BY n.n;
```

```text output
 order_id
----------
     1006
     1014
     1015
     1016
(4 rows)
```

## Classifying tree nodes

A popular puzzle (LeetCode "Tree Node", HackerRank "Binary Tree Nodes"): label each node as a root, an inner node or a leaf. No recursion is needed.

```sql
SELECT c.category_name,
       CASE WHEN c.parent_id IS NULL THEN 'Root'
            WHEN EXISTS (SELECT 1 FROM categories k WHERE k.parent_id = c.category_id) THEN 'Inner'
            ELSE 'Leaf'
       END AS node_type
FROM categories c
ORDER BY c.category_id;
```

```text output
   category_name   | node_type
-------------------+-----------
 Electronics       | Root
 Phones            | Inner
 Laptops           | Leaf
 Home              | Root
 Kitchen           | Leaf
 Books             | Root
 Phone Accessories | Leaf
(7 rows)
```

Do not write this with `NOT IN (SELECT parent_id ...)`. The root rows have a NULL `parent_id`, so you would fall into the trap from [Chapter 13](../part-2-sql-basics/13-subqueries.md).

## CTEs with DML

Oracle puts `WITH` after `INSERT INTO t`, or inside a subquery of `UPDATE` or `DELETE`. PostgreSQL also allows `WITH` in front of `UPDATE` and `DELETE`, and even allows data-changing statements inside a CTE.

## Other ways to store a tree

An adjacency list is simple, and fine for most cases. If you read trees far more than you change them, [Chapter 25](../part-4-database-design/25-schema-design-patterns.md) covers closure tables, materialized paths and nested sets.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Forget `RECURSIVE` on PostgreSQL or MySQL | The CTE cannot see itself | Add `RECURSIVE` |
| Write `RECURSIVE`, or leave out the column list, on Oracle | A syntax error, or `ORA-32039` | Use plain `WITH` and a column list |
| Forget a stop condition when generating rows | It runs forever, or hits a limit | Add `WHERE n < limit` |
| Ignore cycles in real data | Endless recursion | Track the path, or use `CYCLE` |
| Leave the anchor's path column narrow | A type or length error | `CAST` it wide in the anchor |
| Use `WHERE` to cut a branch in `CONNECT BY` | Only that one row goes, and the children stay | Put the test in `CONNECT BY` |
| Use `ORDER BY` on a tree | The tree order is lost | Use `ORDER SIBLINGS BY` or a path |
| Get `PRIOR` on the wrong side | The walk goes the wrong way | `PRIOR emp_id = manager_id` walks down |
| Say CTEs are always faster | It depends on the engine | Check the plan |

## Interview questions

**Q1. What is a CTE, and when do you use one instead of a subquery?**

A CTE is a named result that exists for one statement, written with `WITH`. I use one to name steps so that the query reads top to bottom, to use a result more than once, and for recursion. For a small `EXISTS` or `IN` test, a subquery is simpler. Their performance depends on the engine.

**Q2. Find all employees working directly or indirectly under employee 18.**

I would write a recursive CTE. The anchor selects employee 18. The recursive member joins `employees` to the CTE on `e.manager_id = r.emp_id`. It stops by itself when no new rows appear. On Oracle, `CONNECT BY PRIOR emp_id = manager_id` with `START WITH emp_id = 18` also works.

**Q3. How would you find every manager above an employee, and why is this impossible in plain relational algebra?**

I would reverse the recursive join: `m.emp_id = c.manager_id`. Plain relational algebra cannot do it, because an expression has a fixed number of joins, so it reaches a fixed depth, while the depth here depends on the data. This is called transitive closure.

**Q4. How does a recursive CTE work?**

It has an anchor, which gives the starting rows, and a recursive member, joined to the CTE by `UNION ALL`. The engine runs the anchor, then repeats the recursive member on only the rows from the previous step, until no new rows appear. It is a loop, not a function call.

**Q5. In Oracle, what is the difference between a condition in WHERE and one in CONNECT BY?**

`CONNECT BY` runs first. A condition in `WHERE` removes that row afterward, but its children stay. A condition in `CONNECT BY` stops the walk at that row, so the whole branch goes.

**Q6. How do you handle cycles in a hierarchy?**

On a recursive CTE, I track the path and refuse to revisit a node, or use the `CYCLE` clause on Oracle and PostgreSQL 14 and later. On `CONNECT BY`, I use `NOCYCLE` and `CONNECT_BY_ISCYCLE`. Without a guard, Oracle raises `ORA-01436` for `CONNECT BY`.

**Q7. How do you generate a list of numbers or dates without a table?**

A recursive CTE, `generate_series` on PostgreSQL, or `SELECT LEVEL FROM dual CONNECT BY LEVEL <= n` on Oracle. I use these lists with a `LEFT JOIN` or `NOT EXISTS` to find missing values.

## Practice

**1. Rewrite this using a CTE: list employees whose salary is above the company average.**

<details>
<summary>Show solution</summary>

```sql
WITH company AS (
  SELECT AVG(salary) AS avg_salary FROM employees
)
SELECT e.first_name, e.salary
FROM employees e, company c
WHERE e.salary > c.avg_salary
ORDER BY e.salary DESC, e.emp_id;
```

```text output
 first_name | salary
------------+--------
 Sara       | 180000
 Priya      | 120000
 Arjun      | 105000
 James      |  95000
 Omar       |  95000
(5 rows)
```

</details>

**2. List every category under Electronics, at any depth, with its depth. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
WITH RECURSIVE tree (category_id, category_name, depth) AS (
  SELECT category_id, category_name, 0
  FROM categories
  WHERE category_name = 'Electronics'

  UNION ALL

  SELECT c.category_id, c.category_name, t.depth + 1
  FROM categories c
  JOIN tree t ON c.parent_id = t.category_id
)
SELECT category_name, depth
FROM tree
WHERE depth > 0
ORDER BY depth, category_name;
```

```text output
   category_name   | depth
-------------------+-------
 Laptops           |     1
 Phones            |     1
 Phone Accessories |     2
(3 rows)
```

</details>

**3. Write the same query with Oracle `CONNECT BY`.**

<details>
<summary>Show solution</summary>

```sql oracle
SELECT category_name, LEVEL - 1 AS depth
FROM categories
WHERE category_name <> 'Electronics'
START WITH category_name = 'Electronics'
CONNECT BY PRIOR category_id = parent_id
ORDER BY depth, category_name;
```

```text output
CATEGORY_NAME     DEPTH
----------------- -----
Laptops               1
Phones                1
Phone Accessories     2
```

</details>

**4. For each manager, count everyone below them at any depth. Write it for PostgreSQL.**

<details>
<summary>Show solution</summary>

```sql postgres
WITH RECURSIVE reports (top_id, emp_id) AS (
  SELECT e.manager_id, e.emp_id
  FROM employees e
  WHERE e.manager_id IS NOT NULL

  UNION ALL

  SELECT r.top_id, e.emp_id
  FROM employees e
  JOIN reports r ON e.manager_id = r.emp_id
)
SELECT m.first_name, COUNT(*) AS everyone_below
FROM reports r
JOIN employees m ON m.emp_id = r.top_id
GROUP BY m.emp_id, m.first_name
ORDER BY everyone_below DESC, m.first_name;
```

```text output
 first_name | everyone_below
------------+----------------
 Sara       |             11
 Priya      |              4
 James      |              3
 Arjun      |              2
 Omar       |              1
(5 rows)
```

Start from every employee-manager pair, and keep the top person in a column as the walk goes down.

</details>

## Recap

- A CTE is a named step that lasts for one statement.
- Choose between a CTE and a subquery for readability. Speed depends on the engine.
- A recursive CTE is an anchor, `UNION ALL`, and a recursive member. It stops when no new rows appear.
- PostgreSQL and MySQL need `WITH RECURSIVE`. Oracle needs plain `WITH` and a column list.
- Walk down with `e.manager_id = r.emp_id`, and up by reversing it.
- `CONNECT BY PRIOR emp_id = manager_id` walks down. `WHERE` removes a row, and `CONNECT BY` removes a branch.
- Guard against cycles with a path, or with `CYCLE` or `NOCYCLE`.
- Generated rows plus an anti-join finds what is missing.

**Next:** [Chapter 15: Window functions](15-window-functions-ranking-and-offset.md)
