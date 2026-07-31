'use strict';

const USERNAME_PATTERN = /^[a-z0-9_]{3,32}$/;
const REVIEW_STATES = new Set(['approved', 'rejected', 'suspended']);
const ROLES = new Set(['Staff', 'Administrator']);

class AccessValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AccessValidationError';
  }
}

function normalizeUsername(value) {
  if (typeof value !== 'string') {
    throw new AccessValidationError('Enter a valid username.');
  }
  const username = value.trim().toLowerCase();
  if (!USERNAME_PATTERN.test(username)) {
    throw new AccessValidationError(
      'Username must be 3-32 lowercase letters, numbers, or underscores.',
    );
  }
  return username;
}

function normalizeName(value) {
  if (typeof value !== 'string') {
    throw new AccessValidationError('Name is required.');
  }
  const name = value.trim().replace(/\s+/g, ' ');
  if (!name || name.length > 80 || /[\u0000-\u001f\u007f]/.test(name)) {
    throw new AccessValidationError('Enter a valid name.');
  }
  return name;
}

function validateReview(data) {
  const input = data && typeof data === 'object' ? data : {};
  const uid = typeof input.uid === 'string' ? input.uid.trim() : '';
  if (!uid || uid.length > 128) {
    throw new AccessValidationError('A valid account is required.');
  }
  if (!REVIEW_STATES.has(input.decision)) {
    throw new AccessValidationError('Invalid review decision.');
  }
  const role = input.decision === 'approved' ? (input.role || 'Staff') : 'Staff';
  if (!ROLES.has(role)) {
    throw new AccessValidationError('Invalid account role.');
  }
  return { uid, decision: input.decision, role };
}

module.exports = {
  AccessValidationError,
  normalizeName,
  normalizeUsername,
  validateReview,
};
