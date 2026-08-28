CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase3_constraints()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 3);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 3 (constraints)...', clock_timestamp();

  -- Recreate PKs that were temporarily dropped
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  WITH eligible_pks AS (
    SELECT DISTINCT ON (tc.name, tt.schema_name, tt.name)
      tt.schema_name
    , tt.name        AS table_name
    , tc.name        AS constraint_name
    , tc.expression
    FROM _migrations.migration_ddl md
    JOIN _migrations.current_constraints cc
      ON cc.name  = md.object_name
    JOIN _migrations.current_tables ct
      ON ct.oid   = cc.table_oid
      AND ct.name = md.table_name
      AND ct.schema_name = md.schema_name
    JOIN _migrations.target_constraints tc
      ON tc.name  = cc.name
      AND tc.schema_name = cc.schema_name
    JOIN _migrations.target_tables tt
      ON tt.oid   = tc.table_oid
    WHERE md.phase            = 1
      AND md.object_type      = 'CONSTRAINT'
      AND md.ddl_operation    = 'DROP'
      AND md.is_temporary_drop = TRUE
      AND cc.type             = 'p'
    ORDER BY tc.name, tt.schema_name, tt.name
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY schema_name, table_name, constraint_name)
  , 'CONSTRAINT'
  , 'RECREATE'
  , schema_name
  , table_name
  , constraint_name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , schema_name
    , table_name
    , constraint_name
    , expression
    )
  , FALSE
  FROM eligible_pks;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 3);
  -- Recreate UKs that were temporarily dropped
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  WITH eligible_uks AS (
    SELECT DISTINCT ON (tc.name, tt.schema_name, tt.name)
      tt.schema_name
    , tt.name        AS table_name
    , tc.name        AS constraint_name
    , tc.expression
    , tc.ref_table_oid
    FROM _migrations.migration_ddl md
    JOIN _migrations.current_constraints cc
      ON cc.name  = md.object_name
      AND cc.schema_name = md.schema_name
    JOIN _migrations.current_tables ct
      ON ct.oid   = cc.table_oid
      AND ct.name = md.table_name
    JOIN _migrations.target_constraints tc
      ON tc.name  = cc.name
      AND tc.schema_name = cc.schema_name
    JOIN _migrations.target_tables tt
      ON tt.oid   = tc.table_oid
    WHERE md.phase            = 1
      AND md.object_type      = 'CONSTRAINT'
      AND md.ddl_operation    = 'DROP'
      AND md.is_temporary_drop = TRUE
      AND cc.type             = 'u'
    ORDER BY tc.name, tt.schema_name, tt.name
  )
  SELECT
    3
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY schema_name, table_name, constraint_name)
  , 'CONSTRAINT'
  , 'RECREATE'
  , schema_name
  , table_name
  , constraint_name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , schema_name
    , table_name
    , constraint_name
    , expression
    )
  , FALSE
  FROM eligible_uks ef;

  -- Handle renaming constraints
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    3
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (
      ORDER BY cd.schema_name, cd.table_name, cd.name
    )
  , 'CONSTRAINT'
  , 'ALTER'
  , cd.schema_name
  , cd.table_name
  , cd.name
  , FORMAT(
      'ALTER TABLE %I.%I RENAME CONSTRAINT %I TO %I;'
    , cd.schema_name
    , cd.table_name
    , cd.old_constraint_name
    , cd.name
    )
  , FALSE
  FROM _migrations.constraints_diff cd
  WHERE cd.operation_type = 'RENAME_CONSTRAINT';

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 3);
  -- Recreate FKs that were temporarily dropped
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  WITH eligible_fks AS (
    SELECT DISTINCT ON (tc.name, tt.schema_name, tt.name)
      tt.schema_name
    , tt.name        AS table_name
    , tc.name        AS constraint_name
    , tc.expression
    , tc.ref_table_oid
    FROM _migrations.migration_ddl md
    JOIN _migrations.current_constraints cc
      ON cc.name  = md.object_name
      AND cc.schema_name = md.schema_name
    JOIN _migrations.current_tables ct
      ON ct.oid   = cc.table_oid
      AND ct.name = md.table_name
    JOIN _migrations.target_constraints tc
      ON tc.name  = cc.name
      AND tc.schema_name = cc.schema_name
    JOIN _migrations.target_tables tt
      ON tt.oid   = tc.table_oid
      AND tt.name = md.table_name
    WHERE md.phase            = 1
      AND md.object_type      = 'CONSTRAINT'
      AND md.ddl_operation    = 'DROP'
      AND md.is_temporary_drop = TRUE
      AND cc.type             = 'f'
    ORDER BY tc.name, tt.schema_name, tt.name
  )
  SELECT
    3
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY schema_name, table_name, constraint_name)
  , 'CONSTRAINT'
  , 'RECREATE'
  , schema_name
  , table_name
  , constraint_name
  , FORMAT(
      'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;'
    , schema_name
    , table_name
    , constraint_name
    , expression
    )
  , FALSE
  FROM eligible_fks ef
  -- PKs must be queued in phase 3 before FKs that reference them
  WHERE EXISTS (
    SELECT 1
    FROM _migrations.migration_ddl pk
    JOIN _migrations.target_constraints tc
      ON tc.name = pk.object_name
    WHERE pk.phase         = 3
      AND pk.object_type   = 'CONSTRAINT'
      AND pk.ddl_operation = 'RECREATE'
      AND tc.type          IN ('p', 'u')
      AND tc.table_oid     = ef.ref_table_oid
  )
  -- also include FKs whose referenced PK was never dropped
  -- (table wasn't altered, PK stayed in place)
  OR NOT EXISTS (
    SELECT 1
    FROM _migrations.migration_ddl dropped_pk
    JOIN _migrations.target_constraints tc
      ON tc.name = dropped_pk.object_name
    WHERE dropped_pk.phase         = 1
      AND dropped_pk.object_type   = 'CONSTRAINT'
      AND dropped_pk.ddl_operation = 'DROP'
      AND tc.type                  = 'p'
      AND tc.table_oid             = ef.ref_table_oid
  );
END $FUNC$ LANGUAGE PLPGSQL;
