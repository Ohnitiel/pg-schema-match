CREATE OR REPLACE FUNCTION generate_diff()
RETURNS VOID
AS $FUNC$
BEGIN

  CREATE TABLE new_tables AS
  SELECT
    tt.schema_name, tt.name
  FROM target_tables tt
  LEFT JOIN current_tables ct
    ON tt.schema_name = ct.schema_name
    AND tt.name = ct.name
  WHERE ct.oid IS NULL
  AND ct.relkind = 'r';

  CREATE TABLE columns_diff AS
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
  FROM target_columns tc
  LEFT JOIN current_columns cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_name = cc.table_name
    AND tc.name = cc.name
  LEFT JOIN new_tables nt
    ON tc.schema_name = nt.schema_name
    AND tc.table_name = nt.name
  WHERE
    cc.table_oid IS NULL
    OR tc.type <> cc.type
    OR tc.nullable <> cc.nullable
    OR COALESCE(tc.length, -1) <> COALESCE(cc.length, -1)
    OR COALESCE(tc.default, '-1') <> COALESCE(cc.default, '-1');

  CREATE TABLE constraints_diff AS
  SELECT
    tc.oid
  , tc.table_oid
  , tc.name
  , tc.type
  , tc.expression
  , cc.oid IS NULL AS is_new
  , cc.oid IS NULL
      AND tc.expression <> cc.expression AS is_changed
  FROM target_constraints tc
  LEFT JOIN current_constraints cc
    ON tc.table_oid IN (
      SELECT tt.oid
      FROM target_tables tt
      JOIN current_tables ct
        ON tt.schema_name = ct.schema_name
        AND tt.name = ct.name
      WHERE ct.oid = cc.table_oid
    );

  CREATE TABLE indexes_diff AS
  SELECT
    tc.oid
  , tc.table_oid
  , tc.name
  , tc.type
  , tc.expression
  , cc.oid IS NULL AS is_new
  , cc.oid IS NULL
      AND tc.expression <> cc.expression AS is_changed
  FROM target_indexes tc
  LEFT JOIN current_indexes cc
    ON tc.schema_name = cc.schema_name
    AND tc.table_oid IN (
      SELECT tt.oid
      FROM target_tables tt
      JOIN current_tables ct
        ON tt.schema_name = ct.schema_name
        AND tt.name = ct.name
      WHERE ct.oid = cc.table_oid
    );

  CREATE TABLE sequences_diff AS
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
  FROM target_sequences ts
  LEFT JOIN current_sequences cs
    ON ts.schema_name = cs.schema_name
    AND ts.name       = cs.name
  WHERE cs.oid IS NULL
    OR ts.min <> cs.min
    OR ts.max <> cs.max
    OR ts.increment <> cs.increment
    OR ts.cycles <> cs.cycles
    OR ts.type <> cs.type;

  CREATE TABLE views_diff AS
  SELECT
    tv.oid
  , tv.schema_name
  , tv.name
  , tv.expression
  , tv.is_materialized
  , cv.oid IS NULL AS is_new
  , cv.oid IS NOT NULL
      AND tv.expression <> cv.expression AS is_changed
  FROM target_views tv
  LEFT JOIN current_views cv
    ON tv.schema_name = cv.schema_name
    AND tv.name = cv.name
  WHERE cv.oid IS NULL
    OR tv.expression <> cv.expression;

  CREATE TABLE dropped_tables AS
  SELECT ct.oid, ct.schema_name, ct.name
  FROM current_tables ct
  LEFT JOIN target_tables tt
    ON ct.schema_name = tt.schema_name
    AND ct.name = tt.name
  WHERE tt.oid IS NULL;

  CREATE TABLE dropped_columns AS
  SELECT cc.schema_name, cc.table_name, cc.name
  FROM current_columns cc
  LEFT JOIN target_columns tc
    ON cc.schema_name = tc.schema_name
    AND cc.table_name = tc.table_name
    AND cc.name       = tc.name
  WHERE tc.table_oid IS NULL
    AND cc.schema_name NOT IN (
      SELECT schema_name FROM dropped_tables
    )
    AND cc.table_name NOT IN (
      SELECT name FROM dropped_tables dt
      WHERE dt.schema_name = cc.schema_name
    );

  CREATE TABLE dropped_constraints AS
  SELECT cc.oid, cc.name, cc.type, cc.table_oid, cc.expression
  FROM current_constraints cc
  LEFT JOIN target_constraints tc
    ON cc.name = tc.name
  WHERE tc.oid IS NULL
    AND cc.table_oid NOT IN (SELECT oid FROM dropped_tables);

  CREATE TABLE dropped_indexes AS
  SELECT ci.oid, ci.name, ci.table_oid, ci.expression
  FROM current_indexes ci
  LEFT JOIN target_indexes ti
    ON ci.name = ti.name
  WHERE ti.oid IS NULL
    AND ci.table_oid NOT IN (SELECT oid FROM dropped_tables);

END $FUNC$ LANGUAGE PLPGSQL;
