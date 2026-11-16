# 54. Real-World PL/SQL Programs: Putting It All Together

**Level:** Advanced | **Interview priority:** Should know | **Before this:** The rest of Part 7

> **In one line:** These are the programs interviewers ask you to write, combining everything in this part.

## What you will learn

- Table APIs vs transaction APIs
- A complete `place_order` procedure that cannot oversell
- Error logging that survives a rollback
- Batch updates with partial failures
- How to do work after commit
- Whiteboard programs: reverse, factorial, Fibonacci, prime and palindrome

## Where should business logic live?

**Should client applications touch tables directly, or only go through a PL/SQL API?**

**Thick database** (or SmartDB) means clients reach tables only through a PL/SQL API. Proponents like the single enforcement point, and the security. Critics point to harder scaling, testing and hiring.

Either way, know the difference:

| | Table API | Transaction API |
|---|---|---|
| Wraps | One table's CRUD | One business action |
| Example | `orders_api.insert_row` | `order_api.place_order` |

**Prefer transaction APIs.**

## Placing an order

**Write a procedure that places an order and reduces stock, so that two sessions cannot both sell the last unit.**

```sql oracle
CREATE SEQUENCE order_seq START WITH 2000;

CREATE OR REPLACE PACKAGE order_api IS
  PROCEDURE place_order (
    p_customer_id IN  customers.customer_id%TYPE,
    p_product_id  IN  products.product_id%TYPE,
    p_quantity    IN  order_items.quantity%TYPE,
    p_order_id    OUT orders.order_id%TYPE
  );
END order_api;
/

CREATE OR REPLACE PACKAGE BODY order_api IS

  PROCEDURE place_order (
    p_customer_id IN  customers.customer_id%TYPE,
    p_product_id  IN  products.product_id%TYPE,
    p_quantity    IN  order_items.quantity%TYPE,
    p_order_id    OUT orders.order_id%TYPE
  ) IS
    v_exists NUMBER;
    v_price  products.price%TYPE;
    v_stock  products.stock_qty%TYPE;
  BEGIN
    SELECT COUNT(*) INTO v_exists
    FROM customers
    WHERE customer_id = p_customer_id;

    IF v_exists = 0 THEN
      RAISE_APPLICATION_ERROR(-20101, 'Unknown customer');
    END IF;

    -- The lock makes concurrent buyers of this product wait their turn.
    SELECT price, stock_qty
    INTO v_price, v_stock
    FROM products
    WHERE product_id = p_product_id
    FOR UPDATE;

    IF v_stock < p_quantity THEN
      RAISE_APPLICATION_ERROR(-20102, 'Not enough stock');
    END IF;

    p_order_id := order_seq.NEXTVAL;

    INSERT INTO orders (order_id, customer_id, order_date, status)
    VALUES (p_order_id, p_customer_id, SYSDATE, 'PENDING');

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (p_order_id, p_product_id, p_quantity, v_price);

    UPDATE products
    SET stock_qty = stock_qty - p_quantity
    WHERE product_id = p_product_id;
  END place_order;

END order_api;
/
```

**Notes:**

- `unit_price` is copied, because it is history.
- There is no `COMMIT`. The caller owns the transaction.
- `NO_DATA_FOUND` is left to reach the caller for an unknown product.

**Why the lock matters.** Without it, two sessions can both read a stock of 1, and both sell. `SELECT ... FOR UPDATE` serializes buyers of one product.

**The atomic alternative** needs no separate check:

```sql oracle
DECLARE
  v_qty NUMBER := 1;
BEGIN
  UPDATE products
  SET stock_qty = stock_qty - v_qty
  WHERE product_id = 7 AND stock_qty >= v_qty;

  IF SQL%ROWCOUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Not enough stock');
  END IF;

  ROLLBACK;
END;
/
```

```text output
Not enough stock
```

Prefer this when you do not need the row's values first.

### A cross-row rule

**At most 3 open orders per customer.** A plain count races, because two sessions cannot see each other's uncommitted orders. So lock the parent row first:

```sql oracle
DECLARE
  v_customer_id customers.customer_id%TYPE := 1;
  v_dummy       NUMBER;
  v_open        NUMBER;
BEGIN
  SELECT 1 INTO v_dummy
  FROM customers
  WHERE customer_id = v_customer_id
  FOR UPDATE;

  SELECT COUNT(*) INTO v_open
  FROM orders
  WHERE customer_id = v_customer_id
    AND status = 'PENDING';

  IF v_open >= 3 THEN
    RAISE_APPLICATION_ERROR(-20103, 'Too many open orders');
  END IF;

  DBMS_OUTPUT.PUT_LINE('Allowed, open orders: ' || v_open);
  ROLLBACK;
END;
/
```

```text output
Allowed, open orders: 1
```

## Balances and payments

Order 1003 was paid in two payments, and order 1013 is only partly paid.

```sql oracle
CREATE OR REPLACE FUNCTION order_balance (
  p_order_id IN orders.order_id%TYPE
) RETURN NUMBER IS
  v_due  NUMBER;
  v_paid NUMBER;
BEGIN
  SELECT NVL(SUM(quantity * unit_price), 0) INTO v_due
  FROM order_items
  WHERE order_id = p_order_id;

  SELECT NVL(SUM(amount), 0) INTO v_paid
  FROM payments
  WHERE order_id = p_order_id;

  RETURN v_due - v_paid;
END order_balance;
/

SELECT order_id, order_balance(order_id) AS balance
FROM orders
WHERE order_id IN (1003, 1013)
ORDER BY order_id;
```

```text output
  ORDER_ID    BALANCE
---------- ----------
      1003          0
      1013        499
```

## Error logging that survives a rollback

**How would you build error logging that survives a rollback?** With an autonomous procedure, called at top-level entry points.

```sql oracle
CREATE TABLE error_log (
  logged_at  TIMESTAMP DEFAULT SYSTIMESTAMP,
  err_code   NUMBER,
  err_msg    VARCHAR2(4000),
  backtrace  VARCHAR2(4000),
  who        VARCHAR2(128)
);

CREATE OR REPLACE PROCEDURE log_exception IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_code NUMBER := SQLCODE;
  v_msg  VARCHAR2(4000) := SQLERRM;
BEGIN
  INSERT INTO error_log (err_code, err_msg, backtrace, who)
  VALUES (v_code, v_msg, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, USER);
  COMMIT;
END log_exception;
/

BEGIN
  UPDATE employees SET salary = -1 WHERE emp_id = 1;   -- fails the CHECK
EXCEPTION
  WHEN OTHERS THEN
    log_exception;
    RAISE;
END;
/
```

The handler logs, and then re-raises, so that the caller still sees the failure, and the log row stays.

## A batch update with partial failures

Fetch with `LIMIT`, use `FORALL SAVE EXCEPTIONS`, report per row, and commit per batch.

```sql oracle
DECLARE
  CURSOR c IS SELECT product_id FROM products ORDER BY product_id;

  TYPE t_ids IS TABLE OF products.product_id%TYPE;
  v_ids t_ids;

  e_bulk EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_bulk, -24381);
BEGIN
  OPEN c;

  LOOP
    FETCH c BULK COLLECT INTO v_ids LIMIT 100;
    EXIT WHEN v_ids.COUNT = 0;

    BEGIN
      FORALL i IN 1..v_ids.COUNT SAVE EXCEPTIONS
        UPDATE products
        SET stock_qty = stock_qty - 1
        WHERE product_id = v_ids(i);
    EXCEPTION
      WHEN e_bulk THEN
        FOR j IN 1..SQL%BULK_EXCEPTIONS.COUNT LOOP
          DBMS_OUTPUT.PUT_LINE('Failed product ' ||
            v_ids(SQL%BULK_EXCEPTIONS(j).ERROR_INDEX));
        END LOOP;
    END;
  END LOOP;

  CLOSE c;
  ROLLBACK;   -- a real batch would COMMIT here
END;
/
```

```text output
Failed product 7
```

## An audit trail

[Chapter 48](48-triggers.md) built one. The choice is whether the audit row should share the transaction, or survive it. Share it for "what really changed". Make it autonomous for "what was attempted".

## A customer statement

Return it to a client with a `SYS_REFCURSOR`:

```sql oracle
CREATE OR REPLACE PROCEDURE customer_statement (
  p_customer_id IN  customers.customer_id%TYPE,
  p_rows        OUT SYS_REFCURSOR
) IS
BEGIN
  OPEN p_rows FOR
    SELECT o.order_id, o.order_date, o.status
    FROM orders o
    WHERE o.customer_id = p_customer_id
    ORDER BY o.order_date;
END customer_statement;
/
```

The same report as a pipelined function is in [Chapter 52](52-advanced-plsql.md).

## A nightly job

```sql oracle
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'CANCEL_OLD_PENDING',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN
                          UPDATE orders SET status = ''CANCELLED''
                          WHERE status = ''PENDING''
                            AND order_date < SYSDATE - 30;
                          COMMIT;
                        END;',
    repeat_interval => 'FREQ=DAILY;BYHOUR=1',
    enabled         => TRUE);
END;
/
```

## Work after commit

**How would you send an email or call a web service after a transaction commits, without calling it from a trigger?** Insert a row in an **outbox** table in the same transaction, and let a job read it after commit. If the transaction rolls back, the row vanishes, so no email goes out.

```sql oracle
CREATE TABLE outbox (
  outbox_id   NUMBER PRIMARY KEY,
  event_type  VARCHAR2(30) NOT NULL,
  payload     VARCHAR2(4000),
  sent_at     TIMESTAMP
);
```

A scheduler job reads unsent rows with `FOR UPDATE SKIP LOCKED`, sends each one, and sets `sent_at`. Sending must be idempotent, because a crash can repeat a send. **Transactional Event Queues** give the same guarantee, built in.

## Whiteboard programs

### Reverse a string

**Without using a built-in reverse:**

```sql oracle
DECLARE
  v_text VARCHAR2(30) := 'ORACLE';
  v_out  VARCHAR2(30);
BEGIN
  FOR i IN REVERSE 1..LENGTH(v_text) LOOP
    v_out := v_out || SUBSTR(v_text, i, 1);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(v_out);
END;
/
```

```text output
ELCARO
```

### Palindrome check

```sql oracle
DECLARE
  v_text VARCHAR2(30) := 'LEVEL';
  v_rev  VARCHAR2(30);
BEGIN
  FOR i IN REVERSE 1..LENGTH(v_text) LOOP
    v_rev := v_rev || SUBSTR(v_text, i, 1);
  END LOOP;

  IF v_text = v_rev THEN
    DBMS_OUTPUT.PUT_LINE('Palindrome');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Not a palindrome');
  END IF;
END;
/
```

```text output
Palindrome
```

### Factorial

```sql oracle
DECLARE
  v_result NUMBER := 1;
BEGIN
  FOR i IN 2..5 LOOP
    v_result := v_result * i;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(v_result);
END;
/
```

```text output
120
```

### Fibonacci

```sql oracle
DECLARE
  v_a NUMBER := 0;
  v_b NUMBER := 1;
  v_c NUMBER;
BEGIN
  FOR i IN 1..7 LOOP
    DBMS_OUTPUT.PUT_LINE(v_a);
    v_c := v_a + v_b;
    v_a := v_b;
    v_b := v_c;
  END LOOP;
END;
/
```

```text output
0
1
1
2
3
5
8
```

### Prime check

```sql oracle
DECLARE
  v_n     PLS_INTEGER := 29;
  v_prime BOOLEAN := v_n > 1;
  v_i     PLS_INTEGER := 2;
BEGIN
  WHILE v_i * v_i <= v_n LOOP
    IF MOD(v_n, v_i) = 0 THEN
      v_prime := FALSE;
      EXIT;
    END IF;
    v_i := v_i + 1;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_prime THEN 'Prime' ELSE 'Not prime' END);
END;
/
```

```text output
Prime
```

## Review checklist

Before you finish any PL/SQL answer, check these:

- [ ] Types anchored with `%TYPE`
- [ ] Every value bound
- [ ] Errors re-raised, not swallowed
- [ ] No stray `COMMIT`
- [ ] A set-based option considered
- [ ] Cursors closed on every path
- [ ] Locks taken before check-then-update

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Check stock, then update | Two sessions oversell | Lock, or use an atomic `UPDATE` |
| `COMMIT` inside a procedure | The caller cannot combine work | Let the caller commit |
| Log with a plain `INSERT` | The log rolls back too | Use an autonomous procedure |
| Log and swallow the error | The caller sees success | Re-raise |
| Send mail from a trigger | It cannot roll back | Use an outbox |
| Count then insert for a limit | It races | Lock the parent row |

## Interview questions

**Q1. Should client applications touch tables directly or only go through a PL/SQL API?**

A PL/SQL API gives one enforcement point, and tight security. Direct access is simpler for teams that keep logic in the application. I would use transaction APIs where several applications share the data, or where the rules are critical.

**Q2. Write a procedure that places an order and reduces stock so that two sessions cannot both sell the last unit.**

Lock the product row with `SELECT ... FOR UPDATE`, check the stock, insert the order and lines, and update the stock, or use one atomic `UPDATE ... WHERE stock_qty >= :qty` and check `SQL%ROWCOUNT`. I leave the `COMMIT` to the caller.

**Q3. How would you build error logging that survives a rollback?**

An autonomous procedure that inserts into a log table and commits, called from a top-level handler, which then re-raises.

**Q4. How would you send an email or call a web service after a transaction commits, without calling it from a trigger?**

Write a row to an outbox table in the same transaction. A background job sends it after commit. A rollback removes the row, so nothing is sent.

## Practice

**1. Write a block that counts the vowels in a string.**

<details>
<summary>Show solution</summary>

```sql oracle
DECLARE
  v_text  VARCHAR2(30) := 'DATABASE';
  v_count PLS_INTEGER := 0;
BEGIN
  FOR i IN 1..LENGTH(v_text) LOOP
    IF INSTR('AEIOU', SUBSTR(v_text, i, 1)) > 0 THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(v_count);
END;
/
```

```text output
4
```

</details>

**2. Write `post_payment(p_order_id, p_amount)`. It should reject more than the balance.**

<details>
<summary>Show solution</summary>

```sql oracle
CREATE SEQUENCE payment_seq START WITH 100;

CREATE OR REPLACE PROCEDURE post_payment (
  p_order_id IN payments.order_id%TYPE,
  p_amount   IN payments.amount%TYPE
) IS
  v_lock NUMBER;
BEGIN
  SELECT order_id INTO v_lock
  FROM orders
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF p_amount > order_balance(p_order_id) THEN
    RAISE_APPLICATION_ERROR(-20104, 'Payment exceeds balance');
  END IF;

  INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (payment_seq.NEXTVAL, p_order_id, SYSDATE, p_amount, 'BANK');
END post_payment;
/
```

Locking the order row stops two payments racing past the balance check.

</details>

## Recap

- Prefer transaction APIs over table APIs.
- Lock, or use an atomic `UPDATE`, to stop overselling.
- Leave `COMMIT` to the top-level caller.
- Autonomous logging survives rollback. Always re-raise.
- Use an outbox for work after commit.
- Practice reverse, factorial, Fibonacci, prime and palindrome on paper.

**Next:** [Chapter 55: SQL query problems](../part-8-interview-practice/55-sql-query-problems.md)
