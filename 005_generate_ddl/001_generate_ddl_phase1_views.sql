CREATE OR REPLACE PROCEDURE _migrations.generate_ddl_phase1_views()
AS $FUNC$
BEGIN

  RAISE NOTICE 'Saving non managed views...';
  -- Saves non managed views that depend on altered or dropped tables
  INSERT INTO _migrations.tenant_views (
    oid, schema_name, name, expression, is_materialized, depends_on
  )
  SELECT DISTINCT
    c.oid
  , n.nspname
  , c.relname
  , pg_get_viewdef(c.oid, TRUE)
  , c.relkind = 'm'
  , ARRAY_AGG(tn.nspname || '.' || tc.relname)
      OVER (PARTITION BY c.oid)
  FROM _migrations.columns_diff cd
  JOIN _migrations.current_tables ct
    ON ct.schema_name = cd.schema_name
    AND ct.name = cd.table_name
  JOIN pg_depend dep
    ON dep.refobjid = ct.oid
    AND dep.deptype = 'n'
  JOIN pg_rewrite rw
    ON rw.oid = dep.objid
  JOIN pg_class c
    ON c.oid = rw.ev_class
    AND c.oid <> ct.oid
  JOIN pg_namespace n
    ON n.oid = c.relnamespace
  JOIN pg_class tc
    ON tc.oid = dep.refobjid
  JOIN pg_namespace tn
    ON tn.oid = tc.relnamespace
  WHERE c.relkind IN ('v', 'm')
  -- only tenant views (not managed)
  AND NOT EXISTS (
    SELECT 1 FROM _migrations.target_views tv
    WHERE tv.schema_name = n.nspname
      AND tv.name = c.relname
  )
  -- not already saved
  AND NOT EXISTS (
    SELECT 1 FROM _migrations.tenant_views tv
    WHERE tv.oid = c.oid
  )

  UNION 

  -- Views depending on dropped tables
  SELECT DISTINCT
    c.oid
  , n.nspname
  , c.relname
  , pg_get_viewdef(c.oid, TRUE)
  , c.relkind = 'm'
  , ARRAY_AGG(tn.nspname || '.' || tc.relname)
      OVER (PARTITION BY c.oid)
  FROM _migrations.dropped_tables dt
  JOIN pg_depend dep
    ON dep.refobjid = dt.oid
    AND dep.deptype = 'n'
  JOIN pg_rewrite rw
    ON rw.oid = dep.objid
  JOIN pg_class c
    ON c.oid = rw.ev_class
    AND c.oid <> dt.oid
  JOIN pg_namespace n
    ON n.oid = c.relnamespace
  JOIN pg_class tc
    ON tc.oid = dep.refobjid
  JOIN pg_namespace tn
    ON tn.oid = tc.relnamespace
  WHERE c.relkind IN ('v', 'm')
  -- only tenant views (not managed)
  AND NOT EXISTS (
    SELECT 1 FROM _migrations.target_views tv
    WHERE tv.schema_name = n.nspname
      AND tv.name = c.relname
  )
  -- not already saved
  AND NOT EXISTS (
    SELECT 1 FROM _migrations.tenant_views tv
    WHERE tv.oid = c.oid
  );

  RAISE NOTICE 'Generating DDL for phase 1 (views)...';
  INSERT INTO _migrations.migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  WITH all_dependent_views AS (
    -- managed views from views_diff
    SELECT
      cv.oid
    , cv.schema_name
    , cv.name
    , cv.is_materialized
    , 1 AS depth
    FROM _migrations.views_diff vd
    JOIN _migrations.current_views cv
      ON cv.schema_name = vd.schema_name
      AND cv.name = vd.name

    UNION

    -- ALL views (managed + tenant) directly depending on altered tables
    SELECT DISTINCT
      c.oid
    , n.nspname
    , c.relname
    , c.relkind = 'm'
    , 1
    FROM _migrations.columns_diff cd
    JOIN _migrations.current_tables ct
      ON ct.schema_name = cd.schema_name
      AND ct.name = cd.table_name
    JOIN pg_depend dep
      ON dep.refobjid = ct.oid
      AND dep.deptype = 'n'
    JOIN pg_rewrite rw
      ON rw.oid = dep.objid
    JOIN pg_class c
      ON c.oid = rw.ev_class
      AND c.oid <> ct.oid
    JOIN pg_namespace n
      ON n.oid = c.relnamespace
    WHERE c.relkind IN ('v', 'm')

    UNION

    -- ALL views (managed + tenant) directly depending on dropped tables
    SELECT DISTINCT
      c.oid
    , n.nspname
    , c.relname
    , c.relkind = 'm'
    , 1
    FROM _migrations.dropped_tables dt
    JOIN pg_depend dep
      ON dep.refobjid = dt.oid
      AND dep.deptype = 'n'
    JOIN pg_rewrite rw
      ON rw.oid = dep.objid
    JOIN pg_class c
      ON c.oid = rw.ev_class
      AND c.oid <> dt.oid
    JOIN pg_namespace n
      ON n.oid = c.relnamespace
    WHERE c.relkind IN ('v', 'm')
  )
  SELECT
    1
  , ROW_NUMBER() OVER (
      ORDER BY
        is_materialized DESC  -- matviews first
      , schema_name
      , name
    )
  , CASE WHEN is_materialized
      THEN 'MATERIALIZED VIEW'
      ELSE 'VIEW'
    END
  , 'DROP'
  , schema_name
  , name
  , FORMAT(
      'DROP %s IF EXISTS %I.%I CASCADE;'
    , CASE WHEN is_materialized
        THEN 'MATERIALIZED VIEW'
        ELSE 'VIEW'
      END
    , schema_name
    , name
    )
  , TRUE
  FROM all_dependent_views;

END $FUNC$ LANGUAGE PLPGSQL;
