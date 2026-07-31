'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const projectId = process.env.GCLOUD_PROJECT || 'demo-knz-scent';
const functionsOrigin = `http://127.0.0.1:5001/${projectId}/us-central1`;
const authOrigin = 'http://127.0.0.1:9099';

async function anonymousToken() {
  const response = await fetch(
    `${authOrigin}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  assert.equal(response.status, 200);
  return (await response.json()).idToken;
}

async function emailAccount(email) {
  const response = await fetch(
    `${authOrigin}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email,
        password: 'correct horse',
        returnSecureToken: true,
      }),
    },
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  return { uid: body.localId, token: body.idToken };
}

function firestoreValue(value) {
  if (typeof value === 'boolean') return { booleanValue: value };
  return { stringValue: String(value) };
}

async function seedDocument(collection, id, data) {
  const fields = Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, firestoreValue(value)]),
  );
  const response = await fetch(
    `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`,
    {
      method: 'PATCH',
      headers: {
        authorization: 'Bearer owner',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    },
  );
  assert.ok(response.ok, await response.text());
}

async function readDocument(collection, id) {
  const response = await fetch(
    `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`,
    { headers: { authorization: 'Bearer owner' } },
  );
  const text = await response.text();
  assert.ok(response.ok, text);
  return JSON.parse(text);
}

async function call(functionName, data, token) {
  const response = await fetch(`${functionsOrigin}/${functionName}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return { response, body: await response.json() };
}

test('requestOtp rejects unauthenticated callers', async () => {
  const result = await call('requestOtp', {
    email: 'admin@example.com',
    purpose: 'resetPassword',
  });

  assert.equal(result.body.error.status, 'UNAUTHENTICATED');
});

test('requestOtp validates callable request data', async () => {
  const token = await anonymousToken();
  const result = await call('requestOtp', {
    email: 'not-an-email',
    purpose: 'resetPassword',
  }, token);

  assert.equal(result.body.error.status, 'INVALID_ARGUMENT');
});

test('requestOtp keeps new registration disabled', async () => {
  const token = await anonymousToken();
  const result = await call('requestOtp', {
    email: 'admin@example.com',
    purpose: 'register',
  }, token);

  assert.equal(result.body.error.status, 'FAILED_PRECONDITION');
});

test('submitRegistrationRequest creates only pending Staff access', async () => {
  const account = await emailAccount('Pending@Example.COM');
  const result = await call('submitRegistrationRequest', {
    username: 'pending_staff',
    name: 'Pending Staff',
  }, account.token);

  assert.equal(result.response.status, 200);
  assert.equal(result.body.result.status, 'pending');
  const access = await readDocument('accountAccess', account.uid);
  assert.equal(access.fields.status.stringValue, 'pending');
  assert.equal(access.fields.role.stringValue, 'Staff');
  assert.equal(access.fields.active.booleanValue, false);
  assert.equal(access.fields.email.stringValue, 'pending@example.com');
});

test('submitRegistrationRequest enforces central username uniqueness', async () => {
  await seedDocument('_usernames', 'reserved_name', { uid: 'existing-user' });
  const account = await emailAccount('collision@example.com');
  const result = await call('submitRegistrationRequest', {
    username: 'reserved_name',
    name: 'Collision User',
  }, account.token);

  assert.equal(result.body.error.status, 'ALREADY_EXISTS');
});

test('only an approved Administrator can approve another verified request',
    async () => {
      const admin = await emailAccount('admin@example.com');
      const target = await emailAccount('target@example.com');
      await seedDocument('accountAccess', admin.uid, {
        uid: admin.uid,
        email: 'admin@example.com',
        username: 'admin_user',
        name: 'Admin User',
        status: 'approved',
        role: 'Administrator',
        active: true,
      });
      await seedDocument('accountAccess', target.uid, {
        uid: target.uid,
        email: 'target@example.com',
        username: 'target_user',
        name: 'Target User',
        status: 'pending',
        role: 'Staff',
        active: false,
      });
      await seedDocument('registrationRequests', target.uid, {
        uid: target.uid,
        email: 'target@example.com',
        username: 'target_user',
        name: 'Target User',
        status: 'pending',
        emailVerified: true,
      });

      const result = await call('reviewRegistrationRequest', {
        uid: target.uid,
        decision: 'approved',
      }, admin.token);
      assert.equal(result.response.status, 200);
      assert.equal(result.body.result.role, 'Staff');
      const access = await readDocument('accountAccess', target.uid);
      assert.equal(access.fields.status.stringValue, 'approved');
      assert.equal(access.fields.active.booleanValue, true);
    });

test('administrators cannot approve themselves', async () => {
  const admin = await emailAccount('self-admin@example.com');
  await seedDocument('accountAccess', admin.uid, {
    uid: admin.uid,
    email: 'self-admin@example.com',
    username: 'self_admin',
    name: 'Self Admin',
    status: 'approved',
    role: 'Administrator',
    active: true,
  });

  const result = await call('reviewRegistrationRequest', {
    uid: admin.uid,
    decision: 'approved',
    role: 'Administrator',
  }, admin.token);
  assert.equal(result.body.error.status, 'PERMISSION_DENIED');
});

test('Staff cannot review registration requests', async () => {
  const staff = await emailAccount('staff-reviewer@example.com');
  await seedDocument('accountAccess', staff.uid, {
    uid: staff.uid,
    email: 'staff-reviewer@example.com',
    username: 'staff_reviewer',
    name: 'Staff Reviewer',
    status: 'approved',
    role: 'Staff',
    active: true,
  });

  const result = await call('reviewRegistrationRequest', {
    uid: 'target-user',
    decision: 'approved',
  }, staff.token);
  assert.equal(result.body.error.status, 'PERMISSION_DENIED');
});

test('administrators cannot approve an unverified request', async () => {
  const admin = await emailAccount('verified-admin@example.com');
  const target = await emailAccount('unverified-target@example.com');
  await seedDocument('accountAccess', admin.uid, {
    uid: admin.uid,
    email: 'verified-admin@example.com',
    username: 'verified_admin',
    name: 'Verified Admin',
    status: 'approved',
    role: 'Administrator',
    active: true,
  });
  await seedDocument('accountAccess', target.uid, {
    uid: target.uid,
    email: 'unverified-target@example.com',
    username: 'unverified_target',
    name: 'Unverified Target',
    status: 'pending',
    role: 'Staff',
    active: false,
  });
  await seedDocument('registrationRequests', target.uid, {
    uid: target.uid,
    status: 'pending',
    emailVerified: false,
  });

  const result = await call('reviewRegistrationRequest', {
    uid: target.uid,
    decision: 'approved',
  }, admin.token);
  assert.equal(result.body.error.status, 'FAILED_PRECONDITION');
});

test('requestOtp reports missing secret configuration safely', async () => {
  const token = await anonymousToken();
  const result = await call('requestOtp', {
    email: 'admin@example.com',
    purpose: 'resetPassword',
  }, token);

  assert.equal(result.body.error.status, 'FAILED_PRECONDITION');
  assert.equal(
    result.body.error.message,
    'Email verification is temporarily unavailable.',
  );
});
