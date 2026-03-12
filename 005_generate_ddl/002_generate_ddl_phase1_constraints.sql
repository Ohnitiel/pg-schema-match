CREATE OR REPLACE FUNCTION generate_ddl_phase1_constraints()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 1 (constraints)...';
  -- Drop FKs that are being permanently removed
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , ROW_NUMBER() OVER (ORDER BY dc.name)
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
  FROM dropped_constraints dc
  JOIN current_tables ct
    ON ct.oid = dc.table_oid
  WHERE dc.type = 'f';

  -- Drop FKs that reference tables with altered columns (temporary)
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , ROW_NUMBER() OVER (ORDER BY cc.name)
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
  , TRUE                           -- will be recreated in phase 3
  FROM current_constraints cc
  JOIN current_tables ct
    ON ct.oid = cc.table_oid
  WHERE cc.type = 'f'
    AND cc.ref_table_oid IN (
      SELECT ct2.oid
      FROM columns_diff cd
      JOIN current_tables ct2
        ON ct2.schema_name = cd.schema_name
        AND ct2.name = cd.table_name
    )
    AND NOT EXISTS (
      SELECT 1
      FROM migration_ddl md
      WHERE md.object_type = 'CONSTRAINT'
        AND md.ddl_operation = 'DROP'
        AND md.object_name = cc.name
        AND md.table_name  = ct.name
    );

  -- Drop PKs on tables with altered columns (temporary)
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , ROW_NUMBER() OVER (ORDER BY cc.name)
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
  , TRUE                           -- will be recreated in phase 3
  FROM current_constraints cc
  JOIN current_tables ct
    ON ct.oid = cc.table_oid
  JOIN columns_diff cd
    ON cd.schema_name = ct.schema_name
    AND cd.table_name = ct.name
  WHERE cc.type = 'p'
    AND NOT EXISTS (
      SELECT 1
      FROM migration_ddl md
      WHERE md.object_type = 'CONSTRAINT'
        AND md.ddl_operation = 'DROP'
        AND md.object_name = cc.name
        AND md.table_name = ct.name
    );
END $FUNC$ LANGUAGE PLPGSQL;
