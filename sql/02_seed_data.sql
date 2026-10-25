-- =============================================================================
-- 02_seed_data.sql
-- Loaded BEFORE functions, procedures and triggers, so these rows are the
-- starting picture and are not re-processed by the admit triggers.
-- Arrival times are relative to NOW() so the board looks live on the day
-- the script is run. Waits sit under the aging limits, except none: every
-- active patient is still inside Aging_Policy so the board stays still
-- until the examiner runs aging on purpose.
--
-- Phase II named 8 patients and 4 doctors. Those people are patients 1–8
-- and doctors 1–4. Vitals are chosen so fn_calc_esi reproduces the ESI
-- already stored on the encounter (the Phase II worklist, not the one
-- Q16 pain figure that disagreed with Priya Nair's ESI 3).
-- =============================================================================

USE SmartQueue;

INSERT INTO Department (Department_ID, Name, Description) VALUES
  (1, 'Emergency Medicine', 'Resuscitation and undifferentiated emergency care'),
  (2, 'Cardiology',         'Chest pain, rhythm problems and cardiac emergencies'),
  (3, 'Orthopedics',        'Fractures, sprains and musculoskeletal trauma'),
  (4, 'General Medicine',   'Fever, asthma, headache and other medical illness'),
  (5, 'Pediatrics',         'Illness and injury in children');

INSERT INTO Shift (Shift_ID, Shift_Name, Start_Time, End_Time) VALUES
  (1, 'Morning', '07:00:00', '15:00:00'),
  (2, 'Evening', '15:00:00', '23:00:00'),
  (3, 'Night',   '23:00:00', '07:00:00');  -- crosses midnight

INSERT INTO Triage_Rule (Rule_ID, Rule_Description, Danger_Indicator, ESI_Level) VALUES
  (1, 'Life-threatening instability',
      'SpO2 < 90, or systolic BP < 80, or heart rate > 150 or < 40', 1),
  (2, 'High risk, potentially unstable',
      'SpO2 90-93, or heart rate 120-150, or pain >= 8', 2),
  (3, 'Stable, needs multiple resources',
      'Temperature >= 39.0, or pain 5-7', 3),
  (4, 'Stable, needs one resource',
      'Pain 3-4 with otherwise normal vitals', 4),
  (5, 'Non-urgent',
      'All vitals normal and pain <= 2', 5);

INSERT INTO Aging_Policy (ESI_Level, Max_Wait_Minutes) VALUES
  (2, 30),
  (3, 60),
  (4, 90),
  (5, 120);

INSERT INTO Config (Config_Key, Config_Value) VALUES
  ('doctor_queue_threshold',   '5'),
  ('dept_critical_threshold',  '3'),
  ('default_consult_minutes',  '15'),
  ('audit_archive_days',       '90');

-- Longest keyword wins. "chest pain" beats a shorter fragment if both match.
INSERT INTO Symptom_Department_Map (Keyword, Department_ID) VALUES
  ('chest pain',        2),
  ('chest tightness',   2),
  ('palpitations',      2),
  ('heart',             2),
  ('fracture',          3),
  ('sprain',            3),
  ('dislocation',       3),
  ('ankle',             3),
  ('asthma',            4),
  ('fever',             4),
  ('cough',             4),
  ('headache',          4),
  ('migraine',          4),
  ('sore throat',       4),
  ('pediatric',         5),
  ('infant',            5),
  ('child',             5),
  ('breathlessness',    1),
  ('bleeding',          1),
  ('unconscious',       1),
  ('seizure',           1),
  ('trauma',            1),
  ('hypoxia',           1);

-- Role is the seniority used by ESI-1 assignment.
-- Each shift has exactly one Emergency Medicine consultant so a fallback
-- doctor exists at every hour.
INSERT INTO Doctor
  (Doctor_ID, Name, `Role`, Specialization, Current_Status, Department_ID) VALUES
  (1, 'Dr. Meera Kapoor',   'Senior Consultant', 'Trauma and Resuscitation', 'Off_Duty', 1),
  (2, 'Dr. Sameer Patil',   'Consultant',        'Interventional Cardiology', 'Off_Duty', 2),
  (3, 'Dr. Anjali Sharma',  'Consultant',        'Internal Medicine',         'Off_Duty', 4),
  (4, 'Dr. Rahul Verma',    'Consultant',        'Orthopedic Trauma',         'Off_Duty', 3),
  (5, 'Dr. Neha Kulkarni',  'Consultant',        'Emergency Medicine',        'Off_Duty', 1),
  (6, 'Dr. Arvind Rao',     'Resident',          'Pediatric Emergency',       'Off_Duty', 5),
  (7, 'Dr. Pooja Shah',     'Senior Consultant', 'Clinical Cardiology',       'Off_Duty', 2),
  (8, 'Dr. Kabir Menon',    'Consultant',        'Acute Care',                'Off_Duty', 1);

-- Morning: Meera (EM), Sameer (Cardio), Arvind (Peds)
-- Evening: Anjali (GM), Rahul (Ortho), Kabir (EM)
-- Night:   Neha (EM), Pooja (Cardio)
INSERT INTO Doctor_Shift (Doctor_ID, Shift_ID, Shift_Date)
SELECT roster.Doctor_ID, roster.Shift_ID, DATE_ADD(CURDATE(), INTERVAL d.n DAY)
FROM (
  SELECT 1 AS Doctor_ID, 1 AS Shift_ID UNION ALL
  SELECT 2, 1 UNION ALL
  SELECT 6, 1 UNION ALL
  SELECT 3, 2 UNION ALL
  SELECT 4, 2 UNION ALL
  SELECT 8, 2 UNION ALL
  SELECT 5, 3 UNION ALL
  SELECT 7, 3
) AS roster
CROSS JOIN (
  SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL
  SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
) AS d;

INSERT INTO Patient (Patient_ID, Name, Phone, Email, Date_of_Birth) VALUES
  (1,  'Rohan Mehta',      '9811111001', 'rohan.mehta@example.com',    '1992-04-12'),
  (2,  'Priya Nair',       '9811111002', 'priya.nair@example.com',     '1998-11-03'),
  (3,  'Arjun Deshmukh',   '9811111003', 'arjun.deshmukh@example.com', '1985-01-19'),
  (4,  'Sneha Kulkarni',   '9811111004', 'sneha.kulkarni@example.com', '2001-07-22'),
  (5,  'Imran Shaikh',     '9811111005', 'imran.shaikh@example.com',   '1976-09-30'),
  (6,  'Kavya Iyer',       '9811111006', 'kavya.iyer@example.com',     '1995-02-14'),
  (7,  'Vikram Joshi',     '9811111007', 'vikram.joshi@example.com',   '1988-12-05'),
  (8,  'Ananya Rao',       '9811111008', 'ananya.rao@example.com',     '2000-06-18'),
  (9,  'Dev Sharma',       '9811111009', 'dev.sharma@example.com',     '1991-03-09'),
  (10, 'Meera Iyer',       '9811111010', 'meera.iyer@example.com',     '1982-08-27'),
  (11, 'Farhan Qureshi',   '9811111011', 'farhan.qureshi@example.com', '1999-10-11'),
  (12, 'Lakshmi Nair',     '9811111012', 'lakshmi.nair@example.com',   '1979-05-02'),
  (13, 'Aditi Bose',       '9811111013', 'aditi.bose@example.com',     '2003-01-25'),
  (14, 'Rohit Pawar',      '9811111014', 'rohit.pawar@example.com',    '1994-07-07'),
  (15, 'Sara D Souza',     '9811111015', 'sara.dsouza@example.com',    '2016-09-15');

-- Active visits are today and still inside the aging limits.
-- Priya arrived before Sneha but sits behind her: ESI 3 vs ESI 2.
-- Five discharged visits give each of the original doctors, plus the night
-- EM doctor, a real average consultation time.
INSERT INTO Encounter_Triage_Event
  (Encounter_ID, Patient_ID, Doctor_ID, Department_ID, Rule_ID,
   Arrival_Time, Check_out_Time, Initial_Symptoms, Final_Queue_Score) VALUES
  (1,  1,  2, 2, 1, DATE_SUB(NOW(), INTERVAL 14 MINUTE), NULL,
      'Severe chest pain with sweating and nausea', 1),
  (2,  2,  3, 4, 3, DATE_SUB(NOW(), INTERVAL 25 MINUTE), NULL,
      'High fever, body ache and headache', 3),
  (3,  3,  4, 3, 4, DATE_SUB(NOW(), INTERVAL 16 MINUTE), NULL,
      'Suspected wrist fracture after a fall', 4),
  (4,  4,  3, 4, 2, DATE_SUB(NOW(), INTERVAL 8 MINUTE), NULL,
      'Severe migraine and vomiting', 2),
  (5,  5,  3, 4, 5, DATE_SUB(NOW(), INTERVAL 80 MINUTE), NULL,
      'Mild cough and sore throat', 5),
  (6,  6,  1, 1, 2, DATE_SUB(NOW(), INTERVAL 11 MINUTE), NULL,
      'Breathlessness and hypoxia', 2),
  (7,  7,  2, 2, 2, DATE_SUB(NOW(), INTERVAL 7 MINUTE), NULL,
      'Chest tightness and rising pain', 2),
  (8,  8,  1, 1, 5,
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '08:10:00'),
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '08:28:00'),
      'Mild headache, now resolved', 5),
  (9,  9,  2, 2, 3,
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 2 DAY), '09:00:00'),
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 2 DAY), '09:22:00'),
      'Palpitations that settled after rest', 3),
  (10, 10, 3, 4, 4,
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 3 DAY), '11:15:00'),
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 3 DAY), '11:31:00'),
      'Sore throat and mild fever', 4),
  (11, 11, 4, 3, 4,
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 4 DAY), '14:05:00'),
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 4 DAY), '14:25:00'),
      'Ankle sprain while playing', 4),
  (12, 12, 5, 1, 2,
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 5 DAY), '23:40:00'),
      TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 5 DAY), '23:40:00') + INTERVAL 28 MINUTE,
      'Night asthma attack with breathlessness', 2);

INSERT INTO Vitals_Log
  (Log_ID, Encounter_ID, Log_Timestamp, Type_Name,
   Heart_Rate, SpO2, Systolic_BP, Diastolic_BP, Temperature, Pain_Scale) VALUES
  -- Active, one reading each except Vikram (initial ESI 3, then ESI 2)
  (1,  1, DATE_SUB(NOW(), INTERVAL 13 MINUTE), 'Initial',       132, 88, 84,  52, 37.2, 9),
  (2,  2, DATE_SUB(NOW(), INTERVAL 24 MINUTE), 'Initial',       108, 97, 118, 76, 37.4, 6),
  (3,  3, DATE_SUB(NOW(), INTERVAL 15 MINUTE), 'Initial',        78, 99, 124, 80, 36.8, 4),
  (4,  4, DATE_SUB(NOW(), INTERVAL 7 MINUTE),  'Initial',       118, 96, 130, 84, 37.0, 8),
  (5,  5, DATE_SUB(NOW(), INTERVAL 79 MINUTE), 'Initial',        74, 99, 120, 78, 36.6, 1),
  (6,  6, DATE_SUB(NOW(), INTERVAL 10 MINUTE), 'Initial',       128, 92, 100, 66, 37.1, 2),
  (7,  7, DATE_SUB(NOW(), INTERVAL 6 MINUTE),  'Initial',       104, 97, 128, 82, 37.0, 5),
  (8,  7, DATE_SUB(NOW(), INTERVAL 2 MINUTE),  'Reassessment',  126, 94, 122, 78, 37.2, 7),
  -- Discharged
  (9,  8, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '08:12:00'), 'Initial', 72, 99, 116, 74, 36.6, 2),
  (10, 9, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 2 DAY), '09:02:00'), 'Initial', 110, 98, 138, 86, 36.9, 6),
  (11, 10, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 3 DAY), '11:16:00'), 'Initial', 88, 98, 126, 80, 37.8, 3),
  (12, 11, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 4 DAY), '14:06:00'), 'Initial', 90, 99, 130, 84, 36.7, 4),
  (13, 12, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 5 DAY), '23:42:00'), 'Initial', 124, 93, 128, 82, 37.0, 4);

-- Positions follow ESI, then arrival. Est_Wait_Time is filled by
-- sp_rebuild_queue at the end of 04_procedures.sql.
INSERT INTO Wait_List
  (Queue_ID, Encounter_ID, Doctor_ID, Queue_Position, Assigned_Time, Est_Wait_Time) VALUES
  (1, 1, 2, 1, DATE_SUB(NOW(), INTERVAL 14 MINUTE), 0),
  (2, 7, 2, 2, DATE_SUB(NOW(), INTERVAL 7 MINUTE), 0),
  (3, 4, 3, 1, DATE_SUB(NOW(), INTERVAL 8 MINUTE), 0),
  (4, 2, 3, 2, DATE_SUB(NOW(), INTERVAL 25 MINUTE), 0),
  (5, 5, 3, 3, DATE_SUB(NOW(), INTERVAL 80 MINUTE), 0),
  (6, 6, 1, 1, DATE_SUB(NOW(), INTERVAL 11 MINUTE), 0),
  (7, 3, 4, 1, DATE_SUB(NOW(), INTERVAL 16 MINUTE), 0);

INSERT INTO Score_History
  (History_ID, Encounter_ID, Old_Score, New_Score, History_At, History_Notes) VALUES
  (1,  1, NULL, 1, DATE_SUB(NOW(), INTERVAL 13 MINUTE), 'Initial triage score'),
  (2,  2, NULL, 3, DATE_SUB(NOW(), INTERVAL 24 MINUTE), 'Initial triage score'),
  (3,  3, NULL, 4, DATE_SUB(NOW(), INTERVAL 15 MINUTE), 'Initial triage score'),
  (4,  4, NULL, 2, DATE_SUB(NOW(), INTERVAL 7 MINUTE),  'Initial triage score'),
  (5,  5, NULL, 5, DATE_SUB(NOW(), INTERVAL 79 MINUTE), 'Initial triage score'),
  (6,  6, NULL, 2, DATE_SUB(NOW(), INTERVAL 10 MINUTE), 'Initial triage score'),
  (7,  7, NULL, 3, DATE_SUB(NOW(), INTERVAL 6 MINUTE),  'Initial triage score'),
  (8,  7, 3,    2, DATE_SUB(NOW(), INTERVAL 2 MINUTE),  'Auto-rescored from new vital signs'),
  (9,  8, NULL, 5, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 1 DAY), '08:12:00'), 'Initial triage score'),
  (10, 9, NULL, 3, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 2 DAY), '09:02:00'), 'Initial triage score'),
  (11, 10, NULL, 4, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 3 DAY), '11:16:00'), 'Initial triage score'),
  (12, 11, NULL, 4, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 4 DAY), '14:06:00'), 'Initial triage score'),
  (13, 12, NULL, 2, TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 5 DAY), '23:42:00'), 'Initial triage score');

-- Keep AUTO_INCREMENT ahead of the explicit ids.
ALTER TABLE Department              AUTO_INCREMENT = 6;
ALTER TABLE Shift                   AUTO_INCREMENT = 4;
ALTER TABLE Triage_Rule             AUTO_INCREMENT = 6;
ALTER TABLE Doctor                  AUTO_INCREMENT = 9;
ALTER TABLE Patient                 AUTO_INCREMENT = 16;
ALTER TABLE Encounter_Triage_Event  AUTO_INCREMENT = 13;
ALTER TABLE Vitals_Log              AUTO_INCREMENT = 14;
ALTER TABLE Wait_List               AUTO_INCREMENT = 8;
ALTER TABLE Score_History           AUTO_INCREMENT = 14;

SELECT '02_seed_data.sql complete' AS status,
       (SELECT COUNT(*) FROM Patient)    AS patients,
       (SELECT COUNT(*) FROM Doctor)     AS doctors,
       (SELECT COUNT(*) FROM Encounter_Triage_Event) AS encounters,
       (SELECT COUNT(*) FROM Doctor_Shift) AS roster_rows;
