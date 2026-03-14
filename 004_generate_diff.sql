CREATE OR REPLACE PROCEDURE _migrations.generate_diff()
AS $FUNC$
BEGIN
  RAISE NOTICE 'Starting schema comparison...';

  RAISE NOTICE 'Identifying new tables...';
  DROP TABLE IF EXISTS _migrations.new_tables;
  CREATE TABLE _migrations.new_tables AS
  SELECT
    tt.schema_name, tt.name
  FROM _migrations.target_tables tt
  LEFT JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  WHERE ct.oid IS NULL
  AND tt.relkind = 'r';

  RAISE NOTICE 'Identifying column differences...';
  DROP TABLE IF EXISTS _migrations.columns_diff;
  CREATE TABLE _migrations.columns_diff AS
  SELECT
    tc.schema_name
  , tc.table_name
  , tc.name
  , tc.type
  , tc.nullable
  , tc.length
  , tc.default
  , cc.table_oid IS NULL AS new_column
  , nt.name IS NOT NULL AS new_table
  FROM _migrations.target_columns tc
  LEFT JOIN _migrations.current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN _migrations.new_tables nt
    ON tc.schema_name = nt.schema_name
    AND tc.table_name = nt.name
  WHERE
    cc.table_oid IS NULL
    OR tc.type <> cc.type
    OR tc.nullable <> cc.nullable
    OR COALESCE(tc.length, -1) <> COALESCE(cc.length, -1)
    OR COALESCE(tc.default, '-1') <> COALESCE(cc.default, '-1');

  RAISE NOTICE 'Identifying constraint differences...';
  DROP TABLE IF EXISTS _migrations.constraints_diff;
  CREATE TABLE _migrations.constraints_diff AS
  SELECT
    tc.oid
  , tc.table_oid
  , tc.name
  , tc.type
  , tc.expression
  , cc.oid IS NULL AS is_new
  , cc.oid IS NULL
      AND tc.expression <> cc.expression AS is_changed
  FROM _migrations.target_constraints tc
  JOIN _migrations.target_tables tt
    ON tc.table_oid = tt.oid
  JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  LEFT JOIN _migrations.current_constraints cc
    ON ct.oid = cc.table_oid;

  RAISE NOTICE 'Identifying index differences...';
  DROP TABLE IF EXISTS _migrations.indexes_diff;
  CREATE TABLE _migrations.indexes_diff AS
  SELECT
    ti.oid
  , ti.table_oid
  , ti.name
  , ti.expression
  , ci.oid IS NULL AS is_new
  , ci.oid IS NULL
      AND ti.expression <> ci.expression AS is_changed
  FROM _migrations.target_indexes ti
  JOIN _migrations.target_tables tt
    ON ti.table_oid = tt.oid
  JOIN _migrations.current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  LEFT JOIN _migrations.current_indexes ci
    ON ci.oid = ci.table_oid;

  RAISE NOTICE 'Identifying sequence differences...';
  DROP TABLE IF EXISTS _migrations.sequences_diff;
  CREATE TABLE _migrations.sequences_diff AS
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
  FROM _migrations.target_sequences ts
  LEFT JOIN _migrations.current_sequences cs
    ON ts.schema_name = cs.schema_name
    AND ts.name       = cs.name
  WHERE cs.oid IS NULL
    OR ts.min <> cs.min
    OR ts.max <> cs.max
    OR ts.increment <> cs.increment
    OR ts.cycles <> cs.cycles
    OR ts.type <> cs.type;

  RAISE NOTICE 'Identifying view differences...';
  DROP TABLE IF EXISTS _migrations.views_diff;
  CREATE TABLE _migrations.views_diff AS
  SELECT
    tv.oid
  , tv.schema_name
  , tv.name
  , tv.expression
  , tv.is_materialized
  , cv.oid IS NULL AS is_new
  , cv.oid IS NOT NULL
      AND tv.expression <> cv.expression AS is_changed
  FROM _migrations.target_views tv
  LEFT JOIN _migrations.current_views cv
    ON tv.schema_name = cv.schema_name
    AND tv.name = cv.name
  WHERE cv.oid IS NULL
    OR tv.expression <> cv.expression;

  RAISE NOTICE 'Identifying dropped tables...';
  DROP TABLE IF EXISTS _migrations.dropped_tables;
  CREATE TABLE _migrations.dropped_tables AS
  SELECT ct.oid, ct.schema_name, ct.name
  FROM _migrations.current_tables ct
  LEFT JOIN _migrations.target_tables tt
    ON ct.schema_name = tt.schema_name
    AND ct.name = tt.name
  WHERE tt.oid IS NULL;

  RAISE NOTICE 'Identifying dropped columns...';
  DROP TABLE IF EXISTS _migrations.dropped_columns;
  CREATE TABLE _migrations.dropped_columns AS
  SELECT cc.schema_name, cc.table_name, cc.name
  FROM _migrations.current_columns cc
  LEFT JOIN _migrations.target_columns tc
    ON cc.schema_name = tc.schema_name
    AND cc.table_name = tc.table_name
    AND cc.name       = tc.name
  WHERE tc.table_oid IS NULL
    AND cc.schema_name NOT IN (
      SELECT schema_name FROM _migrations.dropped_tables
    )
    AND cc.table_name NOT IN (
      SELECT name FROM _migrations.dropped_tables dt
      WHERE dt.schema_name = cc.schema_name
    );

  RAISE NOTICE 'Identifying dropped constraints...';
  DROP TABLE IF EXISTS _migrations.dropped_constraints;
  CREATE TABLE _migrations.dropped_constraints AS
  SELECT cc.oid, cc.name, cc.type, cc.table_oid, cc.expression
  FROM _migrations.current_constraints cc
  LEFT JOIN _migrations.target_constraints tc
    ON cc.name = tc.name
  WHERE tc.oid IS NULL
    AND cc.table_oid NOT IN (SELECT oid FROM _migrations.dropped_tables);

  RAISE NOTICE 'Identifying dropped indexes...';
  DROP TABLE IF EXISTS _migrations.dropped_indexes;
  CREATE TABLE _migrations.dropped_indexes AS
  SELECT ci.oid, ci.name, ci.table_oid, ci.expression
  FROM _migrations.current_indexes ci
  LEFT JOIN _migrations.target_indexes ti
    ON ci.name = ti.name
  WHERE ti.oid IS NULL
    AND ci.table_oid NOT IN (SELECT oid FROM _migrations.dropped_tables);

  RAISE NOTICE 'Diff generation complete.';
END $FUNC$ LANGUAGE PLPGSQL;
