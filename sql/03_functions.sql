-- =============================================================================
-- 03_functions.sql
-- All clinical decisions that return a single value live here.
-- None of these functions write. Procedures and triggers call them.
-- log_bin_trust_function_creators lets MySQL accept the functions when the
-- binary log is enabled (typical of a Homebrew MySQL 8 install).
-- =============================================================================

USE SmartQueue;

SET GLOBAL log_bin_trust_function_creators = 1;

DELIMITER $$

-- ESI 1 is the most urgent. The first matching danger level wins, which is
-- the same order as Triage_Rule.Rule_ID.
DROP FUNCTION IF EXISTS fn_calc_esi$$
CREATE FUNCTION fn_calc_esi(
  p_hr   SMALLINT,
  p_spo2 TINYINT,
  p_sys  SMALLINT,
  p_temp DECIMAL(4,1),
  p_pain TINYINT
) RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
  IF p_spo2 < 90 OR p_sys < 80 OR p_hr > 150 OR p_hr < 40 THEN
    RETURN 1;
  ELSEIF p_spo2 BETWEEN 90 AND 93 OR p_hr BETWEEN 120 AND 150 OR p_pain >= 8 THEN
    RETURN 2;
  ELSEIF p_temp >= 39.0 OR p_pain BETWEEN 5 AND 7 THEN
    RETURN 3;
  ELSEIF p_pain BETWEEN 3 AND 4 THEN
    RETURN 4;
  ELSE
    RETURN 5;
  END IF;
END$$

-- TRUE when the doctor has a shift covering p_when.
-- A shift whose end is not after its start crosses midnight: the late half
-- belongs to Shift_Date and the early half belongs to the next morning.
DROP FUNCTION IF EXISTS fn_is_on_duty$$
CREATE FUNCTION fn_is_on_duty(
  p_doctor_id INT,
  p_when      DATETIME
) RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_on TINYINT DEFAULT 0;

  IF p_when IS NULL THEN
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM Doctor_Shift ds
    JOIN Shift s ON s.Shift_ID = ds.Shift_ID
    JOIN Doctor d ON d.Doctor_ID = ds.Doctor_ID AND d.Is_Deleted = 0
    WHERE ds.Doctor_ID = p_doctor_id
      AND (
        (s.End_Time > s.Start_Time
          AND ds.Shift_Date = DATE(p_when)
          AND TIME(p_when) >= s.Start_Time
          AND TIME(p_when) <  s.End_Time)
        OR
        (s.End_Time <= s.Start_Time
          AND ds.Shift_Date = DATE(p_when)
          AND TIME(p_when) >= s.Start_Time)
        OR
        (s.End_Time <= s.Start_Time
          AND ds.Shift_Date = DATE_SUB(DATE(p_when), INTERVAL 1 DAY)
          AND TIME(p_when) < s.End_Time)
      )
  ) INTO v_on;

  RETURN IFNULL(v_on, 0);
END$$

-- Minutes until this queue slot is reached.
-- Average comes from that doctor's discharged visits. Config supplies the
-- default (15) when the doctor has no completed visits.
-- Position 1 waits 0 minutes.
DROP FUNCTION IF EXISTS fn_estimate_wait$$
CREATE FUNCTION fn_estimate_wait(
  p_doctor_id      INT,
  p_queue_position INT
) RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_avg     DECIMAL(10,2);
  DECLARE v_default INT;

  -- A NOT FOUND from the config lookup must not escape into a caller's cursor.
  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  IF p_queue_position IS NULL OR p_queue_position <= 1 THEN
    RETURN 0;
  END IF;

  -- When a trigger on Encounter_Triage_Event calls the queue rebuild, it
  -- sets @sq_consult_avg first. A function is not allowed to read the table
  -- that fired the trigger (error 1442), so the precomputed average is used.
  -- Outside a trigger the variable is NULL and the average is read here.
  IF @sq_consult_avg IS NOT NULL AND @sq_consult_avg > 0 THEN
    SET v_avg = @sq_consult_avg;
  ELSE
    SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, Arrival_Time, Check_out_Time)))
      INTO v_avg
    FROM Encounter_Triage_Event
    WHERE Doctor_ID = p_doctor_id
      AND Check_out_Time IS NOT NULL
      AND Check_out_Time > Arrival_Time;
  END IF;

  IF v_avg IS NULL OR v_avg <= 0 THEN
    SELECT CAST(Config_Value AS SIGNED) INTO v_default
    FROM Config
    WHERE Config_Key = 'default_consult_minutes';
    SET v_avg = IFNULL(v_default, 15);
  END IF;

  IF v_avg IS NULL OR v_avg <= 0 THEN
    SET v_avg = 15;
  END IF;

  RETURN (p_queue_position - 1) * v_avg;
END$$

-- Longest keyword contained in the symptom text. No match → Emergency Medicine.
DROP FUNCTION IF EXISTS fn_pick_department$$
CREATE FUNCTION fn_pick_department(
  p_symptom_text VARCHAR(500)
) RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_dept INT;

  SELECT m.Department_ID INTO v_dept
  FROM Symptom_Department_Map m
  WHERE LOWER(p_symptom_text) LIKE CONCAT('%', LOWER(m.Keyword), '%')
  ORDER BY CHAR_LENGTH(m.Keyword) DESC, m.Map_ID
  LIMIT 1;

  IF v_dept IS NULL THEN
    SELECT Department_ID INTO v_dept
    FROM Department
    WHERE Name = 'Emergency Medicine'
    LIMIT 1;
  END IF;

  IF v_dept IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No department could be selected';
  END IF;

  RETURN v_dept;
END$$

-- Shortest on-duty queue in the department, Doctor_ID breaks ties.
-- ESI 1 will not go to a resident while any consultant is on duty:
--   1. consultant in the mapped department
--   2. consultant in Emergency Medicine
--   3. any on-duty consultant in the hospital
-- Everyone else:
--   1. any on-duty doctor in the mapped department
--   2. any on-duty Emergency Medicine doctor
-- If nobody is on duty, the function raises an error and nobody is inserted.
DROP FUNCTION IF EXISTS fn_pick_doctor$$
CREATE FUNCTION fn_pick_doctor(
  p_department_id INT,
  p_esi           TINYINT
) RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_doctor INT DEFAULT NULL;
  DECLARE v_em     INT;

  SELECT Department_ID INTO v_em
  FROM Department
  WHERE Name = 'Emergency Medicine'
  LIMIT 1;

  IF p_esi = 1 THEN
    SELECT d.Doctor_ID INTO v_doctor
    FROM Doctor d
    LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
    WHERE d.Is_Deleted = 0
      AND d.Department_ID = p_department_id
      AND d.`Role` IN ('Consultant', 'Senior Consultant')
      AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
    GROUP BY d.Doctor_ID
    ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
    LIMIT 1;

    IF v_doctor IS NULL AND v_em IS NOT NULL AND v_em <> p_department_id THEN
      SELECT d.Doctor_ID INTO v_doctor
      FROM Doctor d
      LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
      WHERE d.Is_Deleted = 0
        AND d.Department_ID = v_em
        AND d.`Role` IN ('Consultant', 'Senior Consultant')
        AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
      GROUP BY d.Doctor_ID
      ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
      LIMIT 1;
    END IF;

    IF v_doctor IS NULL THEN
      SELECT d.Doctor_ID INTO v_doctor
      FROM Doctor d
      LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
      WHERE d.Is_Deleted = 0
        AND d.`Role` IN ('Consultant', 'Senior Consultant')
        AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
      GROUP BY d.Doctor_ID
      ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
      LIMIT 1;
    END IF;
  END IF;

  IF v_doctor IS NULL THEN
    SELECT d.Doctor_ID INTO v_doctor
    FROM Doctor d
    LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
    WHERE d.Is_Deleted = 0
      AND d.Department_ID = p_department_id
      AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
    GROUP BY d.Doctor_ID
    ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
    LIMIT 1;
  END IF;

  IF v_doctor IS NULL AND v_em IS NOT NULL THEN
    SELECT d.Doctor_ID INTO v_doctor
    FROM Doctor d
    LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
    WHERE d.Is_Deleted = 0
      AND d.Department_ID = v_em
      AND fn_is_on_duty(d.Doctor_ID, NOW()) = 1
    GROUP BY d.Doctor_ID
    ORDER BY COUNT(w.Queue_ID), d.Doctor_ID
    LIMIT 1;
  END IF;

  IF v_doctor IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No on-duty doctor is available for this case';
  END IF;

  RETURN v_doctor;
END$$

-- 1 when the proposed shift overlaps a shift this doctor already has.
-- Back-to-back shifts (one ends as the next starts) do not overlap.
-- p_exclude_id lets an update ignore the row being changed.
DROP FUNCTION IF EXISTS fn_doctor_shift_overlaps$$
CREATE FUNCTION fn_doctor_shift_overlaps(
  p_doctor_id  INT,
  p_shift_id   INT,
  p_shift_date DATE,
  p_exclude_id INT
) RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_start INT;
  DECLARE v_end   INT;
  DECLARE v_hits  INT DEFAULT 0;

  SELECT TIME_TO_SEC(Start_Time), TIME_TO_SEC(End_Time)
    INTO v_start, v_end
  FROM Shift
  WHERE Shift_ID = p_shift_id;

  IF v_start IS NULL THEN
    RETURN 0;
  END IF;

  IF v_end <= v_start THEN
    SET v_end = v_end + 86400;
  END IF;

  -- Compare as seconds from Shift_Date 00:00, looking one day either side
  -- so an overnight shift is visible to the neighbouring date.
  SELECT COUNT(*) INTO v_hits
  FROM (
    SELECT
      TIME_TO_SEC(s.Start_Time)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(p_shift_date), TIMESTAMP(ds.Shift_Date)) AS s0,
      TIME_TO_SEC(s.End_Time)
        + IF(s.End_Time <= s.Start_Time, 86400, 0)
        + TIMESTAMPDIFF(SECOND, TIMESTAMP(p_shift_date), TIMESTAMP(ds.Shift_Date)) AS e0
    FROM Doctor_Shift ds
    JOIN Shift s ON s.Shift_ID = ds.Shift_ID
    WHERE ds.Doctor_ID = p_doctor_id
      AND (p_exclude_id IS NULL OR ds.Doctor_Shift_ID <> p_exclude_id)
      AND ds.Shift_Date BETWEEN DATE_SUB(p_shift_date, INTERVAL 1 DAY)
                            AND DATE_ADD(p_shift_date, INTERVAL 1 DAY)
  ) AS existing
  WHERE v_start < existing.e0
    AND existing.s0 < v_end;

  RETURN IF(v_hits > 0, 1, 0);
END$$

DELIMITER ;

SELECT '03_functions.sql complete' AS status;
