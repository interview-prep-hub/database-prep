# 26. Data Warehouse Design: OLTP vs OLAP, Star Schemas and History

**Level:** Intermediate | **Interview priority:** Should know | **Before this:** [Chapter 24](24-denormalization-and-trade-offs.md)

> **In one line:** A data warehouse stores history in a shape built for analysis, usually a fact table of events surrounded by dimensions.

## What you will learn

- OLTP vs OLAP from a design point of view
- ETL and ELT
- Facts, dimensions and grain
- Star and snowflake schemas
- Slowly changing dimensions
- Kimball, Inmon and Data Vault

## OLTP vs OLAP for design

[Chapter 1](../part-1-foundations/01-what-is-a-database.md) gave the comparison. For a schema, it means this: OLTP schemas are normalized for many small writes. OLAP schemas are denormalized for big reads.

**A data warehouse** is subject-oriented, integrated, time-variant and non-volatile: it is organized by business area, combines sources, keeps history, and is loaded rather than updated.

## ETL and ELT

**What is ETL, and how is it different from ELT?**

| | ETL | ELT |
|---|---|---|
| Order | Extract, transform, load | Extract, load, transform |
| Transforms run | In a separate tool | Inside the warehouse |
| Suits | Older systems | Cloud warehouses, with cheap compute |

Loads are **full** or **incremental**. Incremental loads use a watermark column, or change data capture.

## Facts and dimensions

**What is a fact table, and what is a dimension table?**

- A **fact** is a measured business event, such as a sale. Fact tables are tall.
- A **dimension** gives its context: who, what, where, when. Dimension tables are wide.
- A **measure** is a number in the fact table.

**Grain** is what one fact row stands for. State it first, in one sentence.

### Kimball's four steps

1. Choose the business process.
2. Declare the grain.
3. Identify the dimensions.
4. Identify the facts.

**Mixed grains cause double counting.** Order 1003 has one line and two payments, so joining payments to order lines counts the item twice ([Chapter 11](../part-2-sql-basics/11-joins.md)). Keep sales and payments in separate fact tables.

## Star schema

**What is a star schema?** One fact table, surrounded by flat dimensions.

```text
              dim_date
                 |
dim_customer -- fact_sales -- dim_product
```

```sql
CREATE TABLE dim_product AS
SELECT p.product_id AS product_key, p.product_name, c.category_name
FROM products p
JOIN categories c ON c.category_id = p.category_id;

CREATE TABLE fact_sales AS
SELECT o.order_id, i.product_id AS product_key,
       o.customer_id AS customer_key,
       TO_CHAR(o.order_date, 'YYYY-MM') AS sale_month,
       i.quantity, i.quantity * i.unit_price AS revenue
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
WHERE o.status <> 'CANCELLED';

SELECT d.category_name, SUM(f.revenue) AS revenue
FROM fact_sales f
JOIN dim_product d ON d.product_key = f.product_key
GROUP BY d.category_name
ORDER BY revenue DESC, d.category_name;
```

```text output
SELECT 10
SELECT 21
   category_name   | revenue
-------------------+---------
 Laptops           | 4996.00
 Phones            | 2745.00
 Kitchen           |  407.00
 Books             |  280.00
 Phone Accessories |  159.92
(5 rows)
```

```sql
DROP TABLE fact_sales;
DROP TABLE dim_product;
```

**Why surrogate keys in dimensions?** They survive source-key changes, let one customer have many history rows, allow an "Unknown" row, and keep joins small.

**The date dimension** has one row per day, with month, quarter, fiscal period, weekday and holiday flags. It beats date functions, because business calendars are not computable.

### Types of fact table

| Type | One row per | Example |
|---|---|---|
| **Transaction** | Event | A sale |
| **Periodic snapshot** | Period | A daily account balance |
| **Accumulating snapshot** | Process, updated as it moves | An order, with dates for each step |

### Measures

| Measure | Can be summed | Example |
|---|---|---|
| Additive | Across everything | Sales amount |
| Semi-additive | Not over time | Account balance |
| Non-additive | Never | A ratio |

### Star vs snowflake

**How does a star differ from a snowflake schema?** A snowflake normalizes dimensions into sub-tables. **Star is the default,** because it has fewer joins, and is simpler to query. Use a snowflake only for very large dimensions.

### Dimension varieties

| Type | Meaning |
|---|---|
| Degenerate | An order number kept on the fact |
| Junk | A small dimension of flags |
| Role-playing | One date dimension used as order date and ship date |
| Conformed | Shared across fact tables, so that reports line up |

## Slowly changing dimensions

**Explain SCD Type 1, 2 and 3.**

| Type | What it does | History |
|---|---|---|
| **Type 0** | Never change | Original only |
| **Type 1** | Overwrite | None |
| **Type 2** | Add a new row | Full |
| **Type 3** | Add a previous-value column | One step |

### SCD Type 2

Each version has a surrogate key, a natural key, `valid_from`, `valid_to` (half-open), and a current flag.

```sql
CREATE TABLE dim_customer (
  customer_key  INTEGER PRIMARY KEY,
  customer_id   INTEGER NOT NULL,
  city          VARCHAR(50) NOT NULL,
  valid_from    DATE NOT NULL,
  valid_to      DATE NOT NULL,
  is_current    VARCHAR(1) NOT NULL
);

INSERT INTO dim_customer VALUES (1, 1, 'London', DATE '2023-01-15', DATE '2024-03-01', 'N');
INSERT INTO dim_customer VALUES (2, 1, 'Leeds', DATE '2024-03-01', DATE '9999-12-31', 'Y');
```

**Using Type 2, how do you query what this customer looked like on March 15?** Use the natural key, plus a date range.

```sql
SELECT customer_id, city
FROM dim_customer
WHERE customer_id = 1
  AND valid_from <= DATE '2024-03-15'
  AND valid_to > DATE '2024-03-15';
```

```text output
 customer_id | city
-------------+-------
           1 | Leeds
(1 row)
```

```sql
DROP TABLE dim_customer;
```

A fact row stores the surrogate key of the version that was current at the time, so history reports correctly by itself.

## Harder modeling

**Many-to-many:** a bridge table with a weighting factor, so that shares add up to 1, and nothing is counted twice.

**One flight carries hundreds of seats, and one ticket spans many flights.** Model the grain as one row per ticket per flight segment. Then flight measures are never added at ticket level, and ticket prices are allocated to segments.

**Late-arriving facts.** A late fact must find the dimension row valid on its event date. A late dimension gets a placeholder row, updated later.

**The bus matrix** lists business processes as rows and dimensions as columns, and shows which conformed dimensions are shared.

## Kimball, Inmon and Data Vault

| Approach | Idea |
|---|---|
| **Kimball** | Bottom-up dimensional marts, linked by conformed dimensions |
| **Inmon** | Top-down, a normalized enterprise warehouse feeding marts |
| **Data Vault** | Hubs, links and satellites, for auditable history |

**One Big Table** on columnar engines has fewer joins and more storage, and attributes are harder to update.

## Worked prompt: a ride-sharing warehouse

**Business processes:** trips, payments and driver shifts.

**Grain:** `fact_trips` has one row per completed trip. `fact_payments` has one row per payment. `fact_shifts` has one row per driver shift.

**Dimensions:** date, rider, driver, vehicle and location (role-playing as pickup and dropoff).

**History:** driver city as SCD Type 2.

**Why not snowflake?** Fewer joins, and simpler queries. **Why surrogate keys?** To hold history. **How does this handle late data?** Late trips look up the dimension row valid at trip time.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Skip the grain | Double counting | State it first |
| Mix grains in one fact | Sums are wrong | Use separate fact tables |
| Use source keys in dimensions | History is impossible | Use surrogate keys |
| Sum a balance over time | Nonsense totals | Treat it as semi-additive |
| Overwrite when history matters | Old reports change | Use SCD Type 2 |
| Use `BETWEEN` on SCD ranges | Boundaries double count | Use half-open ranges |

## Interview questions

**Q1. What is a star schema, and how does it differ from a snowflake schema?**

A star has one fact table surrounded by flat dimensions. A snowflake normalizes the dimensions into sub-tables. I default to a star, because it has fewer joins.

**Q2. What is the difference between a transaction fact table, a periodic snapshot and an accumulating snapshot?**

A transaction fact has one row per event. A periodic snapshot has one row per period. An accumulating snapshot has one row per process, updated as it moves through steps.

**Q3. Explain SCD Type 1, 2 and 3.**

Type 1 overwrites, and keeps no history. Type 2 adds a row per version, with date ranges. Type 3 adds a previous-value column, for one step of history.

**Q4. What is the difference between Kimball, Inmon and Data Vault? Where do conformed dimensions fit?**

Kimball builds dimensional marts bottom-up, and conformed dimensions join them. Inmon builds a normalized warehouse top-down. Data Vault uses hubs, links and satellites for auditable history.

**Q5. Design a data warehouse schema for a ride-sharing service. State the grain first.**

The grain of the main fact is one row per completed trip. Dimensions are date, rider, driver, vehicle and location. Payments get their own fact, because they have a different grain.

## Practice

**1. What is the grain of `order_items`?**

<details>
<summary>Show solution</summary>

One row per product per order.

</details>

**2. Which SCD type fits a correction to a misspelled name? Which fits a customer's move to a new city?**

<details>
<summary>Show solution</summary>

Type 1 for the correction, because the old value was simply wrong. Type 2 for the move, because old sales should still show the old city.

</details>

**3. Is `stock_qty` additive?**

<details>
<summary>Show solution</summary>

It is semi-additive. You can sum it across products on one day, but not across days.

</details>

## Recap

- State the grain first.
- Facts are events, and dimensions are context.
- A star is the default.
- Keep different grains in different fact tables.
- SCD Type 2 adds a row per version, with half-open ranges.
- Conformed dimensions let reports line up.

**Next:** [Chapter 27: Design case studies](27-design-case-studies.md)
