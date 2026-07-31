'use strict';

const fs = require('node:fs');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'knz-scent';

function requiredEnvironment(env, name) {
  const value = String(env[name] || '').trim();
  if (!value) throw new Error(`Set ${name} before running the bootstrap.`);
  return value;
}

function matchingFields(data, expected) {
  return Object.entries(expected).every(([key, value]) => data[key] === value);
}

async function bootstrapAdministrator({
  env = process.env,
  credentialFileExists = fs.existsSync,
  initialize = initializeApp,
  authForApp = getAuth,
  firestoreForApp = getFirestore,
  serverTimestamp = FieldValue.serverTimestamp,
  nowIso = () => new Date().toISOString(),
} = {}) {
  const projectId = requiredEnvironment(env, 'GOOGLE_CLOUD_PROJECT');
  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
      `Bootstrap refused: GOOGLE_CLOUD_PROJECT must be exactly ${EXPECTED_PROJECT_ID}.`,
    );
  }
  const credentialPath = requiredEnvironment(env, 'GOOGLE_APPLICATION_CREDENTIALS');
  if (!credentialFileExists(credentialPath)) {
    throw new Error('Bootstrap refused: the configured credential file does not exist.');
  }
  const uid = requiredEnvironment(env, 'BOOTSTRAP_ADMIN_UID');
  if (!uid) throw new Error('Set BOOTSTRAP_ADMIN_UID to an existing Firebase Auth UID.');

  const app = initialize({ projectId: EXPECTED_PROJECT_ID });
  let authUser;
  try {
    authUser = await authForApp(app).getUser(uid);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      throw new Error(`Bootstrap refused: Firebase Authentication account ${uid} does not exist.`);
    }
    throw error;
  }
  if (!authUser.email || !authUser.emailVerified) {
    throw new Error('The bootstrap Administrator must have a verified email.');
  }
  if (authUser.disabled) {
    throw new Error('Bootstrap refused: the Firebase Authentication account is disabled.');
  }

  const email = authUser.email.trim().toLowerCase();
  const username = String(env.BOOTSTRAP_ADMIN_USERNAME || '')
      .trim()
      .toLowerCase();
  if (!/^[a-z0-9_]{3,32}$/.test(username)) {
    throw new Error('Set BOOTSTRAP_ADMIN_USERNAME to 3-32 lowercase letters, numbers, or underscores.');
  }
  const name = String(authUser.displayName || username).trim();
  const legacyOwnerKey = String(env.BOOTSTRAP_LEGACY_OWNER_KEY || '').trim();
  const db = firestoreForApp(app);
  const accessRef = db.collection('accountAccess').doc(uid);
  const userRef = db.collection('users').doc(uid);
  const usernameRef = db.collection('_usernames').doc(username);

  return db.runTransaction(async (transaction) => {
    const [access, user, usernameReservation] = await Promise.all([
      transaction.get(accessRef),
      transaction.get(userRef),
      transaction.get(usernameRef),
    ]);
    if (usernameReservation.exists && usernameReservation.data().uid !== uid) {
      throw new Error(
        `Bootstrap refused: this username is already reserved at ${usernameRef.path}.`,
      );
    }

    const records = [
      { ref: accessRef, snapshot: access },
      { ref: userRef, snapshot: user },
      { ref: usernameRef, snapshot: usernameReservation },
    ];
    const existingCount = records.filter(({ snapshot }) => snapshot.exists).length;
    if (existingCount > 0 && existingCount < records.length) {
      const states = records
          .map(({ ref, snapshot }) => `${ref.path} (${snapshot.exists ? 'exists' : 'missing'})`)
          .join(', ');
      throw new Error(`Bootstrap refused: partial existing records at ${states}.`);
    }

    if (existingCount === records.length) {
      const accessData = access.data();
      const userData = user.data();
      const usernameData = usernameReservation.data();
      const conflicts = [];
      if (!matchingFields(accessData, {
        uid,
        email,
        username,
        name,
        role: 'Administrator',
        status: 'approved',
        active: true,
        bootstrap: true,
      })) {
        conflicts.push(accessRef.path);
      }
      if (!matchingFields(userData, {
        uid,
        email,
        username,
        name,
        role: 'Administrator',
        account_status: 'approved',
        is_active: true,
      })) {
        conflicts.push(userRef.path);
      }
      if (usernameData.uid !== uid) conflicts.push(usernameRef.path);
      if (accessData.legacyOwnerKey !== userData.legacy_owner_key ||
          (legacyOwnerKey && accessData.legacyOwnerKey !== legacyOwnerKey)) {
        conflicts.push(accessRef.path, userRef.path);
      }
      if (conflicts.length > 0) {
        throw new Error(
          `Bootstrap refused: inconsistent existing records at ${[...new Set(conflicts)].join(', ')}.`,
        );
      }
      return { status: 'already bootstrapped' };
    }

    const now = serverTimestamp();
    transaction.create(accessRef, {
      uid,
      email,
      username,
      name,
      role: 'Administrator',
      status: 'approved',
      active: true,
      ...(legacyOwnerKey ? { legacyOwnerKey } : {}),
      bootstrap: true,
      createdAt: now,
      updatedAt: now,
    });
    transaction.create(usernameRef, {
      uid,
      reservedAt: now,
    });
    transaction.create(userRef, {
      uid,
      email,
      username,
      name,
      role: 'Administrator',
      account_status: 'approved',
      is_active: true,
      ...(legacyOwnerKey ? { legacy_owner_key: legacyOwnerKey } : {}),
      created_at: nowIso(),
    });
    return { status: 'provisioned' };
  });
}

if (require.main === module) {
  bootstrapAdministrator().then(
    (result) => process.stdout.write(
      result.status === 'already bootstrapped' ?
        'Administrator already bootstrapped.\n' :
        'Bootstrap Administrator provisioned.\n',
    ),
    (error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    },
  );
}

module.exports = {
  EXPECTED_PROJECT_ID,
  bootstrapAdministrator,
};
