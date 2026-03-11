CREATE OR REPLACE FUNCTION set_up_migration()
RETURNS VOID
AS $FUNC$
BEGIN

  CREATE TABLE migration_phases (
    phase INT PRIMARY KEY
  , name TEXT NOT NULL
  , description TEXT
  );
  INSERT INTO migration_phases VALUES
    (1, 'preparation', 'Drop dependent objects')
  , (2, 'alteration', 'Structural changes')
  , (3, 'finalization', 'Rebuild dependent objects');

  CREATE TABLE tenant_views (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , expression TEXT NOT NULL
  , is_materialized BOOL NOT NULL DEFAULT FALSE
  , depends_on TEXT[]
  , status TEXT NOT NULL DEFAULT 'PENDING'
  , error_msg TEXT

  , CONSTRAINT status_ck CHECK (status IN
      ('PENDING','DROPPED','RECREATED','ERROR')
    )
  );

  CREATE TABLE IF NOT EXISTS target_tables (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , relkind CHAR NOT NULL
  );

  CREATE TABLE IF NOT EXISTS current_tables (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , relkind CHAR NOT NULL
  );

  CREATE TABLE IF NOT EXISTS target_columns (
    table_oid OID NOT NULL
  , schema_name TEXT NOT NULL
  , table_name TEXT NOT NULL
  , name TEXT NOT NULL
  , nullable BOOL NOT NULL
  , type TEXT NOT NULL
  , length INT4
  , "default" TEXT

  , CONSTRAINT tc_pk PRIMARY KEY (table_oid, name)
  , CONSTRAINT tc_tt_fk FOREIGN KEY (table_oid) REFERENCES target_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS current_columns (
    table_oid OID NOT NULL
  , schema_name TEXT NOT NULL
  , table_name TEXT NOT NULL
  , name TEXT NOT NULL
  , nullable BOOL NOT NULL
  , type TEXT NOT NULL
  , length INT4
  , "default" TEXT

  , CONSTRAINT cc_pk PRIMARY KEY (table_oid, name)
  , CONSTRAINT cc_ct_fk FOREIGN KEY (table_oid) REFERENCES current_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS target_constraints (
    oid OID PRIMARY KEY
  , name TEXT NOT NULL
  , type TEXT NOT NULL CHECK (type IN ('p','f','u','c','x'))
  , table_oid OID NOT NULL
  , ref_table_oid OID
  , cols INT2[]
  , ref_cols INT2[]
  , expression TEXT NOT NULL
  , on_delete CHAR CHECK (on_delete IN ('a', 'r', 'c', 'n', 'd'))
  , on_update CHAR CHECK (on_update IN ('a', 'r', 'c', 'n', 'd'))

  , CONSTRAINT tcon_tt_fk FOREIGN KEY (table_oid) REFERENCES target_tables(oid)
  , CONSTRAINT tcon_ref_tt_fk FOREIGN KEY (ref_table_oid) REFERENCES target_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS current_constraints (
    oid OID PRIMARY KEY
  , name TEXT NOT NULL
  , type TEXT NOT NULL CHECK (type IN ('p','f','u','c','x'))
  , table_oid OID NOT NULL
  , ref_table_oid OID
  , cols INT2[]
  , ref_cols INT2[]
  , expression TEXT NOT NULL
  , on_delete CHAR CHECK (on_delete IN ('a', 'r', 'c', 'n', 'd'))
  , on_update CHAR CHECK (on_update IN ('a', 'r', 'c', 'n', 'd'))

  , CONSTRAINT ccon_ct_fk FOREIGN KEY (table_oid) REFERENCES current_tables(oid)
  , CONSTRAINT ccon_ref_ct_fk FOREIGN KEY (ref_table_oid) REFERENCES current_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS target_indexes (
    oid OID PRIMARY KEY
  , table_oid OID NOT NULL
  , name TEXT NOT NULL
  , expression TEXT NOT NULL

  , CONSTRAINT ti_tt_fk FOREIGN KEY (table_oid) REFERENCES target_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS current_indexes (
    oid OID PRIMARY KEY
  , table_oid OID NOT NULL
  , name TEXT NOT NULL
  , expression TEXT NOT NULL

  , CONSTRAINT ci_ct_fk FOREIGN KEY (table_oid) REFERENCES current_tables(oid)
  );

  CREATE TABLE IF NOT EXISTS target_sequences (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , type TEXT NOT NULL
  , start INT8 NOT NULL DEFAULT 1
  , min INT8 NOT NULL DEFAULT 1
  , max INT8
  , increment INT8 NOT NULL DEFAULT 1
  , cycles BOOL NOT NULL DEFAULT FALSE
  );

  CREATE TABLE IF NOT EXISTS current_sequences (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , type TEXT NOT NULL
  , start INT8 NOT NULL DEFAULT 1
  , min INT8 NOT NULL DEFAULT 1
  , max INT8
  , increment INT8 NOT NULL DEFAULT 1
  , cycles BOOL NOT NULL DEFAULT FALSE
  );

  CREATE TABLE IF NOT EXISTS target_views (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , expression TEXT NOT NULL
  , is_materialized BOOL NOT NULL DEFAULT FALSE
  );

  CREATE TABLE IF NOT EXISTS current_views (
    oid OID PRIMARY KEY
  , schema_name TEXT NOT NULL
  , name TEXT NOT NULL
  , expression TEXT NOT NULL
  , is_materialized BOOL NOT NULL DEFAULT FALSE
  );

END $FUNC$ LANGUAGE PLPGSQL;

