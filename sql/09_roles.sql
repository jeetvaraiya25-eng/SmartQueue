-- =============================================================================
-- 09_roles.sql
-- One MySQL account per job. The website logs in as that account, so a
-- stolen session can only do what the role can do.
--
-- Passwords are for the local coursework demo:
--   receptionist_user / Reception@123
--   nurse_user        / Nurse@123
--   doctor_user       / Doctor@123
--   admin_user        / Admin@123
--   auditor_user      / Auditor@123
--
-- Accounts are created for '%' (TCP, which is what Node uses for 127.0.0.1)
-- and for 'localhost' (the socket client used in a viva).
-- =============================================================================

USE SmartQueue;

DROP USER IF EXISTS 'receptionist_user'@'%';
DROP USER IF EXISTS 'receptionist_user'@'localhost';
DROP USER IF EXISTS 'nurse_user'@'%';
DROP USER IF EXISTS 'nurse_user'@'localhost';
DROP USER IF EXISTS 'doctor_user'@'%';
DROP USER IF EXISTS 'doctor_user'@'localhost';
DROP USER IF EXISTS 'admin_user'@'%';
DROP USER IF EXISTS 'admin_user'@'localhost';
DROP USER IF EXISTS 'auditor_user'@'%';
DROP USER IF EXISTS 'auditor_user'@'localhost';

DROP ROLE IF EXISTS
  receptionist_role, nurse_role, doctor_role, admin_role, auditor_role;

CREATE ROLE receptionist_role, nurse_role, doctor_role, admin_role, auditor_role;

-- Reception: register and find people. No queue, no vitals.
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_register_patient TO receptionist_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_search_patients  TO receptionist_role;
GRANT SELECT  ON SmartQueue.vw_patient_directory          TO receptionist_role;

-- Nurse: the three safe clinical procedures, the board, masked phone only.
-- Column-level grant: name is visible on the base table, phone and email are not.
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_admit_patient_safe     TO nurse_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_reassess_patient_safe  TO nurse_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_discharge_patient_safe TO nurse_role;
GRANT SELECT ON SmartQueue.vw_live_queue          TO nurse_role;
GRANT SELECT ON SmartQueue.vw_open_alerts         TO nurse_role;
GRANT SELECT ON SmartQueue.vw_patients_admittable TO nurse_role;
GRANT SELECT ON SmartQueue.vw_phone_masked        TO nurse_role;
GRANT SELECT ON SmartQueue.vw_doctor_directory    TO nurse_role;
GRANT SELECT (Patient_ID, Name) ON SmartQueue.Patient TO nurse_role;
GRANT SELECT (Doctor_ID, Name, `Role`, Specialization, Current_Status, Department_ID)
  ON SmartQueue.Doctor TO nurse_role;

-- Doctor: clinical view and similar-case search. No phone, no email.
GRANT SELECT  ON SmartQueue.vw_doctor_clinical TO doctor_role;
GRANT SELECT  ON SmartQueue.vw_doctor_directory TO doctor_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_search_similar_cases TO doctor_role;

-- Admin: operations, reports, roster, soft delete. Not the clinical vitals view.
GRANT SELECT ON SmartQueue.vw_admin_summary     TO admin_role;
GRANT SELECT ON SmartQueue.vw_live_queue        TO admin_role;
GRANT SELECT ON SmartQueue.vw_department_load   TO admin_role;
GRANT SELECT ON SmartQueue.vw_wait_by_esi       TO admin_role;
GRANT SELECT ON SmartQueue.vw_busiest_hours     TO admin_role;
GRANT SELECT ON SmartQueue.vw_doctor_workload   TO admin_role;
GRANT SELECT ON SmartQueue.vw_roster            TO admin_role;
GRANT SELECT ON SmartQueue.vw_departments       TO admin_role;
GRANT SELECT ON SmartQueue.vw_shifts            TO admin_role;
GRANT SELECT ON SmartQueue.vw_doctor_directory  TO admin_role;
GRANT SELECT ON SmartQueue.vw_patients_admin    TO admin_role;
GRANT SELECT ON SmartQueue.vw_deleted_directory TO admin_role;
GRANT SELECT ON SmartQueue.vw_open_alerts       TO admin_role;
GRANT SELECT ON SmartQueue.vw_all_alerts        TO admin_role;
GRANT SELECT ON SmartQueue.vw_config            TO admin_role;
GRANT SELECT ON SmartQueue.vw_aging_policy      TO admin_role;
GRANT SELECT ON SmartQueue.vw_score_audit       TO admin_role;

GRANT EXECUTE ON PROCEDURE SmartQueue.sp_assign_shift            TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_unassign_shift          TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_soft_delete_patient     TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_soft_delete_doctor      TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_restore_patient         TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_restore_doctor          TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_daily_report            TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_weekly_report           TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_doctor_report           TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_resolve_alert           TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_set_config              TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_set_aging_policy        TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_add_department          TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_add_doctor              TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_age_queue               TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_toggle_aging            TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_search_patients         TO admin_role;
GRANT EXECUTE ON PROCEDURE SmartQueue.sp_refresh_all_doctor_status TO admin_role;

-- Auditor: the change log and the clinical priority ledger. Nothing else.
GRANT SELECT ON SmartQueue.Audit_Log     TO auditor_role;
GRANT SELECT ON SmartQueue.vw_score_audit TO auditor_role;

CREATE USER 'receptionist_user'@'%'         IDENTIFIED BY 'Reception@123';
CREATE USER 'receptionist_user'@'localhost' IDENTIFIED BY 'Reception@123';
CREATE USER 'nurse_user'@'%'                IDENTIFIED BY 'Nurse@123';
CREATE USER 'nurse_user'@'localhost'        IDENTIFIED BY 'Nurse@123';
CREATE USER 'doctor_user'@'%'               IDENTIFIED BY 'Doctor@123';
CREATE USER 'doctor_user'@'localhost'       IDENTIFIED BY 'Doctor@123';
CREATE USER 'admin_user'@'%'                IDENTIFIED BY 'Admin@123';
CREATE USER 'admin_user'@'localhost'        IDENTIFIED BY 'Admin@123';
CREATE USER 'auditor_user'@'%'              IDENTIFIED BY 'Auditor@123';
CREATE USER 'auditor_user'@'localhost'      IDENTIFIED BY 'Auditor@123';

GRANT receptionist_role TO 'receptionist_user'@'%', 'receptionist_user'@'localhost';
GRANT nurse_role        TO 'nurse_user'@'%',        'nurse_user'@'localhost';
GRANT doctor_role       TO 'doctor_user'@'%',       'doctor_user'@'localhost';
GRANT admin_role        TO 'admin_user'@'%',        'admin_user'@'localhost';
GRANT auditor_role      TO 'auditor_user'@'%',      'auditor_user'@'localhost';

SET DEFAULT ROLE receptionist_role TO 'receptionist_user'@'%', 'receptionist_user'@'localhost';
SET DEFAULT ROLE nurse_role        TO 'nurse_user'@'%',        'nurse_user'@'localhost';
SET DEFAULT ROLE doctor_role       TO 'doctor_user'@'%',       'doctor_user'@'localhost';
SET DEFAULT ROLE admin_role        TO 'admin_user'@'%',        'admin_user'@'localhost';
SET DEFAULT ROLE auditor_role      TO 'auditor_user'@'%',      'auditor_user'@'localhost';

SELECT '09_roles.sql complete' AS status;
