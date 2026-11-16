# 25. Schema Design: Keys, Constraints, Patterns and Anti-Patterns

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 4](../part-1-foundations/04-er-modeling.md) and [Chapter 24](24-denormalization-and-trade-offs.md)

> **In one line:** Good schema design means choosing keys, constraints and shapes so that bad data cannot get in, and the common queries stay simple.

## What you will learn

- Natural vs surrogate keys, and integer vs UUID
- How to model many-to-many, followers and inheritance
- Partial uniqueness and overlap prevention
- Anti-patterns: comma-separated lists, EAV, polymorphic associations
- Hierarchies, status history, soft delete and audit
- Zero-downtime schema changes

## ER recap

[Chapter 4](../part-1-foundations/04-er-modeling.md) owns ER modeling. In short: strong entities become tables, a multivalued attribute gets its own table, a weak entity's key includes its owner's key, 1:N puts the foreign key on the "many" side, and M:N gets a junction table.

**What is the difference between cardinality and participation?** Cardinality is how many: 1:1, 1:N or M:N. Participation is whether every entity must take part: total or partial.

**Hotel rooms and persons have a many-to-many lodging relationship. Where do you store the rent payment?** On the junction table, because it describes the pair, not either side alone.

**Minimum tables for two entities linked by one 1:N and one M:N?** Three: two entity tables and one junction table. The 1:N foreign key sits on the "many" entity's table.

## Relationships

### Junction table keys

A composite primary key is simple. A surrogate key plus `UNIQUE` on the pair is better when other tables must reference the row. Attributes such as `enrolled_at` go here.

```sql
CREATE TABLE enrollments (
  student_id   INTEGER NOT NULL,
  course_id    INTEGER NOT NULL,
  enrolled_at  DATE NOT NULL,
  CONSTRAINT enroll_pk PRIMARY KEY (student_id, course_id)
);

DROP TABLE enrollments;
```

### Followers and friendships

**How would you model followers on a social network?** `follows(follower_id, followee_id)`, with the primary key on the pair, and an index for each direction.

**How does it change for mutual friendships?** Store one canonical ordered pair, with `CHECK (user_a < user_b)`, so that a friendship cannot be stored twice. Queries must then look on both sides. The other way is two mirrored rows, which makes reads simple and writes double.

### Foreign key actions

Choose per relationship: reject the delete by default, `CASCADE` for rows that mean nothing without the parent (order lines), and `SET NULL` when the child can live on. Never use `CASCADE` on anything financial.

### Inheritance

**How would you map an inheritance hierarchy to relational tables?**

| Option | Tables | Good | Bad |
|---|---|---|---|
| Single table | One, with a type column | Simple, fast | Many NULL columns, weak constraints |
| Class table | Parent plus one per subclass | Clean, strong constraints | More joins |
| Concrete table | One per subclass | No joins for one type | A query across types needs `UNION` |

Use single table when subclasses are similar, and class table when they differ.

## Keys

### Natural vs surrogate

A **natural key** has business meaning, such as an email. A **surrogate key** is a generated id with none.

**Why shouldn't email be the primary key of the users table?** Emails change, get reused, and leak personal data, and every foreign key copies them. Use a surrogate primary key, with `UNIQUE` on email.

### Integer, UUID, or something else?

| Key | Width | Insert locality | Generates without a central sequence | Exposes volume |
|---|---|---|---|---|
| `BIGINT` identity | 8 bytes | Excellent | No | Yes |
| UUIDv4 | 16 bytes | Poor, random | Yes | No |
| UUIDv7 | 16 bytes | Good, time-ordered | Yes | Timing only |
| Snowflake-style | 8 bytes | Good | Yes | Timing only |

**Which primary key would you pick for a high-insert table?** `BIGINT` identity on one database. UUIDv7 when many writers generate ids. Avoid random UUIDv4 as a clustered key, because it splits pages all over the tree, and on InnoDB every secondary index also stores the primary key, so a wide key inflates them all.

**On your Oracle 11g,** use a sequence. Identity columns arrived in 12c.

**Locality cuts both ways.** Sequential keys send every insert to the same right-edge block. Oracle reverse key indexes relieve that hot block, but lose range scans. In distributed SQL, the advice flips: a sequential key funnels writes into one range, so hash or random keys spread them better.

### Fixed value sets

| Option | Adding a value costs | Can hold extra columns |
|---|---|---|
| `CHECK` | `ALTER TABLE` | No |
| Lookup table | One `INSERT` | Yes |
| PostgreSQL `ENUM` | `ALTER TYPE`, and values cannot easily be removed | No |

Use a lookup table when the list changes, or carries data. Use `CHECK` for short, stable lists.

## Constraints as design

The database is the last line of defense. `NOT NULL`, `UNIQUE`, `CHECK` and `FOREIGN KEY` hold for every client, script and future service, unlike application validation.

### Partial uniqueness

**How do you enforce "only one active subscription per user"?**

```sql postgres
CREATE TABLE subscriptions (
  sub_id   INTEGER PRIMARY KEY,
  user_id  INTEGER NOT NULL,
  status   VARCHAR(10) NOT NULL
);

CREATE UNIQUE INDEX one_active_sub ON subscriptions (user_id) WHERE status = 'ACTIVE';

INSERT INTO subscriptions VALUES (1, 7, 'ACTIVE');
INSERT INTO subscriptions VALUES (2, 7, 'CANCELLED');
```

```sql postgres error=one_active_sub
INSERT INTO subscriptions VALUES (3, 7, 'ACTIVE');
```

```text output
ERROR:  duplicate key value violates unique constraint "one_active_sub"
DETAIL:  Key (user_id)=(7) already exists.
```

On **Oracle**, a function-based unique index does the same thing, because an all-NULL key is not stored. This works on 11g.

```sql oracle
CREATE UNIQUE INDEX one_active_sub ON subscriptions (
  CASE WHEN status = 'ACTIVE' THEN user_id END
);
```

```sql postgres
DROP TABLE subscriptions;
```

### Why can't a CHECK enforce a rule across rows?

A `CHECK` sees one row. Oracle and PostgreSQL both reject subqueries in it. Use a unique or exclusion constraint where possible, or a locked trigger or transaction otherwise. Oracle 26ai documents `CREATE ASSERTION`, with restrictions.

### Preventing overlaps

For half-open ranges, two bookings overlap when `a.start < b.end AND b.start < a.end`. PostgreSQL can enforce this in the database:

```sql norun
CREATE EXTENSION btree_gist;

CREATE TABLE bookings (
  room_id  INTEGER NOT NULL,
  during   DATERANGE NOT NULL,
  EXCLUDE USING gist (room_id WITH =, during WITH &&)
);
```

PostgreSQL 18 also has temporal `PRIMARY KEY (room_id, during WITHOUT OVERLAPS)`. On Oracle, store one row per night with `UNIQUE (room_id, night)`, or serialize on the room row.

### Foreign keys and indexes

**Should foreign key columns be indexed? What can go wrong in Oracle if they are not?** Yes. In Oracle, deleting a parent row, or changing its key, takes a table lock on the child for that statement. Other sessions can query the child but not change it, and deadlocks become likely.

**At scale,** foreign keys cost validation reads, and make schema changes harder. Sharded MySQL estates often run without them, and then enforce integrity in the application, with reconciliation.

## Where logic lives

[Chapter 41](../part-6-architecture-and-scale/41-where-to-do-what.md) is the full guide. The short rule: use a constraint if it can express the rule, then set-based SQL, then PL/SQL, then application code.

**Should business logic live in the database or in the application?** Data rules that must hold for every writer belong in the database. Workflow and calls to other systems belong in the application.

**When would you use a view rather than a stored procedure?** A view is a named query that you can join, filter and grant on, with no side effects. A procedure is a named action with several steps, DML and error handling.

**How do you organize complex logic into packages?** Group related procedures behind a public specification, one package per business area, and let applications call the package rather than touch tables directly ([Chapter 47](../part-7-plsql/47-packages.md)).

## Anti-patterns

### Repeating groups

```text
Comma-separated ids:    product_ids = '1,3,9'
Numbered columns:       tag1, tag2, tag3
Cloned tables:          orders_2024, orders_2025
```

Each one blocks foreign keys and indexes, or hides a partition. Use a child table, or real partitioning.

### Entity-Attribute-Value

EAV stores `(entity_id, attribute, value)`. It loses types and constraints, and simple reads need self-joins:

```sql
CREATE TABLE product_attrs (
  product_id  INTEGER NOT NULL,
  attr_name   VARCHAR(30) NOT NULL,
  attr_value  VARCHAR(100),
  CONSTRAINT attr_pk PRIMARY KEY (product_id, attr_name)
);

INSERT INTO product_attrs VALUES (1, 'color', 'black');
INSERT INTO product_attrs VALUES (1, 'storage', '256');

SELECT c.product_id, c.attr_value AS color, s.attr_value AS storage
FROM product_attrs c
JOIN product_attrs s ON s.product_id = c.product_id AND s.attr_name = 'storage'
WHERE c.attr_name = 'color';

DROP TABLE product_attrs;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
 product_id | color | storage
------------+-------+---------
          1 | black | 256
(1 row)

DROP TABLE
```

**Customers want custom fields. Would you use EAV, JSONB or extra columns?**

| Situation | Use |
|---|---|
| Few fields, shared by everyone | Extra columns |
| Vary per customer, rarely filtered | JSONB |
| Constrained and queried | A per-type table |
| Nothing else fits | EAV, as a last resort |

Promote hot JSON fields to real or generated columns.

### Polymorphic associations

**Comments can belong to a post, a photo or a video. What does a `commentable_type` column break?** No real foreign key is possible, so orphans and wrong types go unnoticed.

**Fixes:**

- A join table per parent: `post_comments`, `photo_comments`
- An **exclusive arc**: one nullable foreign key per parent, plus a `CHECK` that exactly one is set
- A shared parent table: `commentable(id)`, which posts, photos and videos all reference

## Hierarchies

[Chapter 14](../part-3-advanced-sql/14-cte-and-recursive-queries.md) teaches the queries. Here are the storage models.

| Model | Read a subtree | Move a subtree | Integrity |
|---|---|---|---|
| **Adjacency list** | Recursive query | One update | Foreign key |
| **Materialized path** | `LIKE 'a/b/%'` | Rewrite the subtree | Manual |
| **Nested set** | Very fast | Slow, renumbers much | Manual |
| **Closure table** | Very fast | Many rows change | Foreign keys |

**How would you store threaded comments with unlimited nesting?** Adjacency list by default, with a recursive CTE. If whole threads are fetched constantly, add a `root_id` column, or a materialized path.

## Status history

**A status column forgets the moment it changes. How would you report time spent in each status?** Add an append-only transition table, and keep the current status on the main row.

```sql
CREATE TABLE order_status_history (
  order_id    INTEGER NOT NULL,
  status      VARCHAR(20) NOT NULL,
  changed_at  DATE NOT NULL,
  CONSTRAINT osh_pk PRIMARY KEY (order_id, changed_at)
);

INSERT INTO order_status_history VALUES (1011, 'PENDING', DATE '2024-04-21');
INSERT INTO order_status_history VALUES (1011, 'SHIPPED', DATE '2024-04-23');
INSERT INTO order_status_history VALUES (1011, 'DELIVERED', DATE '2024-04-28');

SELECT status, changed_at,
       LEAD(changed_at) OVER (PARTITION BY order_id ORDER BY changed_at) - changed_at AS days_in_status
FROM order_status_history
ORDER BY changed_at;

DROP TABLE order_status_history;
```

```text output
CREATE TABLE
INSERT 0 1
INSERT 0 1
INSERT 0 1
  status   | changed_at | days_in_status
-----------+------------+----------------
 PENDING   | 2024-04-21 |              2
 SHIPPED   | 2024-04-23 |              5
 DELIVERED | 2024-04-28 |           NULL
(3 rows)

DROP TABLE
```

## Soft delete

**Soft delete or hard delete: how do you decide?** By undo needs, legal retention, and references from other rows.

**What does soft delete cost?**

- Every query must filter it.
- Unique constraints collide with deleted rows.
- `ON DELETE CASCADE` never fires.
- Tables grow forever.
- Privacy laws may require real erasure.

**Unique email with soft deletes:** a partial unique index on PostgreSQL, a filtered index on SQL Server, and a function-based index returning NULL for deleted rows on Oracle.

## Audit and history

**How would you keep a full audit history of every change to a table?**

| Option | Cost | Catches every writer? |
|---|---|---|
| Trigger writing a history table | A little on every write | Yes |
| CDC stream | None inside the transaction | Yes |
| Application logging | Low | No |
| Temporal tables | Built in | Yes |

SQL Server has temporal tables, and Oracle has Flashback Data Archive.

## Zero-downtime schema changes

Use **expand and contract**:

1. **Expand:** add the new shape.
2. Dual-write.
3. Backfill in small, resumable batches.
4. Switch reads.
5. **Contract:** remove the old shape.

Old and new code must both run at each step.

**How do you add a NOT NULL column to a billion-row table without downtime on PostgreSQL?**

```sql norun
-- 1. Metadata only, from version 11, if the default is not volatile
ALTER TABLE orders ADD COLUMN source VARCHAR(10);

-- 2. Backfill in small batches
UPDATE orders SET source = 'web' WHERE order_id BETWEEN 1 AND 10000;

-- 3. Add the constraint without checking old rows
ALTER TABLE orders ADD CONSTRAINT orders_source_nn CHECK (source IS NOT NULL) NOT VALID;

-- 4. Check old rows with a weaker lock
ALTER TABLE orders VALIDATE CONSTRAINT orders_source_nn;
```

**Walk me through renaming a heavily used column.** Never rename in place. Add the new column, dual-write, backfill, switch reads, stop writing the old one, then drop it.

**An `ALTER TABLE` took seconds in staging, but took production down.** Its exclusive lock waited behind one long transaction, and every later query queued behind the `ALTER` ([Chapter 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md)). Use `lock_timeout` with retries.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use email as a primary key | It changes, and it spreads | Surrogate key plus `UNIQUE` |
| Use UUIDv4 as a clustered key | Page splits, and wide indexes | Use UUIDv7 or `BIGINT` |
| Store comma-separated ids | No foreign keys, no indexes | Use a child table |
| Use EAV by default | No types or constraints | Columns or JSONB |
| Use `commentable_type` | No real foreign key | Exclusive arc, or a join table |
| Trust application validation | Scripts bypass it | Add constraints |
| Forget that soft delete collides with `UNIQUE` | Re-signup fails | Use a partial unique index |
| Rename a column in place | Old code breaks | Expand and contract |
| Leave foreign keys unindexed | Slow deletes and locks | Index them |

## Interview questions

**Q1. What is the difference between a natural key and a surrogate key?**

A natural key has business meaning, like an email. A surrogate key is a generated id with none. I use a surrogate as the primary key, and `UNIQUE` on the natural key, because natural keys change, and every foreign key would copy them.

**Q2. UUID or bigint for the primary key? What changes with UUIDv7?**

`BIGINT` is smaller, and inserts in order. UUIDs can be generated anywhere without a central sequence, and do not expose volume. UUIDv4 is random, so it splits pages on clustered tables. UUIDv7 is time-ordered, which fixes most of that.

**Q3. How do you enforce "only one active subscription per user" in the database?**

A partial unique index on `user_id` where `status = 'ACTIVE'` on PostgreSQL. On Oracle, a unique function-based index on `CASE WHEN status = 'ACTIVE' THEN user_id END`, since all-NULL keys are not stored.

**Q4. Why can't a CHECK constraint enforce a rule across rows? What would you use instead?**

A `CHECK` sees only one row. For a cross-row rule, I use a unique or exclusion constraint, or a transaction or trigger that locks properly.

**Q5. How would you map an inheritance hierarchy to relational tables?**

Single table with a type column is simple, but has many NULLs. Class table has a parent plus one table per subclass, which is clean but needs joins. Concrete table has one per subclass, and needs `UNION` across types. I pick by how much the subclasses differ.

**Q6. Customers want custom fields. Would you use EAV, JSONB or extra columns?**

Extra columns if they are few and shared. JSONB if they vary per customer and are rarely filtered. A real per-type table if they are constrained and queried. EAV only as a last resort, since it loses types and constraints.

**Q7. Comments can belong to a post, a photo or a video. How do you model that?**

Not with `commentable_type`, because no foreign key is possible. I use one nullable foreign key per parent, with a `CHECK` that exactly one is set, or a join table per parent.

**Q8. How do you add a NOT NULL column to a billion-row table without downtime?**

Add it as nullable, backfill in batches, add a `CHECK ... NOT VALID`, and then `VALIDATE`, all with `lock_timeout` and retries.

## Practice

**1. Design tables for a blog where posts have many tags and tags have many posts.**

<details>
<summary>Show solution</summary>

```text
posts      (post_id PK, title, body, created_at)
tags       (tag_id PK, name UNIQUE)
post_tags  (post_id FK, tag_id FK, PK (post_id, tag_id))
```

</details>

**2. How would you store a mutual friendship between users 5 and 9?**

<details>
<summary>Show solution</summary>

One row `(5, 9)`, with `CHECK (user_a < user_b)` and a primary key on the pair. To find user 9's friends, look on both sides, with `UNION ALL` or `OR`.

</details>

**3. A `users` table has soft delete. Write a PostgreSQL rule so that an email can be reused only after the old row is deleted.**

<details>
<summary>Show solution</summary>

```sql norun
CREATE UNIQUE INDEX users_email_live ON users (email) WHERE deleted_at IS NULL;
```

</details>

## Recap

- Use a surrogate primary key, with `UNIQUE` on the natural key.
- `BIGINT` on one database, UUIDv7 with many writers, and avoid UUIDv4 on clustered tables.
- Rules across rows need a unique or exclusion constraint.
- Avoid comma lists, EAV and polymorphic foreign keys.
- Keep status history in an append-only table.
- Soft delete costs more than it looks.
- Change schemas with expand and contract.

**Next:** [Chapter 26: Data warehouse design](26-data-warehouse-design.md)
