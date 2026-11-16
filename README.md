# Database Interview Preparation

From your first table to full advanced SQL, PL/SQL, normalization, database design, internals and architecture. Everything for the database round of a software interview, in simple language with simple examples.

## Start here

1. Pick a [study plan](#study-plans) that fits your time.
2. Optional: set up the practice database with [setup/README.md](setup/README.md). You can also just read, because each example shows its result.
3. Work through the chapters in order. Do each chapter's Practice section before you open the solution.
4. Revise with the [cheat sheets](#cheat-sheets).
5. Finish with the [mock interviews](part-8-interview-practice/60-mock-interviews.md), and read [Last-Day Revision](cheat-sheets/last-day-revision.md) the night before.

## The book at a glance

| Part | What you will be able to do |
|---|---|
| 1. Foundations | Explain what a database is, and model data with keys and ER diagrams |
| 2. SQL Basics | Write everyday queries, joins, subqueries and data changes |
| 3. Advanced SQL | Use CTEs, window functions, pivots and the classic interview patterns |
| 4. Database Design | Normalize, denormalize, and design real schemas |
| 5. Internals and Performance | Read plans, tune queries, and explain indexes, transactions and locks |
| 6. Architecture and Scale | Explain server internals, replication, sharding and where to do what |
| 7. PL/SQL | Write Oracle procedures, packages, triggers and bulk code |
| 8. Interview Practice | Rehearse query problems, theory, design, scenarios and full mocks |

## Roadmap

**Must know** chapters come up in most rounds. **Should know** chapters come up often. **Good to know** chapters separate strong candidates, or suit specific roles.

### Part 1: Foundations

| # | Chapter | Level | Priority |
|---|---|---|---|
| 1 | [What Is a Database, and Why Do We Need One?](part-1-foundations/01-what-is-a-database.md) | Basic | Must know |
| 2 | [The Relational Model: Tables, Keys and Rules](part-1-foundations/02-relational-model-and-keys.md) | Basic | Must know |
| 3 | [Relational Algebra: The Math Under SQL](part-1-foundations/03-relational-algebra.md) | Intermediate | Should know |
| 4 | [ER Modeling: Designing a Database Before You Build It](part-1-foundations/04-er-modeling.md) | Intermediate | Must know |
| 5 | [Data Types and NULL: Storing Values Correctly](part-1-foundations/05-data-types-and-null.md) | Basic | Must know |

### Part 2: SQL Basics

| # | Chapter | Level | Priority |
|---|---|---|---|
| 6 | [Creating Tables and Constraints](part-2-sql-basics/06-ddl-and-constraints.md) | Basic | Must know |
| 7 | [Changing Data: INSERT, UPDATE, DELETE and TRUNCATE](part-2-sql-basics/07-dml-insert-update-delete.md) | Basic | Must know |
| 8 | [SELECT: Filtering, Sorting and How a Query Runs](part-2-sql-basics/08-select-filter-sort.md) | Basic | Must know |
| 9 | [Built-in Functions: Text, Numbers, Dates, NULLs and CASE](part-2-sql-basics/09-built-in-functions.md) | Intermediate | Must know |
| 10 | [Grouping and Totals: GROUP BY and HAVING](part-2-sql-basics/10-aggregation-group-by-having.md) | Intermediate | Must know |
| 11 | [Joins](part-2-sql-basics/11-joins.md) | Intermediate | Must know |
| 12 | [Set Operations](part-2-sql-basics/12-set-operations.md) | Basic | Must know |
| 13 | [Subqueries](part-2-sql-basics/13-subqueries.md) | Intermediate | Must know |

### Part 3: Advanced SQL

| # | Chapter | Level | Priority |
|---|---|---|---|
| 14 | [CTEs and Recursive Queries: Naming Steps and Walking Trees](part-3-advanced-sql/14-cte-and-recursive-queries.md) | Intermediate | Must know |
| 15 | [Window Functions: Ranking Rows and Looking at Neighbors](part-3-advanced-sql/15-window-functions-ranking-and-offset.md) | Intermediate | Must know |
| 16 | [Window Functions: Frames, Running Totals and Moving Averages](part-3-advanced-sql/16-window-functions-frames-and-running-totals.md) | Advanced | Must know |
| 17 | [Subtotals, Pivots and Joining Rows into Strings](part-3-advanced-sql/17-advanced-grouping-and-pivot.md) | Intermediate | Should know |
| 18 | [Advanced Data Changes: Upsert, MERGE, RETURNING and Removing Duplicates](part-3-advanced-sql/18-advanced-dml.md) | Intermediate | Must know |
| 19 | [Views, Materialized Views, Sequences and Temporary Tables](part-3-advanced-sql/19-views-materialized-views-sequences.md) | Intermediate | Must know |
| 20 | [Modern SQL: Regular Expressions, Date Series, LATERAL and JSON](part-3-advanced-sql/20-modern-sql.md) | Advanced | Should know |
| 21 | [Classic Query Patterns Interviewers Keep Asking](part-3-advanced-sql/21-classic-query-patterns.md) | Advanced | Must know |

### Part 4: Database Design

| # | Chapter | Level | Priority |
|---|---|---|---|
| 22 | [Functional Dependencies: The Rules Behind Your Data](part-4-database-design/22-functional-dependencies.md) | Intermediate | Must know |
| 23 | [Normalization: From 1NF to 5NF, Step by Step](part-4-database-design/23-normalization.md) | Intermediate | Must know |
| 24 | [Denormalization: When and How to Break the Rules](part-4-database-design/24-denormalization-and-trade-offs.md) | Intermediate | Must know |
| 25 | [Schema Design: Keys, Constraints, Patterns and Anti-Patterns](part-4-database-design/25-schema-design-patterns.md) | Intermediate | Must know |
| 26 | [Data Warehouse Design: OLTP vs OLAP, Star Schemas and History](part-4-database-design/26-data-warehouse-design.md) | Intermediate | Should know |
| 27 | [Design Case Studies: A Repeatable Method and Worked Schemas](part-4-database-design/27-design-case-studies.md) | Advanced | Must know |

### Part 5: Internals and Performance

| # | Chapter | Level | Priority |
|---|---|---|---|
| 28 | [How Data Is Stored: Pages, Files and the Buffer Pool](part-5-internals-and-performance/28-how-data-is-stored.md) | Intermediate | Should know |
| 29 | [Indexes: How Databases Find Rows Fast](part-5-internals-and-performance/29-indexes.md) | Intermediate | Must know |
| 30 | [Execution Plans and How the Optimizer Thinks](part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md) | Advanced | Must know |
| 31 | [The Query Tuning Playbook](part-5-internals-and-performance/31-query-tuning-playbook.md) | Intermediate | Must know |
| 32 | [Transactions and Isolation Levels](part-5-internals-and-performance/32-transactions-and-isolation.md) | Intermediate | Must know |
| 33 | [Locks, Deadlocks and MVCC](part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) | Advanced | Must know |
| 34 | [Backup and Recovery: How Databases Survive Failures](part-5-internals-and-performance/34-backup-and-recovery.md) | Advanced | Should know |

### Part 6: Architecture and Scale

| # | Chapter | Level | Priority |
|---|---|---|---|
| 35 | [Inside a Database Server](part-6-architecture-and-scale/35-database-architecture.md) | Intermediate | Must know |
| 36 | [Partitioning: Splitting a Big Table](part-6-architecture-and-scale/36-partitioning.md) | Intermediate | Must know |
| 37 | [Replication and High Availability](part-6-architecture-and-scale/37-replication-and-high-availability.md) | Intermediate | Must know |
| 38 | [Sharding and Distributed Databases](part-6-architecture-and-scale/38-sharding-and-distributed-databases.md) | Advanced | Must know |
| 39 | [NoSQL and Choosing a Database](part-6-architecture-and-scale/39-nosql-and-choosing-a-database.md) | Intermediate | Must know |
| 40 | [Database Security](part-6-architecture-and-scale/40-database-security.md) | Intermediate | Must know |
| 41 | [Where to Do What: The Decision Guide](part-6-architecture-and-scale/41-where-to-do-what.md) | Intermediate | Must know |

### Part 7: PL/SQL

| # | Chapter | Level | Priority |
|---|---|---|---|
| 42 | [PL/SQL Basics: Blocks, Variables and Data Types](part-7-plsql/42-plsql-basics.md) | Basic | Must know |
| 43 | [IF, CASE and Loops: Controlling the Flow](part-7-plsql/43-control-structures.md) | Basic | Must know |
| 44 | [Cursors: Reading Query Results Row by Row](part-7-plsql/44-cursors.md) | Intermediate | Must know |
| 45 | [Exceptions: Handling Errors the Right Way](part-7-plsql/45-exceptions.md) | Intermediate | Must know |
| 46 | [Procedures and Functions: Reusable Stored Code](part-7-plsql/46-procedures-and-functions.md) | Intermediate | Must know |
| 47 | [Packages: Grouping Related Code](part-7-plsql/47-packages.md) | Intermediate | Must know |
| 48 | [Triggers: Code That Runs Automatically](part-7-plsql/48-triggers.md) | Intermediate | Must know |
| 49 | [Records and Collections: Holding Rows and Lists in Memory](part-7-plsql/49-records-and-collections.md) | Intermediate | Must know |
| 50 | [Bulk Processing: BULK COLLECT and FORALL](part-7-plsql/50-bulk-processing.md) | Advanced | Must know |
| 51 | [Dynamic SQL and SQL Injection](part-7-plsql/51-dynamic-sql.md) | Advanced | Must know |
| 52 | [Advanced PL/SQL Features](part-7-plsql/52-advanced-plsql.md) | Advanced | Should know |
| 53 | [Making PL/SQL Fast, Safe and Easy to Deploy](part-7-plsql/53-plsql-performance-and-best-practices.md) | Advanced | Should know |
| 54 | [Real-World PL/SQL Programs: Putting It All Together](part-7-plsql/54-real-world-plsql-programs.md) | Advanced | Should know |

### Part 8: Interview Practice

| # | Chapter | Level | Priority |
|---|---|---|---|
| 55 | [SQL Query Problems: From Warm-Ups to Hard Interview Questions](part-8-interview-practice/55-sql-query-problems.md) | Intermediate | Must know |
| 56 | [Database Concepts: The Questions You Answer Out Loud](part-8-interview-practice/56-concept-question-bank.md) | Intermediate | Must know |
| 57 | [PL/SQL Questions: Theory, Coding Drills and Production Scenarios](part-8-interview-practice/57-plsql-question-bank.md) | Intermediate | Must know |
| 58 | [Design and Architecture Questions: Schemas, Trade-offs and Where to Do What](part-8-interview-practice/58-design-and-architecture-question-bank.md) | Intermediate | Must know |
| 59 | [Scenario and Troubleshooting Questions: When Production Goes Wrong](part-8-interview-practice/59-scenario-and-troubleshooting-questions.md) | Advanced | Must know |
| 60 | [Mock Interviews: Full Rounds to Rehearse Under Time](part-8-interview-practice/60-mock-interviews.md) | Intermediate | Must know |

## Cheat sheets

| Sheet | Use it for |
|---|---|
| [SQL Cheat Sheet](cheat-sheets/sql-cheat-sheet.md) | Syntax, NULL rules, joins, window functions, error codes |
| [PL/SQL Cheat Sheet](cheat-sheets/plsql-cheat-sheet.md) | Cursor, collection and trigger tables, limits, error codes, packages |
| [Dialect Differences](cheat-sheets/dialect-differences.md) | Oracle, PostgreSQL, MySQL and SQL Server side by side |
| [Concepts Cheat Sheet](cheat-sheets/concepts-cheat-sheet.md) | Normal forms, formulas, and where to do what |
| [Glossary](cheat-sheets/glossary.md) | Every database word in plain English |
| [Last-Day Revision](cheat-sheets/last-day-revision.md) | The night before |

## Study plans

### 7 days: the interview is next week

Must-know topics only.

| Day | Focus | Chapters |
|---|---|---|
| 1 | Core SQL | [Ch 8](part-2-sql-basics/08-select-filter-sort.md), [Ch 10](part-2-sql-basics/10-aggregation-group-by-having.md), [Ch 11](part-2-sql-basics/11-joins.md), [Ch 13](part-2-sql-basics/13-subqueries.md) |
| 2 | Advanced SQL | [Ch 14](part-3-advanced-sql/14-cte-and-recursive-queries.md), [Ch 15](part-3-advanced-sql/15-window-functions-ranking-and-offset.md), [Ch 16](part-3-advanced-sql/16-window-functions-frames-and-running-totals.md), [Ch 21](part-3-advanced-sql/21-classic-query-patterns.md) |
| 3 | Design | [Ch 2](part-1-foundations/02-relational-model-and-keys.md), [Ch 23](part-4-database-design/23-normalization.md), [Ch 25](part-4-database-design/25-schema-design-patterns.md), [Ch 41](part-6-architecture-and-scale/41-where-to-do-what.md) |
| 4 | Performance and transactions | [Ch 29](part-5-internals-and-performance/29-indexes.md), [Ch 30](part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md), [Ch 32](part-5-internals-and-performance/32-transactions-and-isolation.md), [Ch 33](part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md) |
| 5 | PL/SQL | [Ch 42](part-7-plsql/42-plsql-basics.md), [Ch 44](part-7-plsql/44-cursors.md), [Ch 45](part-7-plsql/45-exceptions.md), [Ch 46](part-7-plsql/46-procedures-and-functions.md), [Ch 48](part-7-plsql/48-triggers.md) |
| 6 | Practice | [Ch 55](part-8-interview-practice/55-sql-query-problems.md), [Ch 56](part-8-interview-practice/56-concept-question-bank.md), [Ch 57](part-8-interview-practice/57-plsql-question-bank.md), [Ch 58](part-8-interview-practice/58-design-and-architecture-question-bank.md) |
| 7 | One mock, then revise | [Ch 60](part-8-interview-practice/60-mock-interviews.md), [Last-Day Revision](cheat-sheets/last-day-revision.md) |

No PL/SQL in your round? Replace day 5 with [Ch 35](part-6-architecture-and-scale/35-database-architecture.md) and [Ch 59](part-8-interview-practice/59-scenario-and-troubleshooting-questions.md).

### 14 days: a solid pass

| Day | Focus | Chapters |
|---|---|---|
| 1 | Foundations | [Ch 1](part-1-foundations/01-what-is-a-database.md), [Ch 2](part-1-foundations/02-relational-model-and-keys.md), [Ch 5](part-1-foundations/05-data-types-and-null.md) |
| 2 | SQL basics | [Ch 6](part-2-sql-basics/06-ddl-and-constraints.md), [Ch 7](part-2-sql-basics/07-dml-insert-update-delete.md), [Ch 8](part-2-sql-basics/08-select-filter-sort.md), [Ch 9](part-2-sql-basics/09-built-in-functions.md) |
| 3 | Combining data | [Ch 10](part-2-sql-basics/10-aggregation-group-by-having.md), [Ch 11](part-2-sql-basics/11-joins.md), [Ch 12](part-2-sql-basics/12-set-operations.md), [Ch 13](part-2-sql-basics/13-subqueries.md) |
| 4 | CTEs and windows | [Ch 14](part-3-advanced-sql/14-cte-and-recursive-queries.md), [Ch 15](part-3-advanced-sql/15-window-functions-ranking-and-offset.md), [Ch 16](part-3-advanced-sql/16-window-functions-frames-and-running-totals.md) |
| 5 | Query patterns | [Ch 17](part-3-advanced-sql/17-advanced-grouping-and-pivot.md), [Ch 18](part-3-advanced-sql/18-advanced-dml.md), [Ch 19](part-3-advanced-sql/19-views-materialized-views-sequences.md), [Ch 21](part-3-advanced-sql/21-classic-query-patterns.md) |
| 6 | Modeling and normalization | [Ch 4](part-1-foundations/04-er-modeling.md), [Ch 22](part-4-database-design/22-functional-dependencies.md), [Ch 23](part-4-database-design/23-normalization.md) |
| 7 | Schema design | [Ch 24](part-4-database-design/24-denormalization-and-trade-offs.md), [Ch 25](part-4-database-design/25-schema-design-patterns.md), [Ch 27](part-4-database-design/27-design-case-studies.md) |
| 8 | Performance | [Ch 28](part-5-internals-and-performance/28-how-data-is-stored.md), [Ch 29](part-5-internals-and-performance/29-indexes.md), [Ch 30](part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md), [Ch 31](part-5-internals-and-performance/31-query-tuning-playbook.md) |
| 9 | Transactions | [Ch 32](part-5-internals-and-performance/32-transactions-and-isolation.md), [Ch 33](part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md), [Ch 34](part-5-internals-and-performance/34-backup-and-recovery.md) |
| 10 | Architecture | [Ch 35](part-6-architecture-and-scale/35-database-architecture.md), [Ch 36](part-6-architecture-and-scale/36-partitioning.md), [Ch 37](part-6-architecture-and-scale/37-replication-and-high-availability.md), [Ch 38](part-6-architecture-and-scale/38-sharding-and-distributed-databases.md), [Ch 41](part-6-architecture-and-scale/41-where-to-do-what.md) |
| 11 | PL/SQL basics | [Ch 42](part-7-plsql/42-plsql-basics.md), [Ch 43](part-7-plsql/43-control-structures.md), [Ch 44](part-7-plsql/44-cursors.md), [Ch 45](part-7-plsql/45-exceptions.md) |
| 12 | PL/SQL units | [Ch 46](part-7-plsql/46-procedures-and-functions.md), [Ch 47](part-7-plsql/47-packages.md), [Ch 48](part-7-plsql/48-triggers.md), [Ch 50](part-7-plsql/50-bulk-processing.md) |
| 13 | Practice | [Ch 55](part-8-interview-practice/55-sql-query-problems.md), [Ch 56](part-8-interview-practice/56-concept-question-bank.md), [Ch 57](part-8-interview-practice/57-plsql-question-bank.md) |
| 14 | Mock and revise | [Ch 58](part-8-interview-practice/58-design-and-architecture-question-bank.md), [Ch 59](part-8-interview-practice/59-scenario-and-troubleshooting-questions.md), [Ch 60](part-8-interview-practice/60-mock-interviews.md) |

### 30 days: full scratch to advanced

| Days | Focus | Chapters |
|---|---|---|
| 1 to 3 | Foundations | [Ch 1](part-1-foundations/01-what-is-a-database.md) to [Ch 5](part-1-foundations/05-data-types-and-null.md) |
| 4 to 8 | SQL basics | [Ch 6](part-2-sql-basics/06-ddl-and-constraints.md) to [Ch 13](part-2-sql-basics/13-subqueries.md) |
| 9 to 12 | Advanced SQL | [Ch 14](part-3-advanced-sql/14-cte-and-recursive-queries.md) to [Ch 21](part-3-advanced-sql/21-classic-query-patterns.md) |
| 13 to 15 | Database design | [Ch 22](part-4-database-design/22-functional-dependencies.md) to [Ch 27](part-4-database-design/27-design-case-studies.md) |
| 16 to 19 | Internals and performance | [Ch 28](part-5-internals-and-performance/28-how-data-is-stored.md) to [Ch 34](part-5-internals-and-performance/34-backup-and-recovery.md) |
| 20 to 22 | Architecture and scale | [Ch 35](part-6-architecture-and-scale/35-database-architecture.md) to [Ch 41](part-6-architecture-and-scale/41-where-to-do-what.md) |
| 23 to 26 | PL/SQL | [Ch 42](part-7-plsql/42-plsql-basics.md) to [Ch 54](part-7-plsql/54-real-world-plsql-programs.md) |
| 27 to 29 | Practice and mocks | [Ch 55](part-8-interview-practice/55-sql-query-problems.md) to [Ch 60](part-8-interview-practice/60-mock-interviews.md) |
| 30 | Revise | [Last-Day Revision](cheat-sheets/last-day-revision.md) |

## How to use this book

**Each chapter follows one shape:** what you will learn, the teaching, common mistakes, interview questions, practice with hidden solutions, and a recap. The interview practice chapters are question banks and drills instead.

**Three habits matter most:**

1. **Write before you look.** Try each practice problem first.
2. **Say answers out loud.** Interviews test speech, not reading.
3. **Keep an error log.** Note each mistake, and retry it two days later.

**Which database?** The book teaches standard SQL first. It shows Oracle and PostgreSQL where they differ, with short notes for MySQL and SQL Server. PL/SQL always means Oracle PL/SQL.

**Your Oracle is 11g XE.** Syntax from 12c or later is labeled with its release, so you know what will not run on your machine. XE 11g also lacks partitioning, the result cache and AWR.

**The sample database** is a small shop with 8 tables, used in nearly every example. It holds deliberate trap rows, such as a department with no staff and an employee with no department. See [setup/sample-database.md](setup/sample-database.md).

| Folder | Holds |
|---|---|
| `setup/` | Scripts for the sample database on Oracle and PostgreSQL, and the table guide |
| `part-1-foundations/` to `part-8-interview-practice/` | The 60 chapters |
| `cheat-sheets/` | The 6 revision sheets |

## How the examples were checked

- **PostgreSQL and standard SQL:** 695 SQL blocks ran on PostgreSQL 18, including the multi-session lock, deadlock and isolation demos. The results you see for those blocks are real output.
- **Oracle and PL/SQL were not run.** 234 Oracle blocks, including all the PL/SQL, had static checks only: syntax patterns, block structure and column names. The Oracle setup scripts were not run either.
- **Oracle results:** 69 Oracle results were confirmed through an equivalent query on PostgreSQL. The other 50 are worked out, not run, so treat them as expected results, not proof.
- **MySQL and SQL Server notes were not run.** That covers the 4 code blocks for those engines, and all the tables.
- **27 blocks are skeletons,** shown for their shape, and were not run.
- **Version and licensing facts** are stated as of October 2026, and they age.
- **No independent review took place.** Nobody outside the writing process has checked the book for gaps or errors.

So run the Oracle examples yourself as you learn. If an Oracle example fails, treat the failure as a real finding.
