'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  bootstrapAdministrator,
} = require('../scripts/bootstrap_admin');

const uid = 'admin-uid';
const username = 'kenzoowner';
const baseEnv = {
  GOOGLE_APPLICATION_CREDENTIALS: 'credential.json',
  GOOGLE_CLOUD_PROJECT: 'knz-scent',
  BOOTSTRAP_ADMIN_UID: uid,
  BOOTSTRAP_ADMIN_USERNAME: username,
};
const authUser = {
  uid,
  email: 'owner@example.com',
  emailVerified: true,
  disabled: false,
  displayName: 'KNZ Owner',
};

function createFirestore(initial = {}) {
  const documents = new Map(Object.entries(initial));
  let transactionCount = 0;
  const db = {
    collection(collection) {
      return {
        doc(id) {
          return { path: `${collection}/${id}` };
        },
      };
    },
    async runTransaction(callback) {
      transactionCount += 1;
      const creates = [];
      const transaction = {
        async get(ref) {
          const data = documents.get(ref.path);
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
        create(ref, data) {
          if (documents.has(ref.path)) throw new Error(`already exists: ${ref.path}`);
          creates.push({ path: ref.path, data });
        },
      };
      const result = await callback(transaction);
      for (const create of creates) documents.set(create.path, create.data);
      return result;
    },
  };
  return {
    db,
    documents,
    get transactionCount() {
      return transactionCount;
    },
  };
}

function dependencies({ env = baseEnv, user = authUser, initial = {}, authError } = {}) {
  const firestore = createFirestore(initial);
  let initializedProject;
  return {
    options: {
      env,
      credentialFileExists: () => true,
      initialize: ({ projectId }) => {
        initializedProject = projectId;
        return { projectId };
      },
      authForApp: () => ({
        getUser: async () => {
          if (authError) throw authError;
          return user;
        },
      }),
      firestoreForApp: () => firestore.db,
      serverTimestamp: () => 'server-time',
      nowIso: () => '2026-07-30T00:00:00.000Z',
    },
    firestore,
    get initializedProject() {
      return initializedProject;
    },
  };
}

function expectedDocuments(overrides = {}) {
  return {
    [`accountAccess/${uid}`]: {
      uid,
      email: 'owner@example.com',
      username,
      name: 'KNZ Owner',
      role: 'Administrator',
      status: 'approved',
      active: true,
      bootstrap: true,
      createdAt: 'server-time',
      updatedAt: 'server-time',
    },
    [`users/${uid}`]: {
      uid,
      email: 'owner@example.com',
      username,
      name: 'KNZ Owner',
      role: 'Administrator',
      account_status: 'approved',
      is_active: true,
      created_at: '2026-07-30T00:00:00.000Z',
    },
    [`_usernames/${username}`]: {
      uid,
      reservedAt: 'server-time',
    },
    ...overrides,
  };
}

test('rejects a missing project variable before initialization', async () => {
  const setup = dependencies({ env: { ...baseEnv, GOOGLE_CLOUD_PROJECT: '' } });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    /Set GOOGLE_CLOUD_PROJECT/,
  );
  assert.equal(setup.initializedProject, undefined);
  assert.equal(setup.firestore.transactionCount, 0);
});

test('rejects an incorrect project before initialization', async () => {
  const setup = dependencies({
    env: { ...baseEnv, GOOGLE_CLOUD_PROJECT: 'another-project' },
  });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    /must be exactly knz-scent/,
  );
  assert.equal(setup.initializedProject, undefined);
  assert.equal(setup.firestore.transactionCount, 0);
});

test('rejects a missing Firebase Authentication account', async () => {
  const setup = dependencies({ authError: { code: 'auth/user-not-found' } });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    /Firebase Authentication account admin-uid does not exist/,
  );
  assert.equal(setup.firestore.transactionCount, 0);
});

test('rejects an unverified email', async () => {
  const setup = dependencies({ user: { ...authUser, emailVerified: false } });
  await assert.rejects(bootstrapAdministrator(setup.options), /verified email/);
  assert.equal(setup.firestore.transactionCount, 0);
});

test('rejects a disabled account', async () => {
  const setup = dependencies({ user: { ...authUser, disabled: true } });
  await assert.rejects(bootstrapAdministrator(setup.options), /account is disabled/);
  assert.equal(setup.firestore.transactionCount, 0);
});

test('rejects a username collision and reports its path', async () => {
  const setup = dependencies({
    initial: { [`_usernames/${username}`]: { uid: 'another-uid' } },
  });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    new RegExp(`already reserved at _usernames/${username}`),
  );
});

test('rejects an existing users document collision', async () => {
  const setup = dependencies({
    initial: { [`users/${uid}`]: { uid: 'another-uid' } },
  });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    new RegExp(`partial existing records.*users/${uid} \\(exists\\)`),
  );
});

test('rejects partial existing records', async () => {
  const documents = expectedDocuments();
  delete documents[`_usernames/${username}`];
  const setup = dependencies({ initial: documents });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    new RegExp(`partial existing records.*_usernames/${username} \\(missing\\)`),
  );
});

test('rejects inconsistent existing records and reports paths', async () => {
  const documents = expectedDocuments();
  documents[`accountAccess/${uid}`].role = 'Staff';
  const setup = dependencies({ initial: documents });
  await assert.rejects(
    bootstrapAdministrator(setup.options),
    new RegExp(`inconsistent existing records at accountAccess/${uid}`),
  );
});

test('accepts a safe idempotent rerun without writes', async () => {
  const setup = dependencies({ initial: expectedDocuments() });
  const before = new Map(setup.firestore.documents);
  const result = await bootstrapAdministrator(setup.options);
  assert.deepEqual(result, { status: 'already bootstrapped' });
  assert.deepEqual(setup.firestore.documents, before);
});

test('creates all Administrator records atomically on first bootstrap', async () => {
  const setup = dependencies();
  const result = await bootstrapAdministrator(setup.options);
  assert.deepEqual(result, { status: 'provisioned' });
  assert.equal(setup.initializedProject, 'knz-scent');
  assert.equal(setup.firestore.transactionCount, 1);
  assert.deepEqual(
    Object.fromEntries(setup.firestore.documents),
    expectedDocuments(),
  );
});
