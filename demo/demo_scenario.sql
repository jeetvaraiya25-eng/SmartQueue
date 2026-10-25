-- =============================================================================
-- Demo scenario for the viva. Run AFTER ./setup.sh, in the mysql client,
-- one section at a time, while the website queue is open on another screen.
-- The page refreshes every 3 seconds, so each CALL shows up on the board.
--
-- These statements register new patients. They do not depend on patients
-- 13–15, so they still work after sql/10_tests.sql. Prefer a fresh setup
-- if you want the seeded board (Rohan, Priya, …) as well.
-- =============================================================================

USE SmartQueue;

-- Who is allowed to receive a patient right now?
SELECT Doctor_Name, Department_Name, Doctor_Role, Current_Status
FROM vw_doctor_directory
ORDER BY Current_Status, Department_Name, Doctor_Name;

-- ---------------------------------------------------------------------------
-- (1) Admit a stable patient. Symptom "bleeding" routes to Emergency Medicine.
--     Vitals are normal, so fn_calc_esi returns 5.
-- ---------------------------------------------------------------------------
CALL sp_register_patient('Demo Stable', '9811111801', 'stable@example.com', '1996-04-04');
SET @p_stable = LAST_INSERT_ID();
CALL sp_admit_patient_safe(@p_stable, 'minor cut and bleeding', 76, 99, 120, 78, 36.6, 1);

SELECT Doctor_Name, Queue_Position, Patient_Name, ESI, Est_Wait_Time
FROM vw_live_queue
WHERE Patient_Name IN ('Demo Stable', 'Demo Second', 'Demo Critical')
ORDER BY Doctor_Name, Queue_Position;

-- ---------------------------------------------------------------------------
-- (2) A second stable patient, then a critical one. The critical patient
--     is ESI 1 and moves to position 1. The database does the reordering.
-- ---------------------------------------------------------------------------
CALL sp_register_patient('Demo Second', '9811111802', 'second@example.com', '1994-02-02');
SET @p_second = LAST_INSERT_ID();
CALL sp_admit_patient_safe(@p_second, 'small wound and bleeding', 80, 98, 118, 76, 36.7, 1);

CALL sp_register_patient('Demo Critical', '9811111803', 'critical@example.com', '1988-08-08');
SET @p_critical = LAST_INSERT_ID();
CALL sp_admit_patient_safe(
  @p_critical, 'uncontrolled bleeding and unconscious', 155, 86, 78, 48, 37.0, 8
);

SELECT Doctor_Name, Queue_Position, Patient_Name, ESI, Est_Wait_Time
FROM vw_live_queue
WHERE Patient_Name LIKE 'Demo %'
ORDER BY Queue_Position;

-- ---------------------------------------------------------------------------
-- (3) Reassess Demo Second. SpO2 91 is ESI 2, so they move ahead of Demo Stable.
-- ---------------------------------------------------------------------------
SET @enc_second = (SELECT Encounter_ID FROM Encounter_Triage_Event e
                   JOIN Patient p ON p.Patient_ID = e.Patient_ID
                   WHERE p.Name = 'Demo Second' AND e.Check_out_Time IS NULL);
CALL sp_reassess_patient_safe(@enc_second, 128, 91, 118, 76, 37.1, 4);

SELECT Patient_Name, Old_Score, New_Score, History_Notes
FROM vw_score_audit
WHERE Patient_Name = 'Demo Second'
ORDER BY History_ID;

-- ---------------------------------------------------------------------------
-- (4) Aging. Imran Shaikh (encounter 5) has already been waiting a long time.
--     Drop the ESI 5 limit below that wait, run aging once, then put the
--     limit back so the every-minute event does not keep climbing.
-- ---------------------------------------------------------------------------
CALL sp_toggle_aging(0);
CALL sp_set_aging_policy(5, 30);
CALL sp_age_queue();
SELECT Patient_Name, Old_Score, New_Score, History_Notes
FROM vw_score_audit
WHERE History_Notes LIKE 'Escalated%'
ORDER BY History_ID DESC;
CALL sp_set_aging_policy(5, 120);
CALL sp_toggle_aging(1);

-- ---------------------------------------------------------------------------
-- (5) Overload. Threshold 0 means the next arrival raises an alert.
-- ---------------------------------------------------------------------------
CALL sp_set_config('doctor_queue_threshold', '0');
CALL sp_register_patient('Demo Crowd', '9811111804', 'crowd@example.com', '1992-12-12');
CALL sp_admit_patient_safe(LAST_INSERT_ID(), 'another bleeding wound', 77, 99, 122, 78, 36.5, 1);
SELECT * FROM vw_open_alerts;
CALL sp_set_config('doctor_queue_threshold', '5');
CALL sp_auto_resolve_alerts();

-- ---------------------------------------------------------------------------
-- (6) Audit row, and a soft delete that must fail while the visit is active.
-- ---------------------------------------------------------------------------
SELECT Audit_ID, Table_Name, Action, Changed_By, Changed_At
FROM Audit_Log
ORDER BY Audit_ID DESC
LIMIT 8;

-- This call is supposed to fail: Demo Critical is still in the department.
-- Run it on its own. Expected: Cannot delete a patient who has an active encounter.
-- CALL sp_soft_delete_patient(@p_critical);

-- ---------------------------------------------------------------------------
-- (7) Role check. Open a second client as each user. Passwords are in the README.
--     mysql -u doctor_user -p -h 127.0.0.1 --protocol=TCP SmartQueue
--     SELECT Patient_Name, ESI, Heart_Rate FROM vw_doctor_clinical;   -- allowed
--     SELECT Phone FROM Patient;                                      -- denied
-- =============================================================================
SELECT 'Demo script finished' AS status;
