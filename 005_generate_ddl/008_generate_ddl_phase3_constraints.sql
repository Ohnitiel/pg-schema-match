CREATE OR REPLACE FUNCTION generate_ddl_phase3_constraints()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 3 (constraints)...';
  -- Recreate PKs that were temporarily dropped
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY tt.schema_name, tt.name, tc.name)
  , 'CONSTRAINT'
  , 'CREATE'
  , tt.schema_name
  , tt.name
  , tc.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , tt.schema_name
    , tt.name
    , tc.name
    , tc.expression
    )
  , FALSE
  FROM migration_ddl md
  JOIN current_constraints cc
    ON cc.name = md.object_name
  JOIN current_tables ct
    ON ct.oid  = cc.table_oid
    AND ct.name = md.table_name
  -- use target definition in case it changed
  JOIN target_constraints tc
    ON tc.name = cc.name
  JOIN target_tables tt
    ON tt.oid  = tc.table_oid
  WHERE md.phase            = 1
    AND md.object_type      = 'CONSTRAINT'
    AND md.ddl_operation    = 'DROP'
    AND md.is_temporary_drop = TRUE
    AND cc.type             = 'p';

  -- Recreate FKs that were temporarily dropped
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY tt.schema_name, tt.name, tc.name)
  , 'CONSTRAINT'
  , 'CREATE'
  , tt.schema_name
  , tt.name
  , tc.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , tt.schema_name
    , tt.name
    , tc.name
    , tc.expression
    )
  , FALSE
  FROM migration_ddl md
  JOIN current_constraints cc
    ON cc.name  = md.object_name
  JOIN current_tables ct
    ON ct.oid   = cc.table_oid
    AND ct.name = md.table_name
  -- use target definition — if referenced column type changed
  -- the expression may have changed too
  JOIN target_constraints tc
    ON tc.name  = cc.name
  JOIN target_tables tt
    ON tt.oid   = tc.table_oid
  WHERE md.phase            = 1
    AND md.object_type      = 'CONSTRAINT'
    AND md.ddl_operation    = 'DROP'
    AND md.is_temporary_drop = TRUE
    AND cc.type             = 'f'
  -- PKs must already be in migration_ddl phase 3 before FKs
  -- so we ensure their CREATE is already queued
  AND EXISTS (
    SELECT 1
    FROM migration_ddl pk
    WHERE pk.phase         = 3
      AND pk.object_type   = 'CONSTRAINT'
      AND pk.ddl_operation = 'CREATE'
      AND pk.object_name   IN (
        SELECT tc2.name
        FROM target_constraints tc2
        WHERE tc2.type     = 'p'
          AND tc2.table_oid = tc.ref_table_oid
      )
  );
END $FUNC$ LANGUAGE PLPGSQL;
