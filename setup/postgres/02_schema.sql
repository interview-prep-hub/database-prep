-- Step 2 of 3. Creates the eight sample tables.
-- Run this connected to the dbprep database. It is safe to run again: it drops the tables first.

DROP TABLE IF EXISTS payments, order_items, orders, products, categories, customers, employees, departments CASCADE;

CREATE TABLE departments (
  dept_id    INTEGER          CONSTRAINT dept_pk PRIMARY KEY,
  dept_name  VARCHAR(50)  NOT NULL CONSTRAINT dept_name_uk UNIQUE,
  location   VARCHAR(50)  NOT NULL
);

CREATE TABLE employees (
  emp_id      INTEGER          CONSTRAINT emp_pk PRIMARY KEY,
  first_name  VARCHAR(30)  NOT NULL,
  last_name   VARCHAR(30)  NOT NULL,
  email       VARCHAR(60)  NOT NULL CONSTRAINT emp_email_uk UNIQUE,
  job_title   VARCHAR(40)  NOT NULL,
  salary      NUMERIC(10)    NOT NULL CONSTRAINT emp_salary_ck CHECK (salary > 0),
  commission  NUMERIC(10),
  hire_date   DATE          NOT NULL,
  manager_id  INTEGER          CONSTRAINT emp_manager_fk REFERENCES employees (emp_id),
  dept_id     INTEGER          CONSTRAINT emp_dept_fk REFERENCES departments (dept_id)
);

CREATE TABLE customers (
  customer_id    INTEGER          CONSTRAINT cust_pk PRIMARY KEY,
  customer_name  VARCHAR(60)  NOT NULL,
  email          VARCHAR(60)  CONSTRAINT cust_email_uk UNIQUE,
  city           VARCHAR(50),
  country        VARCHAR(50),
  signup_date    DATE          NOT NULL
);

CREATE TABLE categories (
  category_id    INTEGER          CONSTRAINT cat_pk PRIMARY KEY,
  category_name  VARCHAR(50)  NOT NULL CONSTRAINT cat_name_uk UNIQUE,
  parent_id      INTEGER          CONSTRAINT cat_parent_fk REFERENCES categories (category_id)
);

CREATE TABLE products (
  product_id    INTEGER          CONSTRAINT prod_pk PRIMARY KEY,
  product_name  VARCHAR(60)  NOT NULL CONSTRAINT prod_name_uk UNIQUE,
  category_id   INTEGER          NOT NULL CONSTRAINT prod_cat_fk REFERENCES categories (category_id),
  price         NUMERIC(10,2)  NOT NULL CONSTRAINT prod_price_ck CHECK (price >= 0),
  stock_qty     INTEGER          DEFAULT 0 NOT NULL CONSTRAINT prod_stock_ck CHECK (stock_qty >= 0)
);

CREATE TABLE orders (
  order_id     INTEGER          CONSTRAINT ord_pk PRIMARY KEY,
  customer_id  INTEGER          NOT NULL CONSTRAINT ord_cust_fk REFERENCES customers (customer_id),
  emp_id       INTEGER          CONSTRAINT ord_emp_fk REFERENCES employees (emp_id),
  order_date   DATE          NOT NULL,
  status       VARCHAR(20)  NOT NULL CONSTRAINT ord_status_ck
                 CHECK (status IN ('PENDING', 'SHIPPED', 'DELIVERED', 'CANCELLED'))
);

CREATE TABLE order_items (
  order_id    INTEGER          NOT NULL CONSTRAINT item_order_fk REFERENCES orders (order_id),
  product_id  INTEGER          NOT NULL CONSTRAINT item_prod_fk REFERENCES products (product_id),
  quantity    INTEGER          NOT NULL CONSTRAINT item_qty_ck CHECK (quantity > 0),
  unit_price  NUMERIC(10,2)  NOT NULL,
  CONSTRAINT item_pk PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
  payment_id    INTEGER          CONSTRAINT pay_pk PRIMARY KEY,
  order_id      INTEGER          NOT NULL CONSTRAINT pay_order_fk REFERENCES orders (order_id),
  payment_date  DATE          NOT NULL,
  amount        NUMERIC(10,2)  NOT NULL CONSTRAINT pay_amount_ck CHECK (amount > 0),
  method        VARCHAR(20)  NOT NULL CONSTRAINT pay_method_ck
                 CHECK (method IN ('CARD', 'BANK', 'WALLET'))
);
