/*
 This view must be created on model database to avoid any type array error
 */
CREATE OR REPLACE VIEW migrations.pg_attribute AS
SELECT
  attrelid
, attname
, atttypid
, attstattarget
, attlen
, attnum
, attndims
, attcacheoff
, atttypmod
, attbyval
, attstorage
, attalign
, attnotnull
, atthasdef
, atthasmissing
, attidentity
, attgenerated
, attisdropped
, attislocal
, attinhcount
, attcollation
, attacl
, attoptions
, attfdwoptions
FROM pg_attribute;
