# 1. What Is a Database, and Why Do We Need One?

**Level:** Basic | **Interview priority:** Must know | **Before this:** Nothing. Start here.

> **In one line:** A database is an organized, shared collection of data, and a DBMS is the software that stores, protects and serves it.

## What you will learn

- Data, information and metadata
- Why plain files are not enough
- DBMS vs RDBMS, and SQL vs a database product
- The kinds of SQL statement: DDL, DML, DQL, DCL and TCL
- Schema vs instance, the three-schema architecture, and data independence
- OLTP vs OLAP, ACID in plain words, and SQL vs NoSQL

Before you go on, install the sample database. See the [setup guide](../setup/README.md), and [meet its tables](../setup/sample-database.md).

## Data, information and metadata

Take one fact from the sample shop.

| Term | Meaning | Example |
|---|---|---|
| **Data** | Raw values | `799.00` |
| **Information** | Data with meaning | Phone X costs 799.00 |
| **Metadata** | Data about data | `price` is a `NUMERIC(10,2)` column of `products` |

## What is a database?

- A **database** is an organized, shared collection of related data.
- A **DBMS** (database management system) is the software that stores, protects and serves it. Oracle and PostgreSQL are DBMSs.
- A **database system** is the two together, plus the applications.

## Why not just use files?

Imagine running the shop from CSV files.

| Problem with files | Example |
|---|---|
| **Redundancy and inconsistency** | A customer's city is copied into many files, and one copy goes stale |
| **Hard to get at data** | Every new question needs a new program |
| **Data isolation** | Files in different formats cannot be combined easily |
| **Integrity** | Nothing stops a negative price |
| **Atomicity** | A crash between "take money" and "record order" loses money |
| **Concurrency** | Two people edit the same file, and one change is lost |
| **Security** | You cannot show a clerk some columns and hide others |

A DBMS solves each of these: one copy of each fact, a query language, constraints, transactions, concurrency control and access rights.

**The costs:** licensing, hardware, administration, and overhead. For a small single-user app, or a simple log file, a DBMS may be more than you need.

## Data models

A **data model** is a way of describing data.

| Model | Idea |
|---|---|
| Relational | Tables ([Chapter 2](02-relational-model-and-keys.md)) |
| Entity-relationship | Diagrams for design ([Chapter 4](04-er-modeling.md)) |
| Semi-structured | JSON, XML |
| Hierarchical, network | Older systems |

The everyday words are **table**, **row** and **column**.

## DBMS vs RDBMS

An **RDBMS** is a DBMS built on the relational model: data in tables, relationships through matching key values, and keys and constraints enforced. Oracle, PostgreSQL, MySQL and SQL Server are RDBMSs.

### SQL vs MySQL

**SQL** is a query language, with an international standard (ISO/IEC 9075). **MySQL** is a product that uses SQL. Saying "SQL vs MySQL" is like saying "English vs a particular book".

### Database, SQL and PL/SQL

The database holds the data. SQL reads and changes it. **PL/SQL** is Oracle's procedural language wrapped around SQL, adding variables, loops and error handling ([Part 7](../part-7-plsql/42-plsql-basics.md)).

**SQL is declarative.** You state the result you want, and the **optimizer**, the part of the engine that chooses how to run a query, picks the plan.

## Kinds of SQL statement

| Group | Purpose | Statements |
|---|---|---|
| **DDL** (definition) | Define structure | `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `RENAME`, `COMMENT` |
| **DML** (manipulation) | Change rows | `INSERT`, `UPDATE`, `DELETE`, `MERGE` |
| **DQL** (query) | Read rows | `SELECT` |
| **DCL** (control) | Control access | `GRANT`, `REVOKE` |
| **TCL** (transaction) | Control transactions | `COMMIT`, `ROLLBACK`, `SAVEPOINT` |

```sql
SELECT dept_name FROM departments WHERE location = 'London';
```

```text output
 dept_name
-----------
 Sales
(1 row)
```

**The edge cases.** `SELECT` is DQL in teaching lists, but the Oracle and MySQL manuals file it under DML. **Why is `TRUNCATE` classed as DDL when it removes rows?** Because it does not work row by row: it resets the table's storage, and on Oracle and MySQL it commits implicitly.

## Schema vs instance

The **schema** (or **intension**) is the design. The **instance** (or **extension**, or **database state**) is the data at one moment. It is like a variable's type and its current value.

**The same word means different things:**

| Word | Meaning |
|---|---|
| Schema, in a textbook | The design |
| Schema, on Oracle | The objects owned by one user |
| Schema, on PostgreSQL | A namespace inside a database |
| Schema, on MySQL | A synonym for database |

**In Oracle and PostgreSQL, what is a schema, and how does it differ from a database?** On Oracle, a schema belongs to one user, inside the one database of an instance. On PostgreSQL, one server holds many databases, and each holds many schemas.

## The three-schema architecture

```text
External level     What each user group sees (views)
       |
Conceptual level   The whole logical design (tables, keys, constraints)
       |
Internal level     How data is stored (files, indexes)
```

**Which level do views, relations and indexes each belong to?** Views are external, relations are conceptual, and indexes are internal.

**Data independence** means changing one level without breaking the one above.

| Type | You can change | Without changing |
|---|---|---|
| **Physical** | Storage: add an index, move files | The conceptual schema |
| **Logical** | The conceptual schema: add a column | External views and programs |

Logical independence is harder to achieve, because applications often depend on the logical structure.

## Inside the engine

- **Query processor:** DDL interpreter, DML compiler with the optimizer, and the query evaluation engine.
- **Storage manager:** authorization, transactions, files and the buffer manager.

The **data dictionary** (system catalog) stores metadata in tables you can query.

**Oracle:**

```sql oracle
SELECT table_name FROM user_tables ORDER BY table_name;
```

**PostgreSQL:**

```sql postgres
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

```text output
 table_name
-------------
 categories
 customers
 departments
 employees
 order_items
 orders
 payments
 products
(8 rows)
```

## Two-tier and three-tier

- **Two-tier:** the client talks straight to the database.
- **Three-tier:** the client talks to an application server, which talks to the database. Almost all web systems do this, because the middle tier holds logic and connection pools, and the database is not exposed.

## OLTP vs OLAP

| | OLTP | OLAP |
|---|---|---|
| Purpose | Run the business | Analyze the business |
| Query shape | Short, few rows | Long, many rows |
| Latency target | Milliseconds | Seconds or minutes |
| Users | Many | Few |
| Design | Normalized | Star schema |
| Example | Place an order | Revenue by region and year |

[Chapter 26](../part-4-database-design/26-data-warehouse-design.md) goes deeper.

## Transactions and ACID

A **transaction** is a group of statements that succeed or fail as one unit, ended by `COMMIT` or `ROLLBACK`. Placing an order inserts into `orders` and `order_items`, and both must happen.

Think of a bank transfer:

| Letter | Meaning |
|---|---|
| **Atomicity** | Both accounts change, or neither |
| **Consistency** | Each commit moves the data from one valid state to another |
| **Isolation** | Concurrent transfers do not interfere |
| **Durability** | Once committed, it survives a crash |

**What ACID does not promise.** Consistency covers only the rules you encoded. A successful `COMMIT` says nothing about whether the logic was right. [Chapter 32](../part-5-internals-and-performance/32-transactions-and-isolation.md) covers isolation levels, anomalies and MVCC in depth.

## Database families

| Family | Good for | Examples |
|---|---|---|
| Relational | Joins, transactions, general business data | Oracle, PostgreSQL |
| Document | Whole records with varying shape | MongoDB |
| Key-value | Fast lookup by key | Redis, DynamoDB |
| Wide-column | Huge write volumes, known queries | Cassandra |
| Graph | Relationships across many hops | Neo4j |
| Time-series | Metrics over time | TimescaleDB |
| Vector | Similarity search | pgvector |

**"Schemaless" does not remove the schema.** It moves it into the application's read code. The real trade-off is schema-on-write vs schema-on-read.

**BASE** (basically available, soft state, eventual consistency) is the design posture of many NoSQL systems, and it pushes conflict handling to the application.

### SQL vs NoSQL

| | SQL | NoSQL |
|---|---|---|
| Schema | Enforced on write | Enforced by readers |
| Consistency | Strong by default | Often tunable or eventual |
| Scaling | Up first, then replicas | Out, by design |
| Queries | Flexible, with joins | Designed around known access paths |

**Which would you choose for receiving payments from users, and why?** A relational database. Payments need atomic transactions, constraints and strong consistency. I might add a NoSQL store beside it for high-volume reads, but the money stays in ACID transactions. [Chapter 39](../part-6-architecture-and-scale/39-nosql-and-choosing-a-database.md) covers this.

## Who works with a database?

End users, application developers, and the **DBA** (database administrator), who handles installation, backups, tuning and security.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Say SQL and MySQL are the same | One is a language, one a product | Separate them |
| Say a DBMS is the data | The DBMS is the software | Name each part |
| Say `TRUNCATE` is DML | It is DDL | Explain why |
| Assume "schema" means one thing | It differs by engine | Say which you mean |
| Say NoSQL has no schema | The schema moves to the code | Say schema-on-read |
| Say ACID means your data is right | It only keeps your encoded rules | Say so |

## Interview questions

**Q1. What is the difference between SQL and MySQL?**

SQL is the standard query language. MySQL is a database product that implements it.

**Q2. What is the difference between DBMS and RDBMS?**

A DBMS is any software that manages data. An RDBMS is a DBMS built on the relational model, with tables, keys and SQL.

**Q3. What are the advantages of using a DBMS over a file system?**

It reduces redundancy, enforces integrity, gives atomic transactions and crash recovery, handles many users at once, controls access, and offers a query language. With files, every application must build all of that itself.

**Q4. What are DDL, DML, DCL and TCL? Give an example of each.**

DDL defines structure, such as `CREATE TABLE`. DML changes rows, such as `UPDATE`. DCL controls access, such as `GRANT`. TCL controls transactions, such as `COMMIT`.

**Q5. Why is TRUNCATE classed as DDL when it removes rows?**

It does not delete row by row. It resets the table's storage, with minimal logging, and on Oracle and MySQL it commits implicitly, as DDL does.

**Q6. Explain the difference between intension and extension in a database.**

Intension is the schema: the design, which rarely changes. Extension is the instance: the data at a given moment, which changes constantly.

**Q7. Explain the three-schema architecture.**

External is what each user group sees, through views. Conceptual is the whole logical design. Internal is the physical storage. Views are external, relations are conceptual, and indexes are internal.

**Q8. What is the difference between physical and logical data independence, and which is harder?**

Physical means changing storage without touching the logical schema. Logical means changing the logical schema without touching views and applications. Logical is harder.

**Q9. What is a data dictionary?**

A set of system tables that stores metadata, such as tables, columns and privileges. On Oracle, `USER_TABLES`. On PostgreSQL, `information_schema` and `pg_catalog`.

**Q10. What are the differences between OLTP and OLAP? Give one example of each.**

OLTP runs the business, with many short transactions, such as placing an order. OLAP analyzes it, with long read-heavy queries, such as revenue by region for five years.

**Q11. What do the letters in ACID guarantee, and what does a successful COMMIT not guarantee?**

Atomicity, consistency, isolation and durability. A `COMMIT` does not guarantee your logic was right, and with asynchronous replication it does not prove a replica has the change yet.

## Practice

**1. Classify each statement: `GRANT`, `TRUNCATE`, `MERGE`, `SAVEPOINT`, `SELECT`.**

<details>
<summary>Show solution</summary>

DCL, DDL, DML, TCL and DQL.

</details>

**2. You add an index, and no application changes. Which kind of independence is this?**

<details>
<summary>Show solution</summary>

Physical data independence.

</details>

**3. Is a monthly revenue report OLTP or OLAP? Is updating a user's address?**

<details>
<summary>Show solution</summary>

The report is OLAP, and the address update is OLTP.

</details>

## Recap

- A database is the data, and a DBMS is the software.
- A DBMS solves redundancy, integrity, atomicity, concurrency and security.
- SQL is a language, and MySQL is a product.
- DDL, DML, DQL, DCL and TCL are the kinds of statement.
- Schema is the design, and instance is the current data.
- External, conceptual and internal levels give data independence.
- OLTP runs the business, and OLAP analyzes it.

**Next:** [Chapter 2: The relational model and keys](02-relational-model-and-keys.md)
