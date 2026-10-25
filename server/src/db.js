const mysql = require('mysql2/promise');

const ROLES = {
  receptionist: { user: 'receptionist_user', password: process.env.RECEPTIONIST_PASSWORD },
  nurse:        { user: 'nurse_user',        password: process.env.NURSE_PASSWORD },
  doctor:       { user: 'doctor_user',       password: process.env.DOCTOR_PASSWORD },
  admin:        { user: 'admin_user',        password: process.env.ADMIN_PASSWORD },
  auditor:      { user: 'auditor_user',      password: process.env.AUDITOR_PASSWORD },
};

const pools = {};

function poolFor(role) {
  const cred = ROLES[role];
  if (!cred) {
    throw new Error('Unknown role');
  }
  if (!pools[role]) {
    pools[role] = mysql.createPool({
      host: process.env.DB_HOST || '127.0.0.1',
      port: Number(process.env.DB_PORT || 3306),
      user: cred.user,
      password: cred.password,
      database: process.env.DB_NAME || 'SmartQueue',
      waitForConnections: true,
      connectionLimit: 8,
      dateStrings: true,
      multipleStatements: false,
      timezone: 'local',
    });
  }
  return pools[role];
}

function resultSets(payload) {
  if (!Array.isArray(payload)) return [];
  return payload.filter((set) => Array.isArray(set));
}

async function callProc(role, sql, params = []) {
  const [payload] = await poolFor(role).query(sql, params);
  return resultSets(payload);
}

async function selectRows(role, sql, params = []) {
  const [rows] = await poolFor(role).query(sql, params);
  return rows;
}

module.exports = { ROLES, poolFor, callProc, selectRows };
