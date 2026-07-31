'use strict';

const fs = require('node:fs');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'knz-scent';

function requiredEnvironment(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Set ${name} before running verification.`);
  return value;
}

function matches(data, expected) {
  return Object.entries(expected).every(([key, value]) => data[key] === value);
}

async function verify() {
  const projectId = requiredEnvironment('GOOGLE_CLOUD_PROJECT');
  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`GOOGLE_CLOUD_PROJECT must be exactly ${EXPECTED_PROJECT_ID}.`);
  }
  const credentialPath = requiredEnvironment('GOOGLE_APPLICATION_CREDENTIALS');
  if (!fs.existsSync(credentialPath)) {
    throw new Error('The configured credential file does not exist.');
  }
  const uid = requiredEnvironment('BOOTSTRAP_ADMIN_UID');
  const username = requiredEnvironment('BOOTSTRAP_ADMIN_USERNAME').toLowerCase();
  const app = initializeApp({ projectId: EXPECTED_PROJECT_ID });
  const authUser = await getAuth(app).getUser(uid);

  process.stdout.write('PROJECT_MATCH=YES\n');
  process.stdout.write('AUTH_UID_EXISTS=YES\n');
  process.stdout.write(`EMAIL_VERIFIED=${authUser.emailVerified ? 'YES' : 'NO'}\n`);
  process.stdout.write(`AUTH_DISABLED=${authUser.disabled ? 'YES' : 'NO'}\n`);
  if (!authUser.emailVerified || authUser.disabled || !authUser.email) {
    throw new Error('The Authentication account is not eligible for Administrator bootstrap.');
  }
  if (process.argv.includes('--auth-only')) return;

  const email = authUser.email.trim().toLowerCase();
  const name = String(authUser.displayName || username).trim();
  const db = getFirestore(app);
  const refs = [
    db.collection('accountAccess').doc(uid),
    db.collection('users').doc(uid),
    db.collection('_usernames').doc(username),
  ];
  const snapshots = await db.getAll(...refs);
  const missing = refs.filter((_, index) => !snapshots[index].exists).map((ref) => ref.path);
  if (missing.length > 0) {
    throw new Error(`Missing Administrator records: ${missing.join(', ')}.`);
  }
  const access = snapshots[0].data();
  const user = snapshots[1].data();
  const reservation = snapshots[2].data();
  const conflicts = [];
  if (!matches(access, {
    uid,
    email,
    username,
    name,
    role: 'Administrator',
    status: 'approved',
    active: true,
    bootstrap: true,
  })) {
    conflicts.push(refs[0].path);
  }
  if (!matches(user, {
    uid,
    email,
    username,
    name,
    role: 'Administrator',
    account_status: 'approved',
    is_active: true,
  })) {
    conflicts.push(refs[1].path);
  }
  if (reservation.uid !== uid) conflicts.push(refs[2].path);
  if (access.legacyOwnerKey !== user.legacy_owner_key) {
    conflicts.push(refs[0].path, refs[1].path);
  }
  if (conflicts.length > 0) {
    throw new Error(
      `Inconsistent Administrator records: ${[...new Set(conflicts)].join(', ')}.`,
    );
  }
  process.stdout.write('ADMIN_RECORDS_VALID=YES\n');
}

verify().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
