-- =============================================================================
-- 05_triggers.sql
-- Business rules that must hold no matter who writes the row.
-- Audit triggers for every table except Audit_Log itself are appended
-- below the clinical triggers. Audit_Log has no trigger: an audit of the
-- audit table would recurse.
--
-- MySQL forbids a function called from a trigger from reading the table that
-- fired the trigger (error 1442). The encounter triggers therefore compute
-- the doctor's average consultation time themselves and pass it through
-- @sq_consult_avg, which fn_estimate_wait already understands.
-- Wait_List triggers likewise count the queue in the BEFORE trigger, while
-- the row is still readable, and apply that count afterwards.
-- =============================================================================

USE SmartQueue;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- People: hard delete is refused. Status cannot be typed in by a user.
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_patient_bd$$
CREATE TRIGGER trg_patient_bd
BEFORE DELETE ON Patient
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Patients cannot be hard-deleted. Use soft delete.';
END$$

DROP TRIGGER IF EXISTS trg_doctor_bd$$
CREATE TRIGGER trg_doctor_bd
BEFORE DELETE ON Doctor
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Doctors cannot be hard-deleted. Use soft delete.';
END$$

DROP TRIGGER IF EXISTS trg_doctor_bu_status$$
CREATE TRIGGER trg_doctor_bu_status
BEFORE UPDATE ON Doctor
FOR EACH ROW
BEGIN
  IF NOT (OLD.Current_Status <=> NEW.Current_Status)
     AND IFNULL(@sq_allow_status, 0) <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Doctor status is maintained by the database and cannot be set directly';
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Shifts. The overlap rule is inlined: a function that read Doctor_Shift
-- would be illegal inside this trigger.
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_doctor_shift_bi$$
CREATE TRIGGER trg_doctor_shift_bi
BEFORE INSERT ON Doctor_Shift
FOR EACH ROW
BEGIN
  DECLARE v_start INT;
  DECLARE v_end   INT;
  DECLARE v_hits  INT DEFAULT 0;

  SELECT TIME_TO_SEC(Start_Time), TIME_TO_SEC(End_Time)
    INTO v_start, v_end
  FROM Shift
  WHERE Shift_ID = NEW.Shift_ID;

  IF v_start IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Shift not found';
  END IF;
  IF v_end <= v_start THEN
    SET v_end = v_end + 86400;
  END IF;

  SELECT COUNT(*) INTO v_hits
  FROM (
    SELECT
      TIME_TO_SEC(s.Start_Time)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(NEW.Shift_Date), TIMESTAMP(ds.Shift_Date)) AS s0,
      TIME_TO_SEC(s.End_Time)
        + IF(s.End_Time <= s.Start_Time, 86400, 0)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(NEW.Shift_Date), TIMESTAMP(ds.Shift_Date)) AS e0
    FROM Doctor_Shift ds
    JOIN Shift s ON s.Shift_ID = ds.Shift_ID
    WHERE ds.Doctor_ID = NEW.Doctor_ID
      AND ds.Shift_Date BETWEEN DATE_SUB(NEW.Shift_Date, INTERVAL 1 DAY)
                            AND DATE_ADD(NEW.Shift_Date, INTERVAL 1 DAY)
  ) AS existing
  WHERE v_start < existing.e0
    AND existing.s0 < v_end;

  IF v_hits > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Doctor already has an overlapping shift on this date';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_doctor_shift_bu$$
CREATE TRIGGER trg_doctor_shift_bu
BEFORE UPDATE ON Doctor_Shift
FOR EACH ROW
BEGIN
  DECLARE v_start INT;
  DECLARE v_end   INT;
  DECLARE v_hits  INT DEFAULT 0;

  SELECT TIME_TO_SEC(Start_Time), TIME_TO_SEC(End_Time)
    INTO v_start, v_end
  FROM Shift
  WHERE Shift_ID = NEW.Shift_ID;

  IF v_start IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Shift not found';
  END IF;
  IF v_end <= v_start THEN
    SET v_end = v_end + 86400;
  END IF;

  SELECT COUNT(*) INTO v_hits
  FROM (
    SELECT
      TIME_TO_SEC(s.Start_Time)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(NEW.Shift_Date), TIMESTAMP(ds.Shift_Date)) AS s0,
      TIME_TO_SEC(s.End_Time)
        + IF(s.End_Time <= s.Start_Time, 86400, 0)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(NEW.Shift_Date), TIMESTAMP(ds.Shift_Date)) AS e0
    FROM Doctor_Shift ds
    JOIN Shift s ON s.Shift_ID = ds.Shift_ID
    WHERE ds.Doctor_ID = NEW.Doctor_ID
      AND ds.Doctor_Shift_ID <> NEW.Doctor_Shift_ID
      AND ds.Shift_Date BETWEEN DATE_SUB(NEW.Shift_Date, INTERVAL 1 DAY)
                            AND DATE_ADD(NEW.Shift_Date, INTERVAL 1 DAY)
  ) AS existing
  WHERE v_start < existing.e0
    AND existing.s0 < v_end;

  IF v_hits > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Doctor already has an overlapping shift on this date';
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Vitals
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_vitals_bi$$
CREATE TRIGGER trg_vitals_bi
BEFORE INSERT ON Vitals_Log
FOR EACH ROW
BEGIN
  DECLARE v_checkout DATETIME;

  IF NEW.Heart_Rate IS NULL OR NEW.Heart_Rate NOT BETWEEN 20 AND 250 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Heart rate must be between 20 and 250';
  END IF;
  IF NEW.SpO2 IS NULL OR NEW.SpO2 NOT BETWEEN 0 AND 100 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'SpO2 must be between 0 and 100';
  END IF;
  IF NEW.Pain_Scale IS NULL OR NEW.Pain_Scale NOT BETWEEN 0 AND 10 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Pain scale must be between 0 and 10';
  END IF;
  IF NEW.Diastolic_BP IS NULL OR NEW.Systolic_BP IS NULL
     OR NEW.Diastolic_BP <= 0 OR NEW.Systolic_BP <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Blood pressure values must be positive';
  END IF;
  IF NEW.Diastolic_BP >= NEW.Systolic_BP THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Diastolic BP must be lower than systolic BP';
  END IF;
  IF NEW.Temperature IS NULL OR NEW.Temperature NOT BETWEEN 30.0 AND 45.0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Temperature outside the valid range (30 to 45 C)';
  END IF;

  SELECT Check_out_Time INTO v_checkout
  FROM Encounter_Triage_Event
  WHERE Encounter_ID = NEW.Encounter_ID;

  IF v_checkout IS NOT NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot add vitals to a discharged encounter';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_vitals_ai$$
CREATE TRIGGER trg_vitals_ai
AFTER INSERT ON Vitals_Log
FOR EACH ROW
BEGIN
  DECLARE v_new  TINYINT;
  DECLARE v_cur  TINYINT;
  DECLARE v_rule INT;

  SET v_new = fn_calc_esi(
    NEW.Heart_Rate, NEW.SpO2, NEW.Systolic_BP, NEW.Temperature, NEW.Pain_Scale
  );

  SELECT Final_Queue_Score INTO v_cur
  FROM Encounter_Triage_Event
  WHERE Encounter_ID = NEW.Encounter_ID;

  IF v_cur IS NULL OR v_new <> v_cur THEN
    SELECT Rule_ID INTO v_rule
    FROM Triage_Rule
    WHERE ESI_Level = v_new
    LIMIT 1;

    UPDATE Encounter_Triage_Event
       SET Final_Queue_Score = v_new,
           Rule_ID = v_rule
     WHERE Encounter_ID = NEW.Encounter_ID;
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Encounters: score ledger, queue membership, discharge, delete guard
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_encounter_bu$$
CREATE TRIGGER trg_encounter_bu
BEFORE UPDATE ON Encounter_Triage_Event
FOR EACH ROW
BEGIN
  IF OLD.Check_out_Time IS NOT NULL
     AND NOT (OLD.Final_Queue_Score <=> NEW.Final_Queue_Score) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Score of a discharged encounter cannot be changed';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_encounter_bd$$
CREATE TRIGGER trg_encounter_bd
BEFORE DELETE ON Encounter_Triage_Event
FOR EACH ROW
BEGIN
  IF OLD.Check_out_Time IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Active encounters cannot be deleted; discharge the patient first';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_encounter_ai$$
CREATE TRIGGER trg_encounter_ai
AFTER INSERT ON Encounter_Triage_Event
FOR EACH ROW
BEGIN
  IF NEW.Final_Queue_Score IS NOT NULL THEN
    INSERT INTO Score_History
      (Encounter_ID, Old_Score, New_Score, History_At, History_Notes)
    VALUES
      (NEW.Encounter_ID, NULL, NEW.Final_Queue_Score, NOW(), 'Initial triage score');

    IF NEW.Doctor_ID IS NOT NULL AND NEW.Check_out_Time IS NULL THEN
      INSERT INTO Wait_List
        (Encounter_ID, Doctor_ID, Queue_Position, Assigned_Time, Est_Wait_Time)
      VALUES
        (NEW.Encounter_ID, NEW.Doctor_ID, 1, NOW(), 0);

      SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, Arrival_Time, Check_out_Time)))
        INTO @sq_consult_avg
      FROM Encounter_Triage_Event
      WHERE Doctor_ID = NEW.Doctor_ID
        AND Check_out_Time IS NOT NULL
        AND Check_out_Time > Arrival_Time;

      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SELECT CAST(Config_Value AS SIGNED) INTO @sq_consult_avg
        FROM Config
        WHERE Config_Key = 'default_consult_minutes';
      END IF;
      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SET @sq_consult_avg = 15;
      END IF;

      CALL sp_rebuild_queue(NEW.Doctor_ID);
      SET @sq_consult_avg = NULL;
    END IF;
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_encounter_au$$
CREATE TRIGGER trg_encounter_au
AFTER UPDATE ON Encounter_Triage_Event
FOR EACH ROW
BEGIN
  DECLARE v_note VARCHAR(255);

  IF NOT (OLD.Final_Queue_Score <=> NEW.Final_Queue_Score) THEN
    SET v_note = COALESCE(@sq_score_note, 'Auto-rescored from new vital signs');
    SET @sq_score_note = NULL;

    INSERT INTO Score_History
      (Encounter_ID, Old_Score, New_Score, History_At, History_Notes)
    VALUES
      (NEW.Encounter_ID, OLD.Final_Queue_Score, NEW.Final_Queue_Score, NOW(), v_note);

    IF NEW.Check_out_Time IS NULL AND NEW.Doctor_ID IS NOT NULL THEN
      SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, Arrival_Time, Check_out_Time)))
        INTO @sq_consult_avg
      FROM Encounter_Triage_Event
      WHERE Doctor_ID = NEW.Doctor_ID
        AND Check_out_Time IS NOT NULL
        AND Check_out_Time > Arrival_Time;

      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SELECT CAST(Config_Value AS SIGNED) INTO @sq_consult_avg
        FROM Config
        WHERE Config_Key = 'default_consult_minutes';
      END IF;
      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SET @sq_consult_avg = 15;
      END IF;

      CALL sp_rebuild_queue(NEW.Doctor_ID);
      SET @sq_consult_avg = NULL;
    END IF;
  END IF;

  IF OLD.Check_out_Time IS NULL AND NEW.Check_out_Time IS NOT NULL THEN
    DELETE FROM Wait_List WHERE Encounter_ID = NEW.Encounter_ID;

    IF NEW.Doctor_ID IS NOT NULL THEN
      SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, Arrival_Time, Check_out_Time)))
        INTO @sq_consult_avg
      FROM Encounter_Triage_Event
      WHERE Doctor_ID = NEW.Doctor_ID
        AND Check_out_Time IS NOT NULL
        AND Check_out_Time > Arrival_Time;

      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SELECT CAST(Config_Value AS SIGNED) INTO @sq_consult_avg
        FROM Config
        WHERE Config_Key = 'default_consult_minutes';
      END IF;
      IF @sq_consult_avg IS NULL OR @sq_consult_avg <= 0 THEN
        SET @sq_consult_avg = 15;
      END IF;

      CALL sp_rebuild_queue(NEW.Doctor_ID);
      SET @sq_consult_avg = NULL;
    END IF;
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Queue: doctor status and overload alerts.
-- Counts are taken BEFORE the write, then stored in session variables.
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_waitlist_bi$$
CREATE TRIGGER trg_waitlist_bi
BEFORE INSERT ON Wait_List
FOR EACH ROW
BEGIN
  DECLARE v_esi  TINYINT;
  DECLARE v_dept INT;

  SELECT COUNT(*) INTO @sq_queue_len
  FROM Wait_List
  WHERE Doctor_ID = NEW.Doctor_ID;
  SET @sq_queue_len = IFNULL(@sq_queue_len, 0) + 1;

  SELECT e.Final_Queue_Score, d.Department_ID
    INTO v_esi, v_dept
  FROM Encounter_Triage_Event e
  JOIN Doctor d ON d.Doctor_ID = NEW.Doctor_ID
  WHERE e.Encounter_ID = NEW.Encounter_ID;

  SET @sq_alert_dept = v_dept;

  SELECT COUNT(*) INTO @sq_critical_len
  FROM Wait_List w
  JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
  JOIN Doctor d ON d.Doctor_ID = w.Doctor_ID
  WHERE d.Department_ID = v_dept
    AND e.Final_Queue_Score <= 2;

  IF v_esi IS NOT NULL AND v_esi <= 2 THEN
    SET @sq_critical_len = IFNULL(@sq_critical_len, 0) + 1;
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_waitlist_ai$$
CREATE TRIGGER trg_waitlist_ai
AFTER INSERT ON Wait_List
FOR EACH ROW
BEGIN
  DECLARE v_threshold INT;
  DECLARE v_crit      INT;
  DECLARE v_name      VARCHAR(100);
  DECLARE v_dept_name VARCHAR(80);

  CALL sp_apply_doctor_status(NEW.Doctor_ID, @sq_queue_len);

  SELECT CAST(Config_Value AS SIGNED) INTO v_threshold
  FROM Config WHERE Config_Key = 'doctor_queue_threshold';
  IF v_threshold IS NULL THEN SET v_threshold = 5; END IF;

  IF @sq_queue_len > v_threshold
     AND NOT EXISTS (
       SELECT 1 FROM Alert
       WHERE Is_Resolved = 0
         AND Alert_Type = 'DOCTOR_OVERLOAD'
         AND Doctor_ID = NEW.Doctor_ID
     ) THEN
    SELECT Name INTO v_name FROM Doctor WHERE Doctor_ID = NEW.Doctor_ID;
    INSERT INTO Alert (Alert_Type, Doctor_ID, Department_ID, Message, Created_At, Is_Resolved)
    VALUES (
      'DOCTOR_OVERLOAD', NEW.Doctor_ID, @sq_alert_dept,
      CONCAT(IFNULL(v_name, 'Doctor'), ' has ', @sq_queue_len,
             ' patients waiting, above the threshold of ', v_threshold),
      NOW(), 0
    );
  END IF;

  SELECT CAST(Config_Value AS SIGNED) INTO v_crit
  FROM Config WHERE Config_Key = 'dept_critical_threshold';
  IF v_crit IS NULL THEN SET v_crit = 3; END IF;

  IF @sq_alert_dept IS NOT NULL
     AND @sq_critical_len > v_crit
     AND NOT EXISTS (
       SELECT 1 FROM Alert
       WHERE Is_Resolved = 0
         AND Alert_Type = 'DEPT_CRITICAL'
         AND Department_ID = @sq_alert_dept
     ) THEN
    SELECT Name INTO v_dept_name FROM Department WHERE Department_ID = @sq_alert_dept;
    INSERT INTO Alert (Alert_Type, Doctor_ID, Department_ID, Message, Created_At, Is_Resolved)
    VALUES (
      'DEPT_CRITICAL', NULL, @sq_alert_dept,
      CONCAT(IFNULL(v_dept_name, 'Department'), ' has ', @sq_critical_len,
             ' ESI 1-2 patients waiting, above the threshold of ', v_crit),
      NOW(), 0
    );
  END IF;

  SET @sq_queue_len = NULL;
  SET @sq_critical_len = NULL;
  SET @sq_alert_dept = NULL;
END$$

DROP TRIGGER IF EXISTS trg_waitlist_bd$$
CREATE TRIGGER trg_waitlist_bd
BEFORE DELETE ON Wait_List
FOR EACH ROW
BEGIN
  SELECT COUNT(*) - 1 INTO @sq_queue_len
  FROM Wait_List
  WHERE Doctor_ID = OLD.Doctor_ID;
END$$

DROP TRIGGER IF EXISTS trg_waitlist_ad$$
CREATE TRIGGER trg_waitlist_ad
AFTER DELETE ON Wait_List
FOR EACH ROW
BEGIN
  CALL sp_apply_doctor_status(OLD.Doctor_ID, IFNULL(@sq_queue_len, 0));
  SET @sq_queue_len = NULL;
END$$

DELIMITER ;

SELECT '05_triggers.sql clinical triggers installed' AS status;

-- -----------------------------------------------------------------------------
-- Generic audit. One AFTER trigger per action per table.
-- Audit_Log is deliberately omitted.
-- -----------------------------------------------------------------------------
DELIMITER $$

DROP TRIGGER IF EXISTS trg_audit_dept_ai$$
CREATE TRIGGER trg_audit_dept_ai
AFTER INSERT ON Department
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Department', NEW.Department_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Department_ID', NEW.Department_ID, 'Name', NEW.Name, 'Description', NEW.Description),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_dept_au$$
CREATE TRIGGER trg_audit_dept_au
AFTER UPDATE ON Department
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Department', NEW.Department_ID, 'UPDATE',
  JSON_OBJECT('Department_ID', OLD.Department_ID, 'Name', OLD.Name, 'Description', OLD.Description),
  JSON_OBJECT('Department_ID', NEW.Department_ID, 'Name', NEW.Name, 'Description', NEW.Description),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_dept_ad$$
CREATE TRIGGER trg_audit_dept_ad
AFTER DELETE ON Department
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Department', OLD.Department_ID, 'DELETE',
  JSON_OBJECT('Department_ID', OLD.Department_ID, 'Name', OLD.Name, 'Description', OLD.Description),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_shift_ai$$
CREATE TRIGGER trg_audit_shift_ai
AFTER INSERT ON Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Shift', NEW.Shift_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Shift_ID', NEW.Shift_ID, 'Shift_Name', NEW.Shift_Name, 'Start_Time', NEW.Start_Time, 'End_Time', NEW.End_Time),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_shift_au$$
CREATE TRIGGER trg_audit_shift_au
AFTER UPDATE ON Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Shift', NEW.Shift_ID, 'UPDATE',
  JSON_OBJECT('Shift_ID', OLD.Shift_ID, 'Shift_Name', OLD.Shift_Name, 'Start_Time', OLD.Start_Time, 'End_Time', OLD.End_Time),
  JSON_OBJECT('Shift_ID', NEW.Shift_ID, 'Shift_Name', NEW.Shift_Name, 'Start_Time', NEW.Start_Time, 'End_Time', NEW.End_Time),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_shift_ad$$
CREATE TRIGGER trg_audit_shift_ad
AFTER DELETE ON Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Shift', OLD.Shift_ID, 'DELETE',
  JSON_OBJECT('Shift_ID', OLD.Shift_ID, 'Shift_Name', OLD.Shift_Name, 'Start_Time', OLD.Start_Time, 'End_Time', OLD.End_Time),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_rule_ai$$
CREATE TRIGGER trg_audit_rule_ai
AFTER INSERT ON Triage_Rule
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Triage_Rule', NEW.Rule_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Rule_ID', NEW.Rule_ID, 'Rule_Description', NEW.Rule_Description, 'Danger_Indicator', NEW.Danger_Indicator, 'ESI_Level', NEW.ESI_Level),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_rule_au$$
CREATE TRIGGER trg_audit_rule_au
AFTER UPDATE ON Triage_Rule
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Triage_Rule', NEW.Rule_ID, 'UPDATE',
  JSON_OBJECT('Rule_ID', OLD.Rule_ID, 'Rule_Description', OLD.Rule_Description, 'Danger_Indicator', OLD.Danger_Indicator, 'ESI_Level', OLD.ESI_Level),
  JSON_OBJECT('Rule_ID', NEW.Rule_ID, 'Rule_Description', NEW.Rule_Description, 'Danger_Indicator', NEW.Danger_Indicator, 'ESI_Level', NEW.ESI_Level),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_rule_ad$$
CREATE TRIGGER trg_audit_rule_ad
AFTER DELETE ON Triage_Rule
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Triage_Rule', OLD.Rule_ID, 'DELETE',
  JSON_OBJECT('Rule_ID', OLD.Rule_ID, 'Rule_Description', OLD.Rule_Description, 'Danger_Indicator', OLD.Danger_Indicator, 'ESI_Level', OLD.ESI_Level),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_aging_ai$$
CREATE TRIGGER trg_audit_aging_ai
AFTER INSERT ON Aging_Policy
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Aging_Policy', NEW.ESI_Level, 'INSERT',
  NULL,
  JSON_OBJECT('ESI_Level', NEW.ESI_Level, 'Max_Wait_Minutes', NEW.Max_Wait_Minutes),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_aging_au$$
CREATE TRIGGER trg_audit_aging_au
AFTER UPDATE ON Aging_Policy
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Aging_Policy', NEW.ESI_Level, 'UPDATE',
  JSON_OBJECT('ESI_Level', OLD.ESI_Level, 'Max_Wait_Minutes', OLD.Max_Wait_Minutes),
  JSON_OBJECT('ESI_Level', NEW.ESI_Level, 'Max_Wait_Minutes', NEW.Max_Wait_Minutes),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_aging_ad$$
CREATE TRIGGER trg_audit_aging_ad
AFTER DELETE ON Aging_Policy
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Aging_Policy', OLD.ESI_Level, 'DELETE',
  JSON_OBJECT('ESI_Level', OLD.ESI_Level, 'Max_Wait_Minutes', OLD.Max_Wait_Minutes),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_cfg_ai$$
CREATE TRIGGER trg_audit_cfg_ai
AFTER INSERT ON Config
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Config', NEW.Config_Key, 'INSERT',
  NULL,
  JSON_OBJECT('Config_Key', NEW.Config_Key, 'Config_Value', NEW.Config_Value),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_cfg_au$$
CREATE TRIGGER trg_audit_cfg_au
AFTER UPDATE ON Config
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Config', NEW.Config_Key, 'UPDATE',
  JSON_OBJECT('Config_Key', OLD.Config_Key, 'Config_Value', OLD.Config_Value),
  JSON_OBJECT('Config_Key', NEW.Config_Key, 'Config_Value', NEW.Config_Value),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_cfg_ad$$
CREATE TRIGGER trg_audit_cfg_ad
AFTER DELETE ON Config
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Config', OLD.Config_Key, 'DELETE',
  JSON_OBJECT('Config_Key', OLD.Config_Key, 'Config_Value', OLD.Config_Value),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_sym_ai$$
CREATE TRIGGER trg_audit_sym_ai
AFTER INSERT ON Symptom_Department_Map
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Symptom_Department_Map', NEW.Map_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Map_ID', NEW.Map_ID, 'Keyword', NEW.Keyword, 'Department_ID', NEW.Department_ID),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_sym_au$$
CREATE TRIGGER trg_audit_sym_au
AFTER UPDATE ON Symptom_Department_Map
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Symptom_Department_Map', NEW.Map_ID, 'UPDATE',
  JSON_OBJECT('Map_ID', OLD.Map_ID, 'Keyword', OLD.Keyword, 'Department_ID', OLD.Department_ID),
  JSON_OBJECT('Map_ID', NEW.Map_ID, 'Keyword', NEW.Keyword, 'Department_ID', NEW.Department_ID),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_sym_ad$$
CREATE TRIGGER trg_audit_sym_ad
AFTER DELETE ON Symptom_Department_Map
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Symptom_Department_Map', OLD.Map_ID, 'DELETE',
  JSON_OBJECT('Map_ID', OLD.Map_ID, 'Keyword', OLD.Keyword, 'Department_ID', OLD.Department_ID),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_pat_ai$$
CREATE TRIGGER trg_audit_pat_ai
AFTER INSERT ON Patient
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Patient', NEW.Patient_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Patient_ID', NEW.Patient_ID, 'Name', NEW.Name, 'Phone', NEW.Phone, 'Email', NEW.Email, 'Date_of_Birth', NEW.Date_of_Birth, 'Is_Deleted', NEW.Is_Deleted, 'Deleted_At', NEW.Deleted_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_pat_au$$
CREATE TRIGGER trg_audit_pat_au
AFTER UPDATE ON Patient
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Patient', NEW.Patient_ID, 'UPDATE',
  JSON_OBJECT('Patient_ID', OLD.Patient_ID, 'Name', OLD.Name, 'Phone', OLD.Phone, 'Email', OLD.Email, 'Date_of_Birth', OLD.Date_of_Birth, 'Is_Deleted', OLD.Is_Deleted, 'Deleted_At', OLD.Deleted_At),
  JSON_OBJECT('Patient_ID', NEW.Patient_ID, 'Name', NEW.Name, 'Phone', NEW.Phone, 'Email', NEW.Email, 'Date_of_Birth', NEW.Date_of_Birth, 'Is_Deleted', NEW.Is_Deleted, 'Deleted_At', NEW.Deleted_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_pat_ad$$
CREATE TRIGGER trg_audit_pat_ad
AFTER DELETE ON Patient
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Patient', OLD.Patient_ID, 'DELETE',
  JSON_OBJECT('Patient_ID', OLD.Patient_ID, 'Name', OLD.Name, 'Phone', OLD.Phone, 'Email', OLD.Email, 'Date_of_Birth', OLD.Date_of_Birth, 'Is_Deleted', OLD.Is_Deleted, 'Deleted_At', OLD.Deleted_At),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_doc_ai$$
CREATE TRIGGER trg_audit_doc_ai
AFTER INSERT ON Doctor
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor', NEW.Doctor_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Doctor_ID', NEW.Doctor_ID, 'Name', NEW.Name, 'Role', NEW.`Role`, 'Specialization', NEW.Specialization, 'Current_Status', NEW.Current_Status, 'Department_ID', NEW.Department_ID, 'Is_Deleted', NEW.Is_Deleted, 'Deleted_At', NEW.Deleted_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_doc_au$$
CREATE TRIGGER trg_audit_doc_au
AFTER UPDATE ON Doctor
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor', NEW.Doctor_ID, 'UPDATE',
  JSON_OBJECT('Doctor_ID', OLD.Doctor_ID, 'Name', OLD.Name, 'Role', OLD.`Role`, 'Specialization', OLD.Specialization, 'Current_Status', OLD.Current_Status, 'Department_ID', OLD.Department_ID, 'Is_Deleted', OLD.Is_Deleted, 'Deleted_At', OLD.Deleted_At),
  JSON_OBJECT('Doctor_ID', NEW.Doctor_ID, 'Name', NEW.Name, 'Role', NEW.`Role`, 'Specialization', NEW.Specialization, 'Current_Status', NEW.Current_Status, 'Department_ID', NEW.Department_ID, 'Is_Deleted', NEW.Is_Deleted, 'Deleted_At', NEW.Deleted_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_doc_ad$$
CREATE TRIGGER trg_audit_doc_ad
AFTER DELETE ON Doctor
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor', OLD.Doctor_ID, 'DELETE',
  JSON_OBJECT('Doctor_ID', OLD.Doctor_ID, 'Name', OLD.Name, 'Role', OLD.`Role`, 'Specialization', OLD.Specialization, 'Current_Status', OLD.Current_Status, 'Department_ID', OLD.Department_ID, 'Is_Deleted', OLD.Is_Deleted, 'Deleted_At', OLD.Deleted_At),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_dsh_ai$$
CREATE TRIGGER trg_audit_dsh_ai
AFTER INSERT ON Doctor_Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor_Shift', NEW.Doctor_Shift_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Doctor_Shift_ID', NEW.Doctor_Shift_ID, 'Doctor_ID', NEW.Doctor_ID, 'Shift_ID', NEW.Shift_ID, 'Shift_Date', NEW.Shift_Date),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_dsh_au$$
CREATE TRIGGER trg_audit_dsh_au
AFTER UPDATE ON Doctor_Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor_Shift', NEW.Doctor_Shift_ID, 'UPDATE',
  JSON_OBJECT('Doctor_Shift_ID', OLD.Doctor_Shift_ID, 'Doctor_ID', OLD.Doctor_ID, 'Shift_ID', OLD.Shift_ID, 'Shift_Date', OLD.Shift_Date),
  JSON_OBJECT('Doctor_Shift_ID', NEW.Doctor_Shift_ID, 'Doctor_ID', NEW.Doctor_ID, 'Shift_ID', NEW.Shift_ID, 'Shift_Date', NEW.Shift_Date),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_dsh_ad$$
CREATE TRIGGER trg_audit_dsh_ad
AFTER DELETE ON Doctor_Shift
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Doctor_Shift', OLD.Doctor_Shift_ID, 'DELETE',
  JSON_OBJECT('Doctor_Shift_ID', OLD.Doctor_Shift_ID, 'Doctor_ID', OLD.Doctor_ID, 'Shift_ID', OLD.Shift_ID, 'Shift_Date', OLD.Shift_Date),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_enc_ai$$
CREATE TRIGGER trg_audit_enc_ai
AFTER INSERT ON Encounter_Triage_Event
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Encounter_Triage_Event', NEW.Encounter_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Encounter_ID', NEW.Encounter_ID, 'Patient_ID', NEW.Patient_ID, 'Doctor_ID', NEW.Doctor_ID, 'Department_ID', NEW.Department_ID, 'Rule_ID', NEW.Rule_ID, 'Arrival_Time', NEW.Arrival_Time, 'Check_out_Time', NEW.Check_out_Time, 'Initial_Symptoms', NEW.Initial_Symptoms, 'Final_Queue_Score', NEW.Final_Queue_Score),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_enc_au$$
CREATE TRIGGER trg_audit_enc_au
AFTER UPDATE ON Encounter_Triage_Event
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Encounter_Triage_Event', NEW.Encounter_ID, 'UPDATE',
  JSON_OBJECT('Encounter_ID', OLD.Encounter_ID, 'Patient_ID', OLD.Patient_ID, 'Doctor_ID', OLD.Doctor_ID, 'Department_ID', OLD.Department_ID, 'Rule_ID', OLD.Rule_ID, 'Arrival_Time', OLD.Arrival_Time, 'Check_out_Time', OLD.Check_out_Time, 'Initial_Symptoms', OLD.Initial_Symptoms, 'Final_Queue_Score', OLD.Final_Queue_Score),
  JSON_OBJECT('Encounter_ID', NEW.Encounter_ID, 'Patient_ID', NEW.Patient_ID, 'Doctor_ID', NEW.Doctor_ID, 'Department_ID', NEW.Department_ID, 'Rule_ID', NEW.Rule_ID, 'Arrival_Time', NEW.Arrival_Time, 'Check_out_Time', NEW.Check_out_Time, 'Initial_Symptoms', NEW.Initial_Symptoms, 'Final_Queue_Score', NEW.Final_Queue_Score),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_enc_ad$$
CREATE TRIGGER trg_audit_enc_ad
AFTER DELETE ON Encounter_Triage_Event
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Encounter_Triage_Event', OLD.Encounter_ID, 'DELETE',
  JSON_OBJECT('Encounter_ID', OLD.Encounter_ID, 'Patient_ID', OLD.Patient_ID, 'Doctor_ID', OLD.Doctor_ID, 'Department_ID', OLD.Department_ID, 'Rule_ID', OLD.Rule_ID, 'Arrival_Time', OLD.Arrival_Time, 'Check_out_Time', OLD.Check_out_Time, 'Initial_Symptoms', OLD.Initial_Symptoms, 'Final_Queue_Score', OLD.Final_Queue_Score),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_vit_ai$$
CREATE TRIGGER trg_audit_vit_ai
AFTER INSERT ON Vitals_Log
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Vitals_Log', NEW.Log_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Log_ID', NEW.Log_ID, 'Encounter_ID', NEW.Encounter_ID, 'Log_Timestamp', NEW.Log_Timestamp, 'Type_Name', NEW.Type_Name, 'Heart_Rate', NEW.Heart_Rate, 'SpO2', NEW.SpO2, 'Systolic_BP', NEW.Systolic_BP, 'Diastolic_BP', NEW.Diastolic_BP, 'Temperature', NEW.Temperature, 'Pain_Scale', NEW.Pain_Scale),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_vit_au$$
CREATE TRIGGER trg_audit_vit_au
AFTER UPDATE ON Vitals_Log
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Vitals_Log', NEW.Log_ID, 'UPDATE',
  JSON_OBJECT('Log_ID', OLD.Log_ID, 'Encounter_ID', OLD.Encounter_ID, 'Log_Timestamp', OLD.Log_Timestamp, 'Type_Name', OLD.Type_Name, 'Heart_Rate', OLD.Heart_Rate, 'SpO2', OLD.SpO2, 'Systolic_BP', OLD.Systolic_BP, 'Diastolic_BP', OLD.Diastolic_BP, 'Temperature', OLD.Temperature, 'Pain_Scale', OLD.Pain_Scale),
  JSON_OBJECT('Log_ID', NEW.Log_ID, 'Encounter_ID', NEW.Encounter_ID, 'Log_Timestamp', NEW.Log_Timestamp, 'Type_Name', NEW.Type_Name, 'Heart_Rate', NEW.Heart_Rate, 'SpO2', NEW.SpO2, 'Systolic_BP', NEW.Systolic_BP, 'Diastolic_BP', NEW.Diastolic_BP, 'Temperature', NEW.Temperature, 'Pain_Scale', NEW.Pain_Scale),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_vit_ad$$
CREATE TRIGGER trg_audit_vit_ad
AFTER DELETE ON Vitals_Log
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Vitals_Log', OLD.Log_ID, 'DELETE',
  JSON_OBJECT('Log_ID', OLD.Log_ID, 'Encounter_ID', OLD.Encounter_ID, 'Log_Timestamp', OLD.Log_Timestamp, 'Type_Name', OLD.Type_Name, 'Heart_Rate', OLD.Heart_Rate, 'SpO2', OLD.SpO2, 'Systolic_BP', OLD.Systolic_BP, 'Diastolic_BP', OLD.Diastolic_BP, 'Temperature', OLD.Temperature, 'Pain_Scale', OLD.Pain_Scale),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_wait_ai$$
CREATE TRIGGER trg_audit_wait_ai
AFTER INSERT ON Wait_List
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Wait_List', NEW.Queue_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Queue_ID', NEW.Queue_ID, 'Encounter_ID', NEW.Encounter_ID, 'Doctor_ID', NEW.Doctor_ID, 'Queue_Position', NEW.Queue_Position, 'Assigned_Time', NEW.Assigned_Time, 'Est_Wait_Time', NEW.Est_Wait_Time),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_wait_au$$
CREATE TRIGGER trg_audit_wait_au
AFTER UPDATE ON Wait_List
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Wait_List', NEW.Queue_ID, 'UPDATE',
  JSON_OBJECT('Queue_ID', OLD.Queue_ID, 'Encounter_ID', OLD.Encounter_ID, 'Doctor_ID', OLD.Doctor_ID, 'Queue_Position', OLD.Queue_Position, 'Assigned_Time', OLD.Assigned_Time, 'Est_Wait_Time', OLD.Est_Wait_Time),
  JSON_OBJECT('Queue_ID', NEW.Queue_ID, 'Encounter_ID', NEW.Encounter_ID, 'Doctor_ID', NEW.Doctor_ID, 'Queue_Position', NEW.Queue_Position, 'Assigned_Time', NEW.Assigned_Time, 'Est_Wait_Time', NEW.Est_Wait_Time),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_wait_ad$$
CREATE TRIGGER trg_audit_wait_ad
AFTER DELETE ON Wait_List
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Wait_List', OLD.Queue_ID, 'DELETE',
  JSON_OBJECT('Queue_ID', OLD.Queue_ID, 'Encounter_ID', OLD.Encounter_ID, 'Doctor_ID', OLD.Doctor_ID, 'Queue_Position', OLD.Queue_Position, 'Assigned_Time', OLD.Assigned_Time, 'Est_Wait_Time', OLD.Est_Wait_Time),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_hist_ai$$
CREATE TRIGGER trg_audit_hist_ai
AFTER INSERT ON Score_History
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Score_History', NEW.History_ID, 'INSERT',
  NULL,
  JSON_OBJECT('History_ID', NEW.History_ID, 'Encounter_ID', NEW.Encounter_ID, 'Old_Score', NEW.Old_Score, 'New_Score', NEW.New_Score, 'History_At', NEW.History_At, 'History_Notes', NEW.History_Notes),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_hist_au$$
CREATE TRIGGER trg_audit_hist_au
AFTER UPDATE ON Score_History
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Score_History', NEW.History_ID, 'UPDATE',
  JSON_OBJECT('History_ID', OLD.History_ID, 'Encounter_ID', OLD.Encounter_ID, 'Old_Score', OLD.Old_Score, 'New_Score', OLD.New_Score, 'History_At', OLD.History_At, 'History_Notes', OLD.History_Notes),
  JSON_OBJECT('History_ID', NEW.History_ID, 'Encounter_ID', NEW.Encounter_ID, 'Old_Score', NEW.Old_Score, 'New_Score', NEW.New_Score, 'History_At', NEW.History_At, 'History_Notes', NEW.History_Notes),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_hist_ad$$
CREATE TRIGGER trg_audit_hist_ad
AFTER DELETE ON Score_History
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Score_History', OLD.History_ID, 'DELETE',
  JSON_OBJECT('History_ID', OLD.History_ID, 'Encounter_ID', OLD.Encounter_ID, 'Old_Score', OLD.Old_Score, 'New_Score', OLD.New_Score, 'History_At', OLD.History_At, 'History_Notes', OLD.History_Notes),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_alrt_ai$$
CREATE TRIGGER trg_audit_alrt_ai
AFTER INSERT ON Alert
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Alert', NEW.Alert_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Alert_ID', NEW.Alert_ID, 'Alert_Type', NEW.Alert_Type, 'Doctor_ID', NEW.Doctor_ID, 'Department_ID', NEW.Department_ID, 'Message', NEW.Message, 'Created_At', NEW.Created_At, 'Is_Resolved', NEW.Is_Resolved),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_alrt_au$$
CREATE TRIGGER trg_audit_alrt_au
AFTER UPDATE ON Alert
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Alert', NEW.Alert_ID, 'UPDATE',
  JSON_OBJECT('Alert_ID', OLD.Alert_ID, 'Alert_Type', OLD.Alert_Type, 'Doctor_ID', OLD.Doctor_ID, 'Department_ID', OLD.Department_ID, 'Message', OLD.Message, 'Created_At', OLD.Created_At, 'Is_Resolved', OLD.Is_Resolved),
  JSON_OBJECT('Alert_ID', NEW.Alert_ID, 'Alert_Type', NEW.Alert_Type, 'Doctor_ID', NEW.Doctor_ID, 'Department_ID', NEW.Department_ID, 'Message', NEW.Message, 'Created_At', NEW.Created_At, 'Is_Resolved', NEW.Is_Resolved),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_alrt_ad$$
CREATE TRIGGER trg_audit_alrt_ad
AFTER DELETE ON Alert
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Alert', OLD.Alert_ID, 'DELETE',
  JSON_OBJECT('Alert_ID', OLD.Alert_ID, 'Alert_Type', OLD.Alert_Type, 'Doctor_ID', OLD.Doctor_ID, 'Department_ID', OLD.Department_ID, 'Message', OLD.Message, 'Created_At', OLD.Created_At, 'Is_Resolved', OLD.Is_Resolved),
  NULL,
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_arc_ai$$
CREATE TRIGGER trg_audit_arc_ai
AFTER INSERT ON Audit_Log_Archive
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Audit_Log_Archive', NEW.Audit_ID, 'INSERT',
  NULL,
  JSON_OBJECT('Audit_ID', NEW.Audit_ID, 'Table_Name', NEW.Table_Name, 'Record_ID', NEW.Record_ID, 'Action', NEW.Action, 'Old_Data', NEW.Old_Data, 'New_Data', NEW.New_Data, 'Changed_By', NEW.Changed_By, 'Changed_At', NEW.Changed_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_arc_au$$
CREATE TRIGGER trg_audit_arc_au
AFTER UPDATE ON Audit_Log_Archive
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Audit_Log_Archive', NEW.Audit_ID, 'UPDATE',
  JSON_OBJECT('Audit_ID', OLD.Audit_ID, 'Table_Name', OLD.Table_Name, 'Record_ID', OLD.Record_ID, 'Action', OLD.Action, 'Old_Data', OLD.Old_Data, 'New_Data', OLD.New_Data, 'Changed_By', OLD.Changed_By, 'Changed_At', OLD.Changed_At),
  JSON_OBJECT('Audit_ID', NEW.Audit_ID, 'Table_Name', NEW.Table_Name, 'Record_ID', NEW.Record_ID, 'Action', NEW.Action, 'Old_Data', NEW.Old_Data, 'New_Data', NEW.New_Data, 'Changed_By', NEW.Changed_By, 'Changed_At', NEW.Changed_At),
  CURRENT_USER(), NOW()
)$$

DROP TRIGGER IF EXISTS trg_audit_arc_ad$$
CREATE TRIGGER trg_audit_arc_ad
AFTER DELETE ON Audit_Log_Archive
FOR EACH ROW
INSERT INTO Audit_Log (Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)
VALUES (
  'Audit_Log_Archive', OLD.Audit_ID, 'DELETE',
  JSON_OBJECT('Audit_ID', OLD.Audit_ID, 'Table_Name', OLD.Table_Name, 'Record_ID', OLD.Record_ID, 'Action', OLD.Action, 'Old_Data', OLD.Old_Data, 'New_Data', OLD.New_Data, 'Changed_By', OLD.Changed_By, 'Changed_At', OLD.Changed_At),
  NULL,
  CURRENT_USER(), NOW()
)$$

DELIMITER ;

SELECT '05_triggers.sql audit triggers installed' AS status;
