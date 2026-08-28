CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase4_constraints()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 4 (constraints)...', clock_timestamp();

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- NEW CONSTRAINTS OF OTHER TYPES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    4
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
  WHERE cd.is_new
  AND cd.type NOT IN ('p', 'u')
  ;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- DROP CONSTRAINTS
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    4
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
  FROM _migrations.constraints_diff dc
  JOIN _migrations.current_tables ct
    ON ct.schema_name = dc.schema_name
    AND ct.name = dc.table_name
  WHERE dc.operation_type = 'DROP_CONSTRAINT'
  AND NOT EXISTS (
    SELECT 1
    FROM _migrations.tables_diff td
    WHERE td.operation_type = 'DROP_TABLE'
    AND td.schema_name = ct.schema_name
    AND td.name = ct.name
  )
  ;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- CHANGED CONSTRAINTS
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    4
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, cc.name)
  , 'CONSTRAINT'
  , 'ALTER'
  , ct.schema_name
  , ct.name
  , cc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP CONSTRAINT %I, ADD CONSTRAINT %I %s;'
    , ct.schema_name
    , ct.name
    , cc.name
    , cc.name
    , cc.expression
    )
  , FALSE
  FROM _migrations.constraints_diff cc
  JOIN _migrations.current_tables ct
    ON ct.schema_name = cc.schema_name
    AND ct.name = cc.table_name
  WHERE cc.operation_type = 'ALTER_CONSTRAINT';
END $FUNC$ LANGUAGE PLPGSQL;
