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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
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

async function seedAccess(uid, status, role = 'Staff', active = false,
    accessGeneration = status === 'pending' ? 0 : 1) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'accountAccess', uid), {
      uid,
      status,
      role,
      active,
      accessGeneration,
    });
  });
}

function defaultUsername(uid) {
  return `${uid.replace(/[^a-z0-9_]/g, '_')}_user`;
}

function businessEvent(uid, id, overrides = {}) {
  return {
    id,
    user_id: uid,
    subject_type: 'order',
    subject_id: 'order-1',
    event_type: 'payment',
    amount_centavos: 1000,
    occurred_at: '2026-01-01T00:00:00.000Z',
    recorded_at: '2026-01-01T00:00:00.000Z',
    payment_method: 'cash_on_delivery',
    reference: null,
    related_event_id: null,
    reason: null,
    command_id: id,
    provenance: 'native',
    source_type: null,
    source_id: null,
    schema_version: 1,
    ...overrides,
  };
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
      accessGeneration: 0,
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
    accessGeneration: 0,
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
    accessGeneration: increment(1),
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

test('administrator can suspend and reactivate Staff with generation increments',
    async () => {
      await seedAccess('admin-user', 'approved', 'Administrator', true);
      await seedPending('target-user');
      const administrator = authenticated('admin-user');
      await assertSucceeds(
        reviewBatch(
          administrator,
          'admin-user',
          'target-user',
          'approved',
        ).commit(),
      );
      await assertSucceeds(
        reviewBatch(
          administrator,
          'admin-user',
          'target-user',
          'suspended',
        ).commit(),
      );
      let access = await getDoc(doc(
        administrator,
        'accountAccess/target-user',
      ));
      assert.equal(access.data().accessGeneration, 2);
      await assertSucceeds(
        reviewBatch(
          administrator,
          'admin-user',
          'target-user',
          'approved',
        ).commit(),
      );
      access = await getDoc(doc(
        administrator,
        'accountAccess/target-user',
      ));
      assert.equal(access.data().accessGeneration, 3);
    });

test('Staff cannot change lifecycle state or generation', async () => {
  await seedAccess('admin-user', 'approved', 'Administrator', true);
  await seedPending('target-user');
  const staff = authenticated('target-user');
  const batch = reviewBatch(staff, 'target-user', 'target-user', 'approved');
  await assertFails(batch.commit());
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

test('revision-aware writes advance exactly one and reject stale updates', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const product = doc(firestore, 'users/approved-user/products/product-1');
  await assertSucceeds(setDoc(product, {
    id: 'product-1',
    user_id: 'approved-user',
    revision: 1,
    base_revision: 0,
    writer_device_id: 'DEVICE01',
    updated_at: new Date().toISOString(),
  }));
  await assertSucceeds(updateDoc(product, {
    revision: 2,
    base_revision: 1,
    writer_device_id: 'DEVICE01',
    updated_at: new Date().toISOString(),
  }));
  await assertFails(updateDoc(product, {
    revision: 2,
    base_revision: 1,
    writer_device_id: 'DEVICE02',
    updated_at: new Date().toISOString(),
  }));
  await assertFails(updateDoc(product, {
    revision: 4,
    base_revision: 2,
    writer_device_id: 'DEVICE02',
    updated_at: new Date().toISOString(),
  }));
});

test('Staff cannot delete, restore, or permanently purge business entities', async () => {
  await seedAccess('staff-user', 'approved', 'Staff', true);
  const firestore = authenticated('staff-user');
  for (const collectionName of [
    'products',
    'debts',
    'resellers',
    'custom_orders',
  ]) {
    const reference = doc(
      firestore,
      `users/staff-user/${collectionName}/record-1`,
    );
    await assertSucceeds(setDoc(reference, {
      id: 'record-1',
      user_id: 'staff-user',
      is_deleted: 0,
      deleted_at: null,
    }));
    await assertFails(updateDoc(reference, {
      is_deleted: 1,
      deleted_at: new Date().toISOString(),
    }));
    await assertFails(deleteDoc(reference));
  }
});

test('Administrator can delete, restore, and purge owned business entities', async () => {
  await seedAccess('admin-user', 'approved', 'Administrator', true);
  const firestore = authenticated('admin-user');
  for (const collectionName of [
    'products',
    'debts',
    'resellers',
    'custom_orders',
  ]) {
    const reference = doc(
      firestore,
      `users/admin-user/${collectionName}/record-1`,
    );
    await assertSucceeds(setDoc(reference, {
      id: 'record-1',
      user_id: 'admin-user',
      is_deleted: 0,
      deleted_at: null,
    }));
    await assertSucceeds(updateDoc(reference, {
      is_deleted: 1,
      deleted_at: new Date().toISOString(),
    }));
    await assertSucceeds(updateDoc(reference, {
      is_deleted: 0,
      deleted_at: null,
    }));
    await assertSucceeds(deleteDoc(reference));
  }
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

test('atomic order finalization may allocate one canonical command result', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const batch = writeBatch(firestore);
  const order = doc(firestore, 'users/approved-user/orders/order-1');
  const counter = doc(firestore, 'users/approved-user/counters/orders');
  const command = doc(
    firestore,
    'users/approved-user/order_commands/command-1',
  );
  batch.set(order, {
    id: 'order-1',
    user_id: 'approved-user',
    order_id: 'KNZ-000001',
    command_id: 'command-1',
    status: 'Pending',
    items: [{ product_id: 'product-1', quantity: 1 }],
    is_deleted: 0,
  });
  batch.set(counter, {
    id: 'orders',
    user_id: 'approved-user',
    last_value: 1,
  });
  batch.set(command, {
    id: 'command-1',
    user_id: 'approved-user',
    order_doc_id: 'order-1',
    canonical_order_id: 'KNZ-000001',
    sequence_value: 1,
  });

  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(command, { canonical_order_id: 'KNZ-000002' }));
  await assertFails(deleteDoc(command));
});

test('canonical command must match its order and sequence counter', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const batch = writeBatch(firestore);
  batch.set(doc(firestore, 'users/approved-user/orders/order-1'), {
    id: 'order-1',
    user_id: 'approved-user',
    order_id: 'KNZ-000001',
    command_id: 'command-1',
    status: 'Pending',
    items: [],
    is_deleted: 0,
  });
  batch.set(doc(firestore, 'users/approved-user/counters/orders'), {
    id: 'orders',
    user_id: 'approved-user',
    last_value: 1,
  });
  batch.set(
    doc(firestore, 'users/approved-user/order_commands/command-1'),
    {
      id: 'command-1',
      user_id: 'approved-user',
      order_doc_id: 'order-1',
      canonical_order_id: 'KNZ-999999',
      sequence_value: 1,
    },
  );
  await assertFails(batch.commit());
});

test('debt payment and command records are append-only and allocation-safe', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const debt = doc(firestore, 'users/approved-user/debts/debt-1');
  await assertSucceeds(setDoc(debt, {
    id: 'debt-1',
    user_id: 'approved-user',
    revision: 1,
    base_revision: 0,
    writer_device_id: 'DEVICE01',
    updated_at: new Date().toISOString(),
  }));
  const payment = doc(
    firestore,
    'users/approved-user/debts/debt-1/payments/payment-1',
  );
  const command = doc(
    firestore,
    'users/approved-user/payment_commands/debt-collection-payment-1',
  );
  const batch = writeBatch(firestore);
  batch.update(debt, {
    revision: 2,
    base_revision: 1,
    writer_device_id: 'DEVICE01',
    updated_at: new Date().toISOString(),
  });
  batch.set(payment, {
    id: 'payment-1',
    debt_id: 'debt-1',
    amount_centavos: 1000,
    interest_applied_centavos: 200,
    principal_applied_centavos: 800,
    paid_at: new Date().toISOString(),
    payment_method: 'cash',
    reference: null,
    note: null,
    schema_version: 1,
  });
  batch.set(command, {
    id: 'debt-collection-payment-1',
    user_id: 'approved-user',
    parent_id: 'debt-1',
    payment_id: 'payment-1',
    event_id: 'debt-collection-payment-1',
    resulting_revision: 2,
  });
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(payment, { amount_centavos: 2000 }));
  await assertFails(deleteDoc(payment));
  await assertFails(updateDoc(command, { resulting_revision: 3 }));
});

test('debt payment rejects mismatched allocation', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/approved-user/debts/debt-1'), {
      id: 'debt-1',
      user_id: 'approved-user',
    });
  });
  await assertFails(setDoc(
    doc(firestore, 'users/approved-user/debts/debt-1/payments/payment-1'),
    {
      id: 'payment-1',
      debt_id: 'debt-1',
      amount_centavos: 1000,
      interest_applied_centavos: 200,
      principal_applied_centavos: 700,
      paid_at: new Date().toISOString(),
      payment_method: 'cash',
      reference: null,
      note: null,
      schema_version: 1,
    },
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

test('approved users can create and read valid immutable business events', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const reference = doc(
    firestore,
    'users/approved-user/business_events/event-1',
  );
  await assertSucceeds(setDoc(
    reference,
    businessEvent('approved-user', 'event-1'),
  ));
  await assertSucceeds(getDoc(reference));
  await assertFails(updateDoc(reference, { amount_centavos: 900 }));
  await assertFails(deleteDoc(reference));
});

test('business event rules reject malformed and cross-owner facts', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  const pathPrefix = 'users/approved-user/business_events';
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/bad-amount`),
    businessEvent('approved-user', 'bad-amount', { amount_centavos: 0 }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/bad-subject`),
    businessEvent('approved-user', 'bad-subject', {
      subject_type: 'debt',
      event_type: 'payment',
    }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/wrong-owner`),
    businessEvent('another-user', 'wrong-owner'),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/bad-delivery`),
    businessEvent('approved-user', 'bad-delivery', {
      event_type: 'delivery',
      amount_centavos: 1000,
      payment_method: null,
    }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/missing-time`),
    businessEvent('approved-user', 'missing-time', { occurred_at: null }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/bad-tender`),
    businessEvent('approved-user', 'bad-tender', { payment_method: 'utang' }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/missing-reference`),
    businessEvent('approved-user', 'missing-reference', {
      payment_method: 'gcash',
      reference: null,
    }),
  ));
  await assertFails(setDoc(
    doc(firestore, `${pathPrefix}/partial-source`),
    businessEvent('approved-user', 'partial-source', {
      source_type: 'debt_payment',
      source_id: null,
    }),
  ));
});

test('pending users cannot create business events', async () => {
  await seedAccess('pending-user', 'pending', 'Staff', false);
  const firestore = authenticated('pending-user');
  await assertFails(setDoc(
    doc(firestore, 'users/pending-user/business_events/event-1'),
    businessEvent('pending-user', 'event-1'),
  ));
});

test('approved users cannot read private security collections', async () => {
  await seedAccess('approved-user', 'approved', 'Staff', true);
  const firestore = authenticated('approved-user');
  for (const collectionName of [
    '_authAccounts',
    '_authRateLimits',
    '_usernames',
    '_unrecognizedPrivate',
  ]) {
    await assertFails(getDoc(doc(firestore, collectionName, 'record-1')));
  }
});
