# 32. Transactions and Isolation Levels

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 7](../part-2-sql-basics/07-dml-insert-update-delete.md)

> **In one line:** A transaction is a group of statements that succeed or fail as one unit, and isolation decides how much concurrent transactions can see of each other.

**About the demos:** the session demos in this chapter run on PostgreSQL. On Oracle, a transaction starts by itself, so leave out `BEGIN`.

## What you will learn

- ACID, and what each letter really means
- Dirty reads, non-repeatable reads, phantoms, lost updates and write skew, in live sessions
- Isolation levels, and how each engine really implements them
- Schedules and serializability, for theory rounds
- How to prevent lost updates and overselling

The two-session examples below were run live. Open two terminals, and run each block in the session it names.

## What is a transaction?

A **transaction** groups statements into one unit. Recording a payment and updating the order must happen together, or not at all.

```sql postgres
BEGIN;
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
VALUES (14, 1013, DATE '2024-05-25', 499.00, 'BANK');
UPDATE orders SET status = 'DELIVERED' WHERE order_id = 1013;
COMMIT;
```

| Command | Meaning |
|---|---|
| `BEGIN` or `START TRANSACTION` | Start one (Oracle starts one by itself) |
| `COMMIT` | Make the changes permanent |
| `ROLLBACK` | Undo them |
| `SAVEPOINT name` | Mark a spot to roll back to |

**Autocommit differs.** psql commits each statement unless you say `BEGIN`. SQL*Plus keeps a transaction open until you `COMMIT`.

**Does a DDL statement commit an open transaction?** On Oracle and MySQL, yes. PostgreSQL and SQL Server can roll back most DDL.

## ACID

| Letter | Meaning | Example | Comes from |
|---|---|---|---|
| **Atomicity** | All or nothing | A transfer never debits without crediting | Recovery |
| **Consistency** | Each transaction keeps the data valid | Total money stays the same | Your rules and constraints |
| **Isolation** | Concurrent transactions do not interfere | Two transfers act as if they ran in turn | Concurrency control |
| **Durability** | Committed data survives a crash | Power loss after `COMMIT` loses nothing | Recovery |

**Is the C in ACID the same as the C in CAP?** No. ACID consistency is application-defined correctness. CAP consistency means every read sees the latest write ([Chapter 38](../part-6-architecture-and-scale/38-sharding-and-distributed-databases.md)).

**Transaction states:** active, partially committed, committed, failed, aborted. Partially committed is not yet safe: the last statement ran, but the commit is not durable.

### After an error

- **PostgreSQL** marks the whole transaction aborted until `ROLLBACK`, or a rollback to a savepoint.
- **Oracle** undoes only the failed statement, and keeps the transaction open.

```sql postgres
BEGIN;
UPDATE employees SET salary = 1 WHERE emp_id = 12;
```

```sql postgres error=violates
INSERT INTO departments (dept_id, dept_name, location) VALUES (10, 'Copy', 'X');
```

```sql postgres error=aborted
SELECT COUNT(*) AS staff FROM employees;
```

```text output
ERROR:  current transaction is aborted, commands ignored until end of transaction block
```

```sql postgres
ROLLBACK;
```

## Concurrency anomalies

A **schedule** is the order in which the operations of concurrent transactions run. A **serial** schedule runs one transaction fully before the next. Concurrency exists for throughput, and the goal is a result equal to some serial order.

| Anomaly | What happens |
|---|---|
| **Dirty read** | You read a change that is not committed, and may be rolled back |
| **Non-repeatable read** | You read a row twice, and it changed in between |
| **Phantom** | You run a range query twice, and new rows appear |
| **Lost update** | Two writers overwrite each other |
| **Write skew** | Two transactions read the same data, and update different rows, breaking a rule |

### Non-repeatable read

At `READ COMMITTED`, each statement sees a fresh snapshot.

```sql postgres session=A
BEGIN;
SELECT salary FROM employees WHERE emp_id = 12;
```

```text output
BEGIN
 salary
--------
  30000
(1 row)
```

```sql postgres session=B
UPDATE employees SET salary = 31000 WHERE emp_id = 12;
```

```sql postgres session=A
SELECT salary FROM employees WHERE emp_id = 12;
COMMIT;
```

```text output
 salary
--------
  31000
(1 row)

COMMIT
```

The same query in one transaction gave two answers.

### Snapshot prevents it

At `REPEATABLE READ` on PostgreSQL, the whole transaction sees one snapshot.

```sql postgres session=A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT salary FROM employees WHERE emp_id = 12;
```

```text output
BEGIN
 salary
--------
  31000
(1 row)
```

```sql postgres session=B
UPDATE employees SET salary = 32000 WHERE emp_id = 12;
```

```sql postgres session=A
SELECT salary FROM employees WHERE emp_id = 12;
COMMIT;
```

```text output
 salary
--------
  31000
(1 row)

COMMIT
```

### Phantom read

```sql postgres session=A
BEGIN;
SELECT COUNT(*) AS staff FROM employees WHERE dept_id = 40;
```

```text output
BEGIN
 staff
-------
     2
(1 row)
```

```sql postgres session=B
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, hire_date, dept_id)
VALUES (13, 'Ria', 'Das', 'ria@shop.example', 'Accountant', 50000, DATE '2024-08-01', 40);
```

```sql postgres session=A
SELECT COUNT(*) AS staff FROM employees WHERE dept_id = 40;
COMMIT;
```

```text output
 staff
-------
     3
(1 row)

COMMIT
```

## Isolation levels

### The SQL standard

| Level | Dirty read | Non-repeatable read | Phantom |
|---|---|---|---|
| `READ UNCOMMITTED` | Possible | Possible | Possible |
| `READ COMMITTED` | No | Possible | Possible |
| `REPEATABLE READ` | No | No | Possible |
| `SERIALIZABLE` | No | No | No |

The standard's default is `SERIALIZABLE`, but PostgreSQL, Oracle and SQL Server default to **`READ COMMITTED`**, and MySQL InnoDB defaults to **`REPEATABLE READ`**.

```sql norun
-- PostgreSQL, for one transaction
BEGIN ISOLATION LEVEL SERIALIZABLE;

-- Oracle, as the first statement of a transaction
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- SQL Server and MySQL
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

### The standard vs reality

This table is what separates a strong answer from a textbook one.

| Engine | Reality |
|---|---|
| PostgreSQL | `READ UNCOMMITTED` runs as `READ COMMITTED`. `REPEATABLE READ` is snapshot isolation, and it prevents phantoms. `SERIALIZABLE` is SSI, and truly serializable |
| Oracle | Has `READ COMMITTED`, `SERIALIZABLE` and `READ ONLY`. No `READ UNCOMMITTED`. Its `SERIALIZABLE` is really snapshot isolation |
| MySQL InnoDB | `REPEATABLE READ` uses a snapshot for plain reads, but locking reads and DML see the latest rows |
| SQL Server | `READ COMMITTED` uses locks unless `READ_COMMITTED_SNAPSHOT` is on. `SNAPSHOT` is a separate level |

**Does Repeatable Read prevent phantoms and lost updates?**

| | Phantoms | Lost updates |
|---|---|---|
| PostgreSQL | Prevented | Prevented, with error 40001 |
| MySQL InnoDB | Prevented for snapshot reads and locking reads | **Not prevented** for read-then-write |

### Snapshot isolation

Reads come from a start snapshot. Two writers of one row cannot both win: the second fails. It avoids dirty reads, non-repeatable reads and lost updates. But it allows write skew.

```sql postgres session=A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT stock_qty FROM products WHERE product_id = 1;
```

```sql postgres session=B
UPDATE products SET stock_qty = 20 WHERE product_id = 1;
```

```sql postgres session=A error=concurrent
UPDATE products SET stock_qty = stock_qty - 1 WHERE product_id = 1;
```

```text output
ERROR:  could not serialize access due to concurrent update
```

```sql postgres session=A
ROLLBACK;
```

### Write skew

**Two on-call doctors both go off call at the same moment, and nobody is left on call.** The rule is "at least one on call". Each transaction checks it, and each changes a different row, so neither sees the other.

```sql postgres
CREATE TABLE doctors (name VARCHAR(20) PRIMARY KEY, on_call INTEGER NOT NULL);
INSERT INTO doctors VALUES ('Asha', 1);
INSERT INTO doctors VALUES ('Ben', 1);
```

```sql postgres session=A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) AS on_call_now FROM doctors WHERE on_call = 1;
```

```text output
BEGIN
 on_call_now
-------------
           2
(1 row)
```

```sql postgres session=B
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) AS on_call_now FROM doctors WHERE on_call = 1;
```

```text output
BEGIN
 on_call_now
-------------
           2
(1 row)
```

Both see 2, so each thinks it is safe to leave.

```sql postgres session=A
UPDATE doctors SET on_call = 0 WHERE name = 'Asha';
COMMIT;
```

```sql postgres session=B
UPDATE doctors SET on_call = 0 WHERE name = 'Ben';
COMMIT;
```

```sql postgres
SELECT COUNT(*) AS on_call_now FROM doctors WHERE on_call = 1;
```

```text output
 on_call_now
-------------
           0
(1 row)
```

Nobody is on call, and no error was raised. Now try it at `SERIALIZABLE`.

```sql postgres
UPDATE doctors SET on_call = 1;
```

```sql postgres session=A
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS on_call_now FROM doctors WHERE on_call = 1;
```

```sql postgres session=B
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS on_call_now FROM doctors WHERE on_call = 1;
```

```sql postgres session=A
UPDATE doctors SET on_call = 0 WHERE name = 'Asha';
COMMIT;
```

```sql postgres session=B error=serialize
UPDATE doctors SET on_call = 0 WHERE name = 'Ben';
COMMIT;
```

```text output
ERROR:  could not serialize access due to read/write dependencies among transactions
DETAIL:  Reason code: Canceled on identification as a pivot, during write.
HINT:  The transaction might succeed if retried.
ROLLBACK
```

```sql postgres session=B
ROLLBACK;
```

PostgreSQL's **SSI** (serializable snapshot isolation) detected the danger, and aborted one transaction with SQLSTATE `40001`. The failure may appear at the statement, or at `COMMIT`.

**Is Oracle's SERIALIZABLE truly serializable?** No. It is snapshot isolation. `ORA-08177` fires only on same-row conflicts, so this write skew commits silently on Oracle.

**Ways to prevent write skew:**

- Lock the rows you read (`SELECT ... FOR UPDATE`).
- Materialize the conflict: make both transactions update one shared row.
- Add a unique or exclusion constraint.
- Use `SERIALIZABLE` with retry, except on Oracle.

```sql postgres
DROP TABLE doctors;
```

## Preventing lost updates

**What is a lost update, and what are three ways to prevent it?** Two transactions read a value, change it, and write it back, so one change vanishes ([Chapter 24](../part-4-database-design/24-denormalization-and-trade-offs.md) showed this live).

| Fix | How |
|---|---|
| Atomic update | `UPDATE accounts SET balance = balance + 100` |
| Pessimistic lock | `SELECT ... FOR UPDATE`, then update |
| Optimistic version column | `UPDATE ... SET version = version + 1 WHERE version = ?`. Zero rows means a conflict |

**Two joint holders transfer money at the same time, and both read the same balance. The receiver is credited twice, and the sender debited once.** That is a lost update, so isolation is certainly violated, and so is consistency. Each transaction finished, and was durable, so atomicity and durability held.

### Selling the last item

**How would you stop two buyers from purchasing the last item in stock?** Use a conditional `UPDATE`, and check the rows affected. Do not read, check and write in application code.

```sql postgres
UPDATE products SET stock_qty = 1 WHERE product_id = 10;
```

```sql postgres session=A
BEGIN;
UPDATE products SET stock_qty = stock_qty - 1
WHERE product_id = 10 AND stock_qty > 0;
```

```text output
BEGIN
UPDATE 1
```

The second buyer waits on the row lock.

```sql postgres session=B blocks
UPDATE products SET stock_qty = stock_qty - 1
WHERE product_id = 10 AND stock_qty > 0;
```

```text output
UPDATE 0
```

```sql postgres session=A
COMMIT;
```

```sql postgres session=B
SELECT stock_qty FROM products WHERE product_id = 10;
```

```text output
 stock_qty
-----------
         0
(1 row)
```

The second buyer's `UPDATE` waited, then re-checked the `WHERE` on the new row, and changed **0 rows**. So stock never went below zero, and the application knows that buyer did not get the item.

## Choosing a level

Keep `READ COMMITTED` by default, and protect hot spots with atomic statements or explicit locks. Use `SERIALIZABLE` with retry for rules that span several rows, except on Oracle.

**Retry design.** Retry the **whole** transaction, not just the failed statement, with a bounded number of attempts and random delay (jitter). Retry on `40001` and `40P01` (PostgreSQL), `ORA-08177` and `ORA-00060` (Oracle), `1213` (MySQL), and `1205` and `3960` (SQL Server).

## Schedules and serializability

Theory rounds and GATE-style exams ask this part.

### Conflicts

Two operations **conflict** when they come from different transactions, touch the same item, and at least one is a write. Two reads never conflict.

### Conflict serializability

Draw a **precedence graph**: add an edge `Ti -> Tj` when Ti's conflicting operation comes first. **A schedule is conflict serializable if and only if the graph has no cycle.** A topological sort gives the equivalent serial order.

```text
Schedule A:  R1(X) R2(X) W1(X) W2(X)

  R1(X) before W2(X):  T1 -> T2
  R2(X) before W1(X):  T2 -> T1
  Cycle, so NOT conflict serializable

Schedule B:  R1(X) W1(X) R2(X) W2(X) R1(Y) W1(Y) R2(Y)

  Every conflict goes T1 -> T2
  No cycle, so conflict serializable, equivalent to T1 then T2
```

**Counting.** n transactions have n! serial schedules. Two transactions with n and m operations have (n+m)! / (n! m!) interleavings.

### View serializability

Two schedules are view equivalent if they have the same initial reads, the same reads-from, and the same final writes. Testing it is NP-complete, which is why real systems do not enforce it.

Every view-serializable schedule that is not conflict serializable has a **blind write**, a write with no earlier read. `R1(X) W2(X) W1(X) W3(X)` is one.

```text
serial  is inside  conflict serializable  is inside  view serializable  is inside  all schedules
```

### Recoverability

| Schedule type | Rule |
|---|---|
| **Recoverable** | A transaction commits only after those it read from |
| **Cascadeless** | Read only committed data |
| **Strict** | No read or overwrite of uncommitted data |

Strict is inside cascadeless, which is inside recoverable.

**Can a conflict serializable schedule be non-recoverable?** Yes. They are separate axes.

```text
T1: W(X)                     ABORT
T2:        R(X)   COMMIT

Conflict serializable (T1 -> T2), but T2 committed a value that T1 then undid.
```

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Quote the standard table as the truth | Engines differ | Give the engine's behavior |
| Say Oracle `SERIALIZABLE` is serializable | Write skew still commits | Call it snapshot isolation |
| Say Repeatable Read prevents phantoms everywhere | The standard does not require it | Answer per engine |
| Read, change and write in application code | A lost update | Use an atomic `UPDATE` |
| Retry only the failed statement | The snapshot is stale | Retry the whole transaction |
| Keep a transaction open across a user action | Locks and old versions pile up | Keep transactions short |
| Assume MVCC stops all conflicts | Write skew remains | Use `SERIALIZABLE`, or lock |

## Interview questions

**Q1. What are the ACID properties? Is the C in ACID the same as the C in CAP?**

Atomicity means all or nothing. Consistency means each transaction keeps the data valid. Isolation means concurrent transactions do not interfere. Durability means committed data survives a crash. The C in CAP is different: it means every read sees the latest write.

**Q2. Which isolation level does your database use by default, and how do you change it for one transaction?**

PostgreSQL, Oracle and SQL Server default to `READ COMMITTED`, and MySQL InnoDB to `REPEATABLE READ`. On PostgreSQL I write `BEGIN ISOLATION LEVEL ...`, and on Oracle `SET TRANSACTION ISOLATION LEVEL ...` as the first statement.

**Q3. Explain the isolation levels and which anomalies each one allows.**

`READ UNCOMMITTED` allows dirty reads. `READ COMMITTED` stops them, but allows non-repeatable reads and phantoms. `REPEATABLE READ` stops non-repeatable reads, and the standard still allows phantoms. `SERIALIZABLE` stops them all. Real engines differ: PostgreSQL's `REPEATABLE READ` also stops phantoms, and it is snapshot isolation.

**Q4. Does Repeatable Read prevent phantoms? Does it prevent lost updates? Answer for PostgreSQL and for MySQL.**

On PostgreSQL, it prevents both: a concurrent update raises error 40001. On MySQL, it prevents phantoms for snapshot reads and locking reads, but a read-then-write lost update can still happen, because InnoDB does not abort on concurrent update.

**Q5. What is snapshot isolation? Show a write skew it allows. Is Oracle's SERIALIZABLE truly serializable?**

Each transaction reads from a snapshot taken at its start, and two writers of the same row conflict. Write skew slips through: two doctors each see two on call, and each goes off call by updating a different row, leaving nobody. Oracle's `SERIALIZABLE` is snapshot isolation, so that commits there. PostgreSQL's `SERIALIZABLE` uses SSI, and aborts one of them.

**Q6. What is a lost update, and what are three ways to prevent it?**

Two transactions read a value and write back a changed copy, so one change is lost. Use an atomic `UPDATE` with arithmetic, a pessimistic `SELECT ... FOR UPDATE`, or an optimistic version column.

**Q7. How would you stop two buyers from purchasing the last item in stock?**

`UPDATE products SET stock = stock - 1 WHERE id = ? AND stock > 0`, then check the rows affected. The row lock serializes the buyers, and the second one's `WHERE` is re-checked on the new value, so it changes 0 rows.

**Q8. Your transaction failed with a serialization error. What should the application do?**

Roll back, and retry the whole transaction from the start, with a limited number of attempts and a random delay. It should not retry just the last statement, or ignore the error.

**Q9. When do two operations conflict? How do you test whether a schedule is conflict serializable?**

They conflict when they are from different transactions, on the same item, and at least one writes. I draw a precedence graph, with an edge from the transaction whose operation comes first. No cycle means conflict serializable, and a topological sort gives the serial order.

**Q10. What is the difference between conflict and view serializability?**

Conflict serializability is testable with a graph. View serializability is broader, and allows some blind writes, but testing it is NP-complete, so real systems do not enforce it.

**Q11. Can a conflict serializable schedule be non-recoverable?**

Yes. T2 reads T1's uncommitted write and commits, and then T1 aborts. The order is fine for serializability, but T2 committed a value that never existed.

## Practice

**1. Is `R1(A) R2(B) W1(B) W2(A)` conflict serializable?**

<details>
<summary>Show solution</summary>

```text
R1(A) before W2(A):  T1 -> T2
R2(B) before W1(B):  T2 -> T1
Cycle, so no.
```

</details>

**2. Which anomaly is this: a report adds up all accounts twice in one transaction, and the totals differ, because a new account was added in between?**

<details>
<summary>Show solution</summary>

A phantom: new rows appeared in a repeated range query.

</details>

**3. Write an optimistic update for `products`, assuming a `version` column.**

<details>
<summary>Show solution</summary>

```sql norun
UPDATE products
SET price = 79.00, version = version + 1
WHERE product_id = 6 AND version = 3;
```

If 0 rows changed, someone else changed the row first. Reload it, and try again.

</details>

**4. How many interleavings do two transactions of 2 and 3 operations have?**

<details>
<summary>Show solution</summary>

`5! / (2! 3!) = 120 / 12 = 10`.

</details>

## Recap

- ACID: atomicity, consistency, isolation, durability. ACID's C is not CAP's C.
- PostgreSQL, Oracle and SQL Server default to `READ COMMITTED`, and MySQL to `REPEATABLE READ`.
- PostgreSQL `REPEATABLE READ` is snapshot isolation.
- Oracle `SERIALIZABLE` is snapshot isolation too, so write skew can commit.
- Lost updates: use an atomic `UPDATE`, `FOR UPDATE`, or a version column.
- Overselling: a conditional `UPDATE`, and check the rows affected.
- Retry the whole transaction.
- A schedule is conflict serializable if its precedence graph has no cycle.

**Next:** [Chapter 33: Locks, deadlocks and MVCC](33-locks-deadlocks-and-mvcc.md)
