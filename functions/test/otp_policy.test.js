'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  OtpPolicyError,
  evaluateChallengePolicy,
  evaluateRequestPolicy,
  requireTrustedCallerPolicy,
} = require('../otp_policy');

const timestamp = (milliseconds) => ({ toMillis: () => milliseconds });

test('requires authentication and optional App Check', () => {
  assert.throws(
    () => requireTrustedCallerPolicy({ enforceAppCheck: false }),
    (error) => error instanceof OtpPolicyError && error.code === 'unauthenticated',
  );
  assert.throws(
    () => requireTrustedCallerPolicy({
      auth: { uid: 'user-1' },
      enforceAppCheck: true,
    }),
    (error) => error instanceof OtpPolicyError && error.code === 'failed-precondition',
  );
  assert.equal(requireTrustedCallerPolicy({
    auth: { uid: 'user-1' },
    app: { appId: 'test-app' },
    enforceAppCheck: true,
  }), 'user-1');
});

test('enforces resend cooldown and email/requester limits', () => {
  const common = {
    nowMs: 10_000,
    rateWindowMs: 60_000,
    maxEmailRequests: 5,
    maxRequesterRequests: 20,
  };
  assert.deepEqual(evaluateRequestPolicy({
    ...common,
    emailRate: { nextAllowedAt: timestamp(15_000) },
    requesterRate: {},
  }), { allowed: false, retryAfterSeconds: 5 });

  const emailLimited = evaluateRequestPolicy({
    ...common,
    emailRate: { windowStartedAt: timestamp(1_000), count: 5 },
    requesterRate: {},
  });
  assert.equal(emailLimited.allowed, false);
  assert.equal(emailLimited.retryAfterSeconds, 51);

  const requesterLimited = evaluateRequestPolicy({
    ...common,
    emailRate: {},
    requesterRate: { windowStartedAt: timestamp(1_000), count: 20 },
  });
  assert.equal(requesterLimited.allowed, false);
  assert.equal(requesterLimited.retryAfterSeconds, 51);
});

test('a completed rate window allows a new request', () => {
  const decision = evaluateRequestPolicy({
    emailRate: { windowStartedAt: timestamp(1_000), count: 5 },
    requesterRate: { windowStartedAt: timestamp(1_000), count: 20 },
    nowMs: 61_000,
    rateWindowMs: 60_000,
    maxEmailRequests: 5,
    maxRequesterRequests: 20,
  });

  assert.equal(decision.allowed, true);
  assert.deepEqual(decision.emailWindow, { startedAt: 61_000, count: 0 });
  assert.deepEqual(decision.requesterWindow, { startedAt: 61_000, count: 0 });
});

test('challenge policy enforces owner, pending state, and expiry', () => {
  const challenge = {
    requesterUid: 'owner',
    status: 'pending',
    expiresAt: timestamp(20_000),
    attempts: 0,
    maxAttempts: 5,
    otpHash: 'aa',
  };
  assert.equal(evaluateChallengePolicy({
    challenge,
    requesterUid: 'other',
    nowMs: 10_000,
    submittedHash: 'aa',
    defaultMaxAttempts: 5,
  }).code, 'permission-denied');
  assert.equal(evaluateChallengePolicy({
    challenge: { ...challenge, status: 'superseded' },
    requesterUid: 'owner',
    nowMs: 10_000,
    submittedHash: 'aa',
    defaultMaxAttempts: 5,
  }).code, 'failed-precondition');
  const expired = evaluateChallengePolicy({
    challenge,
    requesterUid: 'owner',
    nowMs: 20_000,
    submittedHash: 'aa',
    defaultMaxAttempts: 5,
  });
  assert.equal(expired.code, 'deadline-exceeded');
  assert.deepEqual(expired.update, { status: 'expired' });
  assert.deepEqual(evaluateChallengePolicy({
    challenge,
    requesterUid: 'owner',
    nowMs: 10_000,
    defaultMaxAttempts: 5,
  }), { ok: true });
});

test('challenge attempts decrement and lock at the configured limit', () => {
  const challenge = {
    requesterUid: 'owner',
    status: 'pending',
    expiresAt: timestamp(20_000),
    attempts: 3,
    maxAttempts: 5,
    otpHash: 'aa',
  };
  const retry = evaluateChallengePolicy({
    challenge,
    requesterUid: 'owner',
    nowMs: 10_000,
    submittedHash: 'bb',
    defaultMaxAttempts: 5,
  });
  assert.equal(retry.code, 'invalid-argument');
  assert.equal(retry.attemptsRemaining, 1);
  assert.deepEqual(retry.update, { attempts: 4, status: 'pending', locked: false });

  const locked = evaluateChallengePolicy({
    challenge: { ...challenge, attempts: 4 },
    requesterUid: 'owner',
    nowMs: 10_000,
    submittedHash: 'bb',
    defaultMaxAttempts: 5,
  });
  assert.equal(locked.code, 'resource-exhausted');
  assert.equal(locked.attemptsRemaining, 0);
  assert.deepEqual(locked.update, { attempts: 5, status: 'locked', locked: true });
});

test('matching challenge hash verifies successfully', () => {
  assert.deepEqual(evaluateChallengePolicy({
    challenge: {
      requesterUid: 'owner',
      status: 'pending',
      expiresAt: timestamp(20_000),
      attempts: 0,
      maxAttempts: 5,
      otpHash: 'aabb',
    },
    requesterUid: 'owner',
    nowMs: 10_000,
    submittedHash: 'aabb',
    defaultMaxAttempts: 5,
  }), { ok: true });
});
