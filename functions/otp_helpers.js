'use strict';

const crypto = require('crypto');

const PURPOSES = new Set(['register', 'resetPassword']);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CHALLENGE_ID_PATTERN = /^[A-Za-z0-9_-]{20,128}$/;
const OTP_PATTERN = /^\d{6}$/;

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}

function normalizeEmail(value) {
  if (typeof value !== 'string') {
    throw new ValidationError('A valid email address is required.');
  }
  const email = value.trim().toLowerCase();
  if (email.length < 3 || email.length > 254 || !EMAIL_PATTERN.test(email)) {
    throw new ValidationError('A valid email address is required.');
  }
  return email;
}

function normalizePurpose(value) {
  if (typeof value !== 'string' || !PURPOSES.has(value)) {
    throw new ValidationError('Invalid OTP purpose.');
  }
  return value;
}

function normalizeOtp(value) {
  if (typeof value !== 'string' || !OTP_PATTERN.test(value)) {
    throw new ValidationError('Enter the complete 6-digit OTP.');
  }
  return value;
}

function normalizeChallengeId(value) {
  if (typeof value !== 'string' || !CHALLENGE_ID_PATTERN.test(value)) {
    throw new ValidationError('Invalid OTP challenge.');
  }
  return value;
}

function validateChallengeRequest(data) {
  const input = data && typeof data === 'object' ? data : {};
  return {
    email: normalizeEmail(input.email),
    purpose: normalizePurpose(input.purpose),
  };
}

function validateChallengeVerification(data) {
  const input = data && typeof data === 'object' ? data : {};
  return {
    challengeId: normalizeChallengeId(input.challengeId),
    otp: normalizeOtp(input.otp),
  };
}

function generateOtp(randomInt = crypto.randomInt) {
  return String(randomInt(100000, 1000000));
}

function hmacHex(secret, value) {
  if (typeof secret !== 'string' || secret.length < 32) {
    throw new Error('OTP_SECURITY_SECRET must contain at least 32 characters.');
  }
  return crypto.createHmac('sha256', secret).update(value).digest('hex');
}

function identityKey(kind, value, secret) {
  return hmacHex(secret, `${kind}\u0000${value}`);
}

function hashOtp({ challengeId, email, purpose, otp }, secret) {
  return hmacHex(
    secret,
    `otp\u0000${challengeId}\u0000${email}\u0000${purpose}\u0000${otp}`,
  );
}

function safeEqualHex(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  if (!/^[0-9a-f]+$/i.test(left) || !/^[0-9a-f]+$/i.test(right)) return false;
  const leftBuffer = Buffer.from(left, 'hex');
  const rightBuffer = Buffer.from(right, 'hex');
  return leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function signVerificationToken(payload, secret) {
  const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  const signature = hmacHex(secret, `verification-token\u0000${encoded}`);
  return `${encoded}.${signature}`;
}

function verifyVerificationToken(token, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (typeof token !== 'string' || token.length > 4096) {
    throw new ValidationError('Invalid verification token.');
  }
  const parts = token.split('.');
  if (parts.length !== 2) {
    throw new ValidationError('Invalid verification token.');
  }
  const [encoded, signature] = parts;
  const expected = hmacHex(secret, `verification-token\u0000${encoded}`);
  if (!safeEqualHex(signature, expected)) {
    throw new ValidationError('Invalid verification token.');
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  } catch (_) {
    throw new ValidationError('Invalid verification token.');
  }

  if (!payload || typeof payload !== 'object' ||
      typeof payload.jti !== 'string' ||
      typeof payload.challengeId !== 'string' ||
      typeof payload.uid !== 'string' ||
      typeof payload.emailKey !== 'string' ||
      !PURPOSES.has(payload.purpose) ||
      !Number.isInteger(payload.iat) ||
      !Number.isInteger(payload.exp) ||
      payload.exp <= nowSeconds ||
      payload.iat > nowSeconds + 30) {
    throw new ValidationError('Verification token is invalid or expired.');
  }
  return payload;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

module.exports = {
  ValidationError,
  escapeHtml,
  generateOtp,
  hashOtp,
  identityKey,
  normalizeChallengeId,
  normalizeEmail,
  normalizeOtp,
  normalizePurpose,
  safeEqualHex,
  signVerificationToken,
  validateChallengeRequest,
  validateChallengeVerification,
  verifyVerificationToken,
};
