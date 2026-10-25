require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const path = require('path');
const express = require('express');
const session = require('express-session');
const { ROLES, poolFor, callProc, selectRows } = require('./db');

const app = express();
const PORT = Number(process.env.PORT || 3000);

app.use(express.json());
app.use(session({
  secret: process.env.SESSION_SECRET || 'smartqueue-local-demo',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 8 * 60 * 60 * 1000 },
}));
app.use(express.static(path.join(__dirname, '..', '..', 'public'), {
  etag: false,
  lastModified: false,
  setHeaders: (res) => res.set('Cache-Control', 'no-store'),
}));

function requireRole(...allowed) {
  return (req, res, next) => {
    if (!req.session.role) {
      return res.status(401).json({ error: 'Not signed in' });
    }
    if (allowed.length && !allowed.includes(req.session.role)) {
      return res.status(403).json({ error: 'This role cannot open that page' });
    }
    next();
  };
}

function sendError(res, err) {
  const message = err.sqlMessage || err.message || 'Database error';
  const status = err.sqlState === '45000' ? 400 : (err.code === 'ER_TABLEACCESS_DENIED_ERROR' || err.errno === 1142 || err.errno === 1143 || err.errno === 1370 ? 403 : 500);
  res.status(status).json({ error: message });
}

async function sets(res, role, sql, params) {
  const data = await callProc(role, sql, params);
  res.json({ sets: data });
}

// A query this role must not be able to run. The database, not this file, says no.
const PROBE = {
  receptionist: 'SELECT Encounter_ID FROM vw_live_queue',
  nurse: 'SELECT Phone, Email FROM Patient LIMIT 1',
  doctor: 'SELECT Phone, Email FROM Patient LIMIT 1',
  admin: 'SELECT Heart_Rate, SpO2 FROM Vitals_Log LIMIT 1',
  auditor: 'SELECT Patient_Name FROM vw_live_queue',
};

app.post('/api/login', async (req, res) => {
  const role = req.body && req.body.role;
  const password = req.body && req.body.password;
  const cred = ROLES[role];
  if (!cred || password !== cred.password) {
    return res.status(401).json({ error: 'Unknown role or wrong password.' });
  }
  try {
    const rows = await selectRows(role, 'SELECT CURRENT_USER() AS db_user');
    req.session.role = role;
    req.session.dbUser = rows[0].db_user;
    res.json({ role, dbUser: rows[0].db_user });
  } catch (err) {
    sendError(res, err);
  }
});

app.post('/api/logout', (req, res) => {
  req.session.destroy(() => res.json({ ok: true }));
});

app.get('/api/me', (req, res) => {
  if (!req.session.role) return res.status(401).json({ error: 'Not signed in' });
  res.json({ role: req.session.role, dbUser: req.session.dbUser });
});

app.get('/api/probe', requireRole('receptionist', 'nurse', 'doctor', 'admin', 'auditor'), async (req, res) => {
  try {
    const rows = await selectRows(req.session.role, PROBE[req.session.role]);
    res.json({ denied: false, rows });
  } catch (err) {
    res.json({ denied: true, error: err.sqlMessage || err.message });
  }
});

// ----- Receptionist -----
app.post('/api/patients', requireRole('receptionist'), async (req, res) => {
  const b = req.body || {};
  try {
    await sets(res, 'receptionist', 'CALL sp_register_patient(?, ?, ?, ?)', [b.name, b.phone, b.email || null, b.dob]);
  } catch (err) { sendError(res, err); }
});

app.get('/api/patients/recent', requireRole('receptionist'), async (req, res) => {
  try {
    const rows = await selectRows('receptionist',
      `SELECT * FROM vw_patient_directory ORDER BY Patient_ID DESC LIMIT 10`);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/patients/search', requireRole('receptionist', 'admin'), async (req, res) => {
  try {
    const data = await callProc(req.session.role, 'CALL sp_search_patients(?)', [req.query.q || '']);
    res.json({ rows: data[0] || [] });
  } catch (err) { sendError(res, err); }
});

// ----- Nurse -----
app.get('/api/queue', requireRole('nurse', 'admin'), async (req, res) => {
  try {
    const rows = await selectRows(req.session.role,
      `SELECT * FROM vw_live_queue ORDER BY Department_Name, Doctor_Name, Queue_Position`);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/admittable', requireRole('nurse'), async (req, res) => {
  try {
    const rows = await selectRows('nurse',
      `SELECT * FROM vw_patients_admittable ORDER BY Name`);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/doctors', requireRole('nurse', 'doctor', 'admin'), async (req, res) => {
  try {
    const rows = await selectRows(req.session.role,
      `SELECT * FROM vw_doctor_directory ORDER BY Department_Name, Doctor_Name`);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/alerts', requireRole('nurse', 'admin'), async (req, res) => {
  try {
    const view = req.session.role === 'admin' ? 'vw_all_alerts' : 'vw_open_alerts';
    const rows = await selectRows(req.session.role,
      `SELECT * FROM ${view} ORDER BY Created_At DESC`);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.post('/api/admit', requireRole('nurse'), async (req, res) => {
  const b = req.body || {};
  try {
    await sets(res, 'nurse', 'CALL sp_admit_patient_safe(?, ?, ?, ?, ?, ?, ?, ?)', [
      b.patient_id, b.symptoms, b.hr, b.spo2, b.sys, b.dia, b.temp, b.pain,
    ]);
  } catch (err) { sendError(res, err); }
});

app.post('/api/reassess', requireRole('nurse'), async (req, res) => {
  const b = req.body || {};
  try {
    await sets(res, 'nurse', 'CALL sp_reassess_patient_safe(?, ?, ?, ?, ?, ?, ?)', [
      b.encounter_id, b.hr, b.spo2, b.sys, b.dia, b.temp, b.pain,
    ]);
  } catch (err) { sendError(res, err); }
});

app.post('/api/discharge', requireRole('nurse'), async (req, res) => {
  try {
    await sets(res, 'nurse', 'CALL sp_discharge_patient_safe(?)', [req.body.encounter_id]);
  } catch (err) { sendError(res, err); }
});

// ----- Doctor -----
app.get('/api/clinical', requireRole('doctor'), async (req, res) => {
  try {
    const rows = await selectRows('doctor',
      `SELECT * FROM vw_doctor_clinical WHERE Doctor_ID = ? ORDER BY Queue_Position`,
      [req.query.doctor_id]);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/similar', requireRole('doctor'), async (req, res) => {
  try {
    const data = await callProc('doctor', 'CALL sp_search_similar_cases(?)', [req.query.q || '']);
    res.json({ rows: data[0] || [] });
  } catch (err) { sendError(res, err); }
});

// ----- Admin -----
app.get('/api/dashboard', requireRole('admin'), async (req, res) => {
  try {
    const [load, esi, hours, workload] = await Promise.all([
      selectRows('admin', 'SELECT * FROM vw_department_load ORDER BY Department'),
      selectRows('admin', 'SELECT * FROM vw_wait_by_esi ORDER BY ESI'),
      selectRows('admin', 'SELECT * FROM vw_busiest_hours ORDER BY Hour_Of_Day'),
      selectRows('admin', 'SELECT * FROM vw_doctor_workload ORDER BY Active_Patients DESC, Doctor_Name'),
    ]);
    res.json({ load, esi, hours, workload });
  } catch (err) { sendError(res, err); }
});

app.get('/api/visits', requireRole('admin'), async (req, res) => {
  try {
    const rows = await selectRows('admin',
      'SELECT * FROM vw_admin_summary ORDER BY Arrival_Time DESC');
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/reports/daily', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_daily_report(?)', [req.query.date]); }
  catch (err) { sendError(res, err); }
});

app.get('/api/reports/weekly', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_weekly_report(?)', [req.query.start]); }
  catch (err) { sendError(res, err); }
});

app.get('/api/reports/doctor', requireRole('admin'), async (req, res) => {
  try {
    await sets(res, 'admin', 'CALL sp_doctor_report(?, ?, ?)', [
      req.query.doctor_id, req.query.from, req.query.to,
    ]);
  } catch (err) { sendError(res, err); }
});

app.get('/api/roster', requireRole('admin'), async (req, res) => {
  try {
    const rows = await selectRows('admin',
      `SELECT * FROM vw_roster WHERE Shift_Date BETWEEN ? AND ? ORDER BY Shift_Date, Department_Name, Doctor_Name`,
      [req.query.from, req.query.to]);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/meta', requireRole('admin'), async (req, res) => {
  try {
    const [departments, shifts, config, aging, patients, deleted] = await Promise.all([
      selectRows('admin', 'SELECT * FROM vw_departments ORDER BY Name'),
      selectRows('admin', 'SELECT * FROM vw_shifts ORDER BY Start_Time'),
      selectRows('admin', 'SELECT * FROM vw_config ORDER BY Config_Key'),
      selectRows('admin', 'SELECT * FROM vw_aging_policy ORDER BY ESI_Level'),
      selectRows('admin', 'SELECT * FROM vw_patients_admin ORDER BY Name'),
      selectRows('admin', 'SELECT * FROM vw_deleted_directory ORDER BY Deleted_At DESC'),
    ]);
    res.json({ departments, shifts, config, aging, patients, deleted });
  } catch (err) { sendError(res, err); }
});

app.post('/api/shifts', requireRole('admin'), async (req, res) => {
  const b = req.body || {};
  try { await sets(res, 'admin', 'CALL sp_assign_shift(?, ?, ?)', [b.doctor_id, b.shift_id, b.shift_date]); }
  catch (err) { sendError(res, err); }
});

app.delete('/api/shifts/:id', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_unassign_shift(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/departments', requireRole('admin'), async (req, res) => {
  const b = req.body || {};
  try { await sets(res, 'admin', 'CALL sp_add_department(?, ?)', [b.name, b.description || null]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/doctors', requireRole('admin'), async (req, res) => {
  const b = req.body || {};
  try {
    await sets(res, 'admin', 'CALL sp_add_doctor(?, ?, ?, ?)', [
      b.name, b.role, b.specialization, b.department_id,
    ]);
  } catch (err) { sendError(res, err); }
});

app.post('/api/people/patient/:id/delete', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_soft_delete_patient(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});
app.post('/api/people/patient/:id/restore', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_restore_patient(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});
app.post('/api/people/doctor/:id/delete', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_soft_delete_doctor(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});
app.post('/api/people/doctor/:id/restore', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_restore_doctor(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/alerts/:id/resolve', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_resolve_alert(?)', [req.params.id]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/config', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_set_config(?, ?)', [req.body.key, String(req.body.value)]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/aging', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_set_aging_policy(?, ?)', [req.body.esi, req.body.minutes]); }
  catch (err) { sendError(res, err); }
});

app.post('/api/aging/run', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_age_queue()'); }
  catch (err) { sendError(res, err); }
});

app.post('/api/aging/toggle', requireRole('admin'), async (req, res) => {
  try { await sets(res, 'admin', 'CALL sp_toggle_aging(?)', [req.body.on ? 1 : 0]); }
  catch (err) { sendError(res, err); }
});

// ----- Auditor -----
app.get('/api/audit', requireRole('auditor'), async (req, res) => {
  try {
    const blank = (value) => (value ? value : null);
    const table = blank(req.query.table);
    const action = blank(req.query.action);
    const from = blank(req.query.from);
    const to = blank(req.query.to);
    const rows = await selectRows('auditor',
      `SELECT Audit_ID, Table_Name, Record_ID, Action, Old_Data, New_Data, Changed_By, Changed_At
       FROM Audit_Log
       WHERE (? IS NULL OR Table_Name = ?)
         AND (? IS NULL OR Action = ?)
         AND (? IS NULL OR Changed_At >= ?)
         AND (? IS NULL OR Changed_At < DATE_ADD(?, INTERVAL 1 DAY))
       ORDER BY Audit_ID DESC
       LIMIT 200`,
      [table, table, action, action, from, from, to, to]);
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/score-audit', requireRole('auditor'), async (req, res) => {
  try {
    const rows = await selectRows('auditor',
      'SELECT * FROM vw_score_audit ORDER BY History_ID DESC');
    res.json({ rows });
  } catch (err) { sendError(res, err); }
});

app.get('/api/health', (_req, res) => {
  res.json({ ok: true });
});

// Keep a reference so an unused import does not look like a dead pool factory.
app.locals.poolFor = poolFor;

app.listen(PORT, () => {
  console.log(`SmartQueue listening on http://localhost:${PORT}`);
});
