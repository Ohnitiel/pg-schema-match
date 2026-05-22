CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase4_indexes()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 4 (indexes)...', clock_timestamp();
  -- DROPPED INDEXES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    4
  , v_max_phase_seq
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, ti.name)
  , 'INDEX'
  , 'DROP'
  , ct.schema_name
  , ct.name
  , ti.name
  , FORMAT(
    'DROP INDEX %I.%I;'
    , ct.schema_name
    , ti.name
    )
  , FALSE
  FROM _migrations.indexes_diff id
  JOIN _migrations.target_indexes ti
    ON ti.oid = id.oid
  JOIN _migrations.target_tables ct
    ON ct.oid = ti.table_oid
  WHERE id.operation_type = 'DROP_INDEX';

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- CHANGED INDEXES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    4
  , v_max_phase_seq
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, ti.name)
  , 'INDEX'
  , 'ALTER'
  , ct.schema_name
  , ct.name
  , ti.name
  , FORMAT(
      'DROP INDEX %I.%I; %s;'
    , ct.schema_name
    , ti.name
    , ti.expression
    )
  , FALSE
  FROM _migrations.indexes_diff id
  JOIN _migrations.target_indexes ti
    ON ti.oid = id.oid
  JOIN _migrations.target_tables ct
    ON ct.oid = ti.table_oid
  WHERE id.operation_type = 'ALTER_INDEX'
  AND id.name NOT IN (
    SELECT name
    FROM _migrations.constraints_diff
    WHERE type IN ('p', 'u')
  );
END $FUNC$ LANGUAGE PLPGSQL;

