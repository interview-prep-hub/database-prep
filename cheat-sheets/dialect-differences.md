# Dialect Differences: Oracle, PostgreSQL, MySQL and SQL Server Side by Side

**Level:** Intermediate | **Interview priority:** Should know | **Before this:** Parts 2, 3 and 5

> **In one line:** The same idea is often spelled differently, and sometimes means something different, on each engine.

**Baseline, as of October 2026:** Oracle 11g XE (your machine), 19c, 21c, 23ai and 26ai. PostgreSQL 18 (your machine) and 19. MySQL 8.4 LTS, 9.7 LTS and 26.7. SQL Server 2022 and 2025.

Rows give the release a feature arrived in. Anything from 12.1 onward does not run on your 11g XE. The MySQL and SQL Server notes here were not run.

## Words that do not translate

| Word | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Schema | A user | A namespace in a database | Another word for database | A namespace in a database |
| Procedural language | PL/SQL | PL/pgSQL | Stored programs | T-SQL |

**Case rules.** Unquoted identifiers fold to upper case on Oracle, and lower case on PostgreSQL. MySQL table-name case depends on the file system and `lower_case_table_names`. SQL Server follows the collation. String comparison is case-sensitive by default on Oracle and PostgreSQL, and case-insensitive under the usual default collations of MySQL and SQL Server.

## Core types

| Need | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Exact decimal | `NUMBER` | `NUMERIC` | `DECIMAL` | `DECIMAL` |
| String | `VARCHAR2` | `VARCHAR`, `TEXT` | `VARCHAR`, `TEXT` | `VARCHAR`, `NVARCHAR` |
| Boolean | SQL type only from 23ai | `BOOLEAN` | `TINYINT(1)` alias | `BIT` |
| `DATE` holds | Date and time | Date only | Date only | Date only |
| `5 / 2` | 2.5 | 2 | 2.5 | 2 |

## Small syntax switches

| Task | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Select with no table | `FROM dual` before 23ai | No `FROM` | No `FROM` | No `FROM` |
| Now | `SYSDATE` | `NOW()` | `NOW()` | `GETDATE()` |
| NULL replacement | `NVL` | `COALESCE` | `IFNULL` | `ISNULL` |
| Recursive CTE | `WITH` | `WITH RECURSIVE` | `WITH RECURSIVE` | `WITH` |
| Sequence value | `seq.NEXTVAL` | `nextval('seq')` | None | `NEXT VALUE FOR seq` |
| Table from a query | `CREATE TABLE AS SELECT` | `CREATE TABLE AS SELECT` | `CREATE TABLE AS SELECT` | `SELECT ... INTO new_table` |
| Regular expression | `REGEXP_LIKE` | `~` | `REGEXP` | `REGEXP` functions in 2025 |
| Plan control | Hints | No core hints (19 adds `pg_plan_advice`) | Hints | Query hints |

`COALESCE` works on all four.

**Empty string and NULL order.** `''` is NULL only on Oracle, and Oracle's documentation warns this may change, so do not rely on it. NULLs sort as the highest value on Oracle and PostgreSQL, and the lowest on MySQL and SQL Server.

## Concatenation

| Engine | Operator | With NULL | `CONCAT` |
|---|---|---|---|
| Oracle | `\|\|` | NULL acts as empty | Exactly two arguments before 23ai, two or more from 23ai |
| PostgreSQL | `\|\|` | Gives NULL | Skips NULLs |
| MySQL | `\|\|` is logical OR, unless `PIPES_AS_CONCAT` is set | | Gives NULL if any argument is NULL. `CONCAT_WS` skips NULLs |
| SQL Server | `+`, and `\|\|` in 2025 | Both give NULL under the default setting | Treats NULL as empty (2012) |

## Row limiting

| Engine | Top 5 | Second page of 5 |
|---|---|---|
| Oracle, all releases | `ROWNUM <= 5` around an ordered subquery | `ROW_NUMBER` in a subquery, `rn BETWEEN 6 AND 10` |
| Oracle 12.1 | `FETCH FIRST 5 ROWS ONLY` | `OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY` |
| PostgreSQL | `LIMIT 5`, or `FETCH FIRST` | `LIMIT 5 OFFSET 5` |
| MySQL | `LIMIT 5` | `LIMIT 5 OFFSET 5` |
| SQL Server | `TOP (5)` | `OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY`, which requires `ORDER BY` (2012) |

## Date difference

| Engine | Form | Result |
|---|---|---|
| Oracle | `d2 - d1` | Days as a `NUMBER`, with fractions when times differ |
| Oracle | `MONTHS_BETWEEN(d2, d1)` | Months |
| PostgreSQL | `d2 - d1` on dates | Integer days |
| PostgreSQL | `t2 - t1` on timestamps | An interval. `AGE` gives years and months |
| MySQL | `DATEDIFF(end, start)` | Days. `TIMESTAMPDIFF(unit, start, end)` for other units |
| SQL Server | `DATEDIFF(unit, start, end)` | Boundaries crossed, so 31 December to 1 January is one year |

## Changing data

| Task | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Update with a join | `MERGE`, a correlated subquery, or a key-preserved inline view. `FROM` from 23ai | `UPDATE ... FROM` | `UPDATE a JOIN b ON ... SET` | `UPDATE a SET ... FROM t a JOIN b` |
| Upsert | `MERGE` | `ON CONFLICT` (9.5), `MERGE` (15) | `ON DUPLICATE KEY UPDATE` | `MERGE` |
| Return changed rows | `RETURNING INTO` in PL/SQL | `RETURNING` | None | `OUTPUT` |
| String list | `LISTAGG` (11.2) | `STRING_AGG` | `GROUP_CONCAT`, cut at `group_concat_max_len` (1024) | `STRING_AGG` (2017) |
| Median | `MEDIAN`, or `PERCENTILE_CONT(0.5)`, as aggregate or window | `PERCENTILE_CONT(0.5)`, aggregate only | No built-in, use `ROW_NUMBER` and `COUNT` | `PERCENTILE_CONT` with a required `OVER` |
| Auto-number | Sequence plus trigger on 11g, `GENERATED AS IDENTITY` from 12.1 | `GENERATED AS IDENTITY`, preferred over `SERIAL` | `AUTO_INCREMENT` | `IDENTITY`, `SEQUENCE` |

Gaps in auto-numbers are normal on every engine, because a rolled-back insert does not return its number.

## TRUNCATE

| Question | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Rollback | No, implicit commit | Yes | No, implicit commit | Yes, inside a transaction |
| Identity counter | Sequence keeps its value | Kept, unless `RESTART IDENTITY` | Reset | Reset to the seed |
| Fires `DELETE` triggers | No | No, but has `ON TRUNCATE` triggers | No | No |
| Referenced by a foreign key | Refused (`ORA-02266`) | Needs `CASCADE`, or all tables named together | Refused | Refused |

## Triggers

| Engine | Model |
|---|---|
| Oracle | Row, statement, compound, `INSTEAD OF` and DDL |
| PostgreSQL | Row and statement, which call a trigger function |
| MySQL | Row only, no `INSTEAD OF` |
| SQL Server | Statement-level `AFTER` and `INSTEAD OF`, reading the `inserted` and `deleted` tables, so the code must handle many rows |

## Feature availability

| Feature | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| `FULL OUTER JOIN` | Yes | Yes | No, use `LEFT JOIN UNION RIGHT JOIN` | Yes |
| Set difference | `MINUS`, `EXCEPT` and `ALL` forms from 21c | `EXCEPT` | `EXCEPT` from 8.0.31 | `EXCEPT` |
| `NULLS FIRST` | Yes | Yes | No, sort on `CASE` | No, sort on `CASE` |
| `QUALIFY` | 26ai | No | No | No |
| `FILTER` | 26ai | 9.4 | No, use `CASE` | No, use `CASE` |
| `IGNORE NULLS` | Yes | 19 | Parsed, then an error | 2022 |
| `LATERAL` | 12.1, with `APPLY` | 9.3 | 8.0.14 | `CROSS APPLY`, `OUTER APPLY` |
| `MERGE` | Yes | 15 | No | Yes |
| `WITH TIES` | 12.1 | 13 | No | `TOP WITH TIES` |
| `WINDOW` clause | 21c | Yes | Yes | 2022 |
| `GROUPS` frames | 21c | 11 | No | No |
| `RANGE` with a numeric offset | Yes | Yes | Yes | No |
| `PIVOT` | 11.1 | No | No | Yes |
| Materialized views | Yes | Yes | No | Indexed views |
| `CHECK` enforced | Yes | Yes | From 8.0.16 | Yes |

`GREATEST` and `LEAST` return NULL if any argument is NULL on Oracle and MySQL, and ignore NULLs on PostgreSQL and SQL Server (2022).

## Transactions and errors

**DDL.** Oracle commits before and after every DDL statement, and MySQL commits implicitly too. PostgreSQL and SQL Server can roll back most DDL.

**Clients.** SQL*Plus waits for `COMMIT`. psql, the mysql client and SQL Server default to autocommit.

**After an error inside a transaction.** Oracle and MySQL normally undo only the failed statement, and the transaction continues. SQL Server usually does the same, unless `XACT_ABORT` is on. PostgreSQL marks the whole transaction failed, and every later statement gets SQLSTATE `25P02` until `ROLLBACK` or `ROLLBACK TO SAVEPOINT`.

**`SELECT INTO` in a routine:**

| Engine | No rows | Many rows |
|---|---|---|
| Oracle | `NO_DATA_FOUND` | `TOO_MANY_ROWS` |
| PL/pgSQL | Sets NULL, unless `STRICT` | First row, unless `STRICT` |
| MySQL | Warning | Error |
| T-SQL `SELECT @x = col` | Keeps the old value | Last returned row |

Error handling is `EXCEPTION WHEN` on Oracle and PostgreSQL, `BEGIN TRY` with `BEGIN CATCH` on SQL Server, and `DECLARE HANDLER` on MySQL. PostgreSQL functions cannot `COMMIT`, while procedures (11) can.

## Isolation

| | Oracle | PostgreSQL | MySQL InnoDB | SQL Server |
|---|---|---|---|---|
| Default | `READ COMMITTED` | `READ COMMITTED` | `REPEATABLE READ` | `READ COMMITTED`, with row versions only if `READ_COMMITTED_SNAPSHOT` is on |
| Levels | `READ COMMITTED`, `SERIALIZABLE`, read-only | All four names. `READ UNCOMMITTED` acts as `READ COMMITTED` | All four | All four plus `SNAPSHOT` |
| `REPEATABLE READ` means | Not offered | Snapshot isolation, no phantoms, write skew possible | Consistent reads plus next-key locks | Held shared locks, phantoms possible |
| `SERIALIZABLE` means | Snapshot isolation, write skew possible, `ORA-08177` | SSI since 9.1, fails with `40001` | Plain `SELECT` becomes `FOR SHARE` when autocommit is off | Key-range locks |

## Locks and MVCC

| | Oracle | PostgreSQL | MySQL InnoDB | SQL Server |
|---|---|---|---|---|
| Readers block writers | No | No | No, on plain reads | Yes, on default locking `READ COMMITTED` |
| Old versions live in | Undo | The table, until `VACUUM` | Undo logs, until purge | tempdb version store, or ADR persistent version store |
| Queue tool | `SKIP LOCKED` | `SKIP LOCKED` (9.5) | `SKIP LOCKED` (8.0) | `READPAST` hint |
| Lock escalation | Never | None, row locks are not kept in memory | Unnecessary | At 5,000 locks on one reference, to the table or partition, never a page |
| Deadlock victim | One statement rolled back (`ORA-00060`), transaction stays open | Whole transaction | Whole transaction | Whole transaction |

SQL Server 2025 optimized locking avoids most escalation, and is off by default per database.

| Error | Engine | Meaning | Retry? |
|---|---|---|---|
| `ORA-00060` | Oracle | Deadlock | Roll back, then yes |
| `ORA-08177` | Oracle | Cannot serialize | Yes |
| `ORA-01555` | Oracle | Snapshot too old | After a fix |
| `ORA-00054` | Oracle | Busy under `NOWAIT` or a timeout | Yes |
| `ORA-30036` | Oracle | Undo tablespace cannot extend | After a fix |
| `40001` | PostgreSQL | Serialization failure | Yes |
| `40P01` | PostgreSQL | Deadlock detected | Yes |
| `55P03` | PostgreSQL | Lock not available | Yes |
| `25P02` | PostgreSQL | Transaction already failed | Roll back first |
| `1213` | MySQL | Deadlock | Yes |
| `1205` | MySQL | Lock wait timeout | Yes |
| `1205` | SQL Server | Deadlock victim | Yes |
| `1222` | SQL Server | Lock request timeout | Yes |
| `3960` | SQL Server | Snapshot update conflict | Yes |

## Indexes

| Feature | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Partial | Function-based index that returns NULL for unwanted rows | `WHERE` | No | Filtered index |
| Expression | Function-based | Expression | Functional key parts (8.0.13) | Index on a computed column |
| Covering `INCLUDE` | Add columns to the key | 11 | Add to the key. InnoDB secondaries carry the primary key | Yes |
| Invisible | 11.1 | No | 8.0 | No |
| Bitmap | Enterprise Edition only | Built at run time | No | No |
| Hash | Hash clusters instead | Hash indexes | `MEMORY` tables. `USING HASH` on InnoDB gives a B-tree | Memory-optimized tables |
| Clustered | Index-organized table | One-time `CLUSTER`, or `REPACK` in 19 | Primary key | Clustered index |
| Skip scan | Yes | 18 | 8.0.13 | Not documented |

**Oracle NULL rule.** A B-tree index has no entry for a row whose key columns are all NULL. A bitmap index keeps those rows. So `WHERE col IS NULL` cannot use a single-column B-tree on `col`, and `COUNT(*)` can use an index only if a key column is `NOT NULL`. Fix it with a composite index such as `(col, 0)`. The other three engines store NULLs in indexes. Bitmap indexes are not on your 11g XE.

## Constraints

| Question | Oracle | PostgreSQL | MySQL InnoDB | SQL Server |
|---|---|---|---|---|
| Child index created for a foreign key | No | No | Yes | No |
| Actions | `ON DELETE CASCADE`, `SET NULL`, no `ON UPDATE` | All | No `SET DEFAULT`, and cascades do not fire triggers | All |
| Deferrable | Yes | Yes | No | No |
| `UNIQUE` with NULLs | Many all-NULL keys. Partly NULL composite keys with equal non-NULL values are duplicates | Many, and `NULLS NOT DISTINCT` (15) | Many | One. A filtered unique index allows many |

An unindexed Oracle foreign key takes a full table lock on the child when the parent key is changed or deleted. SQL Server refuses foreign keys that create multiple cascade paths. MySQL 8.4 `restrict_fk_on_non_standard_key` refuses foreign keys to non-unique or partial keys by default.

## Plans and monitoring

| Need | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Plan | `EXPLAIN PLAN FOR`, `DBMS_XPLAN.DISPLAY` | `EXPLAIN` | `EXPLAIN` | Estimated plan |
| Plan really used | `DBMS_XPLAN.DISPLAY_CURSOR` | `EXPLAIN (ANALYZE, BUFFERS)` | `EXPLAIN ANALYZE` (8.0.18) | Actual plan, `SET STATISTICS IO, TIME` |
| Running now | `V$SESSION`, `V$SQL` | `pg_stat_activity` | `performance_schema` | `sys.dm_exec_requests` |
| Blocking | `V$LOCK`, `BLOCKING_SESSION` | `pg_locks`, `pg_blocking_pids()` | `performance_schema.data_locks` | `sys.dm_tran_locks` |
| History | `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_` views, which need the Diagnostics Pack | `pg_stat_statements` extension | `sys` schema | `sys.dm_exec_query_stats` |

From PostgreSQL 18, `BUFFERS` is automatic under `ANALYZE`.

**Oracle wait events:**

| Event | Meaning |
|---|---|
| `db file sequential read` | Single-block read, usually index or rowid access |
| `db file scattered read` | Multi-block read, usually a full scan |
| `direct path read temp` | A sort or hash spilled to temp |
| `log file sync` | Commit waiting for LGWR |
| `enq: TX - row lock contention` | Waiting for another session's row lock |
| `buffer busy waits` | Several sessions want the same block |
| `latch: cache buffers chains` | Hot blocks in the buffer cache |
| `cursor: pin S wait on X` | Another session holds the cursor pin, often during a hard parse |
| `log file switch (checkpoint incomplete)` | Redo cannot switch until a checkpoint finishes |

## Other names

| Topic | Oracle | PostgreSQL | MySQL | SQL Server |
|---|---|---|---|---|
| Temporary tables | Global temporary, private temporary (18c) | Session | Session | `#temp`, `##global` |
| JSON read | `JSON_VALUE` | `->>` | `->>` | `JSON_VALUE` |
| Partitioning | Range, hash, list | Range, hash, list | Range, hash, list | Partition function and scheme |
| High availability | Data Guard, RAC | Streaming and logical replication | Group Replication, InnoDB Cluster | Always On availability groups |
| Process model | Dedicated or shared server | One process per connection, so pooling matters | Threads | Threads |

## Release notes

**Oracle.**

- **23ai:** SQL `BOOLEAN`, `IF [NOT] EXISTS`, `GROUP BY` alias or position, `HAVING` alias, `SELECT` without `FROM`, table value constructor, direct joins in `UPDATE` and `DELETE`, `VECTOR`, JSON-relational duality views, True Cache, and `GROUP BY ALL` in release update 23.9.
- **26ai:** the next long-term support release, on the 23.26 line. `QUALIFY` and `RESETTABLE` (23.26.0), `FILTER` and SQL assertions (23.26.1), `SELECT FOR UPDATE` with a row limit (23.26.4).

**PostgreSQL.**

- **18:** asynchronous I/O, skip scan, `uuidv7()`, virtual generated columns, `WITHOUT OVERLAPS`, `OLD` and `NEW` in `RETURNING`, and `pg_upgrade` keeps statistics.
- **19:** release candidate 1 came on 15 October 2026, and general availability is planned for 19 November 2026, so say which build you mean. It adds `WAIT FOR LSN`, `ON CONFLICT DO SELECT ... RETURNING`, `REPACK`, and `IGNORE NULLS`.
- **14:** reaches end of life on 12 November 2026.

**MySQL.** 8.4 LTS changed defaults, such as `innodb_adaptive_hash_index` off and `mysql_native_password` disabled. 9.7 LTS arrived in April 2026 as the last sequentially numbered line. 26.7 (July 2026) is the first calendar-versioned release, and is not marked LTS.

**SQL Server.** 2022 added `IS [NOT] DISTINCT FROM`, `GREATEST`, `LEAST`, `WINDOW` and `IGNORE NULLS`. 2025 adds the `||` operator, regular expression functions, JSON and VECTOR types, and optimized locking.

## Common mistakes

| What people do | What is true |
|---|---|
| Say `TRUNCATE` can never be rolled back | It can on PostgreSQL, and on SQL Server inside a transaction |
| Say every engine defaults to `READ COMMITTED` | MySQL InnoDB defaults to `REPEATABLE READ` |
| Say Oracle supports `REPEATABLE READ` | It offers `READ COMMITTED`, `SERIALIZABLE` and read-only |
| Treat Oracle `SERIALIZABLE` as truly serializable | It is snapshot isolation, and allows write skew |
| Read error 1205 the same way on two engines | Lock wait timeout on MySQL, deadlock victim on SQL Server |
| Assume a deadlock rolls back your transaction on Oracle | Only one statement is rolled back, so you must decide |
| Continue after an error in a PostgreSQL transaction | Every statement fails with `25P02` until you roll back |
| Expect `\|\|` to concatenate on MySQL | It is logical OR unless `PIPES_AS_CONCAT` is set |
| Write `GROUP BY ALL` on PostgreSQL | That is the Oracle feature. On PostgreSQL, `ALL` means something else, and a grouping list is still required |
| Assume a foreign key creates a child index | Only InnoDB does |
| Assume Oracle has `ON UPDATE CASCADE` | It does not |
| Mix up `DATEDIFF` arguments | MySQL is `(end, start)`, SQL Server is `(unit, start, end)` |
| Think `db file sequential read` is a full scan | It is a single-block read |
| Say SQL Server escalates to page locks | It goes straight to the table or partition |
| Quote version facts with no date | State the release |

## Quick self-test

1. How do you fetch the top 5 rows, and paginate, on each engine?
2. Can `TRUNCATE` be rolled back? Does it reset identity values? Answer for each engine.
3. Can a `UNIQUE` column hold more than one NULL? Answer for each engine.
4. What happens to your transaction when you are the deadlock victim on Oracle, and on PostgreSQL?
5. Why can a normal Oracle B-tree index not find `WHERE col IS NULL`, and how do you fix it?
6. You run `SELECT INTO` and no row matches. What happens in PL/SQL, PL/pgSQL and T-SQL?

**Next:** [Concepts Cheat Sheet](concepts-cheat-sheet.md)
