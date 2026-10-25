-- =============================================================================
-- 08_indexes.sql
-- Secondary indexes for the access paths the procedures and views actually use.
-- Foreign keys already created single-column indexes. The composites below
-- cover the filters plus the sort, which is what the optimiser needs.
--
-- Each of the three key queries is EXPLAINed twice: once before its index
-- exists, and once after. On a small sample the optimiser may still choose
-- a table scan; compare `possible_keys` and `key`. With more rows the new
-- index is the one it picks.
-- =============================================================================

USE SmartQueue;

SELECT 'EXPLAIN before indexes — queue by doctor and position' AS step;
EXPLAIN
SELECT Queue_ID, Encounter_ID, Queue_Position, Est_Wait_Time
FROM Wait_List
WHERE Doctor_ID = 3
ORDER BY Queue_Position;

SELECT 'EXPLAIN before indexes — discharged visits for one doctor' AS step;
EXPLAIN
SELECT Encounter_ID, Arrival_Time, Check_out_Time
FROM Encounter_Triage_Event
WHERE Doctor_ID = 2
  AND Check_out_Time IS NOT NULL;

SELECT 'EXPLAIN before indexes — vitals for one encounter, newest first' AS step;
EXPLAIN
SELECT Log_ID, Heart_Rate, SpO2, Log_Timestamp
FROM Vitals_Log
WHERE Encounter_ID = 7
ORDER BY Log_Timestamp DESC;

CREATE INDEX idx_waitlist_doctor_pos
  ON Wait_List (Doctor_ID, Queue_Position);

CREATE INDEX idx_enc_checkout_doctor
  ON Encounter_Triage_Event (Check_out_Time, Doctor_ID);

CREATE INDEX idx_enc_patient_checkout
  ON Encounter_Triage_Event (Patient_ID, Check_out_Time);

CREATE INDEX idx_vitals_enc_time
  ON Vitals_Log (Encounter_ID, Log_Timestamp);

CREATE INDEX idx_docshift_date_doctor
  ON Doctor_Shift (Shift_Date, Doctor_ID);

CREATE INDEX idx_audit_table_record
  ON Audit_Log (Table_Name, Record_ID);

CREATE INDEX idx_audit_changed_at
  ON Audit_Log (Changed_At);

-- F15. Used by sp_search_similar_cases (MATCH ... AGAINST).
CREATE FULLTEXT INDEX ft_symptoms
  ON Encounter_Triage_Event (Initial_Symptoms);

SELECT 'EXPLAIN after indexes — queue by doctor and position' AS step;
EXPLAIN
SELECT Queue_ID, Encounter_ID, Queue_Position, Est_Wait_Time
FROM Wait_List
WHERE Doctor_ID = 3
ORDER BY Queue_Position;

SELECT 'EXPLAIN after indexes — discharged visits for one doctor' AS step;
EXPLAIN
SELECT Encounter_ID, Arrival_Time, Check_out_Time
FROM Encounter_Triage_Event
WHERE Doctor_ID = 2
  AND Check_out_Time IS NOT NULL;

SELECT 'EXPLAIN after indexes — vitals for one encounter, newest first' AS step;
EXPLAIN
SELECT Log_ID, Heart_Rate, SpO2, Log_Timestamp
FROM Vitals_Log
WHERE Encounter_ID = 7
ORDER BY Log_Timestamp DESC;

SELECT '08_indexes.sql complete' AS status;
