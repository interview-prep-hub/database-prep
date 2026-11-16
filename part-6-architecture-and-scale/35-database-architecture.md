# 35. Inside a Database Server

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 34](../part-5-internals-and-performance/34-backup-and-recovery.md)

> **In one line:** Every transactional database is shared memory, background workers and files on disk, and the differences between engines are mostly in the details.

## What you will learn

- What happens during a `SELECT`, and during an `UPDATE` and `COMMIT`
- Oracle's instance and database, SGA, PGA, background processes and files
- PostgreSQL and MySQL InnoDB architecture
- Why PostgreSQL needs a connection pooler
- Shared memory, shared disk and shared nothing

## The shape every engine shares

```text
 Clients
    |
 Server processes or threads
    |
 Shared memory: buffer pool, lock table, log buffer
    |
 Background workers: write data pages, write the log, take checkpoints, clean up
    |
 Files: data files, log files
```

### The same words mean different things

| Word | Oracle | PostgreSQL | MySQL |
|---|---|---|---|
| Instance | Memory and processes | A running server | A running server |
| Database | The files | One of many in a cluster | Same as a schema |
| Schema | A user and its objects | A namespace in a database | Same as a database |
| Cluster | RAC instances | One data directory | Replication group |

### Two journeys

**A `SELECT`:** look for the block in memory. Read it from disk only on a miss.

**An `UPDATE` and `COMMIT`:**

1. Find the block in memory, reading it if needed.
2. Write the old value to undo.
3. Change the block in memory, and mark it dirty.
4. Record the change in the log buffer.
5. At `COMMIT`, flush the log buffer to disk. Now the change is durable.
6. Later, a background worker writes the dirty block to the data file.

The data files can be behind. The log is what makes the commit safe ([Chapter 34](../part-5-internals-and-performance/34-backup-and-recovery.md)).

## Oracle

### Instance vs database

**What is the difference between an Oracle instance and a database?** The **instance** is memory plus background processes, and it disappears at shutdown. The **database** is the files on disk. Normally one instance serves one database. In **RAC** (Real Application Clusters), many instances serve one database.

```text
                     INSTANCE
+---------------------------------------------------+
|  SGA (shared memory)                              |
|  +---------------+ +-----------+ +---------------+|
|  | Buffer cache  | |Shared pool| |Redo log buffer||
|  +---------------+ +-----------+ +---------------+|
|                                                   |
|  Background: PMON  SMON  DBWn  LGWR  CKPT  ARCn   |
+---------------------------------------------------+
          |            |            |
      +--------+  +---------+  +-----------+
      | Data   |  | Control |  | Redo log  |     DATABASE (files)
      | files  |  | files   |  | files     |
      +--------+  +---------+  +-----------+
```

### SGA and PGA

**The SGA (System Global Area)** is shared by all processes.

| Part | Holds |
|---|---|
| Buffer cache | Data blocks |
| Shared pool | Library cache (shared cursors), dictionary cache, result cache |
| Redo log buffer | Changes not yet on disk |
| Large pool | Shared server memory, backup buffers |
| Java pool | Java code |
| In-Memory area | Optional column store |

**The PGA (Program Global Area)** is private to each server process: sort and hash work areas, and the private SQL area. The **UGA** holds session state. It sits in the PGA under dedicated server, and in the SGA under shared server.

**Memory settings.** `MEMORY_TARGET` lets Oracle manage both together. `SGA_TARGET` and `PGA_AGGREGATE_TARGET` set two separate targets.

**Where parsing happens.** The library cache holds shared cursors. A statement goes through a syntax check, a semantic check and a library cache lookup. A match is a soft parse, and otherwise it is a hard parse ([Chapter 30](../part-5-internals-and-performance/30-execution-plans-and-the-optimizer.md)).

### Background processes

| Process | Job |
|---|---|
| **PMON** | Detects dead processes (from 12.2, it delegates clean-up) |
| **LREG** | Registers with the listener |
| **SMON** | Instance recovery and clean-up |
| **DBWn** | Writes dirty blocks to data files |
| **LGWR** | Writes redo to the log files |
| **CKPT** | Updates control file and data file headers, and signals DBWn |
| **ARCn** | Archives filled redo logs |
| **MMON** | Collects AWR snapshots |

**When does LGWR write?** At commit, at a log switch, every 3 seconds, when the redo buffer is one-third full or holds 1 MB, and before DBWn writes a modified buffer. That last rule is write-ahead logging in action.

**CKPT writes no data blocks and no redo blocks.** DBWn writes data, LGWR writes redo, and CKPT does the bookkeeping.

**How many?** One PMON per instance. One DBW0 is adequate for most systems.

**Redo and undo.** Redo lives in the redo log files, and undo in the undo tablespace. The **SCN** (System Change Number) is Oracle's logical clock: it stamps every commit, and both read consistency and recovery use it.

### Physical files

| File | Purpose |
|---|---|
| Data files | Tables and indexes |
| Control files | The database's map. Multiplexed, because losing them all stops the database |
| Online redo logs | Changes, in groups and members |
| Archived redo logs | Copies of filled logs, for recovery |
| SPFILE | Binary parameters, changed with `ALTER SYSTEM`. PFILE is the text form |
| Password file | Remote `SYSDBA` login |
| Alert log, trace files | Diagnostics |

### Startup and shutdown

**Explain what happens at STARTUP NOMOUNT, MOUNT and OPEN.**

| Stage | What happens | Needed for |
|---|---|---|
| `NOMOUNT` | Reads the parameter file, allocates the SGA, starts background processes | Creating a database |
| `MOUNT` | Reads the control files | Renaming data files, media recovery |
| `OPEN` | Opens data files and online redo logs | Normal use |

| Shutdown mode | Behavior |
|---|---|
| `NORMAL` | Waits for users to disconnect |
| `TRANSACTIONAL` | Waits for transactions to end |
| `IMMEDIATE` | Rolls back open transactions |
| `ABORT` | Stops at once |

Only `ABORT` leaves instance recovery for the next startup, which runs automatically.

### Logical storage

```text
Tablespace  >  Segment  >  Extent  >  Block
(USERS)        (the EMPLOYEES table)  (a run of blocks)  (8 KB)
```

Every database has the tablespaces `SYSTEM`, `SYSAUX`, `UNDO` and `TEMP`.

**Inside a block:** `PCTFREE` is space kept for future updates. **ITL** and `INITRANS` are transaction slots in the block header.

**What is the difference between row chaining and row migration?** **Chaining:** a row is too big for one block, so it spans several. **Migration:** a row grew and no longer fits, so it moves, leaving a forwarding pointer. Both cost extra reads. Find them with the `table fetch continued row` statistic. Fix migration by rebuilding the table and raising `PCTFREE`. Chaining needs a bigger block size.

**Oracle multitenant.** A **CDB** (container database) holds **PDBs** (pluggable databases). The non-CDB architecture is desupported from 21c. Your XE 11g predates this.

### Connections on Oracle

The **listener** hands a client to a server process.

| Mode | How it works |
|---|---|
| Dedicated server | Each session has its own process |
| Shared server | Dispatchers and a request queue in the large pool |
| DRCP | A pool of server processes, for many short connections |

## PostgreSQL

The **postmaster** forks one backend **process** per connection.

Background processes: checkpointer, background writer, WAL writer, autovacuum launcher and workers, archiver.

**`shared_buffers`** sits on top of the OS page cache, so a page can be cached twice. The docs suggest 25 percent of RAM as a starting value.

**On disk:** `base` (tables and indexes), `pg_wal` (the log), `pg_xact` (commit status). Old row versions stay in the table itself, which is why `VACUUM` exists.

**Settings that trip people up.** `work_mem` applies **per sort or hash operation**, so the total can be many times the setting. `effective_cache_size` allocates nothing: it only tells the planner how much cache to expect.

## MySQL and InnoDB

MySQL has two layers: the SQL server layer, and a pluggable storage engine, InnoDB by default. Each connection is a **thread**, not a process.

**In memory:** a buffer pool with midpoint-insertion LRU, so one big scan does not push out hot pages, plus a log buffer.

**On disk:** file-per-table tablespaces, redo log, undo tablespaces and doublewrite files, which protect against torn pages.

**MySQL's two logs.** The **binary log** belongs to the server layer, and serves replication and point-in-time recovery. The **redo log** belongs to InnoDB, and serves crash recovery. An internal two-phase commit keeps them in step.

## SQL Server, in brief

One process with many threads, scheduled by SQLOS. Data files (MDF, NDF) and a transaction log (LDF). 8 KB pages in 64 KB extents. `tempdb` is shared, and it holds row versions.

## Comparison

| | Oracle | PostgreSQL | MySQL InnoDB | SQL Server |
|---|---|---|---|---|
| Connection | Process (or shared) | Process | Thread | Thread |
| Page size | 8 KB default | 8 KB | 16 KB | 8 KB |
| Log | Redo | WAL | Redo, plus binlog | Transaction log |
| Old versions | Undo | In the table | Undo | `tempdb` |
| Table storage | Heap | Heap | Clustered on the PK | Heap or clustered |

## Connection pooling

**Why does PostgreSQL need a connection pooler?** A new connection costs TCP and TLS setup, authentication, and on PostgreSQL a whole process with its own memory. `max_connections` is typically 100.

**Pool sizing.** Start from (cores x 2) + effective spindles, then measure. A small pool usually wins, because connections beyond what the CPU can run only add queueing.

**Connection multiplication.** Two hundred app instances with a pool of 50 each is 10,000 connections, far above `max_connections`. **The fix** is a smaller pool per instance, and a central pooler such as PgBouncer.

### PgBouncer modes

| Mode | A client keeps a server connection until |
|---|---|
| Session | It disconnects |
| Transaction | Commit or rollback |
| Statement | Each statement ends |

Use transaction mode when connection count is the problem.

**What breaks in transaction mode?** Anything tied to a session: `SET`, `LISTEN`, `WITH HOLD` cursors, SQL `PREPARE`, session advisory locks, and most temp tables. A plain `SET` leaks to the next client, while `SET LOCAL` ends with the transaction.

**Timeouts that protect the pool:** `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`. Never hold a transaction open across a network call.

## Parallel architectures

| Architecture | What is shared | Limit |
|---|---|---|
| **Shared memory** | Many cores, one RAM | Memory bandwidth |
| **Shared disk** | Many servers, one storage | Interconnect and lock traffic |
| **Shared nothing** | Each node has its own disk | Cross-node queries |

**RAC** is the shared disk example. **Cache Fusion** ships blocks between instances over the interconnect. Applications where many instances touch the same blocks do not scale well on RAC.

**Speedup vs scaleup.** Speedup: more hardware, same job, less time. Scaleup: more hardware, bigger job, same time. Results fall short of linear, because of startup costs, interference and skew.

**Inter-query parallelism** (many queries at once) is what OLTP needs. **Intra-query parallelism** (one query split up) is what analytics needs.

**Aggregating across nodes: never average averages.** Each node returns `SUM` and `COUNT`, and the coordinator divides.

```text
Node 1: 10 orders, average 100, so sum 1000
Node 2: 90 orders, average 200, so sum 18000

Wrong: (100 + 200) / 2 = 150
Right: (1000 + 18000) / (10 + 90) = 190
```

### Updating a very large table in parallel

**How would you do it from PL/SQL?** `DBMS_PARALLEL_EXECUTE` (11.2) splits a big table into chunks by `ROWID`, a number column or SQL, runs one statement per chunk through scheduler jobs, and commits each chunk.

```sql oracle
BEGIN
  DBMS_PARALLEL_EXECUTE.CREATE_TASK('raise_task');

  DBMS_PARALLEL_EXECUTE.CREATE_CHUNKS_BY_ROWID(
    task_name   => 'raise_task',
    table_owner => USER,
    table_name  => 'EMPLOYEES',
    by_row      => TRUE,
    chunk_size  => 10000);

  DBMS_PARALLEL_EXECUTE.RUN_TASK(
    task_name      => 'raise_task',
    sql_stmt       => 'UPDATE employees SET salary = salary * 1.01
                       WHERE rowid BETWEEN :start_id AND :end_id',
    language_flag  => DBMS_SQL.NATIVE,
    parallel_level => 4);

  DBMS_PARALLEL_EXECUTE.DROP_TASK('raise_task');
END;
/
```

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Use instance and database as synonyms | On Oracle they differ | Instance is memory, database is files |
| Say COMMIT writes the data files | It flushes the log | LGWR writes at commit, DBWn later |
| Say CKPT writes data | It does the bookkeeping | DBWn writes data |
| Raise `max_connections` to fix load | More queueing, more memory | Use a pooler |
| Set a huge `work_mem` globally | Memory runs out | It is per operation |
| Use transaction pooling with session features | State leaks or breaks | Use `SET LOCAL` |
| Average averages across nodes | The wrong answer | Combine sums and counts |

## Interview questions

**Q1. What is the difference between an Oracle instance and a database?**

The instance is memory and background processes, and it goes away at shutdown. The database is the files on disk. Normally one instance serves one database, and in RAC many instances serve one database.

**Q2. Describe the SGA and the PGA. What lives in each?**

The SGA is shared: the buffer cache, shared pool, redo log buffer and large pool. The PGA is private to a server process: sort and hash areas and session data.

**Q3. Name the main Oracle background processes and what each does. How many PMON and DBWR processes should a database have?**

PMON cleans up after failed processes, SMON handles instance recovery, DBWn writes dirty blocks, LGWR writes redo, CKPT updates headers, and ARCn archives logs. There is one PMON per instance, and one DBW0 is enough for most systems.

**Q4. Explain what happens at STARTUP NOMOUNT, MOUNT and OPEN.**

`NOMOUNT` reads the parameter file, allocates the SGA and starts the background processes. `MOUNT` reads the control files. `OPEN` opens the data files and redo logs, so users can connect.

**Q5. What happens, step by step, when you run an UPDATE and then COMMIT in Oracle?**

The server process finds the block in the buffer cache, reading it from disk if needed. It writes undo, changes the block, and writes redo to the log buffer. At `COMMIT`, LGWR flushes redo to disk, and that makes it durable. DBWn writes the dirty block later.

**Q6. What is the difference between row chaining and row migration?**

Chaining is a row too big for one block, so it spans several. Migration is a row that grew and moved, leaving a pointer. Both add reads. I fix migration by rebuilding the table and raising `PCTFREE`.

**Q7. Why does PostgreSQL need a connection pooler, and what breaks in transaction pooling mode?**

Each connection is a full process, so many connections are expensive. A pooler shares a few server connections among many clients. In transaction mode, session state breaks: `SET`, `LISTEN`, SQL `PREPARE`, session advisory locks, and most temp tables.

**Q8. Two hundred app instances with a pool of 50 each are killing Postgres. What is wrong, and how big should the pool be?**

That is 10,000 possible connections. Each pool should be far smaller, and a central PgBouncer in transaction mode should share a small number of real connections, sized from CPU cores, then measured.

**Q9. Compare shared memory, shared disk and shared nothing architectures.**

Shared memory is one big machine, limited by memory bandwidth. Shared disk is many servers on one storage, like RAC, limited by interconnect traffic. Shared nothing gives each node its own disk, so it scales best, but cross-node queries and transactions are expensive.

## Practice

**1. Which process writes the redo log? Which writes data files? Which updates control file headers?**

<details>
<summary>Show solution</summary>

LGWR, DBWn and CKPT.

</details>

**2. You need to rename a data file. Which startup stage do you use?**

<details>
<summary>Show solution</summary>

`MOUNT`: the control files are open, but the data files are not.

</details>

**3. Node A has 40 rows averaging 50. Node B has 60 rows averaging 100. What is the true average?**

<details>
<summary>Show solution</summary>

`(2000 + 6000) / 100 = 80`.

</details>

**4. Your app sets `search_path` with `SET` behind PgBouncer in transaction mode. What goes wrong?**

<details>
<summary>Show solution</summary>

The setting stays on the server connection, and leaks to the next client that gets it. Use `SET LOCAL` inside a transaction instead.

</details>

## Recap

- The instance is memory and processes. The database is files.
- The SGA is shared, and the PGA is private.
- LGWR writes at commit. DBWn writes data later. CKPT does the bookkeeping.
- `NOMOUNT` needs the parameter file, `MOUNT` the control files, and `OPEN` the data files.
- PostgreSQL uses a process per connection, so use a pooler.
- Transaction pooling breaks session state.
- Never average averages.

**Next:** [Chapter 36: Partitioning](36-partitioning.md)
