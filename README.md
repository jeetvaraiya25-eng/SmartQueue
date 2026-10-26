# SmartQueue — Hospital Emergency Management System

Group 15, Sardar Patel Institute of Technology  
Tanay Soni (2025300250), Aditya D. Trivedi (2025300259), Jeet Varaiya (2025300266)

The emergency department runs inside MySQL 8. Scoring, queue order, doctor assignments, aging, alerts, audit and permissions are stored programs. The website is a thin client: it calls procedures, selects views, and draws the result.

The schema and the reasoning behind it are in [docs/SCHEMA.md](docs/SCHEMA.md). Which file implements F1–F15 is in [docs/FEATURE_MAP.md](docs/FEATURE_MAP.md).

## What you need

- MySQL 8.0 (Homebrew: `brew install mysql@8.0`)
- Node.js 18 or newer

Start MySQL and turn the scheduler on (the setup script also tries):

```sql
SET GLOBAL event_scheduler = ON;
```

If that is not allowed, add this under `[mysqld]` and restart:

```
event_scheduler=ON
```

## Load the database

From the project folder, as MySQL root:

```bash
chmod +x setup.sh
./setup.sh
```

If root needs a password or a TCP connection:

```bash
MYSQL_PWD=yourpassword MYSQL_HOST=127.0.0.1 ./setup.sh
```

The script runs, in order:

1. `sql/01_schema.sql` — tables, keys, checks
2. `sql/02_seed_data.sql` — departments, roster, 15 patients, 12 encounters
3. `sql/03_functions.sql`
4. `sql/04_procedures.sql` — also refreshes doctor status and estimated waits
5. `sql/05_triggers.sql`
6. `sql/06_views.sql`
7. `sql/07_events.sql`
8. `sql/08_indexes.sql` — prints EXPLAIN before and after three queries
9. `sql/09_roles.sql` — one MySQL user per role

`sql/10_tests.sql` is not part of setup. It changes the sample queue. Run it when you want the mark sheet, then run `RESET_DATA=1 ./setup.sh` before the demo. A plain `./setup.sh` leaves an existing database alone so patients registered on the live site are not erased.

```bash
mysql -u root < sql/10_tests.sql
```

Every row of `Test_Result` should be `PASS`.

## Start the website

```bash
cd server
npm install
npm start
```

Open [http://localhost:3000](http://localhost:3000).

Each button on the sign-in screen is a real MySQL account. The password is filled in for the demo.

| Role | MySQL user | Password | Can |
|---|---|---|---|
| Receptionist | `receptionist_user` | `Reception@123` | Register and search patients |
| Nurse | `nurse_user` | `Nurse@123` | Admit, reassess, discharge, live queue, alerts |
| Doctor | `doctor_user` | `Doctor@123` | Clinical queue and similar-case search. No phone or email |
| Admin | `admin_user` | `Admin@123` | Dashboard, reports, roster, soft delete, policies |
| Auditor | `auditor_user` | `Auditor@123` | `Audit_Log` and `vw_score_audit` only |

The same passwords work in the mysql client:

```bash
mysql -u nurse_user -p -h 127.0.0.1 --protocol=TCP SmartQueue
```

A nurse who runs `SELECT Phone FROM Patient` is rejected by MySQL. `SELECT Name FROM Patient` is allowed (column privilege). `SELECT Phone_Masked FROM vw_phone_masked` shows the last four digits.

## Live copy

The same code runs on an Azure for Students VM (Ubuntu 24.04, `Standard_B2ats_v2`, region `indiasouthcentral`, resource group `smartqueue-rg`), installed with `deploy/setup-vm.sh`:

[http://172.198.79.10/](http://172.198.79.10/)

To push a change there:

```bash
rsync -az --exclude node_modules --exclude _docs --exclude .git --exclude server/.env \
  ./ azureuser@172.198.79.10:~/smartqueue/
ssh azureuser@172.198.79.10 'sudo systemctl restart smartqueue'
```

That restart does not touch the database. `./setup.sh` on the server now refuses to wipe patients that are already there. Azure for Students removes idle compute after 90 days without a sign-in, so open the Azure portal once in a while. The VM clock is set to `Asia/Kolkata` so `NOW()` matches the clinic's wall clock.

## Seed, in short

Five departments: Emergency Medicine, Cardiology, Orthopedics, General Medicine, Pediatrics.

Three shifts: Morning 07:00–15:00, Evening 15:00–23:00, Night 23:00–07:00. Eight doctors are rostered for the next seven days. Each shift has one Emergency Medicine consultant, so a new patient can be placed at any hour.

| Shift | On duty |
|---|---|
| Morning | Dr. Meera Kapoor (EM, Senior Consultant), Dr. Sameer Patil (Cardiology), Dr. Arvind Rao (Pediatrics, Resident) |
| Evening | Dr. Kabir Menon (EM), Dr. Anjali Sharma (General Medicine), Dr. Rahul Verma (Orthopedics) |
| Night | Dr. Neha Kulkarni (EM), Dr. Pooja Shah (Cardiology, Senior Consultant) |

Seven patients are already waiting (Rohan Mehta through Vikram Joshi). Priya Nair arrived before Sneha Kulkarni but sits behind her, because Sneha is ESI 2 and Priya is ESI 3. Five earlier visits are discharged so wait estimates use a real average. Patients 13–15 (Aditi, Rohit, Sara) are registered and not yet admitted, for the live demo.

Doctor status is not stored by the website. Busy means the doctor is on duty and has a queue. Available means on duty and idle. Off duty means no shift covers the current time. When a shift ends with patients still waiting, `sp_handover_queue` (run by `evt_refresh_doctor_status` every minute, and once at load time) moves them to the doctor admission would pick now, and logs each move in `Audit_Log` under the name `Handover`.

## Viva script

Sign in as the nurse and leave **Live queue** open. It refreshes every 3 seconds.

1. **Stable patient.** Sign in as receptionist, register someone, sign back in as the nurse, admit them with ordinary vitals (heart rate 76, SpO2 99, BP 120/78, temperature 36.6, pain 1) and the complaint `minor cut and bleeding`. The complaint maps to Emergency Medicine. The score is ESI 5 (green). The result names the doctor and the queue position.

2. **Critical patient jumps the queue.** Admit another patient with heart rate 155, SpO2 86, BP 78/48, temperature 37.0, pain 8, complaint `uncontrolled bleeding and unconscious`. ESI 1 (red) appears at position 1. The stable patient moves down. Nothing on the page sorted that list.

3. **Reassessment.** On the queue page, pick the stable encounter and save heart rate 128, SpO2 91, BP 118/76, temperature 37.1, pain 4. The score becomes ESI 2 and the position changes. Try diastolic 90 with systolic 70. The banner shows `Diastolic BP must be lower than systolic BP` and the reading is not stored.

4. **Aging.** Sign in as admin → Policies. Pause the minute event. Set the ESI 5 limit to 60 (Imran Shaikh has been waiting about 80 minutes). Click **Run aging now**. His score moves from 5 to 4 and `Score_History` says `Escalated: exceeded waiting limit`. Put the limit back to 120 and resume the event. If you leave the lower limit in place, the every-minute job will keep raising him, because each new level still sees the same long wait.

5. **Overload.** Set `doctor_queue_threshold` to `0` and admit one more patient. An alert appears on the nurse alert panel. Set the threshold back to 5. Within a minute `evt_auto_resolve_alerts` closes it, or call the procedure:

   ```sql
   CALL sp_auto_resolve_alerts();
   ```

6. **Audit and soft delete.** Sign in as the auditor and filter the log. Sign in as admin → People and soft-delete a patient who is still waiting. The database refuses. Soft-delete Ananya Rao (she has been discharged), then restore her. A direct `DELETE FROM Patient` raises `Patients cannot be hard-deleted. Use soft delete.`

7. **Each role.** Sign in as each account. The doctor page has vitals and no phone number; the probe card shows the MySQL denial. The admin visit list has phone numbers and no ESI. The auditor cannot open the queue. The receptionist cannot open it either.

The same story, as SQL, is `demo/demo_scenario.sql`. Two admissions at once:

```bash
cd server && node ../demo/concurrent_admit.js
```

## Assumptions worth stating

- Raising a score one level means the ESI number decreases by one. It never goes below 1. One run moves a patient only one level.
- A complaint that matches no keyword goes to Emergency Medicine.
- ESI 1 is given to an on-duty consultant in that department, then an Emergency Medicine consultant, then any on-duty consultant, and only then a resident if no consultant is on duty.
- Off duty overrides a non-empty queue. The off-duty doctor's patients are handed over to an on-duty doctor using the admission rules; a patient only stays put if nobody suitable is on duty.
- `Audit_Log` does not audit itself.
- Views hide soft-deleted people. The restore list is the only view that shows them.
- Average consultation time falls back to 15 minutes when a doctor has no discharged visits (`Config.default_consult_minutes`).
- A department overload alert fires above 3 waiting ESI 1–2 patients (`dept_critical_threshold`).

## Layout

```
sql/           database, in run order
server/        Express + mysql2, no business rules
public/        sign-in and the five role screens
demo/          viva SQL and the two-session script
docs/          schema and the F1–F15 map
```
