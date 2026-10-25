-- =============================================================================
-- 06_views.sql
-- Views are SQL SECURITY DEFINER (the default when this script is run as
-- root). A role granted SELECT on the view can read it without any grant
-- on the base tables.
--
-- Operational views hide soft-deleted people. vw_deleted_directory is the
-- one exception: it lists only deleted rows, so an administrator can restore
-- them. vw_score_audit also hides soft-deleted patients; the Audit_Log table
-- itself still keeps those changes for the auditor.
-- =============================================================================

USE SmartQueue;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_live_queue AS
SELECT d.Doctor_ID,
       d.Name AS Doctor_Name,
       d.Current_Status AS Doctor_Status,
       dep.Department_ID,
       dep.Name AS Department_Name,
       w.Queue_ID,
       w.Queue_Position,
       w.Est_Wait_Time,
       w.Assigned_Time,
       e.Encounter_ID,
       e.Patient_ID,
       p.Name AS Patient_Name,
       e.Final_Queue_Score AS ESI,
       e.Arrival_Time,
       e.Initial_Symptoms
FROM Wait_List w
JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
JOIN Doctor d ON d.Doctor_ID = w.Doctor_ID AND d.Is_Deleted = 0
JOIN Department dep ON dep.Department_ID = d.Department_ID;

-- No phone, email or date of birth. Age is computed.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_doctor_clinical AS
SELECT w.Doctor_ID,
       d.Name AS Doctor_Name,
       dep.Name AS Department_Name,
       w.Queue_Position,
       e.Encounter_ID,
       p.Patient_ID,
       p.Name AS Patient_Name,
       TIMESTAMPDIFF(YEAR, p.Date_of_Birth, CURDATE()) AS Age,
       e.Final_Queue_Score AS ESI,
       e.Initial_Symptoms,
       e.Arrival_Time,
       v.Log_Timestamp AS Vitals_At,
       v.Heart_Rate,
       v.SpO2,
       CONCAT(v.Systolic_BP, '/', v.Diastolic_BP) AS Blood_Pressure,
       v.Temperature,
       v.Pain_Scale,
       w.Est_Wait_Time
FROM Wait_List w
JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
JOIN Doctor d ON d.Doctor_ID = w.Doctor_ID AND d.Is_Deleted = 0
JOIN Department dep ON dep.Department_ID = d.Department_ID
JOIN Vitals_Log v ON v.Encounter_ID = e.Encounter_ID
 AND v.Log_Timestamp = (
   SELECT MAX(v2.Log_Timestamp)
   FROM Vitals_Log v2
   WHERE v2.Encounter_ID = e.Encounter_ID
 );

-- Administrative picture: contacts and times, no symptoms, vitals or ESI.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_admin_summary AS
SELECT e.Encounter_ID,
       p.Patient_ID,
       p.Name AS Patient_Name,
       p.Phone,
       p.Email,
       p.Date_of_Birth,
       d.Name AS Doctor_Name,
       dep.Name AS Department_Name,
       e.Arrival_Time,
       e.Check_out_Time,
       CASE WHEN e.Check_out_Time IS NULL THEN 'Active' ELSE 'Discharged' END AS Status,
       TIMESTAMPDIFF(MINUTE, e.Arrival_Time, COALESCE(e.Check_out_Time, NOW())) AS Length_Of_Stay_Min
FROM Encounter_Triage_Event e
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
LEFT JOIN Doctor d ON d.Doctor_ID = e.Doctor_ID
LEFT JOIN Department dep ON dep.Department_ID = e.Department_ID;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_score_audit AS
SELECT s.History_ID,
       s.Encounter_ID,
       p.Name AS Patient_Name,
       s.Old_Score,
       s.New_Score,
       s.History_At,
       s.History_Notes
FROM Score_History s
JOIN Encounter_Triage_Event e ON e.Encounter_ID = s.Encounter_ID
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_department_load AS
SELECT dep.Department_ID,
       dep.Name AS Department,
       COUNT(w.Queue_ID) AS Patients_Waiting,
       ROUND(AVG(w.Est_Wait_Time), 1) AS Avg_Est_Wait_Min,
       SUM(CASE WHEN e.Final_Queue_Score <= 2 THEN 1 ELSE 0 END) AS Critical_Waiting
FROM Department dep
LEFT JOIN Doctor d
  ON d.Department_ID = dep.Department_ID AND d.Is_Deleted = 0
LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
LEFT JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
GROUP BY dep.Department_ID, dep.Name;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_wait_by_esi AS
SELECT e.Final_Queue_Score AS ESI,
       COUNT(*) AS Patients_Waiting,
       ROUND(AVG(w.Est_Wait_Time), 1) AS Avg_Est_Wait_Min,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, e.Arrival_Time, NOW())), 1) AS Avg_Time_In_Queue_Min
FROM Wait_List w
JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
GROUP BY e.Final_Queue_Score;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_busiest_hours AS
SELECT HOUR(e.Arrival_Time) AS Hour_Of_Day,
       COUNT(*) AS Arrivals
FROM Encounter_Triage_Event e
JOIN Patient p ON p.Patient_ID = e.Patient_ID AND p.Is_Deleted = 0
GROUP BY HOUR(e.Arrival_Time);

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_doctor_workload AS
SELECT d.Doctor_ID,
       d.Name AS Doctor_Name,
       d.`Role` AS Doctor_Role,
       d.Current_Status,
       dep.Name AS Department_Name,
       COUNT(w.Queue_ID) AS Active_Patients,
       ROUND(AVG(e.Final_Queue_Score), 2) AS Avg_ESI,
       MIN(e.Final_Queue_Score) AS Most_Critical_ESI
FROM Doctor d
JOIN Department dep ON dep.Department_ID = d.Department_ID
LEFT JOIN Wait_List w ON w.Doctor_ID = d.Doctor_ID
LEFT JOIN Encounter_Triage_Event e ON e.Encounter_ID = w.Encounter_ID
WHERE d.Is_Deleted = 0
GROUP BY d.Doctor_ID, d.Name, d.`Role`, d.Current_Status, dep.Name;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_open_alerts AS
SELECT a.Alert_ID, a.Alert_Type, a.Doctor_ID, d.Name AS Doctor_Name,
       a.Department_ID, dep.Name AS Department_Name,
       a.Message, a.Created_At
FROM Alert a
LEFT JOIN Doctor d ON d.Doctor_ID = a.Doctor_ID
LEFT JOIN Department dep ON dep.Department_ID = a.Department_ID
WHERE a.Is_Resolved = 0;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_all_alerts AS
SELECT a.Alert_ID, a.Alert_Type, a.Doctor_ID, d.Name AS Doctor_Name,
       a.Department_ID, dep.Name AS Department_Name,
       a.Message, a.Created_At, a.Is_Resolved
FROM Alert a
LEFT JOIN Doctor d ON d.Doctor_ID = a.Doctor_ID
LEFT JOIN Department dep ON dep.Department_ID = a.Department_ID;

-- Last four digits only. Roles that must not see the full number use this.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_phone_masked AS
SELECT Patient_ID,
       Name,
       CONCAT('XXXXXX', RIGHT(Phone, 4)) AS Phone_Masked
FROM Patient
WHERE Is_Deleted = 0;

-- Reception desk. Demographics only.
-- Status tells the receptionist where a patient is right now: inside the
-- hospital (In queue), seen before (Discharged) or only registered.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_patient_directory AS
SELECT p.Patient_ID, p.Name, p.Phone, p.Email, p.Date_of_Birth,
       TIMESTAMPDIFF(YEAR, p.Date_of_Birth, CURDATE()) AS Age,
       CASE
         WHEN EXISTS (SELECT 1 FROM Encounter_Triage_Event e
                      WHERE e.Patient_ID = p.Patient_ID AND e.Check_out_Time IS NULL) THEN 'In queue'
         WHEN EXISTS (SELECT 1 FROM Encounter_Triage_Event e
                      WHERE e.Patient_ID = p.Patient_ID) THEN 'Discharged'
         ELSE 'Registered'
       END AS Status,
       (SELECT COUNT(*) FROM Encounter_Triage_Event e WHERE e.Patient_ID = p.Patient_ID) AS Visits
FROM Patient p
WHERE p.Is_Deleted = 0;

-- Patients a nurse is allowed to check in: registered, not deleted, not already inside.
CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_patients_admittable AS
SELECT p.Patient_ID,
       p.Name,
       TIMESTAMPDIFF(YEAR, p.Date_of_Birth, CURDATE()) AS Age
FROM Patient p
WHERE p.Is_Deleted = 0
  AND NOT EXISTS (
    SELECT 1
    FROM Encounter_Triage_Event e
    WHERE e.Patient_ID = p.Patient_ID
      AND e.Check_out_Time IS NULL
  );

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_patients_admin AS
SELECT Patient_ID, Name, Phone, Email, Date_of_Birth
FROM Patient
WHERE Is_Deleted = 0;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_deleted_directory AS
SELECT 'Patient' AS Person_Type, Patient_ID AS Person_ID, Name, Phone, Deleted_At
FROM Patient
WHERE Is_Deleted = 1
UNION ALL
SELECT 'Doctor', Doctor_ID, Name, NULL, Deleted_At
FROM Doctor
WHERE Is_Deleted = 1;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_doctor_directory AS
SELECT d.Doctor_ID, d.Name AS Doctor_Name, d.`Role` AS Doctor_Role,
       d.Specialization, d.Current_Status,
       dep.Department_ID, dep.Name AS Department_Name
FROM Doctor d
JOIN Department dep ON dep.Department_ID = d.Department_ID
WHERE d.Is_Deleted = 0;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_roster AS
SELECT ds.Doctor_Shift_ID, ds.Shift_Date,
       s.Shift_ID, s.Shift_Name, s.Start_Time, s.End_Time,
       d.Doctor_ID, d.Name AS Doctor_Name, d.Current_Status,
       dep.Name AS Department_Name
FROM Doctor_Shift ds
JOIN Shift s ON s.Shift_ID = ds.Shift_ID
JOIN Doctor d ON d.Doctor_ID = ds.Doctor_ID AND d.Is_Deleted = 0
JOIN Department dep ON dep.Department_ID = d.Department_ID;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_departments AS
SELECT Department_ID, Name, Description FROM Department;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_shifts AS
SELECT Shift_ID, Shift_Name, Start_Time, End_Time FROM Shift;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_config AS
SELECT Config_Key, Config_Value FROM Config;

CREATE OR REPLACE SQL SECURITY DEFINER VIEW vw_aging_policy AS
SELECT ESI_Level, Max_Wait_Minutes FROM Aging_Policy;

SELECT '06_views.sql complete' AS status;
