# Feature map (F1–F15)

Each feature is enforced in MySQL. The Node server only calls a procedure or selects a view.

| Feature | DBMS concept | Where it lives |
|---|---|---|
| F1 Departments | Table, foreign key | `sql/01_schema.sql` — `Department`, `Doctor.Department_ID`, `Encounter_Triage_Event.Department_ID`. Seed in `02_seed_data.sql`. |
| F2 Roster and shifts | Table, UNIQUE, function, procedure, trigger | `Shift`, `Doctor_Shift` unique `(Doctor_ID, Shift_Date, Shift_ID)`. `fn_is_on_duty` in `03_functions.sql`. `sp_assign_shift` in `04_procedures.sql`. Overlap rejected by `trg_doctor_shift_bi` / `trg_doctor_shift_bu` in `05_triggers.sql`. `fn_pick_doctor` refuses an off-duty doctor. |
| F3 Estimated wait | Function, used by a procedure | `fn_estimate_wait` in `03_functions.sql`. `sp_rebuild_queue` in `04_procedures.sql` writes `(position − 1) ×` that average. Default 15 minutes comes from `Config`. |
| F4 Assignment by speciality | Table, two functions, procedure | `Symptom_Department_Map`. `fn_pick_department`, `fn_pick_doctor`. `sp_admit_patient` calls both. ESI 1 prefers Consultant / Senior Consultant, then Emergency Medicine. |
| F5 Aging | Table, procedure, event | `Aging_Policy`. `sp_age_queue` raises ESI one level and sets the history note through `@sq_score_note`, which `trg_encounter_au` writes into `Score_History`. `evt_age_queue` in `07_events.sql` runs it every minute. |
| F6 Doctor status | ENUM, procedure, triggers | `Doctor.Current_Status`. `sp_apply_doctor_status`. Wait-list triggers pass a count taken in the BEFORE trigger. `trg_doctor_bu_status` rejects a direct update unless `@sq_allow_status` is set. `evt_refresh_doctor_status` every 5 minutes. |
| F7 Overload alert | Table, trigger, procedure, event | `Alert`, `Config`. `trg_waitlist_ai` inserts `DOCTOR_OVERLOAD` or `DEPT_CRITICAL` and skips a duplicate open alert. `sp_resolve_alert`, `sp_auto_resolve_alerts`, `evt_auto_resolve_alerts`. |
| F8 Audit | Table, JSON, AFTER triggers | `Audit_Log`. `trg_audit_*` in `05_triggers.sql` on every table except `Audit_Log` (a trigger there would recurse). `Changed_By` is `CURRENT_USER()`. `Score_History` remains the clinical ledger. |
| F9 Soft delete | Columns, BEFORE DELETE trigger, procedures | `Is_Deleted`, `Deleted_At` on `Patient` and `Doctor`. `trg_patient_bd`, `trg_doctor_bd`. `sp_soft_delete_*`, `sp_restore_*`. Views in `06_views.sql` omit deleted rows. `vw_deleted_directory` lists them for restore. |
| F10 Reports and dashboard | Views, procedures, GROUP BY, HAVING, subquery, window | `vw_department_load`, `vw_wait_by_esi`, `vw_busiest_hours`, `vw_doctor_workload`. `sp_daily_report`, `sp_weekly_report`, `sp_doctor_report`. |
| F11 Scheduler | Events | `07_events.sql`: age every minute, status every 5 minutes, auto-resolve alerts every minute, archive audit monthly (`sp_archive_audit_log`). |
| F12 Deadlocks | Transaction, `SELECT … FOR UPDATE`, handler | `sp_admit_patient`, `sp_reassess_patient`, `sp_discharge_patient` lock the patient, then doctors in `Doctor_ID` order, then the encounter, and roll back on any error. `sp_*_safe` catches 1213 and 1205 and retries three times. `demo/concurrent_admit.js`. |
| F13 Indexes | Secondary indexes, EXPLAIN | `08_indexes.sql`. EXPLAIN of the queue lookup, the discharged-visit lookup and the vitals lookup is printed before and after the indexes are created. |
| F14 Roles | Roles, grants, column privileges, view | `09_roles.sql`. `receptionist_role`, `nurse_role`, `doctor_role`, `admin_role`, `auditor_role`. Nurse has `SELECT (Patient_ID, Name)` on `Patient` and reads `vw_phone_masked` (last four digits). Doctor has `vw_doctor_clinical` only. Procedures are `SQL SECURITY DEFINER`. |
| F15 Full text | FULLTEXT index, procedure | `ft_symptoms` in `08_indexes.sql`. `sp_search_similar_cases` uses `MATCH … AGAINST` in natural language mode. |

## Phase III objects that are still here

| Object | File |
|---|---|
| `fn_calc_esi` | `03_functions.sql` |
| `sp_rebuild_queue` | `04_procedures.sql` |
| `sp_admit_patient`, `sp_reassess_patient`, `sp_discharge_patient` | `04_procedures.sql` |
| Vitals validation, rescore, encounter audit/queue, delete guard | `05_triggers.sql` (`trg_vitals_*`, `trg_encounter_*`) |
| `vw_live_queue`, `vw_doctor_clinical`, `vw_admin_summary`, `vw_score_audit` | `06_views.sql` |

The safe wrappers (`sp_admit_patient_safe` and the two siblings) are what the website calls. They add the retry. The inner procedures still do the work.
