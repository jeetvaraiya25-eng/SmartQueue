# SmartQueue relational schema

Database: `SmartQueue`. Engine: InnoDB. Character set: utf8mb4.

The seven Phase I relations are unchanged in meaning. Columns added for the new features are marked. Every table is in BCNF: each determinant is a candidate key. `Doctor.Specialization` is that doctor's own skill (two cardiologists can differ), so it does not depend on `Department_ID`.

## Relations

**Department** (`Department_ID`, Name, Description)  
Name is unique.

**Shift** (`Shift_ID`, Shift_Name, Start_Time, End_Time)  
A shift with `End_Time` earlier than `Start_Time` crosses midnight (Night, 23:00–07:00).

**Patient** (`Patient_ID`, Name, Phone, Email, Date_of_Birth, Is_Deleted, Deleted_At)  
`Is_Deleted` and `Deleted_At` are the soft-delete pair. `DELETE` is rejected.

**Doctor** (`Doctor_ID`, Name, Role, Specialization, Current_Status, Department_ID → Department, Is_Deleted, Deleted_At)  
`Role` is one of Junior Doctor, Resident, Consultant, Senior Consultant.  
`Current_Status` is Available, Busy or Off_Duty, and only the database may change it.

**Triage_Rule** (`Rule_ID`, Rule_Description, Danger_Indicator, ESI_Level)  
`Rule_ID` equals the ESI level it describes (1 most urgent, 5 least).

**Symptom_Department_Map** (`Map_ID`, Keyword, Department_ID → Department)  
Keyword is unique. The longest keyword found inside the complaint wins.

**Encounter_Triage_Event** (`Encounter_ID`, Patient_ID → Patient, Doctor_ID → Doctor, Department_ID → Department, Rule_ID → Triage_Rule, Arrival_Time, Check_out_Time, Initial_Symptoms, Final_Queue_Score)  
`Department_ID` is the department actually handling the case (the assigned doctor's department). An active visit has `Check_out_Time` NULL. `Final_Queue_Score` is the ESI level.

**Vitals_Log** (`Log_ID`, Encounter_ID → Encounter, Log_Timestamp, Type_Name, Heart_Rate, SpO2, Systolic_BP, Diastolic_BP, Temperature, Pain_Scale)  
`Type_Name` is Initial or Reassessment. Diastolic must be lower than systolic. Temperature is 30–45 °C.

**Wait_List** (`Queue_ID`, Encounter_ID UNIQUE → Encounter, Doctor_ID → Doctor, Queue_Position, Assigned_Time, Est_Wait_Time)  
One live queue row per active encounter. Position 1 is next. `Est_Wait_Time` is minutes.

**Score_History** (`History_ID`, Encounter_ID → Encounter, Old_Score, New_Score, History_At, History_Notes)  
The clinical priority ledger. Separate from the generic audit log.

**Doctor_Shift** (`Doctor_Shift_ID`, Doctor_ID → Doctor, Shift_ID → Shift, Shift_Date)  
Unique (`Doctor_ID`, `Shift_Date`, `Shift_ID`). A second trigger rejects a different shift that overlaps in time, including across midnight.

**Aging_Policy** (`ESI_Level`, Max_Wait_Minutes)  
ESI 2 → 30, ESI 3 → 60, ESI 4 → 90, ESI 5 → 120. There is no row for ESI 1.

**Config** (`Config_Key`, Config_Value)  
`doctor_queue_threshold` (5), `dept_critical_threshold` (3), `default_consult_minutes` (15), `audit_archive_days` (90).

**Alert** (`Alert_ID`, Alert_Type, Doctor_ID → Doctor, Department_ID → Department, Message, Created_At, Is_Resolved)  
Types: `DOCTOR_OVERLOAD`, `DEPT_CRITICAL`.

**Audit_Log** (`Audit_ID`, Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At)  
`Old_Data` and `New_Data` are JSON. This table is not audited (that would recurse).

**Audit_Log_Archive** — same columns. Rows older than `audit_archive_days` are moved here once a month.

## How a visit is stored

1. `fn_calc_esi` reads the vital signs and returns 1–5.
2. `fn_pick_department` matches the complaint to a department.
3. `fn_pick_doctor` chooses an on-duty doctor: shortest queue, lowest `Doctor_ID` on a tie. ESI 1 prefers a Consultant or Senior Consultant. If the department has nobody on duty, Emergency Medicine is the fallback.
4. The encounter insert trigger writes `Score_History`, inserts `Wait_List`, and calls `sp_rebuild_queue`.
5. `sp_rebuild_queue` sets `Queue_Position` with `ROW_NUMBER() OVER (ORDER BY ESI, Arrival_Time)` and `Est_Wait_Time` with `fn_estimate_wait`.

## Assumptions

- One active encounter per patient.
- "Raise the score one level" means the ESI number goes down by one (more urgent), and it never goes below 1. One run of `sp_age_queue` moves a patient only one level.
- Wait for aging is measured from `Arrival_Time`.
- If a doctor has no discharged visits, the consultation estimate is `default_consult_minutes` (15).
- A doctor whose shift has ended is `Off_Duty` even if patients are still in that queue. Those patients stay assigned; new patients are not sent there.
- Operational views hide soft-deleted people. `vw_deleted_directory` lists only deleted rows so they can be restored. `Audit_Log` keeps the history either way.
- The handling department stored on the encounter is the assigned doctor's department, which may be Emergency Medicine when the symptom department has nobody on duty.
- Back-to-back shifts (one ends as the next starts) are allowed. Overlapping times are not.
