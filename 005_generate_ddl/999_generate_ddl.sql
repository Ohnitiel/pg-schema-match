CREATE OR REPLACE PROCEDURE _migrations.generate_ddl()
AS $FUNC$
BEGIN
  RAISE NOTICE 'Starting DDL generation...';
  /*
    Phases planning
    1 - Preparation: drop views, FKs, indexes
    2 - Alteration: Run differences (new columns, changed types, etc)
    3 - Finalization: Recreate views, FK, indexes
  */

  CREATE TABLE _migrations.migration_ddl (
    id SERIAL PRIMARY KEY
  , phase INT NOT NULL
  , seq INT NOT NULL
  , object_type TEXT NOT NULL
  , schema_name TEXT
  , table_name TEXT
  , object_name TEXT
  , ddl TEXT NOT NULL
  , ddl_operation TEXT NOT NULL
  , status TEXT DEFAULT 'PENDING'
  , error_msg TEXT
  , executed_at TIMESTAMP
  , is_temporary_drop BOOL NOT NULL DEFAULT FALSE

  , CONSTRAINT object_type_ck CHECK (object_type IN
      ('SCHEMA', 'TABLE', 'COLUMN', 'CONSTRAINT', 'VIEW', 'MATERIALIZED VIEW', 'INDEX', 'SEQUENCE')
    )
  , CONSTRAINT ddl_operation_ck CHECK(ddl_operation IN 
      ('CREATE', 'DROP', 'ALTER')
    )
  , CONSTRAINT status_ck CHECK (status IN 
      ('PENDING', 'DONE', 'ERROR', 'SKIPPED')
    )
  , CONSTRAINT phase_fk FOREIGN KEY (phase) REFERENCES _migrations.migration_phases(phase)
  );

  -- Phase 1 — Preparation (drop dependent objects)
  RAISE NOTICE 'Generating Phase 1 DDL (Views)...';
  CALL _migrations.generate_ddl_phase1_views();
  RAISE NOTICE 'Generating Phase 1 DDL (Constraints)...';
  CALL _migrations.generate_ddl_phase1_constraints();
  RAISE NOTICE 'Generating Phase 1 DDL (Indexes)...';
  CALL _migrations.generate_ddl_phase1_indexes();

  -- Phase 2 — Alteration (structural changes)
  RAISE NOTICE 'Generating Phase 2 DDL (Tables/Columns)...';
  CALL _migrations.generate_ddl_phase2_sequences();
  CALL _migrations.generate_ddl_phase2_tables();
  CALL _migrations.generate_ddl_phase2_constraints();  -- new/dropped CHECK, UNIQUE

  -- Phase 3 — Finalization (rebuild dropped objects)
  CALL _migrations.generate_ddl_phase3_indexes();
  CALL _migrations.generate_ddl_phase3_constraints();  -- recreate PKs, FKs
  CALL _migrations.generate_ddl_phase3_views();        -- recreate managed views

  RAISE NOTICE 'DDL generation complete.';
END $FUNC$ LANGUAGE PLPGSQL;
