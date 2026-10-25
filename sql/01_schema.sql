-- =============================================================================
-- SmartQueue – Hospital Emergency Management System
-- 01_schema.sql
-- Group 15 (Tanay Soni, Aditya D. Trivedi, Jeet Varaiya)
--
-- Run first, as MySQL root. Drops and recreates the SmartQueue database.
-- Engine: MySQL 8.0, InnoDB, utf8mb4.
--
-- The seven Phase I relations are kept and extended. New relations cover
-- departments, shifts, symptom routing, aging policy, alerts, configuration
-- and a generic audit log. Every table is in BCNF: every determinant is a
-- candidate key. Doctor.Specialization is a doctor-specific skill, not a
-- copy of the department name, so it does not depend on Department_ID.
--
-- Secondary indexes for the workload queries are created later, in
-- 08_indexes.sql, so EXPLAIN can be shown before and after.
-- =============================================================================

DROP DATABASE IF EXISTS SmartQueue;
CREATE DATABASE SmartQueue
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE SmartQueue;

-- -----------------------------------------------------------------------------
-- Reference data
-- -----------------------------------------------------------------------------

CREATE TABLE Department (
  Department_ID   INT          NOT NULL AUTO_INCREMENT,
  Name            VARCHAR(80)  NOT NULL,
  Description     VARCHAR(255) NULL,
  PRIMARY KEY (Department_ID),
  UNIQUE KEY uq_department_name (Name)
) ENGINE=InnoDB;

CREATE TABLE Shift (
  Shift_ID    INT         NOT NULL AUTO_INCREMENT,
  Shift_Name  VARCHAR(40) NOT NULL,
  Start_Time  TIME        NOT NULL,
  End_Time    TIME        NOT NULL,
  PRIMARY KEY (Shift_ID),
  UNIQUE KEY uq_shift_name (Shift_Name)
) ENGINE=InnoDB;

CREATE TABLE Triage_Rule (
  Rule_ID           INT          NOT NULL AUTO_INCREMENT,
  Rule_Description  VARCHAR(255) NOT NULL,
  Danger_Indicator  VARCHAR(255) NOT NULL,
  ESI_Level         TINYINT      NOT NULL,
  PRIMARY KEY (Rule_ID),
  UNIQUE KEY uq_triage_esi (ESI_Level),
  CONSTRAINT chk_triage_esi CHECK (ESI_Level BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- How long a waiting patient at each ESI level may wait before the score
-- is raised one level. ESI 1 is omitted: there is no level above it.
CREATE TABLE Aging_Policy (
  ESI_Level         TINYINT NOT NULL,
  Max_Wait_Minutes  INT     NOT NULL,
  PRIMARY KEY (ESI_Level),
  CONSTRAINT chk_aging_esi CHECK (ESI_Level BETWEEN 2 AND 5),
  CONSTRAINT chk_aging_wait CHECK (Max_Wait_Minutes >= 0)
) ENGINE=InnoDB;

-- Runtime thresholds. Changed through sp_set_config, never by the website.
CREATE TABLE Config (
  Config_Key    VARCHAR(64)  NOT NULL,
  Config_Value  VARCHAR(255) NOT NULL,
  PRIMARY KEY (Config_Key)
) ENGINE=InnoDB;

-- Keyword → department. Longest matching keyword wins (see fn_pick_department).
CREATE TABLE Symptom_Department_Map (
  Map_ID         INT          NOT NULL AUTO_INCREMENT,
  Keyword        VARCHAR(80)  NOT NULL,
  Department_ID  INT          NOT NULL,
  PRIMARY KEY (Map_ID),
  UNIQUE KEY uq_symptom_keyword (Keyword),
  CONSTRAINT fk_symptom_department
    FOREIGN KEY (Department_ID) REFERENCES Department (Department_ID)
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- People. Deletes are soft: Is_Deleted / Deleted_At. A BEFORE DELETE trigger
-- rejects DELETE. Specialization is per doctor (BCNF), Department_ID is the
-- unit they belong to.
-- -----------------------------------------------------------------------------

CREATE TABLE Patient (
  Patient_ID     INT          NOT NULL AUTO_INCREMENT,
  Name           VARCHAR(100) NOT NULL,
  Phone          VARCHAR(15)  NOT NULL,
  Email          VARCHAR(120) NULL,
  Date_of_Birth  DATE         NOT NULL,
  Is_Deleted     TINYINT      NOT NULL DEFAULT 0,
  Deleted_At     DATETIME     NULL,
  PRIMARY KEY (Patient_ID),
  CONSTRAINT chk_patient_deleted CHECK (Is_Deleted IN (0, 1))
) ENGINE=InnoDB;

CREATE TABLE Doctor (
  Doctor_ID       INT          NOT NULL AUTO_INCREMENT,
  Name            VARCHAR(100) NOT NULL,
  `Role`          VARCHAR(40)  NOT NULL,
  Specialization  VARCHAR(80)  NOT NULL,
  Current_Status  ENUM('Available', 'Busy', 'Off_Duty') NOT NULL DEFAULT 'Off_Duty',
  Department_ID   INT          NOT NULL,
  Is_Deleted      TINYINT      NOT NULL DEFAULT 0,
  Deleted_At      DATETIME     NULL,
  PRIMARY KEY (Doctor_ID),
  CONSTRAINT fk_doctor_department
    FOREIGN KEY (Department_ID) REFERENCES Department (Department_ID),
  CONSTRAINT chk_doctor_role CHECK (`Role` IN (
    'Junior Doctor', 'Resident', 'Consultant', 'Senior Consultant'
  )),
  CONSTRAINT chk_doctor_deleted CHECK (Is_Deleted IN (0, 1))
) ENGINE=InnoDB;

-- One row per doctor per shift per date. Overlap across different shifts
-- is rejected by trg_doctor_shift_bi / bu (a unique key cannot express it).
CREATE TABLE Doctor_Shift (
  Doctor_Shift_ID  INT  NOT NULL AUTO_INCREMENT,
  Doctor_ID        INT  NOT NULL,
  Shift_ID         INT  NOT NULL,
  Shift_Date       DATE NOT NULL,
  PRIMARY KEY (Doctor_Shift_ID),
  UNIQUE KEY uq_doctor_shift (Doctor_ID, Shift_Date, Shift_ID),
  CONSTRAINT fk_docshift_doctor
    FOREIGN KEY (Doctor_ID) REFERENCES Doctor (Doctor_ID),
  CONSTRAINT fk_docshift_shift
    FOREIGN KEY (Shift_ID) REFERENCES Shift (Shift_ID)
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- Clinical tables (Phase I, plus the department handling the case)
-- -----------------------------------------------------------------------------

CREATE TABLE Encounter_Triage_Event (
  Encounter_ID        INT           NOT NULL AUTO_INCREMENT,
  Patient_ID          INT           NOT NULL,
  Doctor_ID           INT           NOT NULL,
  Department_ID       INT           NOT NULL,
  Rule_ID             INT           NOT NULL,
  Arrival_Time        DATETIME      NOT NULL,
  Check_out_Time      DATETIME      NULL,
  Initial_Symptoms    VARCHAR(500)  NOT NULL,
  Final_Queue_Score   TINYINT       NOT NULL,
  PRIMARY KEY (Encounter_ID),
  CONSTRAINT fk_enc_patient
    FOREIGN KEY (Patient_ID) REFERENCES Patient (Patient_ID),
  CONSTRAINT fk_enc_doctor
    FOREIGN KEY (Doctor_ID) REFERENCES Doctor (Doctor_ID),
  CONSTRAINT fk_enc_department
    FOREIGN KEY (Department_ID) REFERENCES Department (Department_ID),
  CONSTRAINT fk_enc_rule
    FOREIGN KEY (Rule_ID) REFERENCES Triage_Rule (Rule_ID),
  CONSTRAINT chk_enc_esi CHECK (Final_Queue_Score BETWEEN 1 AND 5),
  CONSTRAINT chk_enc_checkout CHECK (
    Check_out_Time IS NULL OR Check_out_Time >= Arrival_Time
  )
) ENGINE=InnoDB;

CREATE TABLE Vitals_Log (
  Log_ID         INT           NOT NULL AUTO_INCREMENT,
  Encounter_ID   INT           NOT NULL,
  Log_Timestamp  DATETIME      NOT NULL,
  Type_Name      ENUM('Initial', 'Reassessment') NOT NULL,
  Heart_Rate     SMALLINT      NOT NULL,
  SpO2           TINYINT       NOT NULL,
  Systolic_BP    SMALLINT      NOT NULL,
  Diastolic_BP   SMALLINT      NOT NULL,
  Temperature    DECIMAL(4,1)  NOT NULL,
  Pain_Scale     TINYINT       NOT NULL,
  PRIMARY KEY (Log_ID),
  CONSTRAINT fk_vitals_encounter
    FOREIGN KEY (Encounter_ID) REFERENCES Encounter_Triage_Event (Encounter_ID),
  CONSTRAINT chk_hr CHECK (Heart_Rate BETWEEN 20 AND 250),
  CONSTRAINT chk_spo2 CHECK (SpO2 BETWEEN 0 AND 100),
  CONSTRAINT chk_sbp CHECK (Systolic_BP BETWEEN 40 AND 250),
  CONSTRAINT chk_dbp CHECK (Diastolic_BP BETWEEN 20 AND 200),
  CONSTRAINT chk_bp_order CHECK (Diastolic_BP < Systolic_BP),
  CONSTRAINT chk_temp CHECK (Temperature BETWEEN 30.0 AND 45.0),
  CONSTRAINT chk_pain CHECK (Pain_Scale BETWEEN 0 AND 10)
) ENGINE=InnoDB;

CREATE TABLE Wait_List (
  Queue_ID        INT      NOT NULL AUTO_INCREMENT,
  Encounter_ID    INT      NOT NULL,
  Doctor_ID       INT      NOT NULL,
  Queue_Position  INT      NOT NULL,
  Assigned_Time   DATETIME NOT NULL,
  Est_Wait_Time   INT      NOT NULL DEFAULT 0,
  PRIMARY KEY (Queue_ID),
  UNIQUE KEY uq_wait_encounter (Encounter_ID),
  CONSTRAINT fk_wait_encounter
    FOREIGN KEY (Encounter_ID) REFERENCES Encounter_Triage_Event (Encounter_ID),
  CONSTRAINT fk_wait_doctor
    FOREIGN KEY (Doctor_ID) REFERENCES Doctor (Doctor_ID),
  CONSTRAINT chk_wait_pos CHECK (Queue_Position >= 1),
  CONSTRAINT chk_wait_est CHECK (Est_Wait_Time >= 0)
) ENGINE=InnoDB;

-- Clinical priority ledger (Phase III). Separate from the generic Audit_Log.
CREATE TABLE Score_History (
  History_ID     INT          NOT NULL AUTO_INCREMENT,
  Encounter_ID   INT          NOT NULL,
  Old_Score      TINYINT      NULL,
  New_Score      TINYINT      NOT NULL,
  History_At     DATETIME     NOT NULL,
  History_Notes  VARCHAR(255) NOT NULL,
  PRIMARY KEY (History_ID),
  CONSTRAINT fk_score_encounter
    FOREIGN KEY (Encounter_ID) REFERENCES Encounter_Triage_Event (Encounter_ID),
  CONSTRAINT chk_score_new CHECK (New_Score BETWEEN 1 AND 5),
  CONSTRAINT chk_score_old CHECK (Old_Score IS NULL OR Old_Score BETWEEN 1 AND 5)
) ENGINE=InnoDB;

CREATE TABLE Alert (
  Alert_ID       INT          NOT NULL AUTO_INCREMENT,
  Alert_Type     VARCHAR(40)  NOT NULL,
  Doctor_ID      INT          NULL,
  Department_ID  INT          NULL,
  Message        VARCHAR(255) NOT NULL,
  Created_At     DATETIME     NOT NULL,
  Is_Resolved    TINYINT      NOT NULL DEFAULT 0,
  PRIMARY KEY (Alert_ID),
  CONSTRAINT fk_alert_doctor
    FOREIGN KEY (Doctor_ID) REFERENCES Doctor (Doctor_ID),
  CONSTRAINT fk_alert_department
    FOREIGN KEY (Department_ID) REFERENCES Department (Department_ID),
  CONSTRAINT chk_alert_type CHECK (Alert_Type IN ('DOCTOR_OVERLOAD', 'DEPT_CRITICAL')),
  CONSTRAINT chk_alert_resolved CHECK (Is_Resolved IN (0, 1))
) ENGINE=InnoDB;

-- Generic change log. No trigger writes back into this table, or a change
-- would audit itself forever. Audit_Log_Archive holds rows moved monthly.
CREATE TABLE Audit_Log (
  Audit_ID     BIGINT       NOT NULL AUTO_INCREMENT,
  Table_Name   VARCHAR(64)  NOT NULL,
  Record_ID    VARCHAR(64)  NOT NULL,
  Action       ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
  Old_Data     JSON         NULL,
  New_Data     JSON         NULL,
  Changed_By   VARCHAR(255) NOT NULL,
  Changed_At   DATETIME     NOT NULL,
  PRIMARY KEY (Audit_ID)
) ENGINE=InnoDB;

CREATE TABLE Audit_Log_Archive (
  Audit_ID     BIGINT       NOT NULL,
  Table_Name   VARCHAR(64)  NOT NULL,
  Record_ID    VARCHAR(64)  NOT NULL,
  Action       ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
  Old_Data     JSON         NULL,
  New_Data     JSON         NULL,
  Changed_By   VARCHAR(255) NOT NULL,
  Changed_At   DATETIME     NOT NULL,
  PRIMARY KEY (Audit_ID)
) ENGINE=InnoDB;

SELECT '01_schema.sql complete' AS status;
