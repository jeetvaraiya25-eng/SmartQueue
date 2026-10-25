/**
 * Two sessions admit at the same time.
 * Run from the server directory after npm install and ./setup.sh:
 *   node ../demo/concurrent_admit.js
 *
 * Both admissions should commit. Doctors are locked in Doctor_ID order, so
 * the sessions queue instead of deadlocking. If error 1213 or 1205 still
 * happens, sp_admit_patient_safe retries up to three times.
 */
const path = require('path');
const mysql = require(path.join(__dirname, '..', 'server', 'node_modules', 'mysql2', 'promise'));

const base = {
  host: '127.0.0.1',
  port: 3306,
  user: 'nurse_user',
  password: 'Nurse@123',
  database: 'SmartQueue',
  dateStrings: true,
};

async function register(name, phone) {
  const conn = await mysql.createConnection({ ...base, user: 'receptionist_user', password: 'Reception@123' });
  try {
    const [sets] = await conn.query('CALL sp_register_patient(?, ?, ?, ?)', [name, phone, null, '1993-03-03']);
    const row = sets[0][0];
    return row.Patient_ID;
  } finally {
    await conn.end();
  }
}

async function admit(label, patientId) {
  const conn = await mysql.createConnection(base);
  const started = Date.now();
  try {
    const [sets] = await conn.query(
      'CALL sp_admit_patient_safe(?, ?, ?, ?, ?, ?, ?, ?)',
      [patientId, label + ' minor bleeding', 78, 98, 120, 76, 36.6, 1]
    );
    const row = sets[0] && sets[0][0];
    console.log(label, `${Date.now() - started} ms`, row);
  } catch (err) {
    console.error(label, 'FAILED', err.sqlMessage || err.message);
  } finally {
    await conn.end();
  }
}

(async () => {
  const stamp = Date.now().toString().slice(-8);
  const a = await register('Concurrent A ' + stamp, '97' + stamp.slice(0, 8));
  const b = await register('Concurrent B ' + stamp, '96' + stamp.slice(0, 8));
  await Promise.all([admit('session-A', a), admit('session-B', b)]);
})();
