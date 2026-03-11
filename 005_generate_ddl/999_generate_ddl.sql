CREATE OR REPLACE FUNCTION generate_ddl()
RETURNS VOID
AS $FUNC$
BEGIN
  /*
    Phases planning
    1 - Preparation: drop views, FKs, indexes
    2 - Alteration: Run differences (new columns, changed types, etc)
    3 - Finalization: Recreate views, FK, indexes
  */

  CREATE TABLE migration_ddl (
    id BIGSERIAL PRIMARY KEY
  , phase INT NOT NULL
  , seq INT NOT NULL
  , object_type TEXT NOT NULL
  , schema_name TEXT
  , object_name TEXT
  , ddl TEXT NOT NULL
  , ddl_operation TEXT NOT NULL
  , status TEXT DEFAULT 'PENDING'
  , error_msg TEXT
  , executed_at TIMESTAMP
  , is_temporary_drop BOOL NOT NULL DEFAULT FALSE

  , CONSTRAINT object_type_ck CHECK (object_type IN
      ('TABLE', 'COLUMN', 'CONSTRAINT', 'VIEW', 'MATERIALIZED VIEW', 'INDEX', 'SEQUENCE')
    )
  , CONSTRAINT ddl_operation_ck CHECK(ddl_operation IN 
      ('CREATE', 'DROP', 'ALTER')
    )
  , CONSTRAINT status)ck CHECK (status IN 
      ('PENDING', 'DONE', 'ERROR', 'SKIPPED')
    )
  , CONSTRAINT phase_fk FOREIGN KEY (phase) REFERENCES migration_phases(phase)
  );

  -- Phase 1 — Preparation (drop dependent objects)
  PERFORM generate_ddl_phase1_views();
  PERFORM generate_ddl_phase1_constraints();
  PERFORM generate_ddl_phase1_indexes();

  -- Phase 2 — Alteration (structural changes)
  PERFORM generate_ddl_phase2_tables();
  -- PERFORM generate_ddl_phase2_constraints();  -- new/dropped CHECK, UNIQUE
  -- PERFORM generate_ddl_phase2_sequences();

  -- Phase 3 — Finalization (rebuild dropped objects)
  -- PERFORM generate_ddl_phase3_indexes();
  -- PERFORM generate_ddl_phase3_constraints();  -- recreate PKs, FKs
  -- PERFORM generate_ddl_phase3_views();        -- recreate managed views

  -- Execution
  -- PERFORM execute_migration(p_dry_run);

  -- Output
  -- PERFORM generate_flyway_files();

  -- Report
  -- PERFORM post_run_report();
END $FUNC$ LANGUAGE PLPGSQL;
