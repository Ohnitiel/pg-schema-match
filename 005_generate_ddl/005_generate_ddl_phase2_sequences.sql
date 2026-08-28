CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase2_sequences()
AS $FUNC$
DECLARE
  v_max_phase_seq INT := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
BEGIN
  -- Create new schemas
  WITH new_schemas AS (
    SELECT schema_name
    FROM _migrations.target_tables
    UNION
    SELECT schema_name
    FROM _migrations.target_sequences
    UNION
    SELECT schema_name
    FROM _migrations.target_views
  )
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
  2
  , ROW_NUMBER() OVER (ORDER BY schema_name)
  , 'SCHEMA'
  , 'CREATE'
  , schema_name
  , schema_name
  , FORMAT(
      'CREATE SCHEMA IF NOT EXISTS %I;'
    , schema_name
    )
  , FALSE
  FROM new_schemas;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  RAISE NOTICE '% - Generating DDL for phase 2 (sequences)...', clock_timestamp();
  -- NEW SEQUENCES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ts.schema_name, ts.name)
  , 'SEQUENCE'
  , 'CREATE'
  , ts.schema_name
  , ts.name
  , FORMAT(
      'CREATE SEQUENCE IF NOT EXISTS %I.%I AS %s START %s %s %s INCREMENT %s%s;'
    , ts.schema_name
    , ts.name
    , ts.type
    , ts.start
    , CASE
        WHEN ts.min IS NULL
          THEN 'NO MINVALUE'
        ELSE 'MINVALUE ' || ts.min::text
      END
    , CASE
        WHEN ts.max IS NULL
          THEN 'NO MAXVALUE'
        ELSE 'MAXVALUE ' || ts.max::text
      END
    , ts.increment
    , CASE WHEN ts.cycles THEN ' CYCLE' ELSE ' NO CYCLE' END
    )
  , FALSE
  FROM _migrations.sequences_diff sd
  JOIN _migrations.target_sequences ts
    ON ts.oid = sd.oid
  WHERE sd.is_new;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- CHANGED SEQUENCES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY ts.schema_name, ts.name)
  , 'SEQUENCE'
  , 'ALTER'
  , ts.schema_name
  , ts.name
  , FORMAT(
      'ALTER SEQUENCE %I.%I AS %s %s %s INCREMENT %s%s;'
    , ts.schema_name
    , ts.name
    , ts.type
    , CASE
        WHEN ts.min IS NULL
          THEN 'NO MINVALUE'
        ELSE 'MINVALUE ' || ts.min::text
      END
    , CASE
        WHEN ts.max IS NULL
          THEN 'NO MAXVALUE'
        ELSE 'MAXVALUE ' || ts.max::text
      END
    , ts.increment
    , CASE WHEN ts.cycles THEN ' CYCLE' ELSE ' NO CYCLE' END
    )
  , FALSE
  FROM _migrations.sequences_diff sd
  JOIN _migrations.target_sequences ts
    ON ts.oid = sd.oid
  WHERE sd.is_changed;

  v_max_phase_seq := (SELECT COALESCE(MAX(seq), 0) FROM _migrations.migration_ddl WHERE phase = 2);
  -- DROP SEQUENCES
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  SELECT
    2
  , v_max_phase_seq 
    + ROW_NUMBER() OVER (ORDER BY sd.schema_name, sd.name)
  , 'SEQUENCE'
  , 'DROP'
  , sd.schema_name
  , sd.name
  , FORMAT(
      'DROP SEQUENCE %I.%I;'
    , sd.schema_name
    , sd.name
    )
  , FALSE
  FROM _migrations.sequences_diff sd
  WHERE sd.operation_type = 'DROP_SEQUENCE';

END $FUNC$ LANGUAGE PLPGSQL;
