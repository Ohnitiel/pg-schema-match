CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase2_tables()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
BEGIN
  RAISE NOTICE 'Generating DDL for phase 2 (tables)...';
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
  FROM _migrations.new_tables;

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
        , CASE
            WHEN tc.type ILIKE '%char%'
              THEN FORMAT(
                '%s%s'
              , type
              , CASE tc.length
                  WHEN -1 THEN ''
                  ELSE FORMAT('(%s)', tc.length)
                END
              )
            ELSE tc.type
          END
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
  JOIN _migrations.new_tables nt
    ON nt.schema_name = tc.schema_name
    AND nt.name       = tc.table_name
  GROUp BY tc.schema_name, tc.table_name;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- Alter columns on existing tables
  WITH _base AS (
    SELECT *
    FROM _migrations.columns_diff cd
    -- skip columns belonging to new tables
    WHERE NOT EXISTS (
      SELECT 1
      FROM _migrations.new_tables nt
      WHERE nt.schema_name = cd.schema_name
        AND nt.name        = cd.table_name
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
            WHEN 'SET_DEFAULT' THEN FORMAT('SET DEFAULT %s', "default")
            WHEN 'DROP_DEFAULT' THEN 'DROP DEFAULT'
            WHEN 'DROP_NOT_NULL' THEN 'DROP NOT NULL'
            WHEN 'ADD_COLUMN' THEN FORMAT(
              '%s%s%s'
            , CASE
                WHEN type ILIKE '%char%'
                  THEN FORMAT(
                    '%s%s'
                  , type
                  , CASE length
                      WHEN -1 THEN ''
                      ELSE FORMAT('(%s)', length)
                    END
                  )
                ELSE type
              END
            , CASE WHEN NOT nullable THEN ' NOT NULL' ELSE '' END
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

    -- TYPE changes require a full table rewrite so we go for shadowing
    -- CREATE new_column with correct type
    -- UPDATE new_column = old_column
    -- DROP old_column
    -- ALTER TABLE RENAME new_column TO old_column
    SELECT
      schema_name
    , table_name
    , name
    , FORMAT(
        'ALTER TABLE %1$I.%2$I ADD COLUMN new_%3$I %4$s%5$s%6$s;
         UPDATE %1$I.%2$I SET new_%3$I = %3$I::%4$s;
         ALTER TABLE %1$I.%2$I DROP COLUMN %3$I;
         ALTER TABLE %1$I.%2$I RENAME COLUMN new_%3$I TO %3$I;'
      , schema_name
      , table_name
      , name
      , CASE
          WHEN type ILIKE '%char%'
            THEN FORMAT(
              '%s%s'
            , type
            , CASE length
                WHEN -1 THEN ''
                ELSE FORMAT('(%s)', length)
              END
            )
          ELSE type
        END
      , CASE WHEN NOT nullable THEN ' NOT NULL' ELSE '' END
      , CASE WHEN "default" IS NOT NULL
          THEN FORMAT(' DEFAULT %s', "default")
          ELSE ''
        END
      )
    , FALSE
    FROM _base
    WHERE operation_type = 'ALTER_TYPE'
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
  FROM _migrations.dropped_tables;
END $FUNC$ LANGUAGE PLPGSQL;
