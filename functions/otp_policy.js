'use strict';

const { safeEqualHex } = require('./otp_helpers');

class OtpPolicyError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = 'OtpPolicyError';
    this.code = code;
    this.details = details;
  }
}

function requireTrustedCallerPolicy({ auth, app, enforceAppCheck }) {
  if (!auth || typeof auth.uid !== 'string' || auth.uid.length === 0) {
    throw new OtpPolicyError(
      'unauthenticated',
      'Sign in is required to request an OTP.',
    );
  }
  if (enforceAppCheck && !app) {
    throw new OtpPolicyError(
      'failed-precondition',
      'App verification is required.',
    );
  }
  return auth.uid;
}

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : 0;
}

function currentWindow(record, nowMs, rateWindowMs) {
  const startedAt = timestampMillis(record && record.windowStartedAt);
  if (!startedAt || nowMs - startedAt >= rateWindowMs) {
    return { startedAt: nowMs, count: 0 };
  }
  return { startedAt, count: Number(record.count) || 0 };
}

function evaluateRequestPolicy({
  emailRate,
  requesterRate,
  nowMs,
  rateWindowMs,
  maxEmailRequests,
  maxRequesterRequests,
}) {
  const emailWindow = currentWindow(emailRate, nowMs, rateWindowMs);
  const requesterWindow = currentWindow(requesterRate, nowMs, rateWindowMs);
  const cooldownRemaining = timestampMillis(emailRate && emailRate.nextAllowedAt) - nowMs;
  if (cooldownRemaining > 0) {
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil(cooldownRemaining / 1000)),
    };
  }
  if (emailWindow.count >= maxEmailRequests) {
    return {
      allowed: false,
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((emailWindow.startedAt + rateWindowMs - nowMs) / 1000),
      ),
    };
  }
  if (requesterWindow.count >= maxRequesterRequests) {
    return {
      allowed: false,
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((requesterWindow.startedAt + rateWindowMs - nowMs) / 1000),
      ),
    };
  }
  return { allowed: true, emailWindow, requesterWindow };
}

function evaluateChallengePolicy({
  challenge,
  requesterUid,
  nowMs,
  submittedHash,
  defaultMaxAttempts,
}) {
  if (challenge.requesterUid !== requesterUid) {
    return {
      ok: false,
      code: 'permission-denied',
      message: 'OTP challenge is not valid for this session.',
    };
  }
  if (challenge.status !== 'pending') {
    return {
      ok: false,
      code: 'failed-precondition',
      message: 'This OTP challenge can no longer be used.',
    };
  }
  if (timestampMillis(challenge.expiresAt) <= nowMs) {
    return {
      ok: false,
      code: 'deadline-exceeded',
      message: 'The OTP has expired. Request a new code.',
      update: { status: 'expired' },
    };
  }
  if (submittedHash === undefined) return { ok: true };
  if (!safeEqualHex(submittedHash, challenge.otpHash)) {
    const attempts = (Number(challenge.attempts) || 0) + 1;
    const maxAttempts = Number(challenge.maxAttempts) || defaultMaxAttempts;
    const locked = attempts >= maxAttempts;
    return {
      ok: false,
      code: locked ? 'resource-exhausted' : 'invalid-argument',
      message: locked
        ? 'Too many incorrect attempts. Request a new code.'
        : 'Invalid OTP. Please check your email and try again.',
      attemptsRemaining: Math.max(0, maxAttempts - attempts),
      update: { attempts, status: locked ? 'locked' : 'pending', locked },
    };
  }
  return { ok: true };
}

module.exports = {
  OtpPolicyError,
  currentWindow,
  evaluateChallengePolicy,
  evaluateRequestPolicy,
  requireTrustedCallerPolicy,
  timestampMillis,
};
