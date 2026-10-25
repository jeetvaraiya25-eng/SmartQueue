-- =============================================================================
-- 07_events.sql
-- The event scheduler runs these jobs inside the database. No application
-- process has to stay awake for aging, status refresh, alert cleanup or
-- the monthly audit archive.
--
-- If SET GLOBAL is denied, enable the scheduler in my.cnf:
--   [mysqld]
--   event_scheduler=ON
-- then restart MySQL. The events are still created and will start once the
-- scheduler is on.
-- =============================================================================

USE SmartQueue;

-- The scheduler is turned on by setup.sh (SET GLOBAL event_scheduler = ON).
-- Doing it here would abort the rest of this file on a server where the
-- account cannot change global variables. Events can be created either way;
-- they start running once the scheduler is on.

DROP EVENT IF EXISTS evt_age_queue;
CREATE EVENT evt_age_queue
  ON SCHEDULE EVERY 1 MINUTE
  STARTS CURRENT_TIMESTAMP
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT 'Raise ESI one level when a patient has waited past Aging_Policy'
  DO CALL sp_age_queue();

DROP EVENT IF EXISTS evt_refresh_doctor_status;
CREATE EVENT evt_refresh_doctor_status
  ON SCHEDULE EVERY 1 MINUTE
  STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT 'Align Doctor.Current_Status with shifts; hand over off-duty queues'
  DO CALL sp_refresh_all_doctor_status();

DROP EVENT IF EXISTS evt_auto_resolve_alerts;
CREATE EVENT evt_auto_resolve_alerts
  ON SCHEDULE EVERY 1 MINUTE
  STARTS CURRENT_TIMESTAMP + INTERVAL 30 SECOND
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT 'Close alerts whose overload condition has cleared'
  DO CALL sp_auto_resolve_alerts();

DROP EVENT IF EXISTS evt_archive_audit;
CREATE EVENT evt_archive_audit
  ON SCHEDULE EVERY 1 MONTH
  STARTS CURRENT_TIMESTAMP + INTERVAL 1 DAY
  ON COMPLETION PRESERVE
  ENABLE
  COMMENT 'Move Audit_Log rows older than audit_archive_days into the archive'
  DO CALL sp_archive_audit_log();

SELECT '07_events.sql complete' AS status;
SHOW EVENTS;
