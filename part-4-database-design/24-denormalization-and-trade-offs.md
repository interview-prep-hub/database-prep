# 24. Denormalization: When and How to Break the Rules

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 23](23-normalization.md)

> **In one line:** Denormalization is a deliberate choice to store redundant data so that reads do less work, and you pay for it on every write.

**About the demos:** the session demos in this chapter run on PostgreSQL. On Oracle, a transaction starts by itself, so leave out `BEGIN`.

## What you will learn

- What denormalization is, and what it costs
- What to try before denormalizing
- The techniques, and how to keep copies in sync
- Why a `like_count` column can go wrong under load
- When never to denormalize

## Normalized is the default

Store each fact once. Denormalize only against a **measured** read bottleneck.

"Joins are slow" is not a reason by itself. Indexed joins that touch few rows are cheap. The cost appears with huge joins and heavy aggregates over millions of rows.

## What is denormalization?

**Denormalization** is a deliberate decision to store redundant or precomputed data, after you have a normalized design, so that reads do less work. It is different from a table that was never normalized. One copy stays the source of truth.

**What you pay:**

- Writes get slower.
- Storage grows.
- You need more code.
- The update anomalies from [Chapter 23](23-normalization.md) come back, and now you must handle them yourself.

Count the fan-out. Renaming one customer who is copied onto 10 million order rows is 10 million updates.

## History capture is not denormalization

**Why does an order line store `unit_price` when `products` already has `price`?** Because the value must **not** change when the source row changes. It is a fact about that sale.

Order 1010 sold Phone X at 749.00, while today's list price is 799.00.

```sql
SELECT p.product_name, i.unit_price AS charged, p.price AS list_price
FROM order_items i
JOIN products p ON p.product_id = i.product_id
WHERE i.order_id = 1010;
```

```text output
 product_name | charged | list_price
--------------+---------+------------
 Phone X      |  749.00 |     799.00
(1 row)
```

This is correct modeling. A shipping address copied onto an order works the same way.

## Try these first

An **index** is a separate sorted copy of some columns that the engine keeps up to date, like the index at the back of a book ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)). It is redundancy too, but the database maintains it for you. So try cheaper fixes first, in this order:

1. Rewrite the query.
2. Add the right index.
3. Add a covering index.
4. Use a materialized view.
5. Cache in the application.
6. Add a read replica.
7. Partition.

## Techniques

| Technique | Speeds up | Every write must also |
|---|---|---|
| Copied column | Reads that need a parent's value | Update the copies |
| Stored derived value (order total) | Reads of a computed value | Recompute it |
| Summary table (daily sales) | Reports | Update or rebuild the summary |
| Pre-joined wide table | Read-heavy pages | Update many rows |

### Worked example: a stored order total

```sql
CREATE TABLE orders_demo AS
SELECT order_id, customer_id, status FROM orders;

ALTER TABLE orders_demo ADD order_total NUMERIC(12,2);

UPDATE orders_demo d
SET order_total = (SELECT SUM(i.quantity * i.unit_price)
                   FROM order_items i
                   WHERE i.order_id = d.order_id);
```

Before, the read needs a join and a `GROUP BY`. After, it is one row:

```sql
SELECT order_id, order_total
FROM orders_demo
WHERE order_id = 1001;
```

```text output
 order_id | order_total
----------+-------------
     1001 |      838.98
(1 row)
```

Now every change to `order_items` must also update `order_total`.

## Keeping copies in sync

| Option | Fresh? | Cost |
|---|---|---|
| Same transaction, in application code | Always | Every writer must remember it |
| Generated column | Always | Same-row calculations only |
| Trigger | Always | Hidden work on every write |
| Materialized view | Stale until refresh | Refresh cost |
| Asynchronous change data capture | Slightly behind | Complex to run |

**Generated columns** handle same-row calculations only. Oracle has virtual columns (11g), PostgreSQL has stored generated columns (12), and virtual ones from 18. They cannot read another table.

**Change data capture (CDC)** reads the database's change log and publishes each change ([Chapter 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md)).

### A trigger that keeps a total current

**PostgreSQL:**

```sql postgres
CREATE FUNCTION refresh_order_total() RETURNS trigger AS $$
BEGIN
  UPDATE orders_demo d
  SET order_total = (SELECT SUM(i.quantity * i.unit_price)
                     FROM order_items i
                     WHERE i.order_id = d.order_id)
  WHERE d.order_id = COALESCE(NEW.order_id, OLD.order_id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER items_total
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION refresh_order_total();

UPDATE order_items SET quantity = 2 WHERE order_id = 1004 AND product_id = 6;

SELECT order_total FROM orders_demo WHERE order_id = 1004;
```

```text output
CREATE FUNCTION
CREATE TRIGGER
UPDATE 1
 order_total
-------------
      179.00
(1 row)
```

**Oracle:** a trigger on `order_items` that updates `orders_demo` works in the same way, because it changes a different table.

```sql oracle
CREATE OR REPLACE TRIGGER items_total
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW
DECLARE
  v_change NUMBER;
BEGIN
  v_change := NVL(:NEW.quantity * :NEW.unit_price, 0)
            - NVL(:OLD.quantity * :OLD.unit_price, 0);

  UPDATE orders_demo
  SET order_total = NVL(order_total, 0) + v_change
  WHERE order_id = NVL(:NEW.order_id, :OLD.order_id);
END;
/
```

The Oracle version adds the difference, instead of re-reading `order_items`. A row trigger that queries its own table fails with `ORA-04091`, the mutating table error ([Chapter 48](../part-7-plsql/48-triggers.md)).

**Trigger costs:** hidden work on every write, and slow bulk loads.

```sql postgres
DROP TRIGGER items_total ON order_items;
DROP FUNCTION refresh_order_total();
```

### Reconciliation

Copies drift. So write the SQL that finds the drift, run it on a schedule, and decide what happens on a mismatch. **The source of truth always wins.**

```sql
SELECT d.order_id, d.order_total, t.real_total
FROM orders_demo d
JOIN (SELECT order_id, SUM(quantity * unit_price) AS real_total
      FROM order_items
      GROUP BY order_id) t ON t.order_id = d.order_id
WHERE d.order_total <> t.real_total
ORDER BY d.order_id;
```

```text output
 order_id | order_total | real_total
----------+-------------+------------
(0 rows)
```

No rows means no drift.

```sql
DROP TABLE orders_demo;
```

## Counter columns: the lost update

**We store `like_count` on the posts table, and it is wrong under load. Why?**

```sql postgres
CREATE TABLE posts (post_id INTEGER PRIMARY KEY, like_count INTEGER NOT NULL);
INSERT INTO posts VALUES (1, 10);
```

Two sessions each read the count, add 1 in the application, and write it back.

```sql postgres session=A
BEGIN;
SELECT like_count FROM posts WHERE post_id = 1;
```

```sql postgres session=B
BEGIN;
SELECT like_count FROM posts WHERE post_id = 1;
UPDATE posts SET like_count = 11 WHERE post_id = 1;
COMMIT;
```

```sql postgres session=A
UPDATE posts SET like_count = 11 WHERE post_id = 1;
COMMIT;
SELECT like_count FROM posts WHERE post_id = 1;
```

```text output
UPDATE 1
COMMIT
 like_count
------------
         11
(1 row)
```

Two likes, and the count went up by one. Both read 10, and both wrote 11. This is a **lost update** ([Chapter 32](../part-5-internals-and-performance/32-transactions-and-isolation.md)).

**The fix** is to let the database do the arithmetic in one statement. The row lock makes the second writer wait, and it then sees the new value.

```sql postgres
UPDATE posts SET like_count = like_count + 1 WHERE post_id = 1;
```

The options, with their trade-offs:

| Option | Trade-off |
|---|---|
| `SET n = n + 1` | Correct, but very hot rows queue up |
| Count from a likes table | Correct, but slow reads |
| Sharded counters: several rows, added up on read | Less contention |
| Batch the increments | Slightly behind |
| Approximate counters | Fine when an exact number does not matter |

```sql postgres
DROP TABLE posts;
```

## When not to denormalize

Do it only with same-transaction updates, or not at all, for:

- Money balances
- Stock levels
- Permissions
- Anything where a stale copy causes real harm

Also avoid copying columns that change often, or that land on many rows.

## Denormalization at scale

Across shards, a join becomes a network fan-out. So sharded systems keep related data in one shard, and copy small reference tables to every shard ([Chapter 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md)). Star schemas ([Chapter 26](26-data-warehouse-design.md)) and feed tables are planned denormalization.

**Other forms:**

- **Caching** is denormalization outside the database, with the same staleness problems.
- **Embedding child rows in a JSON column** gives fast reads of the whole document, but painful partial updates, and no foreign keys.
- A **vertical split** of hot and cold columns shrinks rows without duplicating anything.

## View vs materialized view vs denormalized table

| | View | Materialized view | Denormalized table |
|---|---|---|---|
| Stores rows | No | Yes | Yes |
| Who keeps it current | Nothing to keep | The database, on refresh | You |
| Freshness | Always current | Stale until refresh | Depends on your code |
| Sync code | None | None | Yes |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Denormalize because "joins are slow" | Cost without proof | Measure first, and try an index |
| Copy a column and forget one writer | Copies drift | Update them in one place |
| Have no reconciliation | Drift goes unnoticed | Schedule a check |
| Read, add 1, then write | A lost update | Use `SET n = n + 1` |
| Denormalize balances | A stale copy costs real money | Keep one source, or update in one transaction |
| Call a copied `unit_price` denormalization | It is history, and it must not change | Call it history capture |
| Copy a column that changes often | Huge write fan-out | Keep it normalized |

## Interview questions

**Q1. What is denormalization and when would you use it?**

It is deliberately storing redundant or precomputed data to make reads cheaper. I use it only after measuring a real read bottleneck, and after trying indexes and materialized views. It costs write speed, storage and sync code.

**Q2. When would you denormalize? Give a real example and explain how you keep the copies in sync.**

A dashboard reads order totals constantly, and summing the lines is too slow. I would store `order_total` on `orders`, and update it in the same transaction as the lines, or with a trigger. I would also run a reconciliation query on a schedule, and the lines would stay the source of truth.

**Q3. Why does an order line store unit_price when the products table already has it?**

It is history, not redundancy. The price charged must not change when the list price does. Order 1010 sold a phone at 749 while the list price is 799.

**Q4. We store like_count on the posts table and it is wrong under load. Why, and what are the options?**

It is a lost update: two sessions read 10, add 1 in the application, and both write 11. The simple fix is `SET like_count = like_count + 1` in one statement. For very hot rows, I would use sharded counters or batched increments, or count from a likes table if reads are rare.

**Q5. What is the difference between a view, a materialized view and a denormalized table?**

A view stores no rows, and is always current. A materialized view stores rows, and the database refreshes them, so it can be stale, but there is no sync code to write. A denormalized table stores rows, and my code keeps them current, so it is the most flexible and the most error-prone.

**Q6. Explain 1NF through BCNF, and tell me when you would deliberately denormalize.**

1NF is atomic values, 2NF removes partial dependencies, 3NF removes transitive ones, and in BCNF every determinant is a superkey. I normalize by default, and denormalize only for a measured read problem, with a plan to keep the copies in sync.

## Practice

**1. Name the technique: `customers.order_count`, kept up to date by a trigger.**

<details>
<summary>Show solution</summary>

A stored derived value, kept in sync by a trigger. Reads of the count get faster, and every order insert or delete must update it.

</details>

**2. Write the reconciliation query for a `customers.order_count` column. (Assume the column exists.)**

<details>
<summary>Show solution</summary>

```sql norun
SELECT c.customer_id, c.order_count, COUNT(o.order_id) AS real_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.order_count
HAVING c.order_count <> COUNT(o.order_id);
```

The `LEFT JOIN` keeps customers with no orders, so a wrong non-zero count on them is caught.

</details>

**3. Should a bank keep `balance` on the account row? How?**

<details>
<summary>Show solution</summary>

Yes, it is common, because reading a balance by adding up all transactions is slow. But it must update in the **same transaction** as the ledger row, and the ledger stays the source of truth. A reconciliation job compares them. A separate process that updates the balance later would not be acceptable, because a stale balance can let someone overspend.

</details>

## Recap

- Normalized is the default. Denormalize only for a measured read bottleneck.
- Try a better query, an index, then a materialized view first.
- You pay with write speed, storage, sync code and possible drift.
- Copying `unit_price` onto an order is history, not denormalization.
- Keep copies in sync in one transaction, and reconcile on a schedule.
- `SET n = n + 1` prevents the lost update.
- Never let money or stock go stale.

**Next:** [Chapter 25: Schema design](25-schema-design-patterns.md)
