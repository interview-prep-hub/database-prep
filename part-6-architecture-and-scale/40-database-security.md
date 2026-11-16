# 40. Database Security

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 19](../part-3-advanced-sql/19-views-materialized-views-sequences.md)

> **In one line:** Security means assuming each layer can fail, so injection, access, encryption and auditing all defend the data separately.

## What you will learn

- How SQL injection works, and what a bind variable cannot protect
- Least privilege
- Row-level security on PostgreSQL and Oracle
- What encryption does and does not protect against
- How to store passwords
- How to treat backups and non-production data

## Who are you defending against?

Outsiders through the application, insiders, stolen credentials, stolen backups, and copied production data.

**Authentication** asks who you are. **Authorization** asks what you may do.

## SQL injection

Concatenated input changes the **structure** of the SQL. Suppose an application builds this string from what the user typed:

```text
SELECT customer_name FROM customers WHERE customer_name = '<input>'
```

An attacker types `x' OR '1'='1`. The statement becomes this, and returns everyone:

```sql
SELECT customer_name
FROM customers
WHERE customer_name = 'x' OR '1'='1'
ORDER BY customer_id;
```

```text output
 customer_name
---------------
 Alice Morgan
 Bilal Ahmed
 Chloe Martin
 David Lee
 Fatima Noor
 George Hall
 Hana Sato
 Ivan Novak
(8 rows)
```

**Bind variables separate code from data.** The statement is parsed first, so a value can never become SQL. The same input, bound:

```sql postgres
-- PostgreSQL
PREPARE find_customer (VARCHAR) AS
  SELECT customer_name FROM customers WHERE customer_name = $1;

EXECUTE find_customer('x'' OR ''1''=''1');

DEALLOCATE find_customer;
```

```text output
PREPARE
 customer_name
---------------
(0 rows)

DEALLOCATE
```

No rows: the database searched for someone literally named `x' OR '1'='1`.

**Second-order injection.** Input stored safely is later concatenated into another statement.

**What can a bind variable not protect?** Identifiers and keywords. A dynamic `ORDER BY` or table name needs an allow-list that maps user input to known column names.

**Escaping is discouraged, and stored procedures are not automatically safe.** Dynamic SQL inside one can still be injected ([Chapter 51](../part-7-plsql/51-dynamic-sql.md)).

## Least privilege

- Separate accounts per application.
- No DBA or owner account for the application.
- Use views and execute-only procedures, with no direct table grants.
- Revoke what is not needed.

## Row-level security

**The database adds the row filter,** so one missed `WHERE` in application code cannot leak data.

### PostgreSQL RLS

```sql postgres
DROP ROLE IF EXISTS app_user;
CREATE ROLE app_user NOLOGIN;

CREATE TABLE tenant_notes (
  tenant_id  INTEGER NOT NULL,
  note       VARCHAR(50) NOT NULL
);

INSERT INTO tenant_notes VALUES (1, 'Alpha note');
INSERT INTO tenant_notes VALUES (2, 'Beta note');

ALTER TABLE tenant_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_notes
  USING (tenant_id = current_setting('app.tenant_id')::INTEGER);

GRANT SELECT ON tenant_notes TO app_user;
```

```sql postgres
SET ROLE app_user;
SET app.tenant_id = '1';

SELECT tenant_id, note FROM tenant_notes ORDER BY note;

RESET ROLE;
```

```text output
SET
SET
 tenant_id |    note
-----------+------------
         1 | Alpha note
(1 row)

RESET
```

Only tenant 1's row came back, with no `WHERE` in the query.

- `USING` decides which rows are visible. `WITH CHECK` decides which rows may be written.
- With RLS enabled and no policy, the default is **deny**.

**Where does it catch people out?** Superusers and `BYPASSRLS` roles always bypass it. **Table owners bypass it, unless the table has `FORCE ROW LEVEL SECURITY`.** So never let the application connect as the owner.

**Tenant context under connection pooling.** Under transaction pooling, use `SET LOCAL` inside the transaction, or the setting leaks to the next client ([Chapter 35](35-database-architecture.md)).

```sql postgres
DROP TABLE tenant_notes;
DROP ROLE app_user;
```

### Oracle VPD

**Virtual Private Database:** a policy function returns a predicate, and Oracle adds it to every query.

```sql oracle
CREATE OR REPLACE FUNCTION tenant_policy (
  p_schema IN VARCHAR2,
  p_object IN VARCHAR2
) RETURN VARCHAR2 IS
BEGIN
  RETURN 'tenant_id = SYS_CONTEXT(''app_ctx'', ''tenant_id'')';
END tenant_policy;
/

BEGIN
  DBMS_RLS.ADD_POLICY(
    object_schema   => USER,
    object_name     => 'TENANT_NOTES',
    policy_name     => 'TENANT_ISOLATION',
    policy_function => 'TENANT_POLICY');
END;
/
```

**Who skips VPD?** `SYS`, users connected `AS SYSDBA`, and anyone with `EXEMPT ACCESS POLICY`. VPD is an Enterprise Edition feature.

**SQL Server** has security policies as the equivalent.

## Encryption

| Layer | Protects against |
|---|---|
| **TLS** in transit | Network sniffing |
| **TDE** at rest | Stolen disks and backups |
| **Client-side encryption** | Even a DBA reading the data |

**What does Transparent Data Encryption protect against, and what does it not protect against?** It protects data files and backups if they are stolen. It does **not** protect against an authorized user or SQL injection, because the database decrypts for any valid session.

**TDE details.** Tablespace or column encryption, with two-tier keys held in a keystore. Column TDE blocks index range scans.

## Passwords

**How would you store user passwords in a database?** As **salted, slow hashes**, such as bcrypt or Argon2, and never in a reversible form. A salt defeats precomputed tables, and slowness defeats brute force.

**Hashing vs encryption.** Hashing is one-way. Encryption can be reversed with a key.

**Authentication hardening.** Use SCRAM rather than MD5 on PostgreSQL. No passwords in code or repositories, with rotation, and short-lived credentials. Keep the database on a private network.

**PostgreSQL `SECURITY DEFINER` functions** need a fixed `search_path`, with `pg_temp` last, and `EXECUTE` revoked from `PUBLIC`.

## Masking and auditing

**Masking is not a security boundary.** SQL Server Dynamic Data Masking can be inferred through `WHERE` clauses.

**Auditing.** Oracle Unified Auditing, `pgaudit`, and SQL Server Audit. Decide what to record, protect the logs, and keep secrets out of them. Bind values can appear in logs, so statement logging can leak personal data.

**Oracle SQL Firewall** (23ai) keeps allow-lists of known SQL for each user.

## Privacy

Keep less data, set retention, and plan erasure, including how it interacts with backups. **Crypto-shredding** deletes the key, so that the data becomes unreadable everywhere.

## Backups and copies

Backups are data too. Encrypt them, and restrict who can restore them.

**A developer needs production data to reproduce a bug. What do you do?** Do not copy it as is. Use masked or synthetic data. If real data is truly needed, give time-limited, audited access in a controlled environment.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Concatenate input | SQL injection | Bind values |
| Bind a column name | It does not work | Use an allow-list |
| Connect the app as the table owner | RLS is bypassed | Use a separate role |
| Think TDE stops injection | The database decrypts for valid sessions | Bind, and use least privilege |
| Encrypt passwords | They can be reversed | Use salted, slow hashes |
| Use plain `SET` behind a pooler | Tenant context leaks | Use `SET LOCAL` |
| Copy production to dev | A data breach waiting to happen | Mask it |

## Interview questions

**Q1. How does SQL injection work, how do you prevent it, and what can a bind variable not protect?**

Concatenated input changes the SQL's structure. Bind variables prevent it, because the statement is parsed before values are applied. Binds cannot protect identifiers or keywords, so those need an allow-list.

**Q2. How would you implement row-level security?**

On PostgreSQL, enable RLS, and add a policy on `tenant_id`, with the tenant in a session setting, set with `SET LOCAL`. On Oracle, use VPD. The application must not connect as the owner.

**Q3. How does row level security work in PostgreSQL, and where does it catch people out?**

A policy adds a filter to every query. It catches people out because table owners and superusers bypass it, and because a pooled connection can leak a plain `SET`.

**Q4. What does Transparent Data Encryption protect against, and what does it not protect against?**

It protects stolen files and backups. It does not protect against valid users, or SQL injection.

**Q5. How would you store user passwords in a database?**

As salted, slow hashes such as Argon2 or bcrypt, never reversibly.

**Q6. A developer needs production data to reproduce a bug. What do you do?**

Use masked or synthetic data. If that fails, I give limited, audited access, not a copy.

## Practice

**1. A report lets users sort by any column. How do you build the `ORDER BY` safely?**

<details>
<summary>Show solution</summary>

Map the user's choice to a fixed list of column names in code, and reject anything else. Binds cannot replace a column name.

</details>

**2. Your application connects as the table owner, and RLS seems to do nothing. Why?**

<details>
<summary>Show solution</summary>

Table owners bypass RLS. Use a separate role, or `ALTER TABLE ... FORCE ROW LEVEL SECURITY`.

</details>

## Recap

- Bind every value. Allow-list every identifier.
- Grant the least privilege, and never connect as the owner.
- Row-level security puts the filter in the database.
- TDE protects files, not queries.
- Store passwords as salted, slow hashes.
- Backups and copies are data too.

**Next:** [Chapter 41: Where to do what](41-where-to-do-what.md)
