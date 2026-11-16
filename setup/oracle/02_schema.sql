-- Step 2 of 3. Creates the eight sample tables.
-- Run this connected as DBPREP. It is safe to run again: it drops the tables first.

BEGIN
  FOR t IN (SELECT table_name
            FROM user_tables
            WHERE table_name IN ('PAYMENTS', 'ORDER_ITEMS', 'ORDERS', 'PRODUCTS',
                                 'CATEGORIES', 'CUSTOMERS', 'EMPLOYEES', 'DEPARTMENTS'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE departments (
  dept_id    NUMBER(6)          CONSTRAINT dept_pk PRIMARY KEY,
  dept_name  VARCHAR2(50)  NOT NULL CONSTRAINT dept_name_uk UNIQUE,
  location   VARCHAR2(50)  NOT NULL
);

CREATE TABLE employees (
  emp_id      NUMBER(6)          CONSTRAINT emp_pk PRIMARY KEY,
  first_name  VARCHAR2(30)  NOT NULL,
  last_name   VARCHAR2(30)  NOT NULL,
  email       VARCHAR2(60)  NOT NULL CONSTRAINT emp_email_uk UNIQUE,
  job_title   VARCHAR2(40)  NOT NULL,
  salary      NUMBER(10)    NOT NULL CONSTRAINT emp_salary_ck CHECK (salary > 0),
  commission  NUMBER(10),
  hire_date   DATE          NOT NULL,
  manager_id  NUMBER(6)          CONSTRAINT emp_manager_fk REFERENCES employees (emp_id),
  dept_id     NUMBER(6)          CONSTRAINT emp_dept_fk REFERENCES departments (dept_id)
);

CREATE TABLE customers (
  customer_id    NUMBER(6)          CONSTRAINT cust_pk PRIMARY KEY,
  customer_name  VARCHAR2(60)  NOT NULL,
  email          VARCHAR2(60)  CONSTRAINT cust_email_uk UNIQUE,
  city           VARCHAR2(50),
  country        VARCHAR2(50),
  signup_date    DATE          NOT NULL
);

CREATE TABLE categories (
  category_id    NUMBER(6)          CONSTRAINT cat_pk PRIMARY KEY,
  category_name  VARCHAR2(50)  NOT NULL CONSTRAINT cat_name_uk UNIQUE,
  parent_id      NUMBER(6)          CONSTRAINT cat_parent_fk REFERENCES categories (category_id)
);

CREATE TABLE products (
  product_id    NUMBER(6)          CONSTRAINT prod_pk PRIMARY KEY,
  product_name  VARCHAR2(60)  NOT NULL CONSTRAINT prod_name_uk UNIQUE,
  category_id   NUMBER(6)          NOT NULL CONSTRAINT prod_cat_fk REFERENCES categories (category_id),
  price         NUMBER(10,2)  NOT NULL CONSTRAINT prod_price_ck CHECK (price >= 0),
  stock_qty     NUMBER(6)          DEFAULT 0 NOT NULL CONSTRAINT prod_stock_ck CHECK (stock_qty >= 0)
);

CREATE TABLE orders (
  order_id     NUMBER(6)          CONSTRAINT ord_pk PRIMARY KEY,
  customer_id  NUMBER(6)          NOT NULL CONSTRAINT ord_cust_fk REFERENCES customers (customer_id),
  emp_id       NUMBER(6)          CONSTRAINT ord_emp_fk REFERENCES employees (emp_id),
  order_date   DATE          NOT NULL,
  status       VARCHAR2(20)  NOT NULL CONSTRAINT ord_status_ck
                 CHECK (status IN ('PENDING', 'SHIPPED', 'DELIVERED', 'CANCELLED'))
);

CREATE TABLE order_items (
  order_id    NUMBER(6)          NOT NULL CONSTRAINT item_order_fk REFERENCES orders (order_id),
  product_id  NUMBER(6)          NOT NULL CONSTRAINT item_prod_fk REFERENCES products (product_id),
  quantity    NUMBER(6)          NOT NULL CONSTRAINT item_qty_ck CHECK (quantity > 0),
  unit_price  NUMBER(10,2)  NOT NULL,
  CONSTRAINT item_pk PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
  payment_id    NUMBER(6)          CONSTRAINT pay_pk PRIMARY KEY,
  order_id      NUMBER(6)          NOT NULL CONSTRAINT pay_order_fk REFERENCES orders (order_id),
  payment_date  DATE          NOT NULL,
  amount        NUMBER(10,2)  NOT NULL CONSTRAINT pay_amount_ck CHECK (amount > 0),
  method        VARCHAR2(20)  NOT NULL CONSTRAINT pay_method_ck
                 CHECK (method IN ('CARD', 'BANK', 'WALLET'))
);
