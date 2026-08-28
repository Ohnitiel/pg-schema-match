CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase2_tables()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
BEGIN
  RAISE NOTICE '% - Generating DDL for phase 2 (tables)...', clock_timestamp();
  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Create new tables (columns added next)
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq
    + ROW_NUMBER() OVER (ORDER BY schema_name, name)
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
  FROM _migrations.tables_diff td
  WHERE td.is_new;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Add all columns to new tables
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY tc.schema_name, tc.table_name)
  , 'COLUMN'
  , 'CREATE'
  , tc.schema_name
  , tc.table_name
  , NULL AS object_name
  , FORMAT(
      'ALTER TABLE %I.%I %s;'
    , tc.schema_name
    , tc.table_name
    , STRING_AGG(
        FORMAT('ADD COLUMN IF NOT EXISTS %I %s%s%s'
        , tc.name
        , full_type
        , CASE WHEN NOT tc.nullable THEN ' NOT NULL' ELSE '' END
        , CASE WHEN tc."default" IS NOT NULL
            THEN ' DEFAULT ' || tc."default"
            ELSE ''
          END
        )
      , ', '
      )
    )
  , FALSE
  FROM _migrations.target_columns tc
  JOIN _migrations.tables_diff td
    ON td.schema_name = tc.schema_name
    AND td.name       = tc.table_name
  WHERE td.is_new
  GROUP BY tc.schema_name, tc.table_name;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Alter columns on existing tables
  WITH _base AS (
    SELECT *
    FROM _migrations.columns_diff cd
    -- skip columns belonging to new tables
    WHERE NOT EXISTS (
      SELECT 1
      FROM _migrations.tables_diff td
      WHERE td.is_new
      AND td.schema_name = cd.schema_name
      AND td.name       = cd.table_name
    )
  )
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, table_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY schema_name, table_name, object_name)
  , 'COLUMN'
  , 'ALTER'
  , *
  FROM (

  -- Aggregate simple changes in a single ALTER TABLE operation
    SELECT
      schema_name
    , table_name
    , NULL AS object_name
    , FORMAT(
        'ALTER TABLE %I.%I %s;'
      , schema_name
      , table_name
      , STRING_AGG(
        FORMAT(
          '%s COLUMN %I %s'
        , CASE operation_type
            WHEN 'ADD_COLUMN' THEN 'ADD'
            ELSE 'ALTER'
          END
        , name
        , CASE operation_type
            WHEN 'SET_DEFAULT'
              THEN FORMAT('SET DEFAULT %s', "default")
            WHEN 'DROP_DEFAULT' THEN 'DROP DEFAULT'
            WHEN 'DROP_NOT_NULL' THEN 'DROP NOT NULL'
            WHEN 'ADD_COLUMN' THEN FORMAT(
              '%s%s%s'
            , full_type
            , CASE 
                WHEN operation_type = 'ADD_COLUMN' AND NOT nullable THEN ' NOT NULL '
                WHEN operation_type = 'ADD_COLUMN' AND nullable THEN ''
                WHEN nullable THEN ' SET NOT NULL '
                WHEN NOT nullable THEN ' DROP NOT NULL '
                ELSE ''
              END
            , CASE WHEN "default" IS NOT NULL
                THEN FORMAT(' DEFAULT %s', "default")
                ELSE ''
              END
            )
          END
        )
        , ', '
        )
      )
    , FALSE
    FROM _base
    WHERE operation_type IN (
      'ADD_COLUMN', 'SET_DEFAULT', 'DROP_DEFAULT', 'DROP_NOT_NULL'
    )
    GROUP BY schema_name, table_name

    UNION ALL

    -- SET NOT NULL changes might fail if null values already exist
    -- so we keep them separated for easier debugging
    SELECT
      schema_name
    , table_name
    , name
    , FORMAT(
        'ALTER TABLE %I.%I ALTER COLUMN %I SET NOT NULL;'
      , schema_name
      , table_name
      , name
      )
    , FALSE
    FROM _base
    WHERE operation_type = 'SET_NOT_NULL'
    
    UNION ALL

    -- TYPE changes require a full table rewrite
    -- Group all type changes in a single ALTER TABLE operation
    SELECT
      schema_name
    , table_name
    , NULL
    , FORMAT(
        'ALTER TABLE %I.%I %s;'
      , schema_name
      , table_name
      , STRING_AGG(
          FORMAT(
            'ALTER COLUMN %1$I TYPE %2$s USING %1$I::%2$s'
          , name
          , full_type
          )
        , ', '
        )
      )
    , FALSE
    FROM _base
    WHERE operation_type = 'ALTER_TYPE'
    GROUP BY schema_name, table_name
  ) t;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Drop removed tables
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY schema_name, name)
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
  FROM _migrations.tables_diff td
  WHERE td.operation_type = 'DROP_TABLE';
END $FUNC$ LANGUAGE PLPGSQL;
