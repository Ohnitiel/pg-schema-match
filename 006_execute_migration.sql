CREATE OR REPLACE PROCEDURE _migrations.execute_migration(p_dry_run BOOL DEFAULT TRUE)
AS $PROC$
DECLARE
  v_record    RECORD;
  v_has_error BOOL := FALSE;
BEGIN
  RAISE NOTICE 'Starting migration execution...';
  FOR v_record IN (
    SELECT id, phase, seq, object_type, ddl_operation
         , schema_name, table_name, object_name, ddl
    FROM _migrations.migration_ddl
    WHERE status = 'PENDING'
    ORDER BY phase, seq
  )
  LOOP
    BEGIN
      EXECUTE v_record.ddl;

      UPDATE _migrations.migration_ddl
      SET
        status      = 'DONE'
      , executed_at = NOW()
      WHERE id = v_record.id;

      RAISE INFO '[Phase %/Seq %] % % %.% — OK'
        , v_record.phase
        , v_record.seq
        , v_record.ddl_operation
        , v_record.object_type
        , v_record.schema_name
        , COALESCE(v_record.table_name || '.', '') || v_record.object_name;

    EXCEPTION WHEN OTHERS THEN
      v_has_error := TRUE;

      UPDATE _migrations.migration_ddl
      SET
        status    = 'ERROR'
      , error_msg = SQLERRM
      WHERE id = v_record.id;

      RAISE WARNING '[Phase %/Seq %] % % %.% — ERROR: %'
        , v_record.phase
        , v_record.seq
        , v_record.ddl_operation
        , v_record.object_type
        , v_record.schema_name
        , COALESCE(v_record.table_name || '.', '') || v_record.object_name
        , SQLERRM;
    END;
  END LOOP;

  IF p_dry_run THEN
    RAISE INFO '--- DRY RUN: rolling back all changes ---';
    RAISE INFO 'Check _migrations.migration_ddl for full execution report';
    ROLLBACK;
    -- migration_ddl updates roll back too, so reset status for clean re-run
  ELSE
    IF v_has_error THEN
      RAISE WARNING '--- LIVE RUN COMPLETED WITH ERRORS ---';
      RAISE WARNING 'Check: SELECT * FROM _migrations.migration_ddl WHERE status = ''ERROR''';
      ROLLBACK;
    ELSE
      RAISE INFO '--- LIVE RUN COMPLETED SUCCESSFULLY ---';
      COMMIT;
    END IF;
  END IF;
END $PROC$ LANGUAGE PLPGSQL;
