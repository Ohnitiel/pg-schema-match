CREATE OR REPLACE FUNCTION generate_ddl_phase3_views()
RETURNS VOID
AS $FUNC$
BEGIN
  RAISE NOTICE 'Generating DDL for phase 3 (views)...';
  -- Recreate managed views from target definition
  -- ordered by depth ASC so base views are created before dependent ones
  INSERT INTO migration_ddl (
    phase, seq, object_type, ddl_operation
  , schema_name, object_name
  , ddl, is_temporary_drop
  )
  WITH RECURSIVE view_deps AS (
    -- seed: views we dropped in phase 1
    SELECT
      tv.oid
    , tv.schema_name
    , tv.name
    , tv.is_materialized
    , 1           AS depth
    , ARRAY[tv.oid] AS path
    , FALSE         AS cycle
    FROM migration_ddl md
    JOIN target_views tv
      ON tv.name        = md.object_name
      AND tv.schema_name = md.schema_name
    WHERE md.phase         = 1
      AND md.object_type  IN ('VIEW', 'MATERIALIZED VIEW')
      AND md.ddl_operation = 'DROP'

    UNION ALL

    -- recurse: views that depend on already-captured views
    SELECT
      tv2.oid
    , tv2.schema_name
    , tv2.name
    , tv2.is_materialized
    , vd.depth + 1
    , vd.path || tv2.oid
    , tv2.oid = ANY(vd.path)
    FROM view_deps vd
    JOIN pg_depend dep
      ON dep.refobjid = vd.oid
      AND dep.deptype = 'n'
    JOIN pg_rewrite rw
      ON rw.oid       = dep.objid
    JOIN pg_class c
      ON c.oid        = rw.ev_class
      AND c.oid      <> vd.oid
    JOIN pg_namespace n
      ON n.oid        = c.relnamespace
    JOIN target_views tv2
      ON tv2.name        = c.relname
      AND tv2.schema_name = n.nspname
    WHERE c.relkind IN ('v', 'm')
      AND NOT vd.cycle
  )
  , ranked AS (
    SELECT DISTINCT ON (oid)
      oid
    , schema_name
    , name
    , is_materialized
    , depth
    FROM view_deps
    WHERE NOT cycle
    ORDER BY oid, depth ASC   -- shallowest depth first for recreation
  )
  SELECT
    3
  , ROW_NUMBER() OVER (ORDER BY depth ASC, tv.oid)
  , CASE WHEN tv.is_materialized
      THEN 'MATERIALIZED VIEW'
      ELSE 'VIEW'
    END
  , 'CREATE'
  , tv.schema_name
  , tv.name
  , FORMAT(
      'CREATE OR REPLACE %s %I.%I AS %s;'
    , CASE WHEN tv.is_materialized
        THEN 'MATERIALIZED VIEW'
        ELSE 'VIEW'
      END
    , tv.schema_name
    , tv.name
    , tv.expression
    )
  , FALSE
  FROM ranked r
  JOIN target_views tv
    ON tv.oid = r.oid;
END $FUNC$ LANGUAGE PLPGSQL;
