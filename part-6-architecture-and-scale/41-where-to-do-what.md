# 41. Where to Do What: The Decision Guide

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** Parts 2 to 5, and [Chapter 39](39-nosql-and-choosing-a-database.md)

> **In one line:** Most senior interview questions are not "how", but "where should this live, and why", and one repeatable method answers all of them.

## What you will learn

- A method for every "where should this live" question
- Application logic vs database logic
- Constraint vs trigger, view vs materialized view vs cache
- Index vs partition vs cache vs replica
- The scaling ladder, and how to answer "the database can't keep up"
- One master table to re-read the night before

## The method

Use the same five steps every time. Say them out loud.

1. **Name** the rule or workload.
2. **Ask who else touches this data.** One app, or many?
3. **Compare** correctness, speed, cost and operational burden.
4. **Pick one.**
5. **Say what would change your mind.**

That last step is what makes an answer sound senior.

## Application or database?

**A trigger** is code that runs automatically on a write. **A stored procedure** is a named action with several steps. PL/SQL starts in [Chapter 42](../part-7-plsql/42-plsql-basics.md), and this chapter needs only those definitions.

**The rule of thumb: data rules live in the database. Orchestration and calls to other systems live in the application.**

| Put it in the database | Put it in the application |
|---|---|
| Rules that must hold for every writer | User interface logic and messages |
| Filtering, joining, sorting, aggregating | Formatting and localization |
| Set-based bulk changes | Calls to other services |
| Keys and referential integrity | Workflow and orchestration |

**When would you move logic out of stored procedures and into the application?** When it needs to call other systems, needs frequent release and testing with the app, or needs to scale out, because database CPU is the hardest thing to add. Keep it in the database when many applications share the rule, or when it is set-based work on a lot of data, where moving the data out would be slow.

### Constraint or trigger?

**Constraint first.** `NOT NULL`, `CHECK`, `UNIQUE` and `FOREIGN KEY` are declarative, always on, and safe under concurrency.

```sql norun
ALTER TABLE products ADD CONSTRAINT prod_stock_ck CHECK (stock_qty >= 0);
```

**Use a trigger only for what a constraint cannot declare,** such as an audit trail or a cross-row rule. A trigger-based rule can still race unless it locks, because two transactions cannot see each other's uncommitted rows.

**When is a trigger the right tool?** Audit columns, a change history, keeping a derived value in step, or an `INSTEAD OF` trigger on a view.

**When is it a mistake?** Business workflows, sending email, calling a remote service, or chains of triggers that nobody can follow. A trigger runs inside the user's transaction, so slow or remote work delays the commit, and can fail it.

### Application validation or constraint?

**Do both.** The application gives friendly messages, and the constraint gives the guarantee.

**Two application servers insert at the same moment. Where do you enforce uniqueness?** In the database, with a unique constraint. A `SELECT`-then-`INSERT` check in the application races, and only the constraint closes the gap ([Chapter 18](../part-3-advanced-sql/18-advanced-dml.md)).

### Slow or remote work

Do not do it in a trigger. Publish an event instead: a table the application polls (the outbox pattern, [Chapter 38](38-sharding-and-distributed-databases.md)), or Oracle Advanced Queuing, where the enqueue commits with the transaction.

## Where should the work happen?

**Should filtering and pagination happen in the database or in the application?** In the database. Fetching a million rows to show 20 wastes the network and memory. Filter, join, sort, aggregate and paginate in the database. Format and localize in the application.

**Set-based beats row by row.** One `UPDATE` beats a loop of updates, from the application or from PL/SQL. N+1 queries are the same mistake ([Chapter 31](../part-5-internals-and-performance/31-query-tuning-playbook.md)).

**Transactions belong in the service layer:** short, with no network call inside. The application owns retries for deadlocks and serialization failures.

## Derived values

| Option | Fresh? | Use when |
|---|---|---|
| Compute at read time | Always | Reads are rare, or it is cheap |
| Generated column | Always | It is a same-row calculation |
| Trigger-maintained column | Always | It must be current, and reads are frequent |
| Materialized view | Stale until refresh | An expensive report |
| CDC into another store | Slightly behind | Another system needs it |

Stay normalized until a measured need says otherwise ([Chapter 24](../part-4-database-design/24-denormalization-and-trade-offs.md)).

## View, materialized view, summary table or cache?

| | View | Materialized view | Summary table | Cache |
|---|---|---|---|---|
| Stores data | No | Yes | Yes | Yes, in memory |
| Freshness | Always current | Until refresh | What your code does | Until expiry |
| Who maintains it | Nobody | The database | You | You |
| Speed gain | None by itself | Large | Large | Largest |

**When would you use a materialized view instead of a cache?** When the expensive part is a SQL aggregate, staleness of minutes is fine, and you want the database to do the upkeep. A cache suits repeated identical reads at very high rates, by key. A cache also adds invalidation, and a cold start problem.

**CTE, subquery, temp table or view?** The scope decides it ([Chapter 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md)). One extra rule: a temporary table gives the optimizer real statistics.

## Index, partition, cache or replica?

Each fixes a different bottleneck.

| Tool | Fixes | Does not fix |
|---|---|---|
| **Index** | Finding few rows | Scanning most of a table |
| **Partition** | Retention, and pruning large scans | Slow single-row lookups |
| **Cache** | Repeated identical reads | Writes, or varied queries |
| **Replica** | Read volume, and workload isolation | Writes, or slow queries |
| **Shard** | Write volume and data size | Everything else, and it adds much complexity |

**A dashboard is slow. Index, materialized view, cache or read replica?** First look at the plan. If it scans a lot to find few rows, add an index. If it aggregates a lot and staleness is fine, use a materialized view. If many users load the same thing, cache it. If it competes with OLTP traffic, move it to a replica. Partitioning a table does not help a query that already uses an index well.

## Diagnose before scaling

Is the pressure from reads or writes? Which resource is saturated: CPU, IOPS, locks, connections or storage?

Use wait events, `pg_stat_activity`, `pg_stat_statements`, AWR or ASH, and slow query logs.

### The scaling ladder

Climb from the bottom, cheapest first.

```text
Sharding                               last resort
Vertical partitioning, a separate DB   for one hot workload
Bigger hardware
---------------------------------------
Writes:  batch, remove unused indexes
Size:    archive, partition
Reads:   materialized view, cache, read replicas
---------------------------------------
Everything: fix the query, add the right index, fix the connection pool
```

### Two classic answers

**"The database can't keep up. What do you do?"**

First separate reads from writes, and find the saturated resource. Is it one bad query, connections, locks, or real volume? Fix the top queries, indexes and pool first. Then climb the ladder according to what is under pressure. I would not shard until I had proved the rest was not enough.

**"Our reads have gotten slow. What do you do?"**

What changed, and which queries? Then check plans, statistics, data growth and cache hit rate. Then fix what I find, and only then consider a cache or replicas.

## More decisions

### Reporting

| Size of the work | Where |
|---|---|
| Tiny ad hoc checks | Production |
| Light reports | A read replica |
| Heavy or historical work | A data warehouse ([Chapter 26](../part-4-database-design/26-data-warehouse-design.md)) |

### Bulk changes

Pick by row count, lock impact and replication lag.

| Option | Use when |
|---|---|
| One statement in a quiet window | It is small enough |
| Small committed batches | The table is live |
| Create and swap | Most rows change |
| Partition exchange or drop | The data is partitioned |

### Schema changes

Use online DDL when the engine supports it. Otherwise use **expand and contract**: add the new, write to both, backfill, switch reads, then remove the old ([Chapter 25](../part-4-database-design/25-schema-design-patterns.md)).

### Scheduled work

**Would you run a nightly job with `DBMS_SCHEDULER` or an external scheduler?** Use the database scheduler for data-only jobs that should run with the database. Use an external scheduler for jobs that span systems, because it can see everything, and handle dependencies.

### Queues

A database table with `FOR UPDATE SKIP LOCKED` ([Chapter 33](../part-5-internals-and-performance/33-locks-deadlocks-and-mvcc.md)) suits modest volume, and keeps the enqueue in your transaction. A message broker wins at high volume, with fan-out and replay.

### Search

`LIKE` for simple prefix matches. Built-in full-text search for most applications. A search engine, kept in sync by CDC, for relevance at scale.

### Files

**Should uploaded files be stored in the database?** Usually not. Store the bytes in object storage, and the path and metadata in the database. Use a BLOB only for small files that must stay transactionally consistent with the row.

### JSON or columns?

Real columns for fields you filter, join or constrain. JSON for sparse or truly variable attributes ([Chapter 20](../part-3-advanced-sql/20-modern-sql.md)).

### Identifiers

A sequence or identity column with one primary. UUIDv7 or Snowflake-style ids when many writers generate ids.

### Removing data

| Option | Use when |
|---|---|
| Hard delete | Rows can go, and rules allow it |
| Soft-delete flag | Users can undo, or rows are still referenced |
| Archive table | Old rows are rarely read |
| Partition drop | Retention is time-based |

### Audit trails

Use the database's audit feature for security questions. Use a trigger for a simple change history. Use CDC for a complete history at no cost inside the transaction.

### Multi-tenancy

**Should a multi-tenant application filter by tenant in code or in the database?** Both, if the data is in shared tables. Code alone means one forgotten `WHERE` leaks data. Row-level security ([Chapter 40](40-database-security.md)) enforces it in the database. Options for layout are shared tables with `tenant_id`, a schema per tenant, or a database per tenant.

### Security

Application checks for what a user may do. Row-level security for which rows they may see. TDE protects files on disk, and application-level encryption protects data even from a DBA ([Chapter 40](40-database-security.md)).

### Cross-service consistency

One database when the data is tightly coupled. Then the outbox, saga or 2PC, by the rules in [Chapter 38](38-sharding-and-distributed-databases.md).

### Which datastore?

Relational by default. Others by the rules in [Chapter 39](39-nosql-and-choosing-a-database.md).

## The master table

Re-read this the night before.

| Choice | Pick this when | Pick that when | Warning sign you chose wrong |
|---|---|---|---|
| Constraint vs trigger | The rule can be declared: constraint | It cannot, or it is an audit: trigger | Bad data despite a trigger |
| App vs procedure | It calls other systems: app | Many apps share it, or it is set-based: procedure | Logic copied across services |
| View vs materialized view | Must be current: view | Expensive and can be stale: materialized view | Users complain about old numbers |
| Materialized view vs cache | A SQL aggregate: materialized view | Same reads at a huge rate: cache | Cache hit rate is low |
| Index vs partition | Find few rows: index | Retention, or huge scans: partition | Partitioning made lookups slower |
| Replica vs shard | Read pressure: replica | Write or size limit: shard | Cross-shard queries everywhere |
| Normalize vs denormalize | The default: normalize | A measured read problem: denormalize | Copies drift |
| Column vs JSON | You filter on it: column | Variable attributes: JSON | Queries digging inside JSON |
| Table queue vs broker | Modest volume: table | High volume or fan-out: broker | Workers fighting over rows |
| Database vs object storage | Small, transactional: database | Files: object storage | Backups grow huge |
| Hard vs soft delete | Rows can go: hard | Undo or history needed: soft | Every query forgets the flag |
| Pessimistic vs optimistic | Short, contended: pessimistic | Long, rarely conflicts: optimistic | Constant retries, or long lock waits |

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Answer with one tool at once | It sounds like a guess | Ask what the bottleneck is |
| Shard early | Huge cost and complexity | Climb the ladder |
| Enforce uniqueness in code | A race condition | Use a unique constraint |
| Put business workflows in triggers | Hidden, slow, hard to debug | Keep them in the application |
| Add a read replica for slow queries | The queries are still slow | Fix the queries |
| Partition to speed up lookups | It may slow them down | Use an index |
| Store files in the database by habit | Backups and memory suffer | Use object storage |
| Fetch all rows, then filter in the app | Wasted network and memory | Filter in SQL |

## Interview questions

**Q1. When would you move logic out of stored procedures and into the application?**

When it needs to call other systems, when it changes often with the application, or when it needs to scale out, since database CPU is the hardest thing to add. I keep it in the database when many applications must obey it, or when it is set-based work on a lot of data.

**Q2. Would you enforce this rule with a constraint or a trigger?**

A constraint if it can be declared, because constraints are always on and safe under concurrency. A trigger only for what a constraint cannot express, and I would watch for races, because a trigger cannot see other sessions' uncommitted rows.

**Q3. When is a trigger the right tool, and when is it a mistake?**

Right for audit trails, derived columns and `INSTEAD OF` views. A mistake for business workflows or remote calls, because it runs inside the user's transaction, and it is hidden from people reading the code.

**Q4. The database can't keep up. What do you do?**

Separate reads from writes, and find the saturated resource: CPU, I/O, locks or connections. Fix the top queries, indexes and pool first. Then, for reads, use a materialized view, a cache and replicas. For size, archive and partition. For writes, batch and remove unused indexes. Sharding is last.

**Q5. A dashboard is slow. Index, materialized view, cache or read replica?**

I check the plan first. Index if it finds few rows the hard way. Materialized view if it aggregates a lot and can be a little stale. Cache if many users load the same thing. Replica if it competes with OLTP traffic.

**Q6. Two application servers insert at the same moment. Where do you enforce uniqueness?**

With a unique constraint in the database. Any check in the application races, because neither server can see the other's uncommitted row.

**Q7. Should filtering and pagination happen in the database or in the application?**

In the database. It has the indexes, and fetching everything to show 20 rows wastes the network and memory.

**Q8. Should uploaded files be stored in the database?**

Usually not. Object storage is cheaper, and it keeps backups and the buffer cache small. The database keeps the path and metadata. A BLOB is fine for small files that must commit with the row.

**Q9. Should a multi-tenant application filter by tenant in code or in the database?**

For shared tables, I enforce it in the database with row-level security, since one forgotten `WHERE` in code is a data leak. Code can still filter too, for clarity.

## Practice

For each one, use the five-step method. Pick one, and say what would change your mind.

**1. You must keep a history of every salary change.**

<details>
<summary>Show solution</summary>

A trigger writing to a history table: it catches every writer, including ad hoc updates. I would move to CDC if the write cost mattered, or if another system needed the history.

</details>

**2. The home page shows the same top 10 products to everyone, a thousand times a second.**

<details>
<summary>Show solution</summary>

A cache, with a short expiry, because the reads are identical and very frequent. If it were one user's personalized data, a cache would help far less.

</details>

**3. A nightly report on three years of orders slows down the live site.**

<details>
<summary>Show solution</summary>

Move it to a read replica now, and to a warehouse if it grows. Replicas isolate the workload. An index would not help if it really reads three years of data.

</details>

**4. Each order must have at least one line.**

<details>
<summary>Show solution</summary>

A `CHECK` cannot read another table, and a plain trigger can race. So enforce it in the application or a procedure that inserts the order and its lines in one transaction, and add a reconciliation query. On engines with deferrable constraints or assertions, I would look at those too.

</details>

## Recap

- Name the workload, ask who else touches the data, compare, pick, and say what would change your mind.
- Data rules go in the database. Orchestration goes in the application.
- Constraint first, trigger only when it cannot be declared.
- Index finds few rows, partition manages size, cache repeats reads, replica spreads reads.
- Diagnose before scaling. Fix queries before buying hardware.
- Sharding is the last step.

**Next:** [Chapter 42: PL/SQL basics](../part-7-plsql/42-plsql-basics.md)
