CREATE OR REPLACE FUNCTION generate_ddl_phase3_indexes()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 3 (indexes)...';
  -- Recreate indexes that were temporarily dropped in phase 1
  -- Use target definition in case it changed
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY tt.schema_name, ti.name)
  , 'INDEX'
  , 'CREATE'
  , tt.schema_name
  , ti.name
  , ti.expression || ';'
  , FALSE
  FROM migration_ddl md
  JOIN current_indexes ci
    ON ci.name       = md.object_name
    AND md.schema_name = (
      SELECT ct.schema_name
      FROM current_tables ct
      WHERE ct.oid = ci.table_oid
    )
  -- match to target by name
  JOIN target_indexes ti
    ON ti.name = ci.name
  JOIN target_tables tt
    ON tt.oid = ti.table_oid
  WHERE md.phase           = 1
    AND md.object_type     = 'INDEX'
    AND md.ddl_operation   = 'DROP'
    AND md.is_temporary_drop = TRUE;
END $FUNC$ LANGUAGE PLPGSQL;
