CREATE OR REPLACE FUNCTION set_up_fdw(
  p_model_db TEXT, p_target_user TEXT, p_target_password TEXT
)
RETURNS VOID
AS $FUNC$
DECLARE
  v_create_server_ddl TEXT := FORMAT(
    'CREATE SERVER IF NOT EXISTS model_db FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS(dbname ''%s'');', p_model_db
  );
  v_create_user_mapping_ddl TEXT := FORMAT(
    'CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER
    SERVER model_db
    OPTIONS(USER ''%s'', password ''%s'');'
  , p_target_user, p_target_password
  );
BEGIN

  CREATE EXTENSION IF NOT EXISTS postgres_fdw;
  CREATE SCHEMA IF NOT EXISTS model_schema;

  EXECUTE v_create_server_ddl;
  EXECUTE v_create_user_mapping_ddl;

  IMPORT FOREIGN SCHEMA pg_catalog
    LIMIT TO (
      pg_class, pg_namespace, pg_constraint
    , pg_index, pg_proc, pg_attrdef, pg_type, pg_sequence
    )
    FROM SERVER model_db
    INTO model_schema;

  IMPORT FOREIGN SCHEMA migrations
    LIMIT TO (definitions, pg_attribute)
    FROM SERVER model_db
    INTO model_schema;

  RAISE INFO 'Configurado Postgres FDW! Server: model_db';

END $FUNC$ LANGUAGE PLPGSQL;

