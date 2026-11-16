# 27. Design Case Studies: A Repeatable Method and Worked Schemas

**Level:** Advanced | **Interview priority:** Must know | **Before this:** [Chapter 25](25-schema-design-patterns.md)

> **In one line:** A design round is won by a repeatable method: start from the queries and the rules that must never break, and let them drive the tables, keys and indexes.

## What you will learn

- What a design round looks like
- A method that works for any prompt
- Three defenses against race conditions, reused everywhere
- Worked designs: e-commerce, movie booking, hotels, ride sharing, a bank ledger, a social feed, and multi-tenant SaaS
- How to answer "what changes at 10x?"

## What the round looks like

You get a broad prompt, such as e-commerce orders or hotel booking. You start from the three or four key queries, then tables, keys and indexes, and you write SQL against your own schema. The interviewer then pushes: concurrency, growth and edge cases.

## The method

1. **Restate** the requirements, and ask about scale.
2. **List the key queries,** and the **invariants**: rules that must never break, such as "a seat is sold once".
3. **List entities, relationships and cardinality.**
4. **Draft tables and keys.** Normalize first.
5. **Enforce the invariants** with constraints.
6. **Add indexes,** each one named after a query.
7. **Size it** in round numbers.
8. **Say what breaks at 10x.**

**Quick sizing.** Rows per day, row size, read-to-write ratio, retention. One minute of math decides whether partitioning matters at all.

```text
1 million orders a day x 3 lines x 100 bytes = 300 MB a day, about 110 GB a year
```

## Three defenses against races

A read-then-write is a race ([Chapter 18](../part-3-advanced-sql/18-advanced-dml.md)). These three defenses come up in every design.

| Defense | Example |
|---|---|
| **Conditional update** | `UPDATE ... WHERE stock_qty > 0`, then check the rows affected |
| **Unique constraint** | `UNIQUE (event_id, seat_id)` |
| **Row lock** | `SELECT ... FOR UPDATE`, then update |

## E-commerce orders

**How would you model orders for an e-commerce system?**

**Key queries:** a customer's order history, an order's detail, and stock for a product.

**Invariants:** stock never goes below zero, and an order's price never changes after the sale.

```text
customers (customer_id PK, name, email UNIQUE)
addresses (address_id PK, customer_id FK, line1, city, country)
products  (product_id PK, name, price, stock_qty CHECK >= 0)
orders    (order_id PK, customer_id FK, shipping_address, order_date, status)
order_items (order_id FK, product_id FK, quantity, unit_price, PK (order_id, product_id))
payments  (payment_id PK, order_id FK, amount, method, payment_date)
shipments (shipment_id PK, order_id FK, carrier, tracking_no, shipped_at)
```

**Design points:**

- `unit_price` and `shipping_address` are history ([Chapter 24](24-denormalization-and-trade-offs.md)), so they stay on the order.
- One row per payment, because order 1003 was paid twice.
- Index `orders (customer_id, order_date DESC)` for order history.

**Overselling.** Use a conditional update, and check the row count. The Blender has no stock:

```sql
UPDATE products
SET stock_qty = stock_qty - 1
WHERE product_id = 7 AND stock_qty > 0;

SELECT stock_qty FROM products WHERE product_id = 7;
```

```text output
UPDATE 0
 stock_qty
-----------
         0
(1 row)
```

The update changed no rows, so the application knows the sale failed. [Chapter 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) shows it with two live buyers.

### Variation: an online bookstore

Books and authors are M:N, with a `book_authors` junction table. ISBN is a natural key with `UNIQUE`. `UNIQUE (customer_id, book_id)` on reviews allows one review per customer. A stored average rating is a justified denormalization, because it is read on every page.

## Movie ticket booking

**Key queries:** seats for a showtime, and top movies by gross.

**Invariant:** a seat is sold once per showtime.

```sql
CREATE TABLE movies (
  movie_id  INTEGER PRIMARY KEY,
  title     VARCHAR(100) NOT NULL
);

CREATE TABLE showtimes (
  showtime_id  INTEGER PRIMARY KEY,
  movie_id     INTEGER NOT NULL REFERENCES movies (movie_id),
  starts_at    DATE NOT NULL,
  price        NUMERIC(8,2) NOT NULL
);

CREATE TABLE booked_seats (
  showtime_id  INTEGER NOT NULL REFERENCES showtimes (showtime_id),
  seat_no      VARCHAR(5) NOT NULL,
  customer_id  INTEGER NOT NULL,
  CONSTRAINT booked_uk UNIQUE (showtime_id, seat_no)
);

INSERT INTO movies VALUES (1, 'The Query');
INSERT INTO movies VALUES (2, 'Deadlock');
INSERT INTO showtimes VALUES (10, 1, DATE '2024-06-01', 12.00);
INSERT INTO showtimes VALUES (11, 2, DATE '2024-06-01', 15.00);
INSERT INTO booked_seats VALUES (10, 'A1', 1);
INSERT INTO booked_seats VALUES (10, 'A2', 2);
INSERT INTO booked_seats VALUES (11, 'B1', 3);
```

**How do you stop two people booking the same seat?** The unique constraint is the final guard.

```sql error=booked_uk
INSERT INTO booked_seats VALUES (10, 'A1', 9);
```

```text output
ERROR:  duplicate key value violates unique constraint "booked_uk"
DETAIL:  Key (showtime_id, seat_no)=(10, A1) already exists.
```

**Top movie this month by gross earnings:**

```sql
SELECT m.title, SUM(s.price) AS gross
FROM booked_seats b
JOIN showtimes s ON s.showtime_id = b.showtime_id
JOIN movies m ON m.movie_id = s.movie_id
WHERE s.starts_at >= DATE '2024-06-01'
  AND s.starts_at <  DATE '2024-07-01'
GROUP BY m.movie_id, m.title
ORDER BY gross DESC, m.title;
```

```text output
   title   | gross
-----------+-------
 The Query | 24.00
 Deadlock  | 15.00
(2 rows)
```

**Comparing the options:**

| Method | Good | Bad |
|---|---|---|
| `UNIQUE (showtime_id, seat_no)` | Simple, and it cannot be bypassed | The loser gets an error |
| Conditional update on a seat row | Clean status changes | Needs a row per seat |
| `SELECT FOR UPDATE` | Explicit | Locks are held longer |
| Optimistic version column | No locks held | Retries under load |

**Seat holds:** a status plus `expires_at`, so that an abandoned checkout frees the seat. A background job releases expired holds.

```sql
DROP TABLE booked_seats;
DROP TABLE showtimes;
DROP TABLE movies;
```

## Hotel reservation

**How do you guarantee a room is never double booked for overlapping dates?**

Use half-open dates: `check_out` is not a booked night.

| Approach | Good | Bad |
|---|---|---|
| One row per night, `UNIQUE (room_id, night)` | Portable, and allows nightly prices | More rows |
| Exclusion constraint | One row per stay | PostgreSQL only |
| Lock the room row, then check for overlap | Works anywhere | Serializes bookings per room |

**One row per night or one row per stay?** One per night is the simple portable answer, and it works on your Oracle 11g. Keep a `reservations` table for the stay, and `reservation_nights` for the rows that enforce the rule.

## Ride sharing

**How would you design a database to record rides between riders and drivers?**

```text
users     (user_id PK, name, phone UNIQUE)
drivers   (driver_id PK, user_id FK UNIQUE, license_no)
vehicles  (vehicle_id PK, driver_id FK, plate UNIQUE)
rides     (ride_id PK, rider_id FK, driver_id FK, status,
           requested_at, completed_at, pickup, dropoff, fare)
ride_events (ride_id FK, status, at)
payments  (payment_id PK, ride_id FK, amount)
ratings   (ride_id FK, from_user, to_user, stars)
```

**Invariant:** one active ride per driver. Use a partial unique index on `rides (driver_id) WHERE status = 'ACTIVE'`.

**Indexes:** `rides (rider_id, requested_at DESC)` for history, and `rides (driver_id, requested_at DESC)` for the driver's history.

**Bottlenecks:** driver location updates arrive constantly, so they should not be in the rides table. They belong in a fast store such as Redis, with geo search using PostGIS or geohash cells.

## Bank ledger

**Design a bank account ledger. How do you compute a balance, and how do you fix a wrong entry?**

**Double-entry:** every transaction has entries that net to zero. Entries are **immutable**. You fix a mistake with a **reversing entry**, not an update.

```sql
CREATE TABLE accounts (
  account_id  INTEGER PRIMARY KEY,
  owner       VARCHAR(50) NOT NULL
);

CREATE TABLE ledger_entries (
  entry_id    INTEGER PRIMARY KEY,
  txn_id      INTEGER NOT NULL,
  account_id  INTEGER NOT NULL REFERENCES accounts (account_id),
  amount      NUMERIC(14,2) NOT NULL
);

INSERT INTO accounts VALUES (1, 'Asha');
INSERT INTO accounts VALUES (2, 'Ben');

INSERT INTO ledger_entries VALUES (1, 100, 1, -250.00);
INSERT INTO ledger_entries VALUES (2, 100, 2,  250.00);
```

**The balance** is derived from entries:

```sql
SELECT a.owner, SUM(l.amount) AS balance
FROM accounts a
JOIN ledger_entries l ON l.account_id = a.account_id
GROUP BY a.account_id, a.owner
ORDER BY a.account_id;
```

```text output
 owner | balance
-------+---------
 Asha  | -250.00
 Ben   |  250.00
(2 rows)
```

**A check that the books balance:** every transaction must net to zero.

```sql
SELECT txn_id, SUM(amount) AS net
FROM ledger_entries
GROUP BY txn_id
HAVING SUM(amount) <> 0;
```

```text output
 txn_id | net
--------+-----
(0 rows)
```

For fast reads, keep a stored balance, updated in the **same transaction** as the entries. The ledger stays the source of truth. **Overdraft protection:** a conditional update, `WHERE balance >= amount`.

```sql
DROP TABLE ledger_entries;
DROP TABLE accounts;
```

### Idempotency

**What happens when a client retries a payment?** Without care, it is charged twice. Use an idempotency key.

```text
idempotency_keys (key PK, request_hash, response, created_at)
```

- Insert the key in the **same transaction** as the payment.
- The unique constraint makes a second attempt fail.
- On a repeat, return the stored response.
- The same key with a different payload is an error.

## Social feed

**How do you build a home timeline?**

| | Fan-out on write | Fan-out on read |
|---|---|---|
| How | Copy each post to every follower's timeline | Build the timeline when asked |
| Read | Fast | Slow |
| Write | Expensive for big accounts | Cheap |

**The hybrid:** fan out on write for normal users, and merge in celebrity posts at read time. The follower threshold is a tunable, not a fixed number.

**The math:** posts per day times average followers. One account with 50 million followers changes the answer.

## Chat messages

Partition by `(channel_id, time bucket)`, and order by a time-sortable id, because unbounded partitions and hot channels break reads ([Chapter 39](../part-6-architecture-and-scale/39-nosql-and-choosing-a-database.md)).

## Multi-tenant SaaS

| | Shared tables, `tenant_id` | Schema per tenant | Database per tenant |
|---|---|---|---|
| Isolation | Lowest | Medium | Highest |
| Cost per tenant | Lowest | Medium | Highest |
| Restore one tenant | Hard | Medium | Easy |
| Migrations | One | Many | Many |
| Noisy neighbors | Worst | Some | Least |

**Row-level security** puts the filter in the database, so that one missed `WHERE` cannot leak data ([Chapter 40](../part-6-architecture-and-scale/40-database-security.md)). Composite foreign keys that include `tenant_id` stop a row referencing another tenant's data.

## A fitness app, quickly

```text
users        (user_id PK, name, unit_pref)
exercises    (exercise_id PK, name, muscle_group)
workouts     (workout_id PK, user_id FK, started_at, local_zone)
workout_sets (workout_id FK, set_no, exercise_id FK, reps, weight_kg, PK (workout_id, set_no))
measurements (user_id FK, measured_on, weight_kg, PK (user_id, measured_on))
```

Store one unit, and convert on display. Store workout time as an instant plus the local zone, since "6 am" matters to the user.

## How would this change at 10x?

Say this in order:

1. Add the missing indexes, and fix slow queries.
2. For reads: replicas and caching.
3. For size: partitioning and archiving.
4. Only for write load: sharding, with the shard key chosen from the key queries.

## How do you decide which indexes a new schema needs?

From the key queries. Each index should name its query. Primary keys and unique constraints are indexed already. Index foreign keys. Then compose: equality columns first, then the range or sort.

## Self-review checklist

- [ ] Every table has a primary key.
- [ ] Natural keys have `UNIQUE`.
- [ ] Foreign keys are indexed.
- [ ] Money and time types are right.
- [ ] Status history is decided.
- [ ] Delete policy is decided.
- [ ] Every index names its query.
- [ ] Every invariant has a constraint or a stated method.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Start with tables | They miss what matters | Start with queries and invariants |
| Skip the invariants | Races appear in follow-ups | Name them first |
| Use read-then-write for stock | Overselling | Use a conditional update |
| Update ledger rows | History is lost | Use reversing entries |
| Skip idempotency | Double charges on retry | Use an idempotency key |
| Add indexes "just in case" | Writes slow down | Name the query |
| Jump to sharding at 10x | Huge cost for no reason | Climb the ladder |

## Interview questions

**Q1. Design a movie ticket booking schema. How do you stop two people booking the same seat?**

Movies, theaters, screens, seats, showtimes and bookings. The rule is enforced by `UNIQUE (showtime_id, seat_id)`, so only one insert can win, whatever the application does. For holds, I add a status and an expiry.

**Q2. Design a hotel reservation schema. How do you guarantee a room is never double booked? One row per night or per stay?**

One row per night with `UNIQUE (room_id, night)` is portable, and it allows nightly prices. On PostgreSQL, an exclusion constraint on a date range keeps one row per stay. Otherwise I lock the room row and check for overlap.

**Q3. Design a bank account ledger. How do you compute a balance, and how do you fix a wrong entry?**

Double-entry, with immutable entries that net to zero per transaction. The balance is the sum of entries, optionally stored and updated in the same transaction. A wrong entry is fixed by a reversing entry.

**Q4. Design a scalable idempotent ledger service. What happens when a client retries a payment?**

The client sends an idempotency key. I insert it in the same transaction as the payment, with a unique constraint. A retry hits the constraint, and I return the stored result. A different payload with the same key is an error.

**Q5. Design a multi-tenant SaaS schema. Compare the options.**

Shared tables with `tenant_id` are cheapest, but have the weakest isolation, so I add row-level security. Schema per tenant is in the middle. Database per tenant isolates best and makes per-tenant restore easy, but costs most. A common plan is shared by default, with a dedicated database for the largest tenants.

**Q6. How do you decide which indexes a new schema needs?**

From the key queries. Each index must name the query it serves, with equality columns first. I also index foreign keys.

**Q7. How would this design change at 10x the traffic?**

Fix queries and indexes first. Then replicas and caching for reads, partitioning and archiving for size, and sharding only for write load, with a shard key taken from the main queries.

## Practice

**1. Design a library system: books, copies, members and loans. What is the key invariant?**

<details>
<summary>Show solution</summary>

```text
books    (book_id PK, title, isbn UNIQUE)
copies   (copy_id PK, book_id FK)
members  (member_id PK, name)
loans    (loan_id PK, copy_id FK, member_id FK, loaned_at, returned_at)
```

The invariant is that a copy is on loan to one person at a time: a partial unique index on `loans (copy_id) WHERE returned_at IS NULL`.

</details>

**2. For the ride sharing design, write the index for "a rider's last 20 rides".**

<details>
<summary>Show solution</summary>

```sql norun
CREATE INDEX rides_rider_recent ON rides (rider_id, requested_at DESC);
```

It finds the rider, and the rows are already in order, so a top-N can stop early.

</details>

**3. A payment API times out, and the client retries. The first request actually succeeded. What protects you?**

<details>
<summary>Show solution</summary>

An idempotency key with a unique constraint, inserted in the same transaction as the payment. The retry finds the key and returns the stored result, instead of charging again.

</details>

## Recap

- Start from key queries and invariants, not tables.
- Three defenses: conditional update, unique constraint, row lock.
- Each index names a query.
- Ledger entries are immutable, and they net to zero.
- Idempotency keys make retries safe.
- At 10x: fix, then replicas and cache, then partition, and shard last.

**Next:** [Chapter 28: How data is stored](../part-5-internals-and-performance/28-how-data-is-stored.md)
