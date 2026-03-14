CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase2_constraints()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
BEGIN
  RAISE NOTICE 'Generating DDL for phase 2 (constraints)...';
  -- Add new CHECK constraints
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, tc.name)
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
  FROM _migrations.constraints_diff cd
  JOIN _migrations.target_constraints tc
    ON tc.oid = cd.oid
  JOIN _migrations.target_tables ct
    ON ct.oid = tc.table_oid
  WHERE tc.type = 'c'
    AND cd.is_new;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Add new UNIQUE constraints
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, tc.name)
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
  FROM _migrations.constraints_diff cd
  JOIN _migrations.target_constraints tc
    ON tc.oid = cd.oid
  JOIN _migrations.target_tables ct
    ON ct.oid = tc.table_oid
  WHERE tc.type = 'u'
    AND cd.is_new;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Drop removed CHECK and UNIQUE constraints
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, dc.name)
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
  FROM _migrations.dropped_constraints dc
  JOIN _migrations.current_tables ct
    ON ct.oid = dc.table_oid
  WHERE dc.type IN ('c', 'u');
END $FUNC$ LANGUAGE PLPGSQL;
