-- Step 1 of 3. Creates the practice account.
-- Run this once, connected as SYSTEM.
-- The password is only for this local practice account. Do not reuse it anywhere else.

CREATE USER dbprep IDENTIFIED BY dbprep
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE MATERIALIZED VIEW,
      CREATE SEQUENCE, CREATE SYNONYM, CREATE PROCEDURE, CREATE TRIGGER,
      CREATE TYPE, CREATE JOB
  TO dbprep;

-- Lets you read the data dictionary views used in the tuning chapters.
GRANT SELECT_CATALOG_ROLE TO dbprep;
