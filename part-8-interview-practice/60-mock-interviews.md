# 60. Mock Interviews: Full Rounds to Rehearse Under Time

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** The rest of the book

> **In one line:** A mock tests recall under time pressure and thinking while talking, which reading can never do.

## Mock rules

- Timer on, no notes, and no searching.
- Speak out loud.
- Write the query before you run it.
- Run each mock once. Mocks use fresh problems, so that you test recall, not memory of an answer.

## Know your round

These patterns are as reported by candidates, so check with your recruiter.

| Employer type | Typical round |
|---|---|
| Service companies, campus hiring | Multiple-choice test, then SQL and theory |
| Product companies | Live SQL in a shared editor |
| Oracle shops | PL/SQL coding and theory |
| Data teams | Modeling plus hard SQL |
| Senior roles | Design and production scenarios |

**Level expectations.** Junior means correct core patterns, on time. Senior adds unprompted edge checks, trade-offs and production thinking.

## The scoring sheet

Score each answer from 0 to 2 on each line.

| Criterion | 0 | 1 | 2 |
|---|---|---|---|
| Correctness | Wrong | Partly right | Right |
| Edge cases | Ignored | Some, when asked | Raised unprompted |
| Communication | Silent | Explained after | Explained while working |
| Structure | Tangled | Works | Clean, named steps |
| Trade-offs | None | One | Weighed, with a pick |

## Recovering in the room

- **Stuck:** say what you know, solve a smaller version first, and ask a clear question.
- **A wrong answer:** say "let me correct that", and fix it calmly. This scores well.
- **You do not know:** say so, then reason from what you do know.

### Sentences for thinking aloud

If English is not your first language, learn these:

- "Let me restate the problem to make sure I understand."
- "Before I write this, I want to check one thing: what should happen with NULLs?"
- "One row of the result stands for one customer."
- "I will do this in two steps."
- "There is a trade-off here. I would pick this, because..."
- "I am not sure, but here is how I would find out."

## Mock 1: Online test (30 minutes)

1. Which clause filters groups? (a) `WHERE` (b) `HAVING` (c) `ON`
2. `COUNT(col)` skips what?
3. Which is DDL? (a) `DELETE` (b) `TRUNCATE` (c) `COMMIT`
4. Which normal form removes partial dependencies?
5. Which ACID property does a crash test?
6. What does `LEFT JOIN` keep?
7. What does `UNION` do that `UNION ALL` does not?
8. Fill in: `SELECT dept_id, ____(*) FROM employees ____ BY dept_id;`
9. Fill in: on Oracle, top 3 with no `FETCH FIRST` needs `____` around a sorted inner query.
10. Write: list products never ordered.

<details>
<summary>Show answers</summary>

1. b. 2. NULLs. 3. b. 4. 2NF. 5. Durability. 6. Every left row. 7. It removes duplicates. 8. `COUNT`, `GROUP`. 9. `ROWNUM`. 10. `NOT EXISTS`, or `LEFT JOIN ... IS NULL`.

</details>

## Mock 2: Campus or junior round (30 minutes)

Theory, out loud: primary key vs unique key, `DELETE` vs `TRUNCATE`, what an index is, 3NF, ACID, and what a deadlock is.

**SQL:** using the sample tables, show each department's name and its highest salary, including departments with no employees.

<details>
<summary>Show solution</summary>

```sql
SELECT d.dept_name, MAX(e.salary) AS top_salary
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name
ORDER BY d.dept_id;
```

```text output
  dept_name  | top_salary
-------------+------------
 Executive   |     180000
 Sales       |      95000
 Engineering |     120000
 Finance     |      95000
 Legal       |       NULL
(5 rows)
```

</details>

## Mock 3: Timed SQL screen (32 minutes)

Four problems at 8 minutes each, in a plain editor.

**1.** Find the sales rep with the highest revenue from delivered orders.

**2.** For each product, show its share of its category's revenue.

**3.** Find customers whose first order was over 500.

**4.** Find months where revenue fell compared with the month before.

<details>
<summary>Show solutions</summary>

**1.**

```sql since=12c
-- Oracle 12c or later, and PostgreSQL
SELECT o.emp_id, SUM(i.quantity * i.unit_price) AS revenue
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.status = 'DELIVERED'
GROUP BY o.emp_id
ORDER BY revenue DESC
FETCH FIRST 1 ROW WITH TIES;
```

```text output
 emp_id | revenue
--------+---------
      6 | 2386.50
(1 row)
```

**2.**

```sql
WITH rev AS (
  SELECT p.category_id, p.product_name, SUM(i.quantity * i.unit_price) AS total
  FROM order_items i
  JOIN products p ON p.product_id = i.product_id
  GROUP BY p.category_id, p.product_name
)
SELECT category_id, product_name,
       ROUND(100.0 * total / SUM(total) OVER (PARTITION BY category_id), 1) AS pct
FROM rev
WHERE category_id = 6
ORDER BY pct DESC, product_name;
```

```text output
 category_id |  product_name   | pct
-------------+-----------------+------
           6 | SQL Basics      | 51.8
           6 | Database Design | 48.2
(2 rows)
```

**3.**

```sql
WITH totals AS (
  SELECT o.customer_id, o.order_id, o.order_date,
         SUM(i.quantity * i.unit_price) AS total,
         ROW_NUMBER() OVER (PARTITION BY o.customer_id
                            ORDER BY o.order_date, o.order_id) AS rn
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  GROUP BY o.customer_id, o.order_id, o.order_date
)
SELECT customer_id, order_id, total
FROM totals
WHERE rn = 1 AND total > 500
ORDER BY customer_id;
```

```text output
 customer_id | order_id |  total
-------------+----------+---------
           1 |     1001 |  838.98
           3 |     1003 | 1499.00
           4 |     1005 | 1018.99
           5 |     1007 |  837.98
           6 |     1010 |  749.00
(5 rows)
```

**4.**

```sql
WITH monthly AS (
  SELECT TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
         SUM(i.quantity * i.unit_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.order_id
  GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
),
compared AS (
  SELECT order_month, revenue,
         LAG(revenue) OVER (ORDER BY order_month) AS previous
  FROM monthly
)
SELECT order_month, revenue, previous
FROM compared
WHERE revenue < previous
ORDER BY order_month;
```

```text output
 order_month | revenue | previous
-------------+---------+----------
 2024-02     | 1507.49 |  2411.98
 2024-03     |  973.98 |  1507.49
 2024-04     |  868.00 |   973.98
(3 rows)
```

</details>

## Mock 4: Live SQL round (45 minutes)

Two problems in a shared editor, talking throughout.

**First:** Which customers placed an order in every month from January to March 2024?

**Second:** Show, for product 3, the running total of units ordered by date.

<details>
<summary>Show solutions</summary>

```sql
SELECT customer_id
FROM orders
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-04-01'
GROUP BY customer_id
HAVING COUNT(DISTINCT TO_CHAR(order_date, 'YYYY-MM')) = 3
ORDER BY customer_id;
```

```text output
 customer_id
-------------
           1
(1 row)
```

```sql
SELECT o.order_date, i.quantity,
       SUM(i.quantity) OVER (ORDER BY o.order_date, o.order_id
                             ROWS UNBOUNDED PRECEDING) AS units_so_far
FROM order_items i
JOIN orders o ON o.order_id = i.order_id
WHERE i.product_id = 3
ORDER BY o.order_date, o.order_id;
```

```text output
 order_date | quantity | units_so_far
------------+----------+--------------
 2024-01-05 |        2 |            2
 2024-02-14 |        1 |            3
 2024-03-03 |        2 |            5
 2024-06-01 |        3 |            8
(4 rows)
```

</details>

## Mock 5: Oracle developer round (45 minutes)

- Ten rapid questions from [Chapter 57](57-plsql-question-bank.md).
- **Coding:** write a function that returns a customer's lifetime spend, and 0 if they have no orders.
- **Trigger:** stop a product's price from rising by more than 50 percent at once.
- **Design:** how would you load 10 million rows with partial failures?

<details>
<summary>Show solution notes</summary>

The function uses `NVL(SUM(...), 0)`, and an aggregate never raises `NO_DATA_FOUND`. The trigger is a `BEFORE UPDATE OF price ... FOR EACH ROW`, with `WHEN (NEW.price > OLD.price * 1.5)` and `RAISE_APPLICATION_ERROR`. The load uses `BULK COLLECT` with `LIMIT` and `FORALL SAVE EXCEPTIONS`, or an external table with `LOG ERRORS`, committing per batch.

</details>

## Mock 6: Data modeling round (45 minutes)

**Prompt:** design a food delivery schema. Then: stop a courier taking two deliveries at once. Then: what changes at 10x?

## Mock 7: Warehouse round (45 minutes)

**Prompt:** design a warehouse for a streaming service. State the grain first. Then: a subscriber changes plan. Then: how do you report revenue by plan as of last March?

## Mock 8: Senior production round (45 minutes)

- A query went from 2 seconds to 40 at midnight.
- `pg_wal` is at 95 percent of the disk.
- Where would you put a rule that an order total must match its lines?

## Mock 9: Full loop (about 3 hours, with breaks)

Mocks 3, 6 and 8 in a row, to practice stamina.

## After every mock

Score it, and redo the missed items without help. Add each mistake to a personal error log, and repeat it after two days.

## Database stories

Prepare two or three true stories in situation, task, action, result form:

- **Tell me about a slow query you fixed. How did you prove it was fixed?**
- **Tell me about a production database issue you handled. What did you do first?**
- **Walk me through a schema you designed, and one decision you would change today.**
- **What is the hardest database problem you have solved?**

Use numbers: "from 40 seconds to 200 milliseconds".

## Questions to ask them

- Which engine and version do you use?
- How big are your main tables?
- Who owns the schema and migrations?
- How do you handle a production incident?

## The final week

| Day | Do |
|---|---|
| 7 to 5 days out | A mock on alternate days, in your target format |
| Daily | Review the error log |
| 3 days out | Redo weak chapters |
| 1 day out | [Last-day revision](../cheat-sheets/last-day-revision.md), and no new topics |

## Test and setup tactics

**Online tests:** read every option, check whether wrong answers lose marks, and flag hard items for later.

**Hidden test cases:** run your own edge cases, because passing the sample output proves little.

**Remote interviews:** practice in a shared editor, and test your microphone.

**Take-home tasks:** state your assumptions in comments, and keep CTEs readable.

## Recap

- Timer on, no notes, out loud.
- Score honestly, and redo what you missed.
- Prepare true stories, with numbers.
- Stop learning new topics the day before.

**Next:** [Last-day revision](../cheat-sheets/last-day-revision.md)
