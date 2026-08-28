CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase1_indexes()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 1 (indexes)...', clock_timestamp();
  -- Drop indexes on tables with altered columns
  -- (index may reference the column being changed)
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT DISTINCT ON (ci.name, ct.schema_name)
    1
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ci.name)
  , 'INDEX'
  , 'DROP'
  , ct.schema_name
  , ci.name
  , FORMAT(
      'DROP INDEX IF EXISTS %I.%I;'
    , ct.schema_name
    , ci.name
    )
  , TRUE  -- recreated in phase 3
  FROM _migrations.current_indexes ci
  JOIN _migrations.current_tables ct
    ON ct.oid = ci.table_oid
  JOIN _migrations.columns_diff cd
    ON cd.schema_name = ct.schema_name
    AND cd.table_name = ct.name
  -- exclude indexes that back constraints (PK, FK, UNIQUE)
  -- those are handled by _migrations.generate_ddl_phase1_constraints()
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_constraint pc
    WHERE pc.conindid = ci.oid
  )
  AND cd.operation_type IN ('DROP_COLUMN', 'ALTER_TYPE')
  -- exclude indexes on new tables (nothing to drop)
  AND NOT EXISTS (
    SELECT 1
    FROM _migrations.tables_diff nt
    WHERE nt.schema_name = ct.schema_name
      AND nt.name        = ct.name
      AND nt.is_new
  )
  ORDER BY ci.name, ct.schema_name;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
  -- Drop indexes being permanently removed
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY di.name)
  , 'INDEX'
  , 'DROP'
  , ct.schema_name
  , di.name
  , FORMAT(
      'DROP INDEX IF EXISTS %I.%I;'
    , ct.schema_name
    , di.name
    )
  , FALSE  -- permanently removed
  FROM _migrations.indexes_diff di
  JOIN _migrations.current_tables ct
    ON ct.oid = di.table_oid
  -- not already queued from the first insert
  WHERE NOT EXISTS (
    SELECT 1
    FROM _migrations.migration_ddl md
    WHERE md.object_type   = 'INDEX'
      AND md.ddl_operation = 'DROP'
      AND md.object_name   = di.name
      AND md.schema_name   = ct.schema_name
  )
  AND di.operation_type = 'DROP_INDEX'
  AND NOT EXISTS (
    SELECT 1
    FROM _migrations.tables_diff td
    WHERE td.operation_type = 'DROP_TABLE'
    AND td.schema_name = ct.schema_name
    AND td.name = ct.name
  )
  ;

END $FUNC$ LANGUAGE PLPGSQL;
