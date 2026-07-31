'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  AccessValidationError,
  normalizeName,
  normalizeUsername,
  validateReview,
} = require('../access_helpers');

test('normalizes centrally unique username metadata', () => {
  assert.equal(normalizeUsername('  Staff_01 '), 'staff_01');
  assert.throws(() => normalizeUsername('two words'), AccessValidationError);
});

test('normalizes registration display names', () => {
  assert.equal(normalizeName('  KNZ   Staff  '), 'KNZ Staff');
  assert.throws(() => normalizeName('bad\u0000name'), AccessValidationError);
});

test('validates explicit review states and Staff default role', () => {
  assert.deepEqual(
    validateReview({ uid: 'target-uid', decision: 'approved' }),
    { uid: 'target-uid', decision: 'approved', role: 'Staff' },
  );
  assert.deepEqual(
    validateReview({ uid: 'target-uid', decision: 'suspended', role: 'Administrator' }),
    { uid: 'target-uid', decision: 'suspended', role: 'Staff' },
  );
  assert.throws(
    () => validateReview({ uid: 'target-uid', decision: 'pending' }),
    AccessValidationError,
  );
});
