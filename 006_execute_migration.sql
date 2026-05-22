CREATE OR REPLACE PROCEDURE _migrations.execute_migration(p_dry_run BOOL DEFAULT TRUE)
AS $PROC$
DECLARE
  v_record    RECORD;
  v_has_error BOOL := FALSE;
  v_current_ddl JSONB;
  v_to_update JSONB := '[]'::JSONB;
  v_error_msg TEXT;
BEGIN
  RAISE NOTICE '% - Starting migration execution...', clock_timestamp();

  BEGIN
    FOR v_record IN (
      SELECT id, phase, seq, object_type, ddl_operation
          , schema_name, table_name, object_name, ddl
      FROM _migrations.migration_ddl
      WHERE status = 'PENDING'
      ORDER BY phase, seq
    )
    LOOP
      BEGIN
        v_current_ddl := '{"id":' || v_record.id || '}';

        EXECUTE v_record.ddl;

        UPDATE _migrations.migration_ddl
        SET
          status      = 'DONE'
        , executed_at = NOW()
        WHERE id = v_record.id;

        v_current_ddl := v_current_ddl
          || ('{"status":"DONE", "executed_at":"' || NOW() || '"}')::JSONB;

        RAISE NOTICE '% - [Phase %/Seq %] % % %.% — OK', clock_timestamp()
          , v_record.phase
          , v_record.seq
          , v_record.ddl_operation
          , v_record.object_type
          , v_record.schema_name
          , CASE
              WHEN (
                v_record.table_name IS NOT NULL
                AND v_record.object_name IS NOT NULL
              )
                THEN FORMAT('%I.%I', v_record.table_name, v_record.object_name)
              WHEN v_record.table_name IS NOT NULL
                THEN v_record.table_name
              ELSE v_record.object_name
            END;

      EXCEPTION WHEN OTHERS THEN
        v_has_error := TRUE;
        v_error_msg := SQLERRM;

        UPDATE _migrations.migration_ddl
        SET
          status    = 'ERROR'
        , error_msg = v_error_msg
        WHERE id = v_record.id;

        v_error_msg := REPLACE(v_error_msg, '"', '\"');
        v_current_ddl := v_current_ddl
          || ('{"status":"ERROR", "error_msg":"' || v_error_msg || '"}')::JSONB;

        RAISE WARNING '% - [Phase %/Seq %] % % %.% — ERROR: %. DDL: %'
          , clock_timestamp()
          , v_record.phase
          , v_record.seq
          , v_record.ddl_operation
          , v_record.object_type
          , v_record.schema_name
          , FORMAT(
              '%I.%I'
            , COALESCE(v_record.table_name, '')
            , COALESCE(v_record.object_name, '')
            )
          , SQLERRM
          , v_record.ddl;
      END;

      v_to_update := v_to_update || v_current_ddl;
    END LOOP;

    IF p_dry_run THEN
      RAISE NOTICE '% - --- DRY RUN: rolling back all changes ---', clock_timestamp();
      RAISE NOTICE '% - Check _migrations.migration_ddl for full execution report', clock_timestamp();
      -- migration_ddl updates roll back too, so reset status for clean re-run
      ROLLBACK;

      UPDATE _migrations.migration_ddl
      SET
        status = u.value->>'status'
      , error_msg = u.value->>'error_msg'
      , executed_at = u.value->>'executed_at'
      FROM JSON_ARRAY_ELEMENTS(v_to_update) u;
    ELSE
      IF v_has_error THEN
        RAISE WARNING '--- LIVE RUN COMPLETED WITH ERRORS ---';
        RAISE WARNING 'Check: SELECT * FROM _migrations.migration_ddl WHERE status = ''ERROR''';
        ROLLBACK;

        UPDATE _migrations.migration_ddl
        SET
          status = u.value->>'status'
        , error_msg = u.value->>'error_msg'
        , executed_at = u.value->>'executed_at'
        FROM JSON_ARRAY_ELEMENTS(ARRAY_TO_JSON(v_to_update)) u;
      ELSE
        RAISE NOTICE '% - --- LIVE RUN COMPLETED SUCCESSFULLY ---', clock_timestamp();
        COMMIT;
      END IF;
    END IF;
  END;
END $PROC$ LANGUAGE PLPGSQL;
