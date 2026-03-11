CREATE SCHEMA IF NOT EXISTS migrations;

CREATE OR REPLACE VIEW migrations.definitions AS
SELECT
    'table'::text AS object_type,
    c.oid AS object_oid,
    c.oid AS table_oid,
    n.nspname AS schema_name,
    c.relname AS object_name,
    NULL::text AS definition
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
UNION ALL
SELECT
    'view',
    c.oid,
    c.oid,
    n.nspname,
    c.relname,
    pg_get_viewdef(c.oid, true)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v'
UNION ALL
SELECT
    'materialized_view',
    c.oid,
    c.oid,
    n.nspname,
    c.relname,
    pg_get_viewdef(c.oid, true)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'm'
UNION ALL
SELECT
    'index',
    i.indexrelid,
    i.indrelid,
    n.nspname,
    c.relname,
    pg_get_indexdef(i.indexrelid)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
UNION ALL
SELECT
    'constraint',
    con.oid,
    con.conrelid,
    n.nspname,
    con.conname,
    pg_get_constraintdef(con.oid)
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
UNION ALL
SELECT
    'function',
    p.oid,
    NULL::oid,
    n.nspname,
    p.proname,
    pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog')
UNION ALL
SELECT
    'column_default',
    ad.oid,
    ad.adrelid,
    n.nspname,
    c.relname || '.' || a.attname,
    pg_get_expr(ad.adbin, ad.adrelid)
FROM pg_attrdef ad
JOIN pg_attribute a
  ON a.attrelid = ad.adrelid
 AND a.attnum = ad.adnum
JOIN pg_class c
  ON c.oid = ad.adrelid
JOIN pg_namespace n
  ON n.oid = c.relnamespace
WHERE NOT a.attisdropped
UNION ALL
SELECT
    'trigger',
    t.oid,
    t.tgrelid,
    n.nspname,
    t.tgname,
    pg_get_triggerdef(t.oid)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal;
