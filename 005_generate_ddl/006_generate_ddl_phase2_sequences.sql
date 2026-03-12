CREATE OR REPLACE FUNCTION generate_ddl_phase2_sequences()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 2 (sequences)...';
  -- Create new sequences
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY ts.schema_name, ts.name)
  , 'SEQUENCE'
  , 'CREATE'
  , ts.schema_name
  , ts.name
  , FORMAT(
      'CREATE SEQUENCE IF NOT EXISTS %I.%I AS %s START %s MINVALUE %s MAXVALUE %s INCREMENT %s%s;'
    , ts.schema_name
    , ts.name
    , ts.type
    , ts.start
    , ts.min
    , COALESCE(ts.max::text, '9223372036854775807')  -- pg default bigint max
    , ts.increment
    , CASE WHEN ts.cycles THEN ' CYCLE' ELSE ' NO CYCLE' END
    )
  , FALSE
  FROM sequences_diff sd
  JOIN target_sequences ts
    ON ts.oid = sd.oid
  WHERE sd.is_new;

  -- Alter changed sequence properties
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , ROW_NUMBER() OVER (ORDER BY ts.schema_name, ts.name)
  , 'SEQUENCE'
  , 'ALTER'
  , ts.schema_name
  , ts.name
  , FORMAT(
      'ALTER SEQUENCE %I.%I AS %s MINVALUE %s MAXVALUE %s INCREMENT %s%s;'
    , ts.schema_name
    , ts.name
    , ts.type
    , ts.min
    , COALESCE(ts.max::text, '9223372036854775807')
    , ts.increment
    , CASE WHEN ts.cycles THEN ' CYCLE' ELSE ' NO CYCLE' END
    )
  , FALSE
  FROM sequences_diff sd
  JOIN target_sequences ts
    ON ts.oid = sd.oid
  WHERE sd.is_changed;
END $FUNC$ LANGUAGE PLPGSQL;
