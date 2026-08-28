CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase2_constraints()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 1 (constraints)...', clock_timestamp();

  -- Drop FKs that are being permanently removed
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY dc.name)
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
    ON ct.oid = dc.table_oid
  WHERE dc.type = 'f'
  AND dc.operation_type = 'DROP_CONSTRAINT'
  ;

END $FUNC$ LANGUAGE PLPGSQL;
