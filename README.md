# PG Schema Match

Your dev schema got tons of changes and no documentation or migration scripts? This tool is for you.
A postgresql only solution to schema drift.

# Tools
- [postgres-fdw](https://www.postgresql.org/docs/current/postgres-fdw.html)

# Usage
First, install the postgres-fdw extension.
Then create the two views in the model database.
- 000_definitions_view.sql
- 000_pg_attribute_view.sql

The run scripts in order on the target database, they will configure FDW server and run the schema sync (dry-run by default).
