CREATE OR REPLACE PROCEDURE _migrations.collect_metadata()
AS $FUNC$
BEGIN
  RAISE NOTICE '% - Starting metadata collection...', clock_timestamp();

  RAISE NOTICE '% - Collecting TARGET tables...', clock_timestamp();
  INSERT INTO _migrations.target_tables (oid, schema_name, name, relkind)
  SELECT
    c.oid, n.nspname, c.relname, c.relkind
  FROM model_schema.pg_class c
  JOIN model_schema.pg_namespace n
    ON c.relnamespace = n.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations')
  AND c.relkind IN ('r', 'm');

  RAISE NOTICE '% - Collecting TARGET columns...', clock_timestamp();
  INSERT INTO _migrations.target_columns (
    table_oid, schema_name, table_name, name, nullable
  , type, length, "default", full_type
  )
  SELECT
    c.oid, n.nspname, c.relname, a.attname, NOT a.attnotnull
  , t.typname, a.atttypmod, def.definition, a.full_type
  FROM model_schema.pg_class c
  JOIN model_schema.pg_namespace n
    ON c.relnamespace = n.oid
  JOIN model_schema.pg_attribute a
    ON a.attrelid = c.oid
  JOIN model_schema.pg_type t
    ON a.atttypid = t.oid
    AND a.attnum > 0
  LEFT JOIN model_schema.pg_attrdef d
    ON d.adrelid = a.attrelid
    AND d.adnum = a.attnum
  LEFT JOIN model_schema.definitions def
    ON d.oid = def.object_oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog' , 'information_schema')
    AND c.relkind = 'r'
    AND NOT a.attisdropped;

  RAISE NOTICE '% - Collecting TARGET constraints...', clock_timestamp();
  INSERT INTO _migrations.target_constraints (
    oid, name, type, table_oid, ref_table_oid, cols
  , ref_cols, expression, on_delete, on_update, schema_name
  )
  SELECT
    con.oid, con.conname, con.contype, NULLIF(con.conrelid, 0::OID)
  , NULLIF(con.confrelid, 0::OID), con.conkey, con.confkey, def.definition
  , NULLIF(con.confdeltype, ' '), NULLIF(con.confupdtype, ' ')
  , n.nspname
  FROM model_schema.pg_constraint con
  JOIN model_schema.pg_namespace n ON con.connamespace = n.oid
  LEFT JOIN model_schema.definitions def
    ON con.oid = def.object_oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog' , 'information_schema');

  RAISE NOTICE '% - Collecting TARGET indexes...', clock_timestamp();
  INSERT INTO _migrations.target_indexes (
    oid, table_oid, name, expression, schema_name
  )
  SELECT
    i.indexrelid, i.indrelid, c.relname, def.definition, n.nspname
  FROM model_schema.pg_index i
  JOIN model_schema.pg_class c ON i.indexrelid = c.oid
  JOIN model_schema.pg_namespace n ON c.relnamespace = n.oid
  LEFT JOIN model_schema.definitions def
    ON i.indexrelid = def.object_oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog' , 'information_schema');

  RAISE NOTICE '% - Collecting TARGET sequences...', clock_timestamp();
  INSERT INTO _migrations.target_sequences (
    oid, schema_name, name, type, start, min, max, increment, cycles
  )
  SELECT
    c.oid, n.nspname, c.relname, t.typname, s.seqstart
  , s.seqmin, s.seqmax, s.seqincrement, s.seqcycle
  FROM model_schema.pg_sequence s
  JOIN model_schema.pg_class c
    ON s.seqrelid = c.oid
  JOIN model_schema.pg_namespace n
    ON c.relnamespace = n.oid
  JOIN model_schema.pg_type t
    ON s.seqtypid = t.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog' , 'information_schema');

  RAISE NOTICE '% - Collecting TARGET views...', clock_timestamp();
  INSERT INTO _migrations.target_views (
    oid, schema_name, name, expression, is_materialized
  )
  SELECT
    c.oid, n.nspname, c.relname, def.definition, c.relkind = 'm'
  FROM model_schema.pg_class c
  JOIN model_schema.pg_namespace n
    ON c.relnamespace = n.oid
  JOIN model_schema.definitions def
    ON c.oid = def.object_oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog' , 'information_schema')
  AND c.relkind IN ('v', 'm');

  RAISE NOTICE '% - Collecting CURRENT tables...', clock_timestamp();
  INSERT INTO _migrations.current_tables (oid, schema_name, name, relkind)
  SELECT 
    c.oid, n.nspname, c.relname, c.relkind
  FROM pg_class c
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations')
  AND c.relkind IN ('r', 'm');

  RAISE NOTICE '% - Collecting CURRENT columns...', clock_timestamp();
  INSERT INTO _migrations.current_columns (
    table_oid, schema_name, table_name, name, nullable
  , type, length, "default", full_type
  )
  SELECT 
    c.oid, n.nspname, c.relname, a.attname, NOT a.attnotnull
  , t.typname, a.atttypmod, pg_get_serial_sequence(n.nspname || '.' || c.relname, a.attname)
  , pg_catalog.format_type(a.atttypid, a.atttypmod)
  FROM pg_class c
  JOIN pg_namespace n ON c.relnamespace = n.oid
  JOIN pg_attribute a ON a.attrelid = c.oid
  JOIN pg_type t ON a.atttypid = t.oid
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations')
    AND c.relkind = 'r'
    AND a.attnum > 0 
    AND NOT a.attisdropped;

  RAISE NOTICE '% - Collecting CURRENT constraints...', clock_timestamp();
  INSERT INTO _migrations.current_constraints (
    oid, name, type, table_oid, ref_table_oid, cols
  , ref_cols, expression, on_delete, on_update, schema_name
  )
  SELECT 
    con.oid, con.conname, con.contype, NULLIF(con.conrelid, 0::OID)
  , NULLIF(con.confrelid, 0::OID), con.conkey, con.confkey
  , pg_get_constraintdef(con.oid), NULLIF(con.confdeltype, ' ')
  , NULLIF(con.confupdtype, ' '), n.nspname
  FROM pg_constraint con
  JOIN pg_namespace n ON con.connamespace = n.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations');

  RAISE NOTICE '% - Collecting CURRENT indexes...', clock_timestamp();
  INSERT INTO _migrations.current_indexes (
    oid, table_oid, name, expression, schema_name
  )
  SELECT 
    i.indexrelid, i.indrelid, c.relname
  , pg_get_indexdef(i.indexrelid), n.nspname
  FROM pg_index i
  JOIN pg_class c ON i.indexrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations');

  RAISE NOTICE '% - Collecting CURRENT sequences...', clock_timestamp();
  INSERT INTO _migrations.current_sequences (
    oid, schema_name, name, type, start, min, max, increment, cycles
  )
  SELECT 
    c.oid, n.nspname, c.relname, t.typname
  , s.seqstart, s.seqmin, s.seqmax, s.seqincrement, s.seqcycle
  FROM pg_sequence s
  JOIN pg_class c ON s.seqrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  JOIN pg_type t ON s.seqtypid = t.oid;

  RAISE NOTICE '% - Collecting CURRENT views...', clock_timestamp();
  INSERT INTO _migrations.current_views (
    oid, schema_name, name, expression, is_materialized
  )
  SELECT 
    c.oid, n.nspname, c.relname
  , pg_get_viewdef(c.oid, true)
  , c.relkind = 'm'
  FROM pg_class c
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname NOT IN ('pg_toast', 'pg_catalog', 'information_schema', '_migrations')
    AND c.relkind IN ('v', 'm');

  RAISE NOTICE '% - Metadata collection complete.', clock_timestamp();
END $FUNC$ LANGUAGE PLPGSQL;
