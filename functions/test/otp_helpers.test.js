'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  ValidationError,
  generateOtp,
  hashOtp,
  normalizeEmail,
  normalizePurpose,
  safeEqualHex,
  signVerificationToken,
  validateChallengeVerification,
  verifyVerificationToken,
} = require('../otp_helpers');

const secret = 'test-only-secret-that-is-at-least-32-characters-long';

test('normalizes email and accepts only supported purposes', () => {
  assert.equal(normalizeEmail('  Admin@Example.COM '), 'admin@example.com');
  assert.equal(normalizePurpose('register'), 'register');
  assert.equal(normalizePurpose('resetPassword'), 'resetPassword');
  assert.throws(() => normalizeEmail('not-an-email'), ValidationError);
  assert.throws(() => normalizePurpose('login'), ValidationError);
});

test('generates a six digit server OTP', () => {
  assert.equal(generateOtp(() => 123456), '123456');
  assert.match(generateOtp(), /^\d{6}$/);
});

test('validates challenge IDs and OTP shape', () => {
  assert.deepEqual(
    validateChallengeVerification({
      challengeId: '12345678-1234-1234-1234-123456789abc',
      otp: '012345',
    }),
    {
      challengeId: '12345678-1234-1234-1234-123456789abc',
      otp: '012345',
    },
  );
  assert.throws(
    () => validateChallengeVerification({ challengeId: 'short', otp: '12345x' }),
    ValidationError,
  );
});

test('binds an OTP hash to challenge, email, and purpose', () => {
  const base = {
    challengeId: '12345678-1234-1234-1234-123456789abc',
    email: 'admin@example.com',
    purpose: 'register',
    otp: '123456',
  };
  const hash = hashOtp(base, secret);
  assert.equal(hash, hashOtp(base, secret));
  assert.ok(safeEqualHex(hash, hashOtp(base, secret)));
  assert.notEqual(hash, hashOtp({ ...base, otp: '654321' }, secret));
});

test('signs, verifies, rejects tampering, and expires verification tokens', () => {
  const payload = {
    jti: 'token-id',
    challengeId: '12345678-1234-1234-1234-123456789abc',
    uid: 'firebase-user-id',
    emailKey: 'email-key',
    purpose: 'resetPassword',
    iat: 1_000,
    exp: 1_120,
  };
  const token = signVerificationToken(payload, secret);
  assert.deepEqual(verifyVerificationToken(token, secret, 1_010), payload);
  assert.throws(
    () => verifyVerificationToken(`${token}tampered`, secret, 1_010),
    ValidationError,
  );
  assert.throws(() => verifyVerificationToken(token, secret, 1_121), ValidationError);
});
