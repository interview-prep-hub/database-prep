# The sample database

Almost every example in this book uses this one small database, so you only have to learn it once.
It is a small online shop: staff, customers, products, orders and payments. It has eight tables and
few enough rows that you can check any query result by eye.

To install it, see [the setup guide](README.md).

## How the tables connect

Read "1" and "many" as: one department has many employees, one customer has many orders, and so on.

```text
                 +-------------+
                 | departments |
                 +-------------+
                        | 1
                        |
                        | many
                 +-------------+ <---+
                 |  employees  |     | manager_id
                 +-------------+ ----+ (an employee's manager is also an employee)
                        | 1
                        |
                        | many (emp_id, NULL for website orders)
+-----------+ 1  many +--------+ 1  many +----------+
| customers |---------| orders |---------| payments |
+-----------+         +--------+         +----------+
                          | 1
                          |
                          | many
                   +-------------+ many  1 +----------+ many  1 +------------+ <---+ parent_id
                   | order_items |---------| products |---------| categories |     | (a category can
                   +-------------+         +----------+         +------------+ ----+ sit inside another)
```

## Rows worth remembering

These rows are here on purpose. Each one exists to show a behavior that interviewers like to test.

| Row | Why it is interesting |
|---|---|
| Department 50, Legal | Has no employees. It disappears from an inner join and shows up in a left join. |
| Employee 12, Tom Baker | `dept_id` is NULL: not in any department yet. |
| Employee 1, Sara Khan | `manager_id` is NULL: the top of the tree. |
| Employee 7, Mei Chen | `commission` is 0, while most others have NULL. 0 and NULL are different things. |
| Salaries 95000, 82000 and 60000 | Each is shared by two people. This shows the difference between RANK, DENSE_RANK and ROW_NUMBER. |
| Sara > Priya > Arjun > Emma | A reporting chain four levels deep, for recursive queries. |
| Customers 7 and 8, Hana and Ivan | Neither has placed an order, for "find the rows with no match". |
| Customer 8, Ivan Novak | `email`, `city` and `country` are all NULL. |
| Product 10, Desk Lamp | Has never been ordered. |
| Product 7, Blender | `stock_qty` is 0. It is out of stock. |
| Order 1003 | Paid in two payments. A careless join counts this order twice. |
| Order 1006 | CANCELLED, and has no payment. |
| Order 1010 | Phone X was sold at 749.00, while its list price is 799.00. This is why `order_items` stores `unit_price`. |
| Order 1013 | Only partly paid: 500.00 of 999.00. |
| Orders 1014 and 1016 | `emp_id` is NULL, because they were placed on the website. |
| Orders 1014, 1015 and 1016 | PENDING, with no payment yet. |

## The tables and their rows

### departments

One department per row. Legal (50) has no employees, on purpose.

| dept_id | dept_name | location |
|---|---|---|
| 10 | Executive | New York |
| 20 | Sales | London |
| 30 | Engineering | Toronto |
| 40 | Finance | Dubai |
| 50 | Legal | Singapore |

### employees

Every employee, with `manager_id` pointing at another employee in the same table.

| emp_id | first_name | last_name | email | job_title | salary | commission | hire_date | manager_id | dept_id |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Sara | Khan | sara.khan@shop.example | CEO | 180000 | NULL | 2015-01-12 | NULL | 10 |
| 2 | James | Wilson | james.wilson@shop.example | Sales Manager | 95000 | 5000 | 2016-03-01 | 1 | 20 |
| 3 | Priya | Sharma | priya.sharma@shop.example | Engineering Manager | 120000 | NULL | 2016-06-15 | 1 | 30 |
| 4 | Omar | Farooq | omar.farooq@shop.example | Finance Manager | 95000 | NULL | 2017-02-20 | 1 | 40 |
| 5 | Lena | Fischer | lena.fischer@shop.example | Sales Rep | 60000 | 8000 | 2018-09-10 | 2 | 20 |
| 6 | Diego | Ramos | diego.ramos@shop.example | Sales Rep | 60000 | 6500 | 2019-11-04 | 2 | 20 |
| 7 | Mei | Chen | mei.chen@shop.example | Sales Rep | 52000 | 0 | 2022-01-17 | 2 | 20 |
| 8 | Arjun | Patel | arjun.patel@shop.example | Senior Developer | 105000 | NULL | 2018-04-23 | 3 | 30 |
| 9 | Emma | Brown | emma.brown@shop.example | Developer | 82000 | NULL | 2020-08-03 | 8 | 30 |
| 10 | Yusuf | Ali | yusuf.ali@shop.example | Developer | 82000 | NULL | 2021-05-19 | 8 | 30 |
| 11 | Nina | Petrova | nina.petrova@shop.example | Accountant | 58000 | NULL | 2021-10-11 | 4 | 40 |
| 12 | Tom | Baker | tom.baker@shop.example | Intern | 30000 | NULL | 2023-07-01 | 3 | NULL |

### customers

People who buy from the shop.

| customer_id | customer_name | email | city | country | signup_date |
|---|---|---|---|---|---|
| 1 | Alice Morgan | alice@example.com | London | UK | 2023-01-15 |
| 2 | Bilal Ahmed | bilal@example.com | Dubai | UAE | 2023-02-03 |
| 3 | Chloe Martin | chloe@example.com | Paris | France | 2023-02-20 |
| 4 | David Lee | david@example.com | Toronto | Canada | 2023-04-11 |
| 5 | Fatima Noor | fatima@example.com | Dubai | UAE | 2023-05-30 |
| 6 | George Hall | george@example.com | London | UK | 2023-07-08 |
| 7 | Hana Sato | hana@example.com | Tokyo | Japan | 2023-09-14 |
| 8 | Ivan Novak | NULL | NULL | NULL | 2024-01-05 |

### categories

Product categories. `parent_id` points at another category, so this table is a small tree.

| category_id | category_name | parent_id |
|---|---|---|
| 1 | Electronics | NULL |
| 2 | Phones | 1 |
| 3 | Laptops | 1 |
| 4 | Home | NULL |
| 5 | Kitchen | 4 |
| 6 | Books | NULL |
| 7 | Phone Accessories | 2 |

### products

What the shop sells. `price` is today's list price.

| product_id | product_name | category_id | price | stock_qty |
|---|---|---|---|---|
| 1 | Phone X | 2 | 799.00 | 25 |
| 2 | Phone Lite | 2 | 399.00 | 40 |
| 3 | Phone Case | 7 | 19.99 | 200 |
| 4 | Laptop Pro | 3 | 1499.00 | 10 |
| 5 | Laptop Air | 3 | 999.00 | 15 |
| 6 | Coffee Maker | 5 | 89.50 | 30 |
| 7 | Blender | 5 | 49.00 | 0 |
| 8 | SQL Basics | 6 | 29.00 | 100 |
| 9 | Database Design | 6 | 45.00 | 60 |
| 10 | Desk Lamp | 4 | 35.00 | 12 |

### orders

One row per order. `emp_id` is the sales rep. It is NULL for orders placed on the website.

| order_id | customer_id | emp_id | order_date | status |
|---|---|---|---|---|
| 1001 | 1 | 5 | 2024-01-05 | DELIVERED |
| 1002 | 2 | 5 | 2024-01-09 | DELIVERED |
| 1003 | 3 | 6 | 2024-01-20 | DELIVERED |
| 1004 | 1 | 6 | 2024-02-02 | DELIVERED |
| 1005 | 4 | 7 | 2024-02-14 | DELIVERED |
| 1006 | 2 | 5 | 2024-02-28 | CANCELLED |
| 1007 | 5 | 5 | 2024-03-03 | DELIVERED |
| 1008 | 3 | 7 | 2024-03-15 | DELIVERED |
| 1009 | 1 | 6 | 2024-03-30 | DELIVERED |
| 1010 | 6 | 6 | 2024-04-04 | DELIVERED |
| 1011 | 4 | 5 | 2024-04-21 | SHIPPED |
| 1012 | 5 | 7 | 2024-05-02 | SHIPPED |
| 1013 | 2 | 5 | 2024-05-19 | SHIPPED |
| 1014 | 1 | NULL | 2024-06-01 | PENDING |
| 1015 | 6 | 7 | 2024-06-11 | PENDING |
| 1016 | 3 | NULL | 2024-06-18 | PENDING |

### order_items

The lines of each order. The primary key is the pair (`order_id`, `product_id`). `unit_price` is the price actually charged, which can differ from today's list price.

| order_id | product_id | quantity | unit_price |
|---|---|---|---|
| 1001 | 1 | 1 | 799.00 |
| 1001 | 3 | 2 | 19.99 |
| 1002 | 8 | 1 | 29.00 |
| 1002 | 9 | 1 | 45.00 |
| 1003 | 4 | 1 | 1499.00 |
| 1004 | 6 | 1 | 89.50 |
| 1005 | 5 | 1 | 999.00 |
| 1005 | 3 | 1 | 19.99 |
| 1006 | 2 | 1 | 399.00 |
| 1007 | 2 | 2 | 399.00 |
| 1007 | 3 | 2 | 19.99 |
| 1008 | 8 | 3 | 29.00 |
| 1009 | 7 | 1 | 49.00 |
| 1010 | 1 | 1 | 749.00 |
| 1011 | 9 | 2 | 45.00 |
| 1011 | 8 | 1 | 29.00 |
| 1012 | 6 | 2 | 89.50 |
| 1013 | 5 | 1 | 999.00 |
| 1014 | 3 | 3 | 19.99 |
| 1015 | 4 | 1 | 1499.00 |
| 1015 | 6 | 1 | 89.50 |
| 1016 | 2 | 1 | 399.00 |

### payments

Money received against an order. One order can have several payments, or none.

| payment_id | order_id | payment_date | amount | method |
|---|---|---|---|---|
| 1 | 1001 | 2024-01-05 | 838.98 | CARD |
| 2 | 1002 | 2024-01-09 | 74.00 | CARD |
| 3 | 1003 | 2024-01-21 | 1000.00 | BANK |
| 4 | 1003 | 2024-02-10 | 499.00 | BANK |
| 5 | 1004 | 2024-02-02 | 89.50 | CARD |
| 6 | 1005 | 2024-02-14 | 1018.99 | CARD |
| 7 | 1007 | 2024-03-03 | 837.98 | WALLET |
| 8 | 1008 | 2024-03-16 | 87.00 | CARD |
| 9 | 1009 | 2024-03-30 | 49.00 | WALLET |
| 10 | 1010 | 2024-04-05 | 749.00 | BANK |
| 11 | 1011 | 2024-04-21 | 119.00 | CARD |
| 12 | 1012 | 2024-05-02 | 179.00 | WALLET |
| 13 | 1013 | 2024-05-20 | 500.00 | BANK |

## Column types

| Kind of column | Oracle | PostgreSQL |
|---|---|---|
| Ids, `quantity`, `stock_qty` | `NUMBER(6)` | `INTEGER` |
| `salary`, `commission` | `NUMBER(10)` | `NUMERIC(10)` |
| `price`, `unit_price`, `amount` | `NUMBER(10,2)` | `NUMERIC(10,2)` |
| Text | `VARCHAR2(n)` | `VARCHAR(n)` |
| Dates | `DATE` | `DATE` |

Chapter 5 explains why these types were chosen. The full definitions, including every constraint,
are in [setup/oracle/02_schema.sql](oracle/02_schema.sql) and [setup/postgres/02_schema.sql](postgres/02_schema.sql).
