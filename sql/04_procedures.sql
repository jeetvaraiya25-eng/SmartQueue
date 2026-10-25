-- =============================================================================
-- 04_procedures.sql
-- Every change the website is allowed to make is a procedure in this file.
-- Procedures are SQL SECURITY DEFINER: the nurse, receptionist, doctor and
-- admin accounts have no INSERT/UPDATE/DELETE on the base tables.
--
-- Lock order in the three clinical procedures, always:
--   1. the patient row
--   2. doctor rows in Doctor_ID order
--   3. the encounter row
-- Two admissions therefore queue on the same doctor locks instead of
-- deadlocking. The *_safe wrappers still retry error 1213 and 1205.
-- =============================================================================

USE SmartQueue;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- Queue, duty status, shifts
-- -----------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_rebuild_queue$$
CREATE PROCEDURE sp_rebuild_queue(IN p_doctor_id INT)
SQL SECURITY DEFINER
BEGIN
  -- ROW_NUMBER cannot sit directly in UPDATE, so the ranking is a derived
  -- table. Wait time is (people ahead) × this doctor's own average.
  UPDATE Wait_List w
  JOIN (
    SELECT w2.Queue_ID,
           ROW_NUMBER() OVER (
             ORDER BY e.Final_Queue_Score ASC, e.Arrival_Time ASC
           ) AS new_pos
    FROM Wait_List w2
    JOIN Encounter_Triage_Event e ON e.Encounter_ID = w2.Encounter_ID
    WHERE w2.Doctor_ID = p_doctor_id
  ) AS ranked ON ranked.Queue_ID = w.Queue_ID
  SET w.Queue_Position = ranked.new_pos,
      w.Est_Wait_Time  = fn_estimate_wait(p_doctor_id, ranked.new_pos);
END$$

-- p_waiting is passed in so a Wait_List trigger does not have to read
-- Wait_List again (MySQL error 1442). Off duty wins over a non-empty queue;
-- sp_handover_queue then moves those patients to a doctor who is on duty.
DROP PROCEDURE IF EXISTS sp_apply_doctor_status$$
CREATE PROCEDURE sp_apply_doctor_status(
  IN p_doctor_id INT,
  IN p_waiting   INT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_deleted TINYINT;
  DECLARE v_status  VARCHAR(20);

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  SELECT Is_Deleted INTO v_deleted
  FROM Doctor
  WHERE Doctor_ID = p_doctor_id;

  IF v_deleted IS NULL THEN
    SET v_status = NULL;
  ELSEIF v_deleted = 1 OR fn_is_on_duty(p_doctor_id, NOW()) = 0 THEN
    SET v_status = 'Off_Duty';
  ELSEIF IFNULL(p_waiting, 0) > 0 THEN
    SET v_status = 'Busy';
  ELSE
    SET v_status = 'Available';
  END IF;

  IF v_status IS NOT NULL THEN
    SET @sq_allow_status = 1;
    UPDATE Doctor
       SET Current_Status = v_status
     WHERE Doctor_ID = p_doctor_id
       AND Current_Status <> v_status;
    SET @sq_allow_status = 0;
  END IF;
END$$

-- Shift handover. A doctor whose shift has ended may still have patients
-- waiting. Each of them is moved to the doctor admission would have chosen
-- right now (fn_pick_doctor: same department first, then Emergency
-- Medicine, consultants only for ESI 1). A patient stays put when nobody
-- suitable is on duty. Every move is written to Audit_Log under the
-- name 'Handover' so the auditor can see who handed over to whom.
-- Never called from a trigger: it writes Wait_List and Encounter_Triage_Event.
DROP PROCEDURE IF EXISTS sp_handover_queue$$
CREATE PROCEDURE sp_handover_queue(IN p_doctor_id INT)
SQL SECURITY DEFINER
proc: BEGIN
  DECLARE v_deleted   TINYINT;
  DECLARE v_old_name  VARCHAR(100);
  DECLARE v_enc       INT;
  DECLARE v_esi       TINYINT;
  DECLARE v_dept      INT;
  DECLARE v_new       INT;
  DECLARE v_new_dept  INT;
  DECLARE v_new_name  VARCHAR(100);
  DECLARE v_last_enc  INT DEFAULT 0;
  DECLARE v_no_doctor TINYINT DEFAULT 0;
  DECLARE v_moved     TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;
  -- fn_pick_doctor signals 45000 when nobody is on duty for the case.
  DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_no_doctor = 1;

  SELECT Is_Deleted, Name INTO v_deleted, v_old_name
  FROM Doctor
  WHERE Doctor_ID = p_doctor_id;

  IF v_deleted IS NULL THEN
    LEAVE proc;
  END IF;
  IF v_deleted = 0 AND fn_is_on_duty(p_doctor_id, NOW()) = 1 THEN
    LEAVE proc;
  END IF;

  move_loop: LOOP
    SET v_enc = NULL;
    SELECT w.Encounter_ID, e.Final_Queue_Score, e.Department_ID
      INTO v_enc, v_esi, v_dept
    FROM Wait_List w
    JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
    WHERE w.Doctor_ID = p_doctor_id
      AND w.Encounter_ID > v_last_enc
    ORDER BY w.Encounter_ID
    LIMIT 1;

    IF v_enc IS NULL THEN
      LEAVE move_loop;
    END IF;
    SET v_last_enc = v_enc;

    SET v_no_doctor = 0;
    SET v_new = NULL;
    SET v_new = fn_pick_doctor(v_dept, v_esi);

    -- Admission may refuse a case when the department and Emergency
    -- Medicine are both uncovered. A patient already inside the hospital
    -- cannot be refused, so fall back to the on-duty doctor with the
    -- shortest queue anywhere.
    IF v_no_doctor = 1 OR v_new IS NULL THEN
      SET v_new = NULL;
      SELECT d.Doctor_ID INTO v_new
      FROM Doctor d
      LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
      WHERE d.Is_Deleted = 0
        AND d.Doctor_ID <> p_doctor_id
        AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
      GROUP BY d.Doctor_ID
      ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
      LIMIT 1;
    END IF;

    IF v_new IS NULL OR v_new = p_doctor_id THEN
      ITERATE move_loop;
    END IF;

    SELECT Department_ID, Name INTO v_new_dept, v_new_name
    FROM Doctor
    WHERE Doctor_ID = v_new;

    -- The visit now belongs to the receiving doctor and their department.
    UPDATE Encounter_Triage_Event
       SET Doctor_ID = v_new, Department_ID = v_new_dept
     WHERE Encounter_ID = v_enc;

    -- Delete + insert so the Wait_List triggers keep both doctors' status
    -- and the overload alerts correct.
    DELETE FROM Wait_List WHERE Encounter_ID = v_enc;
    INSERT INTO Wait_List
      (Encounter_ID, Doctor_ID, Queue_Position, Assigned_Time, Est_Wait_Time)
    VALUES
      (v_enc, v_new, 1, NOW(), 0);

    -- Wait_List rows are audited by their own triggers; this extra row,
    -- under the logical name 'Handover', records the hand-off itself.
    INSERT INTO Audit_Log
      (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
    VALUES (
      'Handover', v_enc, 'UPDATE',
      JSON_OBJECT('Encounter_ID', v_enc, 'Doctor_ID', p_doctor_id, 'Doctor', v_old_name),
      JSON_OBJECT('Encounter_ID', v_enc, 'Doctor_ID', v_new, 'Doctor', v_new_name,
                  'Reason', 'Shift handover'),
      CURRENT_USER(), NOW()
    );

    CALL sp_rebuild_queue(v_new);
    SET v_moved = 1;
  END LOOP;

  IF v_moved = 1 THEN
    CALL sp_rebuild_queue(p_doctor_id);
  END IF;
END proc$$

-- Hands over first, so an off-duty doctor ends up Off_Duty with an empty
-- queue rather than Off_Duty with patients nobody is seeing.
DROP PROCEDURE IF EXISTS sp_refresh_doctor_status$$
CREATE PROCEDURE sp_refresh_doctor_status(IN p_doctor_id INT)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_waiting INT DEFAULT 0;
  CALL sp_handover_queue(p_doctor_id);
  SELECT COUNT(*) INTO v_waiting
  FROM Wait_List
  WHERE Doctor_ID = p_doctor_id;
  CALL sp_apply_doctor_status(p_doctor_id, v_waiting);
END$$

DROP PROCEDURE IF EXISTS sp_refresh_all_doctor_status$$
CREATE PROCEDURE sp_refresh_all_doctor_status()
SQL SECURITY DEFINER
BEGIN
  DECLARE v_id   INT;
  DECLARE v_last INT DEFAULT 0;

  -- Hand over every off-duty queue before any status is computed, so a
  -- receiving doctor with a lower ID is not marked Available too early.
  handover_loop: LOOP
    SET v_id = NULL;
    SELECT Doctor_ID INTO v_id
    FROM Doctor
    WHERE Is_Deleted = 0
      AND Doctor_ID > v_last
    ORDER BY Doctor_ID
    LIMIT 1;

    IF v_id IS NULL THEN
      LEAVE handover_loop;
    END IF;

    CALL sp_handover_queue(v_id);
    SET v_last = v_id;
  END LOOP;

  SET v_last = 0;
  refresh_loop: LOOP
    SET v_id = NULL;
    SELECT Doctor_ID INTO v_id
    FROM Doctor
    WHERE Is_Deleted = 0
      AND Doctor_ID > v_last
    ORDER BY Doctor_ID
    LIMIT 1;

    IF v_id IS NULL THEN
      LEAVE refresh_loop;
    END IF;

    CALL sp_refresh_doctor_status(v_id);
    SET v_last = v_id;
  END LOOP;
END$$

DROP PROCEDURE IF EXISTS sp_assign_shift$$
CREATE PROCEDURE sp_assign_shift(
  IN p_doctor_id INT,
  IN p_shift_id  INT,
  IN p_date      DATE
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_deleted TINYINT;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  IF p_date IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Shift date is required';
  END IF;

  SELECT Is_Deleted INTO v_deleted
  FROM Doctor WHERE Doctor_ID = p_doctor_id;

  IF v_deleted IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
  END IF;
  IF v_deleted = 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot assign a shift to a deleted doctor';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM Shift WHERE Shift_ID = p_shift_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Shift not found';
  END IF;
  IF fn_doctor_shift_overlaps(p_doctor_id, p_shift_id, p_date, NULL) = 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Doctor already has an overlapping shift on this date';
  END IF;

  INSERT INTO Doctor_Shift (Doctor_ID, Shift_ID, Shift_Date)
  VALUES (p_doctor_id, p_shift_id, p_date);

  CALL sp_refresh_doctor_status(p_doctor_id);

  SELECT LAST_INSERT_ID() AS Doctor_Shift_ID, p_doctor_id AS Doctor_ID,
         p_shift_id AS Shift_ID, p_date AS Shift_Date;
END$$

DROP PROCEDURE IF EXISTS sp_unassign_shift$$
CREATE PROCEDURE sp_unassign_shift(IN p_doctor_shift_id INT)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_doctor INT;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  SELECT Doctor_ID INTO v_doctor
  FROM Doctor_Shift
  WHERE Doctor_Shift_ID = p_doctor_shift_id;

  IF v_doctor IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Shift assignment not found';
  END IF;

  DELETE FROM Doctor_Shift WHERE Doctor_Shift_ID = p_doctor_shift_id;
  CALL sp_refresh_doctor_status(v_doctor);
  SELECT p_doctor_shift_id AS Removed_ID, v_doctor AS Doctor_ID;
END$$

-- -----------------------------------------------------------------------------
-- Admission, reassessment, discharge
-- -----------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_admit_patient$$
CREATE PROCEDURE sp_admit_patient(
  IN  p_patient_id   INT,
  IN  p_symptoms     VARCHAR(500),
  IN  p_hr           SMALLINT,
  IN  p_spo2         TINYINT,
  IN  p_sys          SMALLINT,
  IN  p_dia          SMALLINT,
  IN  p_temp         DECIMAL(4,1),
  IN  p_pain         TINYINT,
  OUT p_encounter_id INT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_score   TINYINT;
  DECLARE v_rule    INT;
  DECLARE v_dept    INT;
  DECLARE v_doctor  INT;
  DECLARE v_active  INT;
  DECLARE v_deleted TINYINT;
  DECLARE v_lock_id INT;
  DECLARE v_last    INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_encounter_id = NULL;

  IF p_symptoms IS NULL OR CHAR_LENGTH(TRIM(p_symptoms)) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Symptom description is required';
  END IF;

  START TRANSACTION;

  SELECT Is_Deleted INTO v_deleted
  FROM Patient
  WHERE Patient_ID = p_patient_id
  FOR UPDATE;

  IF v_deleted IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient not found';
  END IF;
  IF v_deleted = 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient record has been deleted';
  END IF;

  SELECT COUNT(*) INTO v_active
  FROM Encounter_Triage_Event
  WHERE Patient_ID = p_patient_id
    AND Check_out_Time IS NULL;

  IF v_active > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Patient already has an active encounter';
  END IF;

  -- Lock every working doctor in primary-key order before choosing one.
  lock_doctors: LOOP
    SET v_lock_id = NULL;
    SELECT Doctor_ID INTO v_lock_id
    FROM Doctor
    WHERE Is_Deleted = 0
      AND Doctor_ID > v_last
    ORDER BY Doctor_ID
    LIMIT 1
    FOR UPDATE;

    IF v_lock_id IS NULL THEN
      LEAVE lock_doctors;
    END IF;
    SET v_last = v_lock_id;
  END LOOP;

  SET v_score  = fn_calc_esi(p_hr, p_spo2, p_sys, p_temp, p_pain);
  SET v_dept   = fn_pick_department(p_symptoms);
  SET v_doctor = fn_pick_doctor(v_dept, v_score);

  SELECT Rule_ID INTO v_rule
  FROM Triage_Rule
  WHERE ESI_Level = v_score
  LIMIT 1;

  IF v_rule IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No triage rule is configured for this ESI level';
  END IF;

  -- The department stored on the visit is the one actually handling it.
  SELECT Department_ID INTO v_dept
  FROM Doctor
  WHERE Doctor_ID = v_doctor;

  INSERT INTO Encounter_Triage_Event
    (Patient_ID, Doctor_ID, Department_ID, Rule_ID,
     Arrival_Time, Initial_Symptoms, Final_Queue_Score)
  VALUES
    (p_patient_id, v_doctor, v_dept, v_rule,
     NOW(), TRIM(p_symptoms), v_score);

  SET p_encounter_id = LAST_INSERT_ID();

  INSERT INTO Vitals_Log
    (Encounter_ID, Log_Timestamp, Type_Name, Heart_Rate, SpO2,
     Systolic_BP, Diastolic_BP, Temperature, Pain_Scale)
  VALUES
    (p_encounter_id, NOW(), 'Initial', p_hr, p_spo2, p_sys, p_dia, p_temp, p_pain);

  COMMIT;

  SELECT e.Encounter_ID, p.Name AS Patient_Name, d.Name AS Doctor_Name,
         d.`Role` AS Doctor_Role, dep.Name AS Department_Name,
         e.Final_Queue_Score AS ESI, w.Queue_Position, w.Est_Wait_Time
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID
  JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID
  JOIN Department dep ON dep.Department_ID = e.Department_ID
  LEFT JOIN Wait_List w ON w.Encounter_ID = e.Encounter_ID
  WHERE e.Encounter_ID = p_encounter_id;
END$$

DROP PROCEDURE IF EXISTS sp_reassess_patient$$
CREATE PROCEDURE sp_reassess_patient(
  IN p_encounter_id INT,
  IN p_hr           SMALLINT,
  IN p_spo2         TINYINT,
  IN p_sys          SMALLINT,
  IN p_dia          SMALLINT,
  IN p_temp         DECIMAL(4,1),
  IN p_pain         TINYINT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_patient INT;
  DECLARE v_doctor  INT;
  DECLARE v_out     DATETIME;
  DECLARE v_lock    INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT Patient_ID, Doctor_ID, Check_out_Time
    INTO v_patient, v_doctor, v_out
  FROM Encounter_Triage_Event
  WHERE Encounter_ID = p_encounter_id;

  IF v_patient IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Encounter not found';
  END IF;
  IF v_out IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot add vitals to a discharged encounter';
  END IF;

  -- Lock patient, then that doctor, then the encounter. No result set is
  -- sent to the client (SELECT ... INTO).
  SELECT Patient_ID INTO v_lock FROM Patient WHERE Patient_ID = v_patient FOR UPDATE;
  SELECT Doctor_ID  INTO v_lock FROM Doctor  WHERE Doctor_ID  = v_doctor  FOR UPDATE;
  SELECT Encounter_ID INTO v_lock FROM Encounter_Triage_Event
   WHERE Encounter_ID = p_encounter_id FOR UPDATE;

  INSERT INTO Vitals_Log
    (Encounter_ID, Log_Timestamp, Type_Name, Heart_Rate, SpO2,
     Systolic_BP, Diastolic_BP, Temperature, Pain_Scale)
  VALUES
    (p_encounter_id, NOW(), 'Reassessment', p_hr, p_spo2, p_sys, p_dia, p_temp, p_pain);

  COMMIT;

  SELECT e.Encounter_ID, e.Final_Queue_Score AS ESI,
         w.Queue_Position, w.Est_Wait_Time, d.Name AS Doctor_Name
  FROM Encounter_Triage_Event e
  JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID
  LEFT JOIN Wait_List w ON w.Encounter_ID = e.Encounter_ID
  WHERE e.Encounter_ID = p_encounter_id;
END$$

DROP PROCEDURE IF EXISTS sp_discharge_patient$$
CREATE PROCEDURE sp_discharge_patient(IN p_encounter_id INT)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_patient INT;
  DECLARE v_doctor  INT;
  DECLARE v_out     DATETIME;
  DECLARE v_lock    INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT Patient_ID, Doctor_ID, Check_out_Time
    INTO v_patient, v_doctor, v_out
  FROM Encounter_Triage_Event
  WHERE Encounter_ID = p_encounter_id;

  IF v_patient IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Encounter not found or already discharged';
  END IF;
  IF v_out IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Encounter not found or already discharged';
  END IF;

  SELECT Patient_ID INTO v_lock FROM Patient WHERE Patient_ID = v_patient FOR UPDATE;
  SELECT Doctor_ID  INTO v_lock FROM Doctor  WHERE Doctor_ID  = v_doctor  FOR UPDATE;
  SELECT Encounter_ID INTO v_lock FROM Encounter_Triage_Event
   WHERE Encounter_ID = p_encounter_id FOR UPDATE;

  UPDATE Encounter_Triage_Event
     SET Check_out_Time = NOW()
   WHERE Encounter_ID = p_encounter_id
     AND Check_out_Time IS NULL;

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Encounter not found or already discharged';
  END IF;

  COMMIT;

  SELECT p_encounter_id AS Encounter_ID, 'Discharged' AS Status;
END$$

-- Retry wrappers. DECLARE CONTINUE HANDLER catches the resignaled
-- deadlock (1213) or lock-wait timeout (1205) from the inner procedure.
-- Any other SIGNAL, such as a bad blood pressure, is not caught here.

DROP PROCEDURE IF EXISTS sp_admit_patient_safe$$
CREATE PROCEDURE sp_admit_patient_safe(
  IN p_patient_id INT,
  IN p_symptoms   VARCHAR(500),
  IN p_hr         SMALLINT,
  IN p_spo2       TINYINT,
  IN p_sys        SMALLINT,
  IN p_dia        SMALLINT,
  IN p_temp       DECIMAL(4,1),
  IN p_pain       TINYINT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_retry   TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1213, 1205
  BEGIN
    SET v_retry = 1;
  END;

  SET @sq_admit_id = NULL;

  retry_loop: WHILE v_attempt < 3 DO
    SET v_attempt = v_attempt + 1;
    SET v_retry = 0;

    CALL sp_admit_patient(
      p_patient_id, p_symptoms, p_hr, p_spo2, p_sys, p_dia, p_temp, p_pain,
      @sq_admit_id
    );

    IF v_retry = 0 THEN
      LEAVE retry_loop;
    END IF;
  END WHILE;

  IF v_retry = 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Admission failed after 3 attempts because of a lock conflict. Please try again.';
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_reassess_patient_safe$$
CREATE PROCEDURE sp_reassess_patient_safe(
  IN p_encounter_id INT,
  IN p_hr           SMALLINT,
  IN p_spo2         TINYINT,
  IN p_sys          SMALLINT,
  IN p_dia          SMALLINT,
  IN p_temp         DECIMAL(4,1),
  IN p_pain         TINYINT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_retry   TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1213, 1205
  BEGIN
    SET v_retry = 1;
  END;

  retry_loop: WHILE v_attempt < 3 DO
    SET v_attempt = v_attempt + 1;
    SET v_retry = 0;
    CALL sp_reassess_patient(
      p_encounter_id, p_hr, p_spo2, p_sys, p_dia, p_temp, p_pain
    );
    IF v_retry = 0 THEN
      LEAVE retry_loop;
    END IF;
  END WHILE;

  IF v_retry = 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Reassessment failed after 3 attempts because of a lock conflict. Please try again.';
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_discharge_patient_safe$$
CREATE PROCEDURE sp_discharge_patient_safe(IN p_encounter_id INT)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_retry   TINYINT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR 1213, 1205
  BEGIN
    SET v_retry = 1;
  END;

  retry_loop: WHILE v_attempt < 3 DO
    SET v_attempt = v_attempt + 1;
    SET v_retry = 0;
    CALL sp_discharge_patient(p_encounter_id);
    IF v_retry = 0 THEN
      LEAVE retry_loop;
    END IF;
  END WHILE;

  IF v_retry = 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Discharge failed after 3 attempts because of a lock conflict. Please try again.';
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Aging, alerts, audit archive
-- -----------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_age_queue$$
CREATE PROCEDURE sp_age_queue()
SQL SECURITY DEFINER
BEGIN
  DECLARE v_enc  INT;
  DECLARE v_new  TINYINT;
  DECLARE v_last INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_age;
    SET @sq_score_note = NULL;
    RESIGNAL;
  END;

  DROP TEMPORARY TABLE IF EXISTS tmp_age;
  CREATE TEMPORARY TABLE tmp_age (
    Encounter_ID INT PRIMARY KEY,
    New_Score    TINYINT NOT NULL
  );

  -- One level only. The next run of this procedure may raise them again
  -- if they are still past the limit of the new ESI level.
  INSERT INTO tmp_age (Encounter_ID, New_Score)
  SELECT e.Encounter_ID, e.Final_Queue_Score - 1
  FROM Wait_List w
  JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
  JOIN Aging_Policy a ON a.ESI_Level = e.Final_Queue_Score
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE e.Check_out_Time IS NULL
    AND e.Final_Queue_Score > 1
    AND TIMESTAMPDIFF(MINUTE, e.Arrival_Time, NOW()) > a.Max_Wait_Minutes;

  age_loop: LOOP
    SET v_enc = NULL;
    SELECT Encounter_ID, New_Score INTO v_enc, v_new
    FROM tmp_age
    WHERE Encounter_ID > v_last
    ORDER BY Encounter_ID
    LIMIT 1;

    IF v_enc IS NULL THEN
      LEAVE age_loop;
    END IF;

    -- The encounter trigger reads this note and then clears it.
    SET @sq_score_note = 'Escalated: exceeded waiting limit';
    UPDATE Encounter_Triage_Event e
    JOIN Triage_Rule r ON r.ESI_Level = v_new
       SET e.Final_Queue_Score = v_new,
           e.Rule_ID = r.Rule_ID
     WHERE e.Encounter_ID = v_enc
       AND e.Check_out_Time IS NULL
       AND e.Final_Queue_Score = v_new + 1;
    SET @sq_score_note = NULL;
    SET v_last = v_enc;
  END LOOP;

  SELECT t.Encounter_ID, p.Name AS Patient_Name,
         (t.New_Score + 1) AS Old_ESI, t.New_Score AS New_ESI
  FROM tmp_age t
  JOIN Encounter_Triage_Event e ON e.Encounter_ID = t.Encounter_ID
  JOIN Patient p ON p.Patient_ID = e.Patient_ID
  ORDER BY t.Encounter_ID;

  DROP TEMPORARY TABLE IF EXISTS tmp_age;
END$$

DROP PROCEDURE IF EXISTS sp_resolve_alert$$
CREATE PROCEDURE sp_resolve_alert(IN p_alert_id INT)
SQL SECURITY DEFINER
BEGIN
  UPDATE Alert
     SET Is_Resolved = 1
   WHERE Alert_ID = p_alert_id
     AND Is_Resolved = 0;

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alert not found or already resolved';
  END IF;

  SELECT p_alert_id AS Alert_ID, 'Resolved' AS Status;
END$$

DROP PROCEDURE IF EXISTS sp_auto_resolve_alerts$$
CREATE PROCEDURE sp_auto_resolve_alerts()
SQL SECURITY DEFINER
BEGIN
  UPDATE Alert a
  LEFT JOIN (
    SELECT Doctor_ID, COUNT(*) AS qlen
    FROM Wait_List
    GROUP BY Doctor_ID
  ) AS q ON q.Doctor_ID = a.Doctor_ID
  JOIN Config c ON c.Config_Key = 'doctor_queue_threshold'
     SET a.Is_Resolved = 1
   WHERE a.Is_Resolved = 0
     AND a.Alert_Type = 'DOCTOR_OVERLOAD'
     AND COALESCE(q.qlen, 0) <= CAST(c.Config_Value AS SIGNED);

  UPDATE Alert a
  JOIN Config c ON c.Config_Key = 'dept_critical_threshold'
  LEFT JOIN (
    SELECT d.Department_ID, COUNT(*) AS critical_n
    FROM Wait_List w
    JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
    JOIN Doctor d ON d.Doctor_ID = w.Doctor_ID
    WHERE e.Final_Queue_Score <= 2
      AND e.Check_out_Time IS NULL
    GROUP BY d.Department_ID
  ) AS crit ON crit.Department_ID = a.Department_ID
     SET a.Is_Resolved = 1
   WHERE a.Is_Resolved = 0
     AND a.Alert_Type = 'DEPT_CRITICAL'
     AND COALESCE(crit.critical_n, 0) <= CAST(c.Config_Value AS SIGNED);
END$$

DROP PROCEDURE IF EXISTS sp_archive_audit_log$$
CREATE PROCEDURE sp_archive_audit_log()
SQL SECURITY DEFINER
BEGIN
  DECLARE v_days INT;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  SELECT CAST(Config_Value AS SIGNED) INTO v_days
  FROM Config
  WHERE Config_Key = 'audit_archive_days';

  IF v_days IS NULL OR v_days < 1 THEN
    SET v_days = 90;
  END IF;

  INSERT INTO Audit_Log_Archive
    (Audit_ID, Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
  SELECT Audit_ID, Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At
  FROM Audit_Log
  WHERE Changed_At < NOW() - INTERVAL v_days DAY;

  DELETE FROM Audit_Log
  WHERE Changed_At < NOW() - INTERVAL v_days DAY;

  SELECT ROW_COUNT() AS Archived_Rows;
END$$

DROP PROCEDURE IF EXISTS sp_toggle_aging$$
CREATE PROCEDURE sp_toggle_aging(IN p_on TINYINT)
SQL SECURITY DEFINER
BEGIN
  IF p_on = 1 THEN
    ALTER EVENT evt_age_queue ENABLE;
    SELECT 'Aging event enabled' AS Status;
  ELSE
    ALTER EVENT evt_age_queue DISABLE;
    SELECT 'Aging event paused' AS Status;
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Registration, people, departments, configuration
-- -----------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_register_patient$$
CREATE PROCEDURE sp_register_patient(
  IN p_name  VARCHAR(100),
  IN p_phone VARCHAR(15),
  IN p_email VARCHAR(120),
  IN p_dob   DATE
)
SQL SECURITY DEFINER
BEGIN
  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient name is required';
  END IF;
  IF p_phone IS NULL OR p_phone NOT REGEXP '^[0-9]{10}$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Phone must be a 10-digit number';
  END IF;
  IF p_email IS NOT NULL AND TRIM(p_email) <> '' AND p_email NOT LIKE '%_@_%._%' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email address is not valid';
  END IF;
  IF p_dob IS NULL
     OR p_dob > CURDATE()
     OR p_dob < DATE_SUB(CURDATE(), INTERVAL 120 YEAR) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Date of birth is not valid';
  END IF;

  INSERT INTO Patient (Name, Phone, Email, Date_of_Birth)
  VALUES (TRIM(p_name), p_phone, NULLIF(TRIM(p_email), ''), p_dob);

  SELECT LAST_INSERT_ID() AS Patient_ID, TRIM(p_name) AS Name, p_phone AS Phone;
END$$

DROP PROCEDURE IF EXISTS sp_search_patients$$
CREATE PROCEDURE sp_search_patients(IN p_text VARCHAR(100))
SQL SECURITY DEFINER
BEGIN
  SELECT Patient_ID, Name, Phone, Email, Date_of_Birth
  FROM Patient
  WHERE Is_Deleted = 0
    AND (
      p_text IS NULL OR TRIM(p_text) = ''
      OR Name  LIKE CONCAT('%', p_text, '%')
      OR Phone LIKE CONCAT('%', p_text, '%')
      OR Email LIKE CONCAT('%', p_text, '%')
    )
  ORDER BY Name
  LIMIT 50;
END$$

DROP PROCEDURE IF EXISTS sp_add_department$$
CREATE PROCEDURE sp_add_department(
  IN p_name VARCHAR(80),
  IN p_description VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Department name is required';
  END IF;

  INSERT INTO Department (Name, Description)
  VALUES (TRIM(p_name), NULLIF(TRIM(p_description), ''));

  SELECT LAST_INSERT_ID() AS Department_ID, TRIM(p_name) AS Name;
END$$

DROP PROCEDURE IF EXISTS sp_add_doctor$$
CREATE PROCEDURE sp_add_doctor(
  IN p_name           VARCHAR(100),
  IN p_role           VARCHAR(40),
  IN p_specialization VARCHAR(80),
  IN p_department_id  INT
)
SQL SECURITY DEFINER
BEGIN
  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor name is required';
  END IF;
  IF p_role NOT IN ('Junior Doctor', 'Resident', 'Consultant', 'Senior Consultant') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role must be Junior Doctor, Resident, Consultant or Senior Consultant';
  END IF;
  IF p_specialization IS NULL OR CHAR_LENGTH(TRIM(p_specialization)) < 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specialization is required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM Department WHERE Department_ID = p_department_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Department not found';
  END IF;

  INSERT INTO Doctor (Name, `Role`, Specialization, Current_Status, Department_ID)
  VALUES (TRIM(p_name), p_role, TRIM(p_specialization), 'Off_Duty', p_department_id);

  CALL sp_refresh_doctor_status(LAST_INSERT_ID());

  SELECT LAST_INSERT_ID() AS Doctor_ID, TRIM(p_name) AS Name;
END$$

DROP PROCEDURE IF EXISTS sp_soft_delete_patient$$
CREATE PROCEDURE sp_soft_delete_patient(IN p_patient_id INT)
SQL SECURITY DEFINER
BEGIN
  IF NOT EXISTS (SELECT 1 FROM Patient WHERE Patient_ID = p_patient_id AND Is_Deleted = 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient not found or already deleted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM Encounter_Triage_Event
    WHERE Patient_ID = p_patient_id AND Check_out_Time IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot delete a patient who has an active encounter';
  END IF;

  UPDATE Patient
     SET Is_Deleted = 1, Deleted_At = NOW()
   WHERE Patient_ID = p_patient_id AND Is_Deleted = 0;

  SELECT p_patient_id AS Patient_ID, 'Soft-deleted' AS Status;
END$$

DROP PROCEDURE IF EXISTS sp_restore_patient$$
CREATE PROCEDURE sp_restore_patient(IN p_patient_id INT)
SQL SECURITY DEFINER
BEGIN
  UPDATE Patient
     SET Is_Deleted = 0, Deleted_At = NULL
   WHERE Patient_ID = p_patient_id AND Is_Deleted = 1;

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deleted patient not found';
  END IF;

  SELECT p_patient_id AS Patient_ID, 'Restored' AS Status;
END$$

DROP PROCEDURE IF EXISTS sp_soft_delete_doctor$$
CREATE PROCEDURE sp_soft_delete_doctor(IN p_doctor_id INT)
SQL SECURITY DEFINER
BEGIN
  IF NOT EXISTS (SELECT 1 FROM Doctor WHERE Doctor_ID = p_doctor_id AND Is_Deleted = 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found or already deleted';
  END IF;

  IF EXISTS (SELECT 1 FROM Wait_List WHERE Doctor_ID = p_doctor_id)
     OR EXISTS (
       SELECT 1 FROM Encounter_Triage_Event
       WHERE Doctor_ID = p_doctor_id AND Check_out_Time IS NULL
     ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot delete a doctor who still has an active patient';
  END IF;

  SET @sq_allow_status = 1;
  UPDATE Doctor
     SET Is_Deleted = 1, Deleted_At = NOW(), Current_Status = 'Off_Duty'
   WHERE Doctor_ID = p_doctor_id AND Is_Deleted = 0;
  SET @sq_allow_status = 0;

  SELECT p_doctor_id AS Doctor_ID, 'Soft-deleted' AS Status;
END$$

DROP PROCEDURE IF EXISTS sp_restore_doctor$$
CREATE PROCEDURE sp_restore_doctor(IN p_doctor_id INT)
SQL SECURITY DEFINER
BEGIN
  UPDATE Doctor
     SET Is_Deleted = 0, Deleted_At = NULL
   WHERE Doctor_ID = p_doctor_id AND Is_Deleted = 1;

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deleted doctor not found';
  END IF;

  CALL sp_refresh_doctor_status(p_doctor_id);
  SELECT p_doctor_id AS Doctor_ID, 'Restored' AS Status;
END$$

DROP PROCEDURE IF EXISTS sp_set_config$$
CREATE PROCEDURE sp_set_config(
  IN p_key   VARCHAR(64),
  IN p_value VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
  IF p_key NOT IN (
    'doctor_queue_threshold', 'dept_critical_threshold',
    'default_consult_minutes', 'audit_archive_days'
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown configuration key';
  END IF;
  IF p_value IS NULL OR p_value NOT REGEXP '^[0-9]+$' OR CAST(p_value AS SIGNED) < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Configuration value must be a non-negative integer';
  END IF;

  UPDATE Config SET Config_Value = p_value WHERE Config_Key = p_key;
  SELECT p_key AS Config_Key, p_value AS Config_Value;
END$$

DROP PROCEDURE IF EXISTS sp_set_aging_policy$$
CREATE PROCEDURE sp_set_aging_policy(
  IN p_esi     TINYINT,
  IN p_minutes INT
)
SQL SECURITY DEFINER
BEGIN
  IF p_esi NOT BETWEEN 2 AND 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Aging policy applies to ESI levels 2 to 5';
  END IF;
  IF p_minutes IS NULL OR p_minutes < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Max wait minutes cannot be negative';
  END IF;

  INSERT INTO Aging_Policy (ESI_Level, Max_Wait_Minutes)
  VALUES (p_esi, p_minutes)
  ON DUPLICATE KEY UPDATE Max_Wait_Minutes = p_minutes;

  SELECT p_esi AS ESI_Level, p_minutes AS Max_Wait_Minutes;
END$$

DROP PROCEDURE IF EXISTS sp_search_similar_cases$$
CREATE PROCEDURE sp_search_similar_cases(IN p_search VARCHAR(200))
SQL SECURITY DEFINER
BEGIN
  IF p_search IS NULL OR CHAR_LENGTH(TRIM(p_search)) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enter at least 3 characters to search';
  END IF;

  SELECT e.Encounter_ID,
         p.Name AS Patient_Name,
         e.Initial_Symptoms,
         e.Final_Queue_Score AS ESI,
         dep.Name AS Department,
         d.Name AS Doctor_Name,
         e.Arrival_Time,
         CASE WHEN e.Check_out_Time IS NULL THEN 'Active' ELSE 'Discharged' END AS Status,
         MATCH(e.Initial_Symptoms) AGAINST (p_search IN NATURAL LANGUAGE MODE) AS Relevance
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  JOIN Department dep ON dep.Department_ID = e.Department_ID
  LEFT JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID AND d.Is_Deleted = 0
  WHERE MATCH(e.Initial_Symptoms) AGAINST (p_search IN NATURAL LANGUAGE MODE)
  ORDER BY Relevance DESC, e.Arrival_Time DESC
  LIMIT 20;
END$$

-- -----------------------------------------------------------------------------
-- Reports. Each procedure returns more than one result set.
-- -----------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_daily_report$$
CREATE PROCEDURE sp_daily_report(IN p_date DATE)
SQL SECURITY DEFINER
BEGIN
  IF p_date IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Report date is required';
  END IF;

  -- 1. Headline
  SELECT p_date AS Report_Date,
         COUNT(*) AS Arrivals,
         SUM(e.Check_out_Time IS NOT NULL) AS Discharged,
         SUM(e.Check_out_Time IS NULL) AS Still_Active,
         ROUND(AVG(TIMESTAMPDIFF(MINUTE, e.Arrival_Time,
                    COALESCE(e.Check_out_Time, NOW()))), 1) AS Avg_Stay_Min
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE DATE(e.Arrival_Time) = p_date;

  -- 2. ESI mix, with each level's share of the day (window function)
  SELECT e.Final_Queue_Score AS ESI,
         COUNT(*) AS Cases,
         ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS Pct_Of_Day
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE DATE(e.Arrival_Time) = p_date
  GROUP BY e.Final_Queue_Score
  ORDER BY ESI;

  -- 3. Department load, ranked, only departments that actually had an arrival
  SELECT dep.Name AS Department,
         COUNT(*) AS Arrivals,
         ROUND(AVG(e.Final_Queue_Score), 2) AS Avg_ESI,
         RANK() OVER (ORDER BY COUNT(*) DESC, dep.Name) AS Load_Rank
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  JOIN Department dep ON dep.Department_ID = e.Department_ID
  WHERE DATE(e.Arrival_Time) = p_date
  GROUP BY dep.Department_ID, dep.Name
  HAVING COUNT(*) >= 1
  ORDER BY Load_Rank, Department;

  -- 4. Doctors busier than the average doctor that day (nested subquery)
  SELECT d.Name AS Doctor,
         COUNT(*) AS Cases
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID
  WHERE DATE(e.Arrival_Time) = p_date
  GROUP BY d.Doctor_ID, d.Name
  HAVING COUNT(*) > (
    SELECT AVG(cnt) FROM (
      SELECT COUNT(*) AS cnt
      FROM Encounter_Triage_Event e2
      JOIN Patient p2 ON p2.Patient_ID = e2.Patient_ID AND p2.Is_Deleted = 0
      WHERE DATE(e2.Arrival_Time) = p_date
      GROUP BY e2.Doctor_ID
    ) AS per_doctor
  )
  ORDER BY Cases DESC, Doctor;
END$$

DROP PROCEDURE IF EXISTS sp_weekly_report$$
CREATE PROCEDURE sp_weekly_report(IN p_start DATE)
SQL SECURITY DEFINER
BEGIN
  IF p_start IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Week start date is required';
  END IF;

  -- 1. One row per day, with a running total
  SELECT DATE(e.Arrival_Time) AS Day_Date,
         COUNT(*) AS Arrivals,
         SUM(e.Final_Queue_Score <= 2) AS Critical_Cases,
         SUM(COUNT(*)) OVER (ORDER BY DATE(e.Arrival_Time)) AS Running_Arrivals
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE e.Arrival_Time >= p_start
    AND e.Arrival_Time <  p_start + INTERVAL 7 DAY
  GROUP BY DATE(e.Arrival_Time)
  ORDER BY Day_Date;

  -- 2. ESI totals for the week
  SELECT e.Final_Queue_Score AS ESI,
         COUNT(*) AS Cases,
         ROUND(AVG(TIMESTAMPDIFF(MINUTE, e.Arrival_Time,
                    COALESCE(e.Check_out_Time, NOW()))), 1) AS Avg_Stay_Min
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE e.Arrival_Time >= p_start
    AND e.Arrival_Time <  p_start + INTERVAL 7 DAY
  GROUP BY e.Final_Queue_Score
  ORDER BY ESI;

  -- 3. Departments that handled more than one patient
  SELECT dep.Name AS Department,
         COUNT(*) AS Arrivals,
         ROUND(AVG(e.Final_Queue_Score), 2) AS Avg_ESI
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  JOIN Department dep ON dep.Department_ID = e.Department_ID
  WHERE e.Arrival_Time >= p_start
    AND e.Arrival_Time <  p_start + INTERVAL 7 DAY
  GROUP BY dep.Department_ID, dep.Name
  HAVING COUNT(*) > 1
  ORDER BY Arrivals DESC;
END$$

DROP PROCEDURE IF EXISTS sp_doctor_report$$
CREATE PROCEDURE sp_doctor_report(
  IN p_doctor_id INT,
  IN p_from      DATE,
  IN p_to        DATE
)
SQL SECURITY DEFINER
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A valid from-date and to-date are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM Doctor WHERE Doctor_ID = p_doctor_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
  END IF;

  -- 1. This doctor against the hospital average in the same window
  SELECT d.Name AS Doctor,
         d.`Role` AS Doctor_Role,
         dep.Name AS Department,
         COUNT(e.Encounter_ID) AS Cases,
         SUM(e.Check_out_Time IS NOT NULL) AS Discharged,
         ROUND(AVG(e.Final_Queue_Score), 2) AS Avg_ESI,
         ROUND(AVG(CASE
           WHEN e.Check_out_Time IS NOT NULL
           THEN TIMESTAMPDIFF(MINUTE, e.Arrival_Time, e.Check_out_Time)
         END), 1) AS Avg_Consult_Min,
         (
           SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, e2.Arrival_Time, e2.Check_out_Time)), 1)
           FROM Encounter_Triage_Event e2
           JOIN Patient p2 ON p2.Patient_ID = e2.Patient_ID AND p2.Is_Deleted = 0
           WHERE e2.Check_out_Time IS NOT NULL
             AND e2.Arrival_Time >= p_from
             AND e2.Arrival_Time <  p_to + INTERVAL 1 DAY
         ) AS Hospital_Avg_Consult_Min
  FROM Doctor d
  JOIN Department dep ON dep.Department_ID = d.Department_ID
  LEFT JOIN Encounter_Triage_Event e
    ON e.Doctor_ID = d.Doctor_ID
   AND e.Arrival_Time >= p_from
   AND e.Arrival_Time <  p_to + INTERVAL 1 DAY
  LEFT JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE d.Doctor_ID = p_doctor_id
  GROUP BY d.Doctor_ID, d.Name, d.`Role`, dep.Name;

  -- 2. Each visit, numbered, with how it ranked that day for this doctor
  SELECT e.Encounter_ID,
         p.Name AS Patient_Name,
         e.Arrival_Time,
         e.Check_out_Time,
         e.Final_Queue_Score AS ESI,
         e.Initial_Symptoms,
         ROW_NUMBER() OVER (ORDER BY e.Arrival_Time) AS Visit_Number,
         RANK() OVER (PARTITION BY DATE(e.Arrival_Time)
                      ORDER BY e.Final_Queue_Score) AS Urgency_Rank_That_Day
  FROM Encounter_Triage_Event e
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE e.Doctor_ID = p_doctor_id
    AND e.Arrival_Time >= p_from
    AND e.Arrival_Time <  p_to + INTERVAL 1 DAY
  ORDER BY e.Arrival_Time;

  -- 3. Priority changes for those visits
  SELECT s.History_ID, s.Encounter_ID, p.Name AS Patient_Name,
         s.Old_Score, s.New_Score, s.History_At, s.History_Notes
  FROM Score_History s
  JOIN Encounter_Triage_Event e ON e.Encounter_ID = s.Encounter_ID
  JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
  WHERE e.Doctor_ID = p_doctor_id
    AND e.Arrival_Time >= p_from
    AND e.Arrival_Time <  p_to + INTERVAL 1 DAY
  ORDER BY s.History_At, s.History_ID;
END$$

DELIMITER ;

-- Status and estimated waits for the seeded queue. Triggers are not installed
-- yet, so this is a one-time alignment of the sample picture. The seed pins
-- patients to fixed doctors; whichever of them is off shift at load time
-- hands their queue over here, exactly as the scheduler would.
CALL sp_refresh_all_doctor_status();
CALL sp_rebuild_queue(1);
CALL sp_rebuild_queue(2);
CALL sp_rebuild_queue(3);
CALL sp_rebuild_queue(4);
CALL sp_rebuild_queue(5);
CALL sp_rebuild_queue(6);
CALL sp_rebuild_queue(7);
CALL sp_rebuild_queue(8);

SELECT '04_procedures.sql complete' AS status;
