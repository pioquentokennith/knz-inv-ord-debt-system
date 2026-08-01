'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} = require('firebase/firestore');

const projectId = process.env.GCLOUD_PROJECT || 'demo-knz-scent';
let environment;

function authenticated(uid, { verified = true, email } = {}) {
  return environment.authenticatedContext(uid, {
    email: email || `${uid}@example.com`,
    email_verified: verified,
    firebase: { sign_in_provider: 'password' },
  }).firestore();
}

function anonymous(uid) {
  return environment.authenticatedContext(uid, {
    firebase: { sign_in_provider: 'anonymous' },
  }).firestore();
}

async function seedAccess(uid, status, role = 'Staff', active = false) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'accountAccess', uid), {
      uid,
      status,
      role,
      active,
    });
  });
}

function defaultUsername(uid) {
  return `${uid.replace(/[^a-z0-9_]/g, '_')}_user`;
}

async function seedPending(uid, username = defaultUsername(uid)) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    const timestamp = Timestamp.now();
    const email = `${uid}@example.com`;
    await setDoc(doc(firestore, 'accountAccess', uid), {
      uid,
      email,
      username,
      name: `User ${uid}`,
      role: 'Staff',
      status: 'pending',
      active: false,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    await setDoc(doc(firestore, 'users', uid), {
      uid,
      email,
      username,
      name: `User ${uid}`,
      role: 'Staff',
      account_status: 'pending',
      is_active: false,
      created_at: new Date().toISOString(),
    });
    await setDoc(doc(firestore, '_usernames', username), {
      uid,
      reservedAt: timestamp,
    });
  });
}

function registrationBatch(firestore, uid, {
  email = `${uid}@example.com`,
  username = defaultUsername(uid),
  role = 'Staff',
  status = 'pending',
  active = false,
} = {}) {
  const batch = writeBatch(firestore);
  batch.set(doc(firestore, 'accountAccess', uid), {
    uid,
    email,
    username,
    name: `User ${uid}`,
    role,
    status,
    active,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(firestore, 'users', uid), {
    uid,
    email,
    username,
    name: `User ${uid}`,
    role,
    account_status: status,
    is_active: active,
    created_at: new Date().toISOString(),
  });
  batch.set(doc(firestore, '_usernames', username), {
    uid,
    reservedAt: serverTimestamp(),
  });
  return batch;
}

function reviewBatch(firestore, administratorUid, targetUid, decision) {
  const batch = writeBatch(firestore);
  batch.update(doc(firestore, 'accountAccess', targetUid), {
    status: decision,
    active: decision === 'approved',
    role: 'Staff',
    reviewedBy: administratorUid,
    reviewedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.update(doc(firestore, 'users', targetUid), {
    role: 'Staff',
    account_status: decision,
    is_active: decision === 'approved',
    updated_at: new Date().toISOString(),
  });
  return batch;
}

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

test.beforeEach(async () => environment.clearFirestore());
test.after(async () => environment.cleanup());

test('denies unauthenticated and anonymous business access', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const unauthenticated = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(unauthenticated, 'users/approved-user')));
  await assertFails(getDoc(doc(anonymous('approved-user'), 'users/approved-user')));
});

test('denies cross-UID business access', async () => {
  await seedAccess('user-a', 'approved', 'Staff', true);
  await seedAccess('user-b', 'approved', 'Staff', true);
  await assertFails(getDoc(doc(authenticated('user-a'), 'users/user-b')));
  await assertFails(setDoc(
    doc(authenticated('user-a'), 'users/user-b/products/product-1'),
    { id: 'product-1', user_id: 'user-b' },
  ));
});

test('unverified user cannot create registration documents', async () => {
  const firestore = authenticated('unverified', { verified: false });
  await assertFails(registrationBatch(firestore, 'unverified').commit());
});

test('verified user may create only their own pending Staff request', async () => {
  const firestore = authenticated('verified-user');
  await assertSucceeds(registrationBatch(firestore, 'verified-user').commit());
  await assertSucceeds(getDoc(doc(firestore, 'accountAccess/verified-user')));
  await assertFails(
    registrationBatch(firestore, 'different-user').commit(),
  );
});

test('registration documents cannot be created separately', async () => {
  const uid = 'partial-user';
  const firestore = authenticated(uid);
  await assertFails(setDoc(doc(firestore, 'accountAccess', uid), {
    uid,
    email: `${uid}@example.com`,
    username: defaultUsername(uid),
    name: `User ${uid}`,
    role: 'Staff',
    status: 'pending',
    active: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('registration email must equal the authenticated verified email', async () => {
  const firestore = authenticated('verified-user');
  await assertFails(registrationBatch(firestore, 'verified-user', {
    email: 'different@example.com',
  }).commit());
});

test('Administrator self-assignment on registration is denied', async () => {
  const firestore = authenticated('new-admin');
  await assertFails(registrationBatch(firestore, 'new-admin', {
    role: 'Administrator',
  }).commit());
});

test('approved status on registration is denied', async () => {
  const firestore = authenticated('approved-request');
  await assertFails(registrationBatch(firestore, 'approved-request', {
    status: 'approved',
  }).commit());
});

test('active true on registration is denied', async () => {
  const firestore = authenticated('active-request');
  await assertFails(registrationBatch(firestore, 'active-request', {
    active: true,
  }).commit());
});

test('duplicate username is denied', async () => {
  await seedPending('first-user', 'reserved_name');
  const firestore = authenticated('second-user');
  await assertFails(registrationBatch(firestore, 'second-user', {
    username: 'reserved_name',
  }).commit());
});

test('a UID cannot reserve a second username', async () => {
  const firestore = authenticated('one-name');
  await assertSucceeds(registrationBatch(firestore, 'one-name').commit());
  await assertFails(setDoc(doc(firestore, '_usernames/second_name'), {
    uid: 'one-name',
    reservedAt: serverTimestamp(),
  }));
});

test('pending users inspect state but cannot access business data', async () => {
  await seedPending('pending-user');
  const firestore = authenticated('pending-user');
  await assertSucceeds(getDoc(doc(firestore, 'accountAccess/pending-user')));
  await assertFails(getDoc(doc(firestore, 'users/pending-user')));
});

test('ordinary Staff approval is denied', async () => {
  await seedAccess('staff-reviewer', 'approved', 'Staff', true);
  await seedPending('target-user');
  const firestore = authenticated('staff-reviewer');
  await assertFails(
    reviewBatch(firestore, 'staff-reviewer', 'target-user', 'approved').commit(),
  );
});

test('self-approval is denied', async () => {
  await seedPending('self-reviewer');
  const firestore = authenticated('self-reviewer');
  await assertFails(
    reviewBatch(firestore, 'self-reviewer', 'self-reviewer', 'approved').commit(),
  );
});

test('active approved Administrator approval is allowed and atomic', async () => {
  await seedAccess('admin-user', 'approved', 'Administrator', true);
  await seedPending('target-user');
  const firestore = authenticated('admin-user');
  await assertSucceeds(
    reviewBatch(firestore, 'admin-user', 'target-user', 'approved').commit(),
  );
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestoreWithoutRules = context.firestore();
    const access = await getDoc(doc(
      firestoreWithoutRules,
      'accountAccess/target-user',
    ));
    const profile = await getDoc(doc(
      firestoreWithoutRules,
      'users/target-user',
    ));
    assert.equal(access.data().status, 'approved');
    assert.equal(access.data().active, true);
    assert.equal(access.data().role, 'Staff');
    assert.equal(profile.data().account_status, 'approved');
    assert.equal(profile.data().is_active, true);
    assert.equal(profile.data().role, 'Staff');
  });
});

test('Administrator cannot assign Administrator or make a partial decision', async () => {
  await seedAccess('admin-user', 'approved', 'Administrator', true);
  await seedPending('target-user');
  const firestore = authenticated('admin-user');
  await assertFails(updateDoc(doc(firestore, 'accountAccess/target-user'), {
    status: 'approved',
    active: true,
    role: 'Administrator',
    reviewedBy: 'admin-user',
    reviewedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(firestore, 'accountAccess/target-user'), {
    status: 'approved',
    active: true,
    role: 'Staff',
    reviewedBy: 'admin-user',
    reviewedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('protected identity fields are immutable during review', async () => {
  await seedAccess('admin-user', 'approved', 'Administrator', true);
  await seedPending('target-user');
  const firestore = authenticated('admin-user');
  const batch = reviewBatch(
    firestore,
    'admin-user',
    'target-user',
    'approved',
  );
  batch.update(doc(firestore, 'users/target-user'), {
    email: 'changed@example.com',
  });
  await assertFails(batch.commit());
});

test('rejected and suspended states remain inactive and deny business access',
    async () => {
      await seedAccess('admin-user', 'approved', 'Administrator', true);
      await seedPending('rejected-user');
      await seedPending('suspended-user');
      const firestore = authenticated('admin-user');
      await assertSucceeds(
        reviewBatch(
          firestore,
          'admin-user',
          'rejected-user',
          'rejected',
        ).commit(),
      );
      await assertSucceeds(
        reviewBatch(
          firestore,
          'admin-user',
          'suspended-user',
          'suspended',
        ).commit(),
      );
      await assertFails(getDoc(doc(
        authenticated('rejected-user'),
        'users/rejected-user',
      )));
      await assertFails(getDoc(doc(
        authenticated('suspended-user'),
        'users/suspended-user',
      )));
    });

test('approved active users can access only UID-owned business documents', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  await assertSucceeds(setDoc(
    doc(firestore, 'users/approved-user/products/product-1'),
    { id: 'product-1', user_id: 'approved-user' },
  ));
  await assertSucceeds(getDocs(
    collection(firestore, 'users/approved-user/products'),
  ));
  await assertFails(setDoc(
    doc(firestore, 'users/approved-user/products/product-2'),
    { id: 'product-2', user_id: 'another-user' },
  ));
});

test('allows required reseller and custom-order sync paths', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  await assertSucceeds(setDoc(
    doc(firestore, 'users/approved-user/resellers/reseller-1'),
    { id: 'reseller-1', user_id: 'approved-user', is_deleted: 0 },
  ));
  await assertSucceeds(setDoc(
    doc(firestore, 'users/approved-user/custom_orders/custom-1'),
    { id: 'custom-1', user_id: 'approved-user', is_deleted: 0 },
  ));
});

test('rejects invalid remote order transitions', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const order = doc(firestore, 'users/approved-user/orders/order-1');
  await assertSucceeds(setDoc(order, {
    id: 'order-1',
    user_id: 'approved-user',
    order_id: 'KNZ-001',
    status: 'Pending',
    items: [],
    is_deleted: 0,
  }));
  await assertFails(updateDoc(order, { status: 'Delivered' }));
  await assertSucceeds(updateDoc(order, { status: 'Processing' }));
});

test('tombstones retain owner and document identity validation', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  await assertSucceeds(setDoc(
    doc(firestore, 'users/approved-user/orders/order-1'),
    {
      id: 'order-1',
      user_id: 'approved-user',
      is_deleted: 1,
      deleted_at: '2026-01-01T00:00:00.000Z',
    },
  ));
  await assertFails(setDoc(
    doc(firestore, 'users/approved-user/orders/order-2'),
    { id: 'wrong-id', user_id: 'approved-user', is_deleted: 1 },
  ));
});

test('approved users cannot read private security collections', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  for (const collectionName of [
    '_otpChallenges',
    '_otpRateLimits',
    '_otpTokenUses',
    '_authAccounts',
    '_authRateLimits',
    '_usernames',
  ]) {
    await assertFails(getDoc(doc(firestore, collectionName, 'record-1')));
  }
});
