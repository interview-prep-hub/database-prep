-- Step 3 of 3. Loads the sample rows.
-- Run this connected to the dbprep database. Run it again at any time to restore the original rows.

BEGIN;

DELETE FROM payments;
DELETE FROM order_items;
DELETE FROM orders;
DELETE FROM products;
DELETE FROM categories;
DELETE FROM customers;
DELETE FROM employees;
DELETE FROM departments;

INSERT INTO departments (dept_id, dept_name, location)
  VALUES (10, 'Executive', 'New York');
INSERT INTO departments (dept_id, dept_name, location)
  VALUES (20, 'Sales', 'London');
INSERT INTO departments (dept_id, dept_name, location)
  VALUES (30, 'Engineering', 'Toronto');
INSERT INTO departments (dept_id, dept_name, location)
  VALUES (40, 'Finance', 'Dubai');
INSERT INTO departments (dept_id, dept_name, location)
  VALUES (50, 'Legal', 'Singapore');

INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (1, 'Sara', 'Khan', 'sara.khan@shop.example', 'CEO', 180000, NULL, DATE '2015-01-12', NULL, 10);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (2, 'James', 'Wilson', 'james.wilson@shop.example', 'Sales Manager', 95000, 5000, DATE '2016-03-01', 1, 20);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (3, 'Priya', 'Sharma', 'priya.sharma@shop.example', 'Engineering Manager', 120000, NULL, DATE '2016-06-15', 1, 30);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (4, 'Omar', 'Farooq', 'omar.farooq@shop.example', 'Finance Manager', 95000, NULL, DATE '2017-02-20', 1, 40);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (5, 'Lena', 'Fischer', 'lena.fischer@shop.example', 'Sales Rep', 60000, 8000, DATE '2018-09-10', 2, 20);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (6, 'Diego', 'Ramos', 'diego.ramos@shop.example', 'Sales Rep', 60000, 6500, DATE '2019-11-04', 2, 20);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (7, 'Mei', 'Chen', 'mei.chen@shop.example', 'Sales Rep', 52000, 0, DATE '2022-01-17', 2, 20);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (8, 'Arjun', 'Patel', 'arjun.patel@shop.example', 'Senior Developer', 105000, NULL, DATE '2018-04-23', 3, 30);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (9, 'Emma', 'Brown', 'emma.brown@shop.example', 'Developer', 82000, NULL, DATE '2020-08-03', 8, 30);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (10, 'Yusuf', 'Ali', 'yusuf.ali@shop.example', 'Developer', 82000, NULL, DATE '2021-05-19', 8, 30);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (11, 'Nina', 'Petrova', 'nina.petrova@shop.example', 'Accountant', 58000, NULL, DATE '2021-10-11', 4, 40);
INSERT INTO employees (emp_id, first_name, last_name, email, job_title, salary, commission, hire_date, manager_id, dept_id)
  VALUES (12, 'Tom', 'Baker', 'tom.baker@shop.example', 'Intern', 30000, NULL, DATE '2023-07-01', 3, NULL);

INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (1, 'Alice Morgan', 'alice@example.com', 'London', 'UK', DATE '2023-01-15');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (2, 'Bilal Ahmed', 'bilal@example.com', 'Dubai', 'UAE', DATE '2023-02-03');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (3, 'Chloe Martin', 'chloe@example.com', 'Paris', 'France', DATE '2023-02-20');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (4, 'David Lee', 'david@example.com', 'Toronto', 'Canada', DATE '2023-04-11');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (5, 'Fatima Noor', 'fatima@example.com', 'Dubai', 'UAE', DATE '2023-05-30');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (6, 'George Hall', 'george@example.com', 'London', 'UK', DATE '2023-07-08');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (7, 'Hana Sato', 'hana@example.com', 'Tokyo', 'Japan', DATE '2023-09-14');
INSERT INTO customers (customer_id, customer_name, email, city, country, signup_date)
  VALUES (8, 'Ivan Novak', NULL, NULL, NULL, DATE '2024-01-05');

INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (1, 'Electronics', NULL);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (2, 'Phones', 1);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (3, 'Laptops', 1);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (4, 'Home', NULL);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (5, 'Kitchen', 4);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (6, 'Books', NULL);
INSERT INTO categories (category_id, category_name, parent_id)
  VALUES (7, 'Phone Accessories', 2);

INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (1, 'Phone X', 2, 799, 25);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (2, 'Phone Lite', 2, 399, 40);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (3, 'Phone Case', 7, 19.99, 200);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (4, 'Laptop Pro', 3, 1499, 10);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (5, 'Laptop Air', 3, 999, 15);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (6, 'Coffee Maker', 5, 89.5, 30);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (7, 'Blender', 5, 49, 0);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (8, 'SQL Basics', 6, 29, 100);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (9, 'Database Design', 6, 45, 60);
INSERT INTO products (product_id, product_name, category_id, price, stock_qty)
  VALUES (10, 'Desk Lamp', 4, 35, 12);

INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1001, 1, 5, DATE '2024-01-05', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1002, 2, 5, DATE '2024-01-09', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1003, 3, 6, DATE '2024-01-20', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1004, 1, 6, DATE '2024-02-02', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1005, 4, 7, DATE '2024-02-14', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1006, 2, 5, DATE '2024-02-28', 'CANCELLED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1007, 5, 5, DATE '2024-03-03', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1008, 3, 7, DATE '2024-03-15', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1009, 1, 6, DATE '2024-03-30', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1010, 6, 6, DATE '2024-04-04', 'DELIVERED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1011, 4, 5, DATE '2024-04-21', 'SHIPPED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1012, 5, 7, DATE '2024-05-02', 'SHIPPED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1013, 2, 5, DATE '2024-05-19', 'SHIPPED');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1014, 1, NULL, DATE '2024-06-01', 'PENDING');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1015, 6, 7, DATE '2024-06-11', 'PENDING');
INSERT INTO orders (order_id, customer_id, emp_id, order_date, status)
  VALUES (1016, 3, NULL, DATE '2024-06-18', 'PENDING');

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1001, 1, 1, 799);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1001, 3, 2, 19.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1002, 8, 1, 29);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1002, 9, 1, 45);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1003, 4, 1, 1499);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1004, 6, 1, 89.5);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1005, 5, 1, 999);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1005, 3, 1, 19.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1006, 2, 1, 399);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1007, 2, 2, 399);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1007, 3, 2, 19.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1008, 8, 3, 29);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1009, 7, 1, 49);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1010, 1, 1, 749);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1011, 9, 2, 45);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1011, 8, 1, 29);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1012, 6, 2, 89.5);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1013, 5, 1, 999);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1014, 3, 3, 19.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1015, 4, 1, 1499);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1015, 6, 1, 89.5);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (1016, 2, 1, 399);

INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (1, 1001, DATE '2024-01-05', 838.98, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (2, 1002, DATE '2024-01-09', 74, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (3, 1003, DATE '2024-01-21', 1000, 'BANK');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (4, 1003, DATE '2024-02-10', 499, 'BANK');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (5, 1004, DATE '2024-02-02', 89.5, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (6, 1005, DATE '2024-02-14', 1018.99, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (7, 1007, DATE '2024-03-03', 837.98, 'WALLET');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (8, 1008, DATE '2024-03-16', 87, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (9, 1009, DATE '2024-03-30', 49, 'WALLET');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (10, 1010, DATE '2024-04-05', 749, 'BANK');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (11, 1011, DATE '2024-04-21', 119, 'CARD');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (12, 1012, DATE '2024-05-02', 179, 'WALLET');
INSERT INTO payments (payment_id, order_id, payment_date, amount, method)
  VALUES (13, 1013, DATE '2024-05-20', 500, 'BANK');

COMMIT;

SELECT 'departments' AS table_name, COUNT(*) AS row_count FROM departments
UNION ALL
SELECT 'employees' AS table_name, COUNT(*) AS row_count FROM employees
UNION ALL
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'categories' AS table_name, COUNT(*) AS row_count FROM categories
UNION ALL
SELECT 'products' AS table_name, COUNT(*) AS row_count FROM products
UNION ALL
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'order_items' AS table_name, COUNT(*) AS row_count FROM order_items
UNION ALL
SELECT 'payments' AS table_name, COUNT(*) AS row_count FROM payments;
