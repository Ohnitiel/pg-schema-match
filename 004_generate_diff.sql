CREATE OR REPLACE PROCEDURE _migrations.generate_diff()
AS $FUNC$
BEGIN
  RAISE NOTICE '% - Starting schema comparison...', clock_timestamp();

  RAISE NOTICE '% - Identifying tables differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.tables_diff;
  CREATE TABLE _migrations.tables_diff AS
  -- NEW TABLES
  SELECT
    tt.oid
  , tt.schema_name
  , tt.name
  , ct.oid IS NULL AS is_new
  , CASE
      WHEN ct.oid IS NULL THEN 'CREATE_TABLE'
    END AS operation_type
  FROM _migrations.target_tables tt
  LEFT JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  WHERE tt.relkind = 'r'
  AND ct.oid IS NULL

  UNION ALL

  -- DROPPED TABLES
  SELECT
    ct.oid
  , ct.schema_name
  , ct.name
  , ct.oid IS NULL AS is_new
  , 'DROP_TABLE' AS operation_type
  FROM _migrations.current_tables ct
  LEFT JOIN _migrations.target_tables tt
    ON ct.schema_name = tt.schema_name
    AND ct.name = tt.name
  WHERE tt.oid IS NULL
  ;

  RAISE NOTICE '% - Identifying column differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.columns_diff;
  CREATE TABLE _migrations.columns_diff AS
  -- NEW COLUMNS
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'ADD_COLUMN' AS operation_type
  FROM _migrations.target_columns tc
  JOIN _migrations.target_tables tt
    ON tc.schema_name = tt.schema_name
    AND tc.table_name = tt.name
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  WHERE
    cc.table_oid IS NULL

  UNION ALL

  -- DROPPED COLUMNS
  SELECT
    cc.schema_name
  , cc.table_name
  , cc.name
  , cc.type
  , cc.nullable
  , cc.length
  , cc.default
  , 'DROP_COLUMN' AS operation_type
  FROM _migrations.current_columns cc
  JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.target_columns tc
    ON cc.schema_name = tc.schema_name
    AND cc.table_name = tc.table_name
    AND cc.name = tc.name
  WHERE tc.table_oid IS NULL

  UNION ALL

  -- TYPE CHANGES
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'ALTER_TYPE' AS operation_type
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.tables_diff td
    ON tc.schema_name = td.schema_name
    AND tc.table_name = td.name
  WHERE cc.table_oid IS NOT NULL
    AND (
      tc.type <> cc.type
      OR COALESCE(tc.length, -1) <> COALESCE(cc.length, -1)
    )

  UNION ALL

  -- SET NOT NULL
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'SET_NOT_NULL' AS operation_type
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.tables_diff td
    ON tc.schema_name = td.schema_name
    AND tc.table_name = td.name
  WHERE tc.nullable <> cc.nullable AND cc.nullable AND cc.table_oid IS NOT NULL

  UNION ALL

  -- DROP NOT NULL
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'DROP_NOT_NULL' AS operation_type
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.tables_diff td
    ON tc.schema_name = td.schema_name
    AND tc.table_name = td.name
  WHERE tc.nullable <> cc.nullable AND tc.nullable AND cc.table_oid IS NOT NULL

  UNION ALL

  -- DROP DEFAULT
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'DROP_DEFAULT' AS operation_type
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.tables_diff td
    ON tc.schema_name = td.schema_name
    AND tc.table_name = td.name
  WHERE COALESCE(tc.default, '') <> COALESCE(cc.default, '')
    AND tc.default IS NULL AND cc.table_oid IS NOT NULL

  UNION ALL

  -- SET DEFAULT
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , 'SET_DEFAULT' AS operation_type
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.tables_diff td
    ON tc.schema_name = td.schema_name
    AND tc.table_name = td.name
  WHERE COALESCE(tc.default, '') <> COALESCE(cc.default, '')
    AND tc.default IS NOT NULL AND cc.table_oid IS NOT NULL
  ;

  RAISE NOTICE '% - Identifying constraint differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.constraints_diff;
  CREATE TABLE _migrations.constraints_diff AS
  -- NEW AND CHANGED CONSTRAINTS
  SELECT
    tc.oid
  , tc.table_oid
  , tt.schema_name
  , tt.name AS table_name
  , tc.name
  , tc.type
  , tc.expression
  , cc.oid IS NULL AS is_new
  , cc.oid IS NOT NULL
      AND tc.expression <> cc.expression AS is_changed
  , CASE
      WHEN cc.oid IS NULL THEN 'CREATE_CONSTRAINT'
      WHEN tc.expression <> cc.expression THEN 'ALTER_CONSTRAINT'
    END AS operation_type
  FROM _migrations.target_constraints tc
  JOIN _migrations.target_tables tt
    ON tc.table_oid = tt.oid
  LEFT JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  LEFT JOIN _migrations.current_constraints cc
    ON ct.oid = cc.table_oid
    AND tc.name = cc.name

  UNION ALL

  -- DROPPED CONSTRAINTS
  SELECT
    cc.oid
  , cc.table_oid
  , ct.schema_name
  , ct.name
  , cc.name
  , cc.type
  , cc.expression
  , NULL AS is_new
  , NULL AS is_changed
  , 'DROP_CONSTRAINT' AS operation_type
  FROM _migrations.current_constraints cc
  JOIN _migrations.current_tables ct
    ON cc.table_oid = ct.oid
  LEFT JOIN _migrations.target_tables tt
    ON ct.schema_name = tt.schema_name
    AND ct.name = tt.name
  LEFT JOIN _migrations.target_constraints tc
    ON tt.oid = tc.table_oid
    AND cc.name = tc.name
  WHERE tc.oid IS NULL
  ;

  RAISE NOTICE '% - Identifying index differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.indexes_diff;
  CREATE TABLE _migrations.indexes_diff AS
  -- NEW AND CHANGED INDEXES
  SELECT
    ti.oid
  , ti.table_oid
  , tt.schema_name
  , tt.name AS table_name
  , ti.name
  , ti.expression
  , ci.oid IS NULL AS is_new
  , ci.oid IS NOT NULL
      AND ti.expression <> ci.expression AS is_changed
  , CASE
      WHEN ci.oid IS NULL THEN 'CREATE_INDEX'
      WHEN ti.expression <> ci.expression THEN 'ALTER_INDEX'
    END AS operation_type
  FROM _migrations.target_indexes ti
  JOIN _migrations.target_tables tt
    ON ti.table_oid = tt.oid
  LEFT JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  LEFT JOIN _migrations.current_indexes ci
    ON ci.table_oid = ct.oid
    AND ci.name = ti.name
  -- WHERE ti.name NOT IN (
  --   SELECT name
  --   FROM _migrations.constraints_diff
  --   WHERE type = 'u'
  --   AND is_new
  -- )

  UNION ALL

  -- DROPPED INDEXES
  SELECT
    ci.oid
  , ci.table_oid
  , ct.schema_name
  , ct.name
  , ci.name
  , ci.expression
  , NULL AS is_new
  , NULL AS is_changed
  , 'DROP_INDEX' AS operation_type
  FROM _migrations.current_indexes ci
  JOIN _migrations.current_tables ct
    ON ci.table_oid = ct.oid
  LEFT JOIN _migrations.target_tables tt
    ON ct.schema_name = tt.schema_name
    AND ct.name = tt.name
  LEFT JOIN _migrations.target_indexes ti
    ON tt.oid = ti.table_oid
    AND ci.name = ti.name
  WHERE ti.oid IS NULL
  ;

  RAISE NOTICE '% - Identifying sequence differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.sequences_diff;
  CREATE TABLE _migrations.sequences_diff AS
  -- NEW AND CHANGED SEQUENCES
  SELECT
    ts.oid
  , ts.schema_name
  , ts.name
  , ts.type
  , ts.start
  , ts.min
  , ts.max
  , ts.increment
  , ts.cycles
  , cs.oid IS NULL AS is_new
  , cs.oid IS NOT NULL AND (
      ts.min <> cs.min
      OR ts.max <> cs.max
      OR ts.increment <> cs.increment
      OR ts.cycles <> cs.cycles
      OR ts.type <> cs.type
    ) AS is_changed
  , CASE
      WHEN cs.oid IS NULL THEN 'CREATE_SEQUENCE'
      WHEN ts.min <> cs.min
        OR ts.max <> cs.max
        OR ts.increment <> cs.increment
        OR ts.cycles <> cs.cycles
        OR ts.type <> cs.type THEN 'ALTER_SEQUENCE'
    END AS operation_type
  FROM _migrations.target_sequences ts
  LEFT JOIN _migrations.current_sequences cs
    ON ts.schema_name = cs.schema_name
    AND ts.name       = cs.name
  WHERE cs.oid IS NULL
    OR ts.min <> cs.min
    OR ts.max <> cs.max
    OR ts.increment <> cs.increment
    OR ts.cycles <> cs.cycles
    OR ts.type <> cs.type

  UNION ALL

  -- DROPPED SEQUENCES
  SELECT
    cs.oid
  , cs.schema_name
  , cs.name
  , cs.type
  , cs.start
  , cs.min
  , cs.max
  , cs.increment
  , cs.cycles
  , NULL AS is_new
  , NULL AS is_changed
  , 'DROP_SEQUENCE' AS operation_type
  FROM _migrations.current_sequences cs
  LEFT JOIN _migrations.target_sequences ts
    ON cs.schema_name = ts.schema_name
    AND cs.name       = ts.name
  WHERE ts.oid IS NULL
  ;

  RAISE NOTICE '% - Identifying view differences...', clock_timestamp();
  DROP TABLE IF EXISTS _migrations.views_diff;
  CREATE TABLE _migrations.views_diff AS
  -- NEW AND CHANGED VIEWS
  SELECT
    tv.oid
  , tv.schema_name
  , tv.name
  , tv.expression
  , tv.is_materialized
  , cv.oid IS NULL AS is_new
  , cv.oid IS NOT NULL
      AND tv.expression <> cv.expression AS is_changed
  , CASE
      WHEN cv.oid IS NULL THEN 'CREATE_VIEW'
      WHEN tv.expression <> cv.expression THEN 'ALTER_VIEW'
    END AS operation_type
  FROM _migrations.target_views tv
  LEFT JOIN _migrations.current_views cv
    ON tv.schema_name = cv.schema_name
    AND tv.name = cv.name
  WHERE cv.oid IS NULL
    OR tv.expression <> cv.expression

  UNION ALL

  -- DROPPED VIEWS
  SELECT
    cv.oid
  , cv.schema_name
  , cv.name
  , cv.expression
  , cv.is_materialized
  , NULL AS is_new
  , NULL AS is_changed
  , 'DROP_VIEW' AS operation_type
  FROM _migrations.current_views cv
  LEFT JOIN _migrations.target_views tv
    ON cv.schema_name = tv.schema_name
    AND cv.name = tv.name
  WHERE tv.oid IS NULL
  ;

  -- Clean up unchanged objects
  DELETE FROM _migrations.tables_diff WHERE operation_type IS NULL;
  DELETE FROM _migrations.columns_diff WHERE operation_type IS NULL;
  DELETE FROM _migrations.constraints_diff WHERE operation_type IS NULL;
  DELETE FROM _migrations.indexes_diff WHERE operation_type IS NULL;
  DELETE FROM _migrations.sequences_diff WHERE operation_type IS NULL;
  DELETE FROM _migrations.views_diff WHERE operation_type IS NULL;

  RAISE NOTICE '% - Diff generation complete.', clock_timestamp();
END $FUNC$ LANGUAGE PLPGSQL;
