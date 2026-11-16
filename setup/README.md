# Setting up your practice database

You learn SQL by running it. This page gets the sample database onto your machine in a few minutes.

Your machine has both Oracle XE 11g and PostgreSQL 18, so you can install either one, or both.

| If your interview is about | Install |
|---|---|
| Oracle or PL/SQL | Oracle |
| PostgreSQL | PostgreSQL |
| "SQL" in general, or you are not sure | Both, if you have the time. Otherwise Oracle, because PL/SQL needs it. |

Run every command below from the book's folder:

```powershell
cd D:/www/database-prep
```

## Option A: Oracle

These Oracle scripts have not been run on a real Oracle database. If one fails, read the error first, and expect a small fix.

**1. Log in as SYSTEM.** SYSTEM is an administrator account, and you chose its password when you
installed Oracle XE. SQL*Plus will ask for it.

```powershell
sqlplus system@//localhost:1521/XE
```

**2. Run these lines at the `SQL>` prompt, one at a time.**

```text
@setup/oracle/01_create_user.sql
CONNECT dbprep/dbprep@//localhost:1521/XE
@setup/oracle/02_schema.sql
@setup/oracle/03_data.sql
@setup/oracle/session.sql
```

Here is what each line does:

| Line | What it does |
|---|---|
| `01_create_user.sql` | Creates a practice account called `dbprep`, so you never touch your other schemas |
| `CONNECT` | Switches you to that account |
| `02_schema.sql` | Creates the eight tables |
| `03_data.sql` | Loads the rows, then prints how many rows each table has |
| `session.sql` | Makes your output look like the output in this book |

**Each time you come back later:**

```powershell
sqlplus dbprep/dbprep@//localhost:1521/XE
```

Then run this at the `SQL>` prompt:

```text
@setup/oracle/session.sql
```

The `dbprep` password is only for this local practice account. Do not reuse it anywhere else.

## Option B: PostgreSQL

`psql` is not on your PATH, so use its full path. It will ask for the password of the `postgres`
user, which you chose when you installed PostgreSQL.

**1. Create the database and load it.** Run these one at a time.

```powershell
& "C:/Program Files/PostgreSQL/18/bin/psql.exe" -U postgres -f setup/postgres/01_create_database.sql
```

```powershell
& "C:/Program Files/PostgreSQL/18/bin/psql.exe" -U postgres -d dbprep -f setup/postgres/02_schema.sql
```

```powershell
& "C:/Program Files/PostgreSQL/18/bin/psql.exe" -U postgres -d dbprep -f setup/postgres/03_data.sql
```

The notices about tables that do "not exist, skipping" are normal the first time.

**2. Open it for practice.**

```powershell
& "C:/Program Files/PostgreSQL/18/bin/psql.exe" -U postgres -d dbprep
```

Then run this at the `dbprep=#` prompt, so that your output matches the book:

```text
\i setup/postgres/session.sql
```

## Check that it worked

The data script finishes by printing this table on either database. Your numbers should match.

```text
 table_name  | row_count
-------------+-----------
 departments |         5
 employees   |        12
 customers   |         8
 categories  |         7
 products    |        10
 orders      |        16
 order_items |        22
 payments    |        13
```

Then read [the sample database guide](sample-database.md) to meet the tables.

## Undo your experiments

You will change and delete rows while you practice. That is fine.

| To do this | Oracle | PostgreSQL |
|---|---|---|
| Restore the original rows | `@setup/oracle/03_data.sql` | `\i setup/postgres/03_data.sql` |
| Rebuild the tables as well | `@setup/oracle/02_schema.sql`, then the line above | `\i setup/postgres/02_schema.sql`, then the line above |
| Remove everything when you are finished | Log in as SYSTEM, then `@setup/oracle/99_remove.sql` | From the `postgres` database, `\i setup/postgres/99_remove.sql` |

## How to read the code in this book

- A code block with no label is standard SQL, and it is written to run on both Oracle and PostgreSQL.
- A block is for one engine only if it says so: in a bold **Oracle:** or **PostgreSQL:** label above it, in a first comment line such as `-- PostgreSQL`, or in a note at the top of the chapter.
- Every chapter in the PL/SQL part is Oracle.

Your Oracle XE is version 11g, which is old. Interviewers expect you to know newer syntax too, so the
book teaches it and says which release introduced it. If a block says "Oracle 12c and later", it will
not run on your XE. Read it and learn it anyway.

The same value can look a little different on each engine. The book's output comes from PostgreSQL,
unless the block is Oracle only.

| You will see | PostgreSQL | Oracle SQL*Plus |
|---|---|---|
| Number with zero decimals | `799.00` | `799` |
| Fraction below 1 | `0.50` | `.5` |
| Column headings | lower case | UPPER CASE |
| Row count | `(3 rows)` | `3 rows selected.` (shown for 6 rows or more by default) |

These differences are only about display. The stored value is the same.

**If a long line wraps badly in SQL*Plus**, make the output wider with `SET LINESIZE 200`, or shorten
a column with `COLUMN email FORMAT A25`.
