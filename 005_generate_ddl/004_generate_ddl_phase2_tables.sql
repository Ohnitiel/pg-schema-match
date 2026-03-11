CREATE OR REPLACE FUNCTION generate_ddl_phase2_tables()
RETURNS VOID
AS $FUNC$
BEGIN
  -- Create new tables (columns added next)
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY schema_name, name)
  , 'TABLE'
  , 'CREATE'
  , schema_name
  , name
  , FORMAT(
      'CREATE TABLE IF NOT EXISTS %I.%I ();'
    , schema_name
    , name
    )
  , FALSE
  FROM new_tables;

  -- Add all columns to new tables
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY tc.schema_name, tc.table_name, tc.name)
  , 'COLUMN'
  , 'CREATE'
  , tc.schema_name
  , tc.table_name
  , tc.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS %I %s%s%s;'
    , tc.schema_name
    , tc.table_name
    , tc.name
    , tc.type
    , CASE WHEN NOT tc.nullable THEN ' NOT NULL' ELSE '' END
    , CASE WHEN tc.default_value IS NOT NULL
        THEN ' DEFAULT ' || tc.default_value
        ELSE ''
      END
    )
  , FALSE
  FROM target_columns tc
  JOIN new_tables nt
    ON nt.schema_name = tc.schema_name
    AND nt.name       = tc.table_name;

  -- Alter columns on existing tables
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY cd.schema_name, cd.table_name, cd.name)
  , 'COLUMN'
  , 'ALTER'
  , cd.schema_name
  , cd.table_name
  , cd.name
  , FORMAT(
      'ALTER TABLE %I.%I ALTER COLUMN %I TYPE %s USING %I::%s%s%s;'
    , cd.schema_name
    , cd.table_name
    , cd.name
    , cd.type
    , cd.name
    , cd.type
    , CASE WHEN NOT cd.nullable
        THEN FORMAT(', ALTER COLUMN %I SET NOT NULL', cd.name)
        ELSE FORMAT(', ALTER COLUMN %I DROP NOT NULL', cd.name)
      END
    , CASE WHEN cd.default_value IS NOT NULL
        THEN FORMAT(', ALTER COLUMN %I SET DEFAULT %s', cd.name, cd.default_value)
        ELSE FORMAT(', ALTER COLUMN %I DROP DEFAULT', cd.name)
      END
    )
  , FALSE
  FROM columns_diff cd
  -- skip columns belonging to new tables
  WHERE NOT EXISTS (
    SELECT 1
    FROM new_tables nt
    WHERE nt.schema_name = cd.schema_name
      AND nt.name        = cd.table_name
  )
  -- skip new columns (handled separately below)
  AND NOT cd.new_column;

  -- Add new columns to existing tables
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY cd.schema_name, cd.table_name, cd.name)
  , 'COLUMN'
  , 'CREATE'
  , cd.schema_name
  , cd.table_name
  , cd.name
  , FORMAT(
      'ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS %I %s%s%s;'
    , cd.schema_name
    , cd.table_name
    , cd.name
    , cd.type
    , CASE WHEN NOT cd.nullable THEN ' NOT NULL' ELSE '' END
    , CASE WHEN cd.default_value IS NOT NULL
        THEN ' DEFAULT ' || cd.default_value
        ELSE ''
      END
    )
  , FALSE
  FROM columns_diff cd
  WHERE cd.new_column
  AND NOT EXISTS (
    SELECT 1
    FROM new_tables nt
    WHERE nt.schema_name = cd.schema_name
      AND nt.name        = cd.table_name
  );

  -- Drop removed columns from existing tables
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY dc.schema_name, dc.table_name, dc.name)
  , 'COLUMN'
  , 'DROP'
  , dc.schema_name
  , dc.table_name
  , dc.name
  , FORMAT(
      'ALTER TABLE %I.%I DROP COLUMN IF EXISTS %I;'
    , dc.schema_name
    , dc.table_name
    , dc.name
    )
  , FALSE
  FROM dropped_columns dc;

  -- Drop removed tables
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY schema_name, name)
  , 'TABLE'
  , 'DROP'
  , schema_name
  , name
  , FORMAT(
      'DROP TABLE IF EXISTS %I.%I;'
    , schema_name
    , name
    )
  , FALSE
  FROM dropped_tables;
END $FUNC$ LANGUAGE PLPGSQL;
