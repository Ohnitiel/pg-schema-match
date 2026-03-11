CREATE OR REPLACE FUNCTION generate_ddl_phase1_constraints()
RETURNS VOID
AS $FUNC$
BEGIN

  INSERT INTO migration_ddl (
    phase, seq, object_type, schema_name, object_name, ddl, ddl_operation
  )
  WITH RECURSIVE view_deps AS (
    -- Seed 1: views that depend on tables being altered
    SELECT DISTINCT
      c.oid        AS view_oid
    , n.nspname    AS schema_name
    , c.relname    AS view_name
    , c.relkind    AS view_kind
    , 1            AS depth
    , ARRAY[c.oid] AS path
    , FALSE        AS cycle
    FROM columns_diff cd
    JOIN current_tables ct
      ON ct.schema_name = cd.schema_name
      AND ct.name       = cd.table_name
    JOIN pg_depend dep
      ON dep.refobjid = ct.oid
    JOIN pg_rewrite rw
      ON rw.oid = dep.objid
    JOIN pg_class c
      ON c.oid = rw.ev_class
      AND c.oid <> ct.oid
    JOIN pg_namespace n
      ON n.oid = c.relnamespace
    WHERE c.relkind IN ('v', 'm')
      AND dep.deptype = 'n'
    UNION
    -- Seed 2: views whose definition changed in target
    SELECT DISTINCT
      cv.oid
    , cv.schema_name
    , cv.name
    , CASE WHEN cv.is_materialized THEN 'm' ELSE 'v' END
    , 1
    , ARRAY[cv.oid]
    , FALSE
    FROM views_diff vd
    JOIN current_views cv
      ON cv.schema_name = vd.schema_name
      AND cv.name       = vd.name
    UNION ALL
    -- Recurse: views that depend on already-captured views
    SELECT DISTINCT
      c2.oid
    , n2.nspname
    , c2.relname
    , c2.relkind
    , vd.depth + 1
    , vd.path || c2.oid
    , c2.oid = ANY(vd.path)
    FROM view_deps vd
    JOIN pg_depend dep
      ON dep.refobjid = vd.view_oid
    JOIN pg_rewrite rw
      ON rw.oid = dep.objid
    JOIN pg_class c2
      ON c2.oid = rw.ev_class
      AND c2.oid <> vd.view_oid
    JOIN pg_namespace n2
      ON n2.oid = c2.relnamespace
    WHERE c2.relkind IN ('v', 'm')
      AND dep.deptype = 'n'
      AND NOT vd.cycle
  )
  , ranked AS (
    -- keep the maximum depth seen for each view
    SELECT DISTINCT ON (view_oid)
      view_oid
    , schema_name
    , view_name
    , view_kind
    , depth
    FROM view_deps
    WHERE NOT cycle
    ORDER BY view_oid, depth DESC
  )
  SELECT
    1 AS phase
  , ROW_NUMBER() OVER (ORDER BY depth DESC, view_oid) AS seq
  , CASE view_kind
      WHEN 'm' THEN 'MATERIALIZED VIEW'
      ELSE 'VIEW'
    END AS object_type
  , schema_name
  , view_name
  , FORMAT(
      'DROP %s IF EXISTS %I.%I;'
    , CASE view_kind
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        ELSE 'VIEW'
      END
    , schema_name
    , view_name
    ) AS ddl
  , 1 AS ddl_operation
  FROM ranked;

END $FUNC$ LANGUAGE PLPGSQL;
