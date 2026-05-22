CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase4_uniques_and_pks()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 4 (constraints)...', clock_timestamp();

  -- NEW PKS
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
  AND cd.type = 'p'
  ;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- NEW UNIQUE CONSTRAINTS
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
  AND cd.type = 'u'
  ;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 4);
  -- NEW INDEXES
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
  , 'CREATE'
  , ct.schema_name
  , ct.name
  , ti.name
  , FORMAT(
      '%s;'  -- Index expression is the full syntax (CREATE INDEX...)
    , ti.expression
    )
  , FALSE
  FROM _migrations.indexes_diff id
  JOIN _migrations.target_indexes ti
    ON ti.oid = id.oid
  JOIN _migrations.target_tables ct
    ON ct.oid = ti.table_oid
  WHERE id.is_new
  AND id.name NOT IN (
    SELECT name
    FROM _migrations.constraints_diff
    WHERE type IN ('p', 'u')
    AND is_new
  );

END $FUNC$ LANGUAGE PLPGSQL;

