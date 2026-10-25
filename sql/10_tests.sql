-- =============================================================================
-- 10_tests.sql
-- Run as root, after 01 through 09, on a freshly loaded database.
-- The script admits real patients and escalates one seeded visit, then
-- tries to put that visit back. Re-run ./setup.sh afterwards if the board
-- should look exactly like the seed again.
--
-- Expected results are inserted into Test_Result. The last SELECT is the
-- mark sheet: every row should say PASS.
--
-- Two-session deadlock / lock demo is not a single connection. See
-- demo/concurrent_admit.js and the comments at the bottom of this file.
-- =============================================================================

USE SmartQueue;

-- Hold the scheduler still while the assertions run.
CALL sp_toggle_aging(0);

DROP TABLE IF EXISTS Test_Result;
CREATE TABLE Test_Result (
  Test_Name VARCHAR(80)  NOT NULL PRIMARY KEY,
  Result    VARCHAR(8)   NOT NULL,
  Detail    VARCHAR(255) NULL
);

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_expect_error$$
CREATE PROCEDURE sp_expect_error(
  IN p_name VARCHAR(80),
  IN p_like VARCHAR(120)
)
BEGIN
  -- Placeholder. Each negative test is its own procedure so the handler
  -- can see a real CALL. This one only documents the pattern.
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Do not call sp_expect_error';
END$$

DROP PROCEDURE IF EXISTS sp_test_bad_phone$$
CREATE PROCEDURE sp_test_bad_phone()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  CALL sp_register_patient('Bad Phone', '12345', 'a@b.co', '2000-01-01');
  INSERT INTO Test_Result VALUES (
    'register_rejects_short_phone',
    IF(v_msg LIKE '%10-digit%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_bad_bp$$
CREATE PROCEDURE sp_test_bad_bp(IN p_encounter INT)
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  CALL sp_reassess_patient_safe(p_encounter, 80, 98, 70, 90, 36.6, 3);
  INSERT INTO Test_Result VALUES (
    'diastolic_must_be_lower',
    IF(v_msg LIKE '%Diastolic BP must be lower than systolic BP%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_double_discharge$$
CREATE PROCEDURE sp_test_double_discharge(IN p_encounter INT)
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  CALL sp_discharge_patient_safe(p_encounter);
  INSERT INTO Test_Result VALUES (
    'second_discharge_rejected',
    IF(v_msg LIKE '%already discharged%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_hard_delete$$
CREATE PROCEDURE sp_test_hard_delete()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  DELETE FROM Patient WHERE Patient_ID = 8;
  INSERT INTO Test_Result VALUES (
    'hard_delete_patient_blocked',
    IF(v_msg LIKE '%soft delete%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_active_soft_delete$$
CREATE PROCEDURE sp_test_active_soft_delete()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  CALL sp_soft_delete_patient(1);
  INSERT INTO Test_Result VALUES (
    'soft_delete_active_patient_blocked',
    IF(v_msg LIKE '%active encounter%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_status_guard$$
CREATE PROCEDURE sp_test_status_guard()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  UPDATE Doctor SET Current_Status = 'Available' WHERE Doctor_ID = 1;
  INSERT INTO Test_Result VALUES (
    'direct_status_update_blocked',
    IF(v_msg LIKE '%maintained by the database%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_overlap$$
CREATE PROCEDURE sp_test_overlap()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE v_shift INT;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  INSERT INTO Shift (Shift_Name, Start_Time, End_Time)
  VALUES ('Short morning', '08:00:00', '12:00:00');
  SET v_shift = LAST_INSERT_ID();
  CALL sp_assign_shift(1, v_shift, CURDATE());
  INSERT INTO Test_Result VALUES (
    'overlapping_shift_blocked',
    IF(v_msg LIKE '%overlapping shift%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DROP PROCEDURE IF EXISTS sp_test_active_delete_encounter$$
CREATE PROCEDURE sp_test_active_delete_encounter()
BEGIN
  DECLARE v_msg TEXT DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
  END;
  DELETE FROM Encounter_Triage_Event WHERE Encounter_ID = 1;
  INSERT INTO Test_Result VALUES (
    'active_encounter_delete_blocked',
    IF(v_msg LIKE '%cannot be deleted%', 'PASS', 'FAIL'),
    LEFT(v_msg, 250)
  );
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------
-- 1. ESI function, including the boundaries from Triage_Rule
-- ---------------------------------------------------------------------------
INSERT INTO Test_Result
SELECT 'esi_matches_rules',
       IF(SUM(ok) = COUNT(*), 'PASS', 'FAIL'),
       CONCAT(SUM(ok), ' of ', COUNT(*), ' boundaries')
FROM (
  SELECT fn_calc_esi(80, 89, 120, 36.6, 0) = 1 AS ok
  UNION ALL SELECT fn_calc_esi(80, 98, 79, 36.6, 0) = 1
  UNION ALL SELECT fn_calc_esi(151, 98, 120, 36.6, 0) = 1
  UNION ALL SELECT fn_calc_esi(39, 98, 120, 36.6, 0) = 1
  UNION ALL SELECT fn_calc_esi(80, 90, 120, 36.6, 0) = 2
  UNION ALL SELECT fn_calc_esi(80, 93, 120, 36.6, 0) = 2
  UNION ALL SELECT fn_calc_esi(120, 98, 120, 36.6, 0) = 2
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 8) = 2
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 39.0, 0) = 3
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 5) = 3
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 7) = 3
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 4) = 4
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 3) = 4
  UNION ALL SELECT fn_calc_esi(80, 98, 120, 36.6, 2) = 5
  UNION ALL SELECT fn_calc_esi(40, 94, 80, 38.9, 2) = 5
) AS boundaries;

-- Seeded readings still agree with the function. Vikram's first reading is
-- ESI 3 and his reassessment is ESI 2, which is what Score_History stored.
INSERT INTO Test_Result
SELECT 'esi_matches_seed_vitals',
       IF(SUM(ok) = COUNT(*), 'PASS', 'FAIL'),
       CONCAT(SUM(ok), ' of ', COUNT(*), ' readings')
FROM (
  SELECT fn_calc_esi(Heart_Rate, SpO2, Systolic_BP, Temperature, Pain_Scale) =
         CASE Log_ID WHEN 7 THEN 3 ELSE
           (SELECT e.Final_Queue_Score
            FROM Encounter_Triage_Event e
            WHERE e.Encounter_ID = v.Encounter_ID)
         END AS ok
  FROM Vitals_Log v
  WHERE Log_ID <> 8
  UNION ALL
  SELECT fn_calc_esi(Heart_Rate, SpO2, Systolic_BP, Temperature, Pain_Scale) = 2
  FROM Vitals_Log WHERE Log_ID = 8
) AS seeded;

-- ---------------------------------------------------------------------------
-- 2. Duty, department routing, wait estimate
-- ---------------------------------------------------------------------------
INSERT INTO Test_Result VALUES
  ('on_duty_morning',
   IF(fn_is_on_duty(1, TIMESTAMP(CURDATE(), '08:00:00')) = 1, 'PASS', 'FAIL'),
   'Dr. Meera Kapoor at 08:00'),
  ('off_duty_late',
   IF(fn_is_on_duty(1, TIMESTAMP(CURDATE(), '23:30:00')) = 0, 'PASS', 'FAIL'),
   'Dr. Meera Kapoor at 23:30'),
  ('on_duty_night',
   IF(fn_is_on_duty(5, TIMESTAMP(CURDATE(), '23:30:00')) = 1, 'PASS', 'FAIL'),
   'Dr. Neha Kulkarni at 23:30'),
  ('dept_chest_pain',
   IF(fn_pick_department('severe chest pain and sweating') = 2, 'PASS', 'FAIL'),
   'Cardiology'),
  ('dept_longest_keyword',
   IF(fn_pick_department('child with a wrist fracture') = 3, 'PASS', 'FAIL'),
   'fracture beats child'),
  ('dept_default_em',
   IF(fn_pick_department('feeling vaguely unwell') = 1, 'PASS', 'FAIL'),
   'Emergency Medicine'),
  ('wait_position_one_is_zero',
   IF(fn_estimate_wait(1, 1) = 0, 'PASS', 'FAIL'),
   'front of queue'),
  ('wait_uses_real_average',
   IF(fn_estimate_wait(1, 2) = 18, 'PASS', 'FAIL'),
   'Meera Kapoor discharged visit was 18 minutes'),
  ('wait_uses_default',
   IF(fn_estimate_wait(6, 2) = 15, 'PASS', 'FAIL'),
   'Arvind Rao has no discharged visits');

-- ---------------------------------------------------------------------------
-- 3. Line-cutting. All three complaints contain "bleeding", so they share
--    the one on-duty Emergency Medicine doctor.
-- ---------------------------------------------------------------------------
CALL sp_admit_patient_safe(13, 'minor cut and bleeding', 76, 99, 120, 78, 36.6, 1);
SET @enc_a = @sq_admit_id;

CALL sp_admit_patient_safe(14, 'small cut and bleeding', 80, 98, 118, 76, 36.7, 2);
SET @enc_b = @sq_admit_id;

CALL sp_reassess_patient_safe(@enc_b, 130, 92, 110, 70, 37.0, 4);

INSERT INTO Test_Result
SELECT 'reassess_jumps_queue',
       IF(wb.Queue_Position < wa.Queue_Position
          AND eb.Final_Queue_Score = 2
          AND ea.Final_Queue_Score = 5
          AND ea.Doctor_ID = eb.Doctor_ID, 'PASS', 'FAIL'),
       CONCAT('A pos ', wa.Queue_Position, ' ESI ', ea.Final_Queue_Score,
              '; B pos ', wb.Queue_Position, ' ESI ', eb.Final_Queue_Score)
FROM Wait_List wa
JOIN Wait_List wb ON wb.Doctor_ID = wa.Doctor_ID
JOIN Encounter_Triage_Event ea ON ea.Encounter_ID = wa.Encounter_ID
JOIN Encounter_Triage_Event eb ON eb.Encounter_ID = wb.Encounter_ID
WHERE wa.Encounter_ID = @enc_a AND wb.Encounter_ID = @enc_b;

CALL sp_admit_patient_safe(
  15, 'uncontrolled bleeding and unconscious', 155, 86, 78, 48, 37.0, 8
);
SET @enc_c = @sq_admit_id;

-- Nobody with a worse ESI may sit ahead of an ESI 1 patient. Position 1 is
-- not asserted literally: depending on the shift at run time, a handed-over
-- ESI 1 patient who arrived earlier may legitimately be ahead.
INSERT INTO Test_Result
SELECT 'critical_patient_takes_position_1',
       IF(e.Final_Queue_Score = 1
          AND d.`Role` IN ('Consultant', 'Senior Consultant')
          AND NOT EXISTS (
            SELECT 1
            FROM Wait_List w2
            JOIN Encounter_Triage_Event e2 ON e2.Encounter_ID = w2.Encounter_ID
            WHERE w2.Doctor_ID = w.Doctor_ID
              AND w2.Queue_Position < w.Queue_Position
              AND e2.Final_Queue_Score > 1
          ), 'PASS', 'FAIL'),
       CONCAT(d.Name, ' ', d.`Role`, ' ESI ', e.Final_Queue_Score, ' pos ', w.Queue_Position)
FROM Encounter_Triage_Event e
JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID
JOIN Wait_List w ON w.Encounter_ID = e.Encounter_ID
WHERE e.Encounter_ID = @enc_c;

CALL sp_test_bad_bp(@enc_a);

-- The rejected reading must not have been stored.
INSERT INTO Test_Result
SELECT 'bad_bp_not_stored',
       IF(COUNT(*) = 1, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' vital row(s) on encounter A')
FROM Vitals_Log
WHERE Encounter_ID = @enc_a;

CALL sp_discharge_patient_safe(@enc_a);
CALL sp_test_double_discharge(@enc_a);

INSERT INTO Test_Result
SELECT 'discharge_removes_queue_row',
       IF(COUNT(*) = 0, 'PASS', 'FAIL'),
       'encounter A should be gone from Wait_List'
FROM Wait_List
WHERE Encounter_ID = @enc_a;

-- ---------------------------------------------------------------------------
-- 4. Aging, alerts, soft delete, guards, full text, audit
-- ---------------------------------------------------------------------------
CALL sp_set_aging_policy(5, 60);
CALL sp_age_queue();

INSERT INTO Test_Result
SELECT 'aging_raises_one_level',
       IF(e.Final_Queue_Score = 4, 'PASS', 'FAIL'),
       CONCAT('Imran ESI is now ', e.Final_Queue_Score)
FROM Encounter_Triage_Event e
WHERE e.Encounter_ID = 5;

INSERT INTO Test_Result
SELECT 'aging_writes_score_history',
       IF(s.History_Notes = 'Escalated: exceeded waiting limit'
          AND s.Old_Score = 5 AND s.New_Score = 4, 'PASS', 'FAIL'),
       s.History_Notes
FROM Score_History s
WHERE s.Encounter_ID = 5
ORDER BY s.History_ID DESC
LIMIT 1;

CALL sp_set_aging_policy(5, 120);

-- Put Imran back so the seeded board is still explainable, and so the
-- scheduler does not keep escalating him (he had already waited 100 min).
SET @sq_score_note = 'Test cleanup: restore seeded ESI';
UPDATE Encounter_Triage_Event
   SET Final_Queue_Score = 5,
       Rule_ID = 5,
       Arrival_Time = DATE_SUB(NOW(), INTERVAL 10 MINUTE)
 WHERE Encounter_ID = 5;
SET @sq_score_note = NULL;

CALL sp_set_config('doctor_queue_threshold', '0');
CALL sp_register_patient('Test Overload', '9811111999', 'overload@example.com', '1990-05-05');
SET @overload_patient = (
  SELECT Patient_ID FROM Patient WHERE Phone = '9811111999' ORDER BY Patient_ID DESC LIMIT 1
);
CALL sp_admit_patient_safe(@overload_patient, 'another small bleeding wound', 78, 99, 120, 76, 36.6, 1);

INSERT INTO Test_Result
SELECT 'overload_alert_created',
       IF(COUNT(*) >= 1, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' overload alert(s)')
FROM Alert
WHERE Alert_Type = 'DOCTOR_OVERLOAD';

-- Raise the limit above any queue the handover could have built, resolve,
-- then restore the seeded value.
CALL sp_set_config('doctor_queue_threshold', '50');
CALL sp_auto_resolve_alerts();

INSERT INTO Test_Result
SELECT 'overload_alert_auto_resolved',
       IF(
         (SELECT COUNT(*) FROM Alert WHERE Alert_Type = 'DOCTOR_OVERLOAD' AND Is_Resolved = 0) = 0
         AND (SELECT COUNT(*) FROM Alert WHERE Alert_Type = 'DOCTOR_OVERLOAD' AND Is_Resolved = 1) >= 1,
         'PASS', 'FAIL'),
       'open overload alerts should be gone'
FROM DUAL;
CALL sp_set_config('doctor_queue_threshold', '5');

-- ---------------------------------------------------------------------------
-- 4b. Shift handover: take today's shifts away from a doctor who is on duty
-- with a queue. The refresh must move every patient to an on-duty doctor,
-- leave the queue empty, and log each move.
-- ---------------------------------------------------------------------------
SET @handover_doc = (
  SELECT w.Doctor_ID
  FROM Wait_List w
  JOIN Doctor d ON d.Doctor_ID = w.Doctor_ID
  WHERE d.Is_Deleted = 0
    AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
  GROUP BY w.Doctor_ID
  ORDER BY COUNT(*) DESC, w.Doctor_ID
  LIMIT 1
);
SET @handover_n = (SELECT COUNT(*) FROM Wait_List WHERE Doctor_ID = @handover_doc);
SET @audit_before = (SELECT COUNT(*) FROM Audit_Log WHERE Table_Name = 'Handover');

DELETE FROM Doctor_Shift
 WHERE Doctor_ID = @handover_doc
   AND Shift_Date BETWEEN DATE_SUB(CURDATE(), INTERVAL 1 DAY) AND CURDATE();
CALL sp_refresh_doctor_status(@handover_doc);

INSERT INTO Test_Result
SELECT 'handover_empties_off_duty_queue',
       IF(@handover_n > 0
          AND (SELECT COUNT(*) FROM Wait_List WHERE Doctor_ID = @handover_doc) = 0
          AND (SELECT Current_Status FROM Doctor WHERE Doctor_ID = @handover_doc) = 'Off_Duty',
          'PASS', 'FAIL'),
       CONCAT('doctor ', @handover_doc, ' had ', @handover_n, ' waiting')
FROM DUAL;

INSERT INTO Test_Result
SELECT 'handover_moves_to_on_duty_doctor',
       IF(COUNT(*) = @handover_n, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' of ', @handover_n, ' now with on-duty doctors')
FROM Audit_Log a
JOIN Wait_List w ON w.Encounter_ID = CAST(a.Record_ID AS UNSIGNED)
WHERE a.Table_Name = 'Handover'
  AND JSON_EXTRACT(a.Old_Data, '$.Doctor_ID') = @handover_doc
  AND fn_is_on_duty(w.Doctor_ID, NOW()) = 1;

INSERT INTO Test_Result
SELECT 'handover_is_audited',
       IF(COUNT(*) - @audit_before = @handover_n, 'PASS', 'FAIL'),
       CONCAT(COUNT(*) - @audit_before, ' Handover audit row(s) written')
FROM Audit_Log
WHERE Table_Name = 'Handover';

CALL sp_test_active_soft_delete();
CALL sp_soft_delete_patient(8);
CALL sp_restore_patient(8);

INSERT INTO Test_Result
SELECT 'soft_delete_and_restore',
       IF(Is_Deleted = 0 AND Deleted_At IS NULL, 'PASS', 'FAIL'),
       'Ananya Rao restored'
FROM Patient WHERE Patient_ID = 8;

CALL sp_test_hard_delete();
CALL sp_test_status_guard();
CALL sp_test_overlap();
CALL sp_test_active_delete_encounter();
CALL sp_test_bad_phone();

INSERT INTO Test_Result
SELECT 'similar_cases_chest_pain',
       IF(COUNT(*) >= 1 AND MAX(Relevance) > 0, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' hit(s)')
FROM (
  SELECT MATCH(Initial_Symptoms) AGAINST ('chest pain' IN NATURAL LANGUAGE MODE) AS Relevance
  FROM Encounter_Triage_Event
  WHERE MATCH(Initial_Symptoms) AGAINST ('chest pain' IN NATURAL LANGUAGE MODE)
) AS hits;

INSERT INTO Test_Result
SELECT 'audit_log_records_registration',
       IF(COUNT(*) >= 1, 'PASS', 'FAIL'),
       CONCAT(COUNT(*), ' Patient insert audit row(s)')
FROM Audit_Log
WHERE Table_Name = 'Patient' AND Action = 'INSERT';

CALL sp_toggle_aging(1);

SELECT Result, COUNT(*) AS Tests
FROM Test_Result
GROUP BY Result
ORDER BY Result;

SELECT Test_Name, Result, Detail
FROM Test_Result
ORDER BY Result, Test_Name;

-- ---------------------------------------------------------------------------
-- Two sessions at once (run in two terminals, not in this file):
--
--   Session A                          Session B
--   USE SmartQueue;                    USE SmartQueue;
--   START TRANSACTION;                 START TRANSACTION;
--   -- locks doctors in id order, so B waits instead of deadlocking
--   CALL sp_admit_patient_safe(13, 'minor cut and bleeding',
--        76, 99, 120, 78, 36.6, 1);
--                                      CALL sp_admit_patient_safe(14, 'small cut and bleeding',
--                                           80, 98, 118, 76, 36.7, 2);
--
-- Both calls commit. If a deadlock (1213) or lock wait (1205) does occur,
-- the safe wrapper retries up to three times. demo/concurrent_admit.js
-- fires the two calls together.
-- ---------------------------------------------------------------------------
