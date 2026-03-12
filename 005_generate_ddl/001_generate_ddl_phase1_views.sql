CREATE OR REPLACE FUNCTION generate_ddl_phase1_views()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 1 (views)...';
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    1
  , ROW_NUMBER() OVER (ORDER BY
      CASE cv.is_materialized WHEN TRUE THEN 1 ELSE 0 END DESC  -- matviews first
    , cv.schema_name
    , cv.name
    )
  , CASE WHEN cv.is_materialized
      THEN 'MATERIALIZED VIEW'
      ELSE 'VIEW'
    END
  , 'DROP'
  , cv.schema_name
  , cv.name
  , FORMAT(
      'DROP %s IF EXISTS %I.%I CASCADE;'
    , CASE WHEN cv.is_materialized
        THEN 'MATERIALIZED VIEW'
        ELSE 'VIEW'
      END
    , cv.schema_name
    , cv.name
    )
  , TRUE
  FROM views_diff vd
  JOIN current_views cv
    ON cv.schema_name = vd.schema_name
    AND cv.name       = vd.name;
END $FUNC$ LANGUAGE PLPGSQL;
