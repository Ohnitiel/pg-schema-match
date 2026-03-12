CREATE OR REPLACE FUNCTION cleanup_fdw()
RETURNS VOID
AS $FUNC$
BEGIN

  RAISE NOTICE 'Dropping schema model_schema...';
  DROP SCHEMA model_schema;
  RAISE NOTICE 'Dropping user mapping for current user...';
  DROP USER MAPPING FOR CURRENT_USER SERVER model_db;
  RAISE NOTICE 'Dropping server model_db...';
  DROP SERVER model_db;

  RAISE NOTICE 'Cleanup complete.';
END $FUNC$ LANGUAGE PLPGSQL;

