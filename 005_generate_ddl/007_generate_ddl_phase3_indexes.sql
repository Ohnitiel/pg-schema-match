CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase3_indexes()
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 3 (indexes)...';

  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  WITH eligible AS (
    SELECT DISTINCT ON (ti.name, tt.schema_name)
      tt.schema_name
    , ti.name
    , ti.expression
    FROM _migrations.migration_ddl md
    JOIN _migrations.current_indexes ci
      ON ci.name        = md.object_name
    JOIN _migrations.current_tables ct
      ON ct.oid         = ci.table_oid
      AND ct.schema_name = md.schema_name
    JOIN _migrations.target_indexes ti
      ON ti.name        = ci.name
    JOIN _migrations.target_tables tt
      ON tt.oid         = ti.table_oid
    WHERE md.phase            = 1
      AND md.object_type      = 'INDEX'
      AND md.ddl_operation    = 'DROP'
      AND md.is_temporary_drop = TRUE
    ORDER BY ti.name, tt.schema_name
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY schema_name, name)
  , 'INDEX'
  , 'CREATE'
  , schema_name
  , name
  , expression || ';'
  , FALSE
  FROM eligible;
END $FUNC$ LANGUAGE PLPGSQL;
