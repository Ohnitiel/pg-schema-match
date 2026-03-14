CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase1_constraints()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
BEGIN
  RAISE NOTICE 'Generating DDL for phase 1 (constraints)...';

  -- Drop FKs that are being permanently removed
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
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
  FROM _migrations.dropped_constraints dc
  JOIN _migrations.current_tables ct
    ON ct.oid = dc.table_oid
  WHERE dc.type = 'f';

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
  -- Drop FKs that reference tables with altered columns (temporary)
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY cc.name)
  , 'CONSTRAINT'
  , 'DROP'
  , ct.schema_name
  , ct.name
  , cc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;'
    , ct.schema_name
    , ct.name
    , cc.name
    )
  , TRUE 
  FROM _migrations.current_constraints cc
  JOIN _migrations.current_tables ct
    ON ct.oid = cc.table_oid
  WHERE cc.type = 'f'
    AND cc.ref_table_oid IN (
      SELECT ct2.oid
      FROM _migrations.columns_diff cd
      JOIN _migrations.current_tables ct2
        ON ct2.schema_name = cd.schema_name
        AND ct2.name = cd.table_name
    )
    AND NOT EXISTS (
      SELECT 1
      FROM _migrations.migration_ddl md
      WHERE md.object_type = 'CONSTRAINT'
        AND md.ddl_operation = 'DROP'
        AND md.object_name = cc.name
        AND md.table_name  = ct.name
    );

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
  -- Drop PKs on tables with altered columns (temporary)
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY cc.name)
  , 'CONSTRAINT'
  , 'DROP'
  , ct.schema_name
  , ct.name
  , cc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;'
    , ct.schema_name
    , ct.name
    , cc.name
    )
  , TRUE
  FROM _migrations.current_constraints cc
  JOIN _migrations.current_tables ct
    ON ct.oid = cc.table_oid
  JOIN _migrations.columns_diff cd
    ON cd.schema_name = ct.schema_name
    AND cd.table_name = ct.name
  WHERE cc.type = 'p'
    AND NOT EXISTS (
      SELECT 1
      FROM _migrations.migration_ddl md
      WHERE md.object_type = 'CONSTRAINT'
        AND md.ddl_operation = 'DROP'
        AND md.object_name = cc.name
        AND md.table_name = ct.name
    );

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 1);
  -- Drop constraints backed by indexes on tables with altered columns
  -- Covers UNIQUE, PK, and EXCLUSION constraints that would block
  -- index drops or ALTER COLUMN operations
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , v_max_phase_seq
    + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, cc.name)
  , 'CONSTRAINT'
  , 'DROP'
  , ct.schema_name
  , ct.name
  , cc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;'
    , ct.schema_name
    , ct.name
    , cc.name
    )
  , TRUE
  FROM _migrations.current_constraints cc
  JOIN _migrations.current_tables ct
    ON ct.oid = cc.table_oid
  -- only constraints that are backed by an index
  JOIN _migrations.current_indexes ci
    ON ci.table_oid = cc.table_oid
  JOIN pg_constraint pc
    ON pc.conindid = ci.oid
    AND pc.conname = cc.name
  -- on tables that have altered columns
  WHERE EXISTS (
    SELECT 1
    FROM _migrations.columns_diff cd
    WHERE cd.schema_name = ct.schema_name
      AND cd.table_name  = ct.name
  )
  -- not already queued
  AND NOT EXISTS (
    SELECT 1
    FROM _migrations.migration_ddl md
    WHERE md.phase         = 1
      AND md.object_type   = 'CONSTRAINT'
      AND md.ddl_operation = 'DROP'
      AND md.object_name   = cc.name
      AND md.table_name    = ct.name
  );

  -- Drop constraints backed by indexes that will be dropped
  -- INSERT INTO _migrations.migration_ddl (
  --   phase, seq, object_type, ddl_operation
  -- , schema_name, table_name, object_name
  -- , ddl, is_temporary_drop
  -- )
  -- SELECT
  --   1
  -- , v_max_phase_seq
  --   + ROW_NUMBER() OVER (ORDER BY ct.schema_name, ct.name, cc.name)
  -- , 'CONSTRAINT'
  -- , 'DROP'
  -- , ct.schema_name
  -- , ct.name
  -- , cc.name
  -- , FORMAT(
  --     'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;'
  --   , ct.schema_name
  --   , ct.name
  --   , cc.name
  --   )
  -- , TRUE
  -- FROM _migrations.current_constraints cc
  -- JOIN _migrations.current_tables ct
  --   ON ct.oid = cc.table_oid
  -- -- only constraints that are backed by an index
  -- JOIN _migrations.current_indexes ci
  --   ON ci.table_oid = cc.table_oid
  -- JOIN pg_constraint pc
  --   ON pc.conindid = ci.oid
  --   AND pc.conname = cc.name
  -- WHERE NOT EXISTS (
  --   SELECT 1
  --   FROM _migrations.migration_ddl md
  --   WHERE md.phase         = 1
  --     AND md.object_type   = 'CONSTRAINT'
  --     AND md.ddl_operation = 'DROP'
  --     AND md.object_name   = cc.name
  --     AND md.table_name    = ct.name
  -- );

END $FUNC$ LANGUAGE PLPGSQL;
