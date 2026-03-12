CREATE OR REPLACE FUNCTION generate_ddl_phase2_constraints()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 2 (constraints)...';
  -- Add new CHECK constraints
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, tc.name)
  , 'CONSTRAINT'
  , 'CREATE'
  , ct.schema_name
  , ct.name
  , tc.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , ct.schema_name
    , ct.name
    , tc.name
    , tc.expression
    )
  , FALSE
  FROM constraints_diff cd
  JOIN target_constraints tc
    ON tc.oid = cd.oid
  JOIN target_tables ct
    ON ct.oid = tc.table_oid
  WHERE tc.type = 'c'
    AND cd.is_new;

  -- Add new UNIQUE constraints
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, tc.name)
  , 'CONSTRAINT'
  , 'CREATE'
  , ct.schema_name
  , ct.name
  , tc.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , ct.schema_name
    , ct.name
    , tc.name
    , tc.expression
    )
  , FALSE
  FROM constraints_diff cd
  JOIN target_constraints tc
    ON tc.oid = cd.oid
  JOIN target_tables ct
    ON ct.oid = tc.table_oid
  WHERE tc.type = 'u'
    AND cd.is_new;

  -- Drop removed CHECK and UNIQUE constraints
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, dc.name)
  , 'CONSTRAINT'
  , 'DROP'
  , ct.schema_name
  , ct.name
  , dc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;'
    , ct.schema_name
    , ct.name
    , dc.name
    )
  , FALSE
  FROM dropped_constraints dc
  JOIN current_tables ct
    ON ct.oid = dc.table_oid
  WHERE dc.type IN ('c', 'u');
END $FUNC$ LANGUAGE PLPGSQL;
