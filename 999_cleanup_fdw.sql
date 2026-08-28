CREATE OR REPLACE PROCEDURE _migrations.cleanup()
AS $FUNC$
BEGIN

  RAISE NOTICE 'Dropping schema model_schema...';
  DROP SCHEMA model_schema;
  RAISE NOTICE 'Dropping user mapping for current user...';
  DROP USER MAPPING FOR CURRENT_USER SERVER model_db;
  RAISE NOTICE 'Dropping server model_db...';
  DROP SERVER model_db;

  RAISE NOTICE 'Dropping all tables and functions used for migration...';
  DROP SCHEMA _migrations CASCADE;

  RAISE NOTICE 'Cleanup complete.';
END $FUNC$ LANGUAGE PLPGSQL;

