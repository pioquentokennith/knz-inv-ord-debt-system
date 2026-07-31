'use strict';

const crypto = require('crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { defineBoolean, defineSecret, defineString } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

const {
  ValidationError,
  generateOtp,
  hashOtp,
  identityKey,
  normalizeEmail,
  normalizePurpose,
  signVerificationToken,
  validateChallengeRequest,
  validateChallengeVerification,
} = require('./otp_helpers');
const {
  BackendConfigurationError,
  readOtpSecuritySecret,
  sendOtpEmail,
} = require('./otp_delivery');
const {
  AccessValidationError,
  normalizeName: normalizeAccessName,
  normalizeUsername: normalizeAccessUsername,
  validateReview,
} = require('./access_helpers');
const {
  OtpPolicyError,
  evaluateChallengePolicy,
  evaluateRequestPolicy,
  requireTrustedCallerPolicy,
  timestampMillis,
} = require('./otp_policy');

initializeApp();
const db = getFirestore();

const BREVO_API_KEY = defineSecret('BREVO_API_KEY');
const OTP_SECURITY_SECRET = defineSecret('OTP_SECURITY_SECRET');
const BREVO_SENDER_EMAIL = defineString('BREVO_SENDER_EMAIL', {
  default: 'unconfigured@example.invalid',
});
const BREVO_SENDER_NAME = defineString('BREVO_SENDER_NAME', {
  default: 'KNZ Scent',
});
const OTP_ENFORCE_APP_CHECK = defineBoolean('OTP_ENFORCE_APP_CHECK', {
  default: false,
});

const REGION = 'us-central1';
const CHALLENGES = '_otpChallenges';
const RATE_LIMITS = '_otpRateLimits';
const ACCOUNT_ACCESS = 'accountAccess';
const REGISTRATION_REQUESTS = 'registrationRequests';
const USERNAMES = '_usernames';
const OTP_LIFETIME_MS = 10 * 60 * 1000;
const TOKEN_LIFETIME_SECONDS = 2 * 60;
const COOLDOWN_MS = 60 * 1000;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const MAX_EMAIL_REQUESTS_PER_WINDOW = 5;
const MAX_REQUESTER_REQUESTS_PER_WINDOW = 20;
const MAX_VERIFY_ATTEMPTS = 5;
const SECURITY_RECORD_RETENTION_MS = 24 * 60 * 60 * 1000;

const requestOptions = {
  region: REGION,
  timeoutSeconds: 30,
  memory: '256MiB',
  secrets: [BREVO_API_KEY, OTP_SECURITY_SECRET],
};

const verificationOptions = {
  region: REGION,
  timeoutSeconds: 15,
  memory: '256MiB',
  secrets: [OTP_SECURITY_SECRET],
};

const accessOptions = {
  region: REGION,
  timeoutSeconds: 15,
  memory: '256MiB',
};

function requireNativeCaller(request) {
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  const email = request.auth?.token?.email;
  if (!request.auth?.uid || provider === 'anonymous' || typeof email !== 'string') {
    throw new HttpsError('unauthenticated', 'Firebase email authentication is required.');
  }
  return {
    uid: request.auth.uid,
    email: normalizeEmail(email),
    emailVerified: request.auth.token.email_verified === true,
  };
}

async function requireAdministrator(request) {
  const caller = requireNativeCaller(request);
  const snapshot = await db.collection(ACCOUNT_ACCESS).doc(caller.uid).get();
  const access = snapshot.data() || {};
  if (access.status !== 'approved' || access.active !== true ||
      access.role !== 'Administrator') {
    throw new HttpsError('permission-denied', 'Administrator approval is required.');
  }
  return caller;
}

function requireTrustedCaller(request) {
  try {
    return requireTrustedCallerPolicy({
      auth: request.auth,
      app: request.app,
      enforceAppCheck: OTP_ENFORCE_APP_CHECK.value(),
    });
  } catch (error) {
    if (error instanceof OtpPolicyError) {
      throw new HttpsError(error.code, error.message, error.details);
    }
    throw error;
  }
}

function asHttpsValidationError(error) {
  if (error instanceof ValidationError) {
    return new HttpsError('invalid-argument', error.message);
  }
  return error;
}

function otpSecuritySecret() {
  try {
    return readOtpSecuritySecret(OTP_SECURITY_SECRET.value());
  } catch (error) {
    logger.error('OTP backend configuration is unavailable.', {
      errorType: error && error.name ? error.name : 'Error',
    });
    throw new HttpsError(
      'failed-precondition',
      'Email verification is temporarily unavailable.',
    );
  }
}

exports.requestOtp = onCall(requestOptions, async (request) => {
  const requesterUid = requireTrustedCaller(request);
  let input;
  try {
    input = validateChallengeRequest(request.data);
  } catch (error) {
    throw asHttpsValidationError(error);
  }

  if (input.purpose === 'register') {
    throw new HttpsError(
      'failed-precondition',
      'New account registration requires administrator approval and is temporarily unavailable.',
    );
  }

  const secret = otpSecuritySecret();
  const nowMs = Date.now();
  const challengeId = crypto.randomUUID();
  const otp = generateOtp();
  const emailKey = identityKey('email', input.email, secret);
  const requesterKey = identityKey('requester', requesterUid, secret);
  const otpHash = hashOtp({
    challengeId,
    email: input.email,
    purpose: input.purpose,
    otp,
  }, secret);

  const emailRateRef = db.collection(RATE_LIMITS).doc(`email_${emailKey}`);
  const requesterRateRef = db.collection(RATE_LIMITS).doc(`requester_${requesterKey}`);
  const challengeRef = db.collection(CHALLENGES).doc(challengeId);

  const reservation = await db.runTransaction(async (transaction) => {
    const [emailRateSnap, requesterRateSnap] = await Promise.all([
      transaction.get(emailRateRef),
      transaction.get(requesterRateRef),
    ]);
    const emailRate = emailRateSnap.data() || {};
    const requesterRate = requesterRateSnap.data() || {};
    const policy = evaluateRequestPolicy({
      emailRate,
      requesterRate,
      nowMs,
      rateWindowMs: RATE_WINDOW_MS,
      maxEmailRequests: MAX_EMAIL_REQUESTS_PER_WINDOW,
      maxRequesterRequests: MAX_REQUESTER_REQUESTS_PER_WINDOW,
    });
    if (!policy.allowed) return policy;
    const { emailWindow, requesterWindow } = policy;

    const createdAt = Timestamp.fromMillis(nowMs);
    const expiresAt = Timestamp.fromMillis(nowMs + OTP_LIFETIME_MS);
    const deleteAt = Timestamp.fromMillis(
      nowMs + OTP_LIFETIME_MS + SECURITY_RECORD_RETENTION_MS,
    );

    transaction.create(challengeRef, {
      email: input.email,
      emailKey,
      purpose: input.purpose,
      otpHash,
      requesterUid,
      attempts: 0,
      maxAttempts: MAX_VERIFY_ATTEMPTS,
      status: 'pending_delivery',
      previousChallengeId: typeof emailRate.activeChallengeId === 'string'
        ? emailRate.activeChallengeId
        : null,
      createdAt,
      expiresAt,
      deleteAt,
    });
    transaction.set(emailRateRef, {
      kind: 'email',
      count: emailWindow.count + 1,
      windowStartedAt: Timestamp.fromMillis(emailWindow.startedAt),
      nextAllowedAt: Timestamp.fromMillis(nowMs + COOLDOWN_MS),
      activeChallengeId: typeof emailRate.activeChallengeId === 'string'
        ? emailRate.activeChallengeId
        : null,
      updatedAt: createdAt,
      deleteAt: Timestamp.fromMillis(nowMs + RATE_WINDOW_MS + SECURITY_RECORD_RETENTION_MS),
    });
    transaction.set(requesterRateRef, {
      kind: 'requester',
      count: requesterWindow.count + 1,
      windowStartedAt: Timestamp.fromMillis(requesterWindow.startedAt),
      updatedAt: createdAt,
      deleteAt: Timestamp.fromMillis(nowMs + RATE_WINDOW_MS + SECURITY_RECORD_RETENTION_MS),
    });
    return { allowed: true };
  });

  if (!reservation.allowed) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many OTP requests. Please wait before trying again.',
      { retryAfterSeconds: reservation.retryAfterSeconds },
    );
  }

  try {
    await sendOtpEmail({
      email: input.email,
      otp,
      purpose: input.purpose,
      apiKey: BREVO_API_KEY.value(),
      senderEmail: BREVO_SENDER_EMAIL.value(),
      senderName: BREVO_SENDER_NAME.value(),
    });
    await db.runTransaction(async (transaction) => {
      const challengeSnap = await transaction.get(challengeRef);
      if (!challengeSnap.exists || challengeSnap.data().status !== 'pending_delivery') {
        throw new Error('OTP challenge delivery state changed unexpectedly.');
      }
      const previousChallengeId = challengeSnap.data().previousChallengeId;
      let previousChallengeSnap = null;
      if (typeof previousChallengeId === 'string') {
        previousChallengeSnap = await transaction.get(
          db.collection(CHALLENGES).doc(previousChallengeId),
        );
      }
      const deliveredAt = Timestamp.now();
      if (previousChallengeSnap && previousChallengeSnap.exists &&
          previousChallengeSnap.data().status === 'pending') {
        transaction.update(previousChallengeSnap.ref, {
          status: 'superseded',
          supersededAt: deliveredAt,
        });
      }
      transaction.update(challengeRef, {
        status: 'pending',
        deliveredAt,
      });
      transaction.set(emailRateRef, {
        activeChallengeId: challengeId,
        updatedAt: deliveredAt,
      }, { merge: true });
    });
  } catch (error) {
    await challengeRef.update({
      status: 'delivery_failed',
      deliveryFailedAt: Timestamp.now(),
    }).catch(() => undefined);
    logger.error('OTP delivery failed.', {
      challengeId,
      errorType: error && error.name ? error.name : 'Error',
    });
    if (error instanceof BackendConfigurationError) {
      throw new HttpsError(
        'failed-precondition',
        'Email verification is temporarily unavailable.',
      );
    }
    throw new HttpsError('internal',
      'The verification email could not be sent. Please try again later.');
  }

  return {
    challengeId,
    expiresInSeconds: Math.floor(OTP_LIFETIME_MS / 1000),
    cooldownSeconds: Math.floor(COOLDOWN_MS / 1000),
  };
});

exports.verifyOtp = onCall(verificationOptions, async (request) => {
  const requesterUid = requireTrustedCaller(request);
  let input;
  try {
    input = validateChallengeVerification(request.data);
  } catch (error) {
    throw asHttpsValidationError(error);
  }

  const secret = otpSecuritySecret();
  const nowMs = Date.now();
  const challengeRef = db.collection(CHALLENGES).doc(input.challengeId);

  const result = await db.runTransaction(async (transaction) => {
    const challengeSnap = await transaction.get(challengeRef);
    if (!challengeSnap.exists) {
      return { ok: false, code: 'not-found', message: 'OTP challenge is invalid or expired.' };
    }
    const challenge = challengeSnap.data();
    const precondition = evaluateChallengePolicy({
      challenge,
      requesterUid,
      nowMs,
      defaultMaxAttempts: MAX_VERIFY_ATTEMPTS,
    });
    if (!precondition.ok && precondition.update?.status === 'expired') {
      transaction.update(challengeRef, {
        status: 'expired',
        expiredAt: Timestamp.fromMillis(nowMs),
      });
      return precondition;
    }
    if (!precondition.ok) return precondition;

    const submittedHash = hashOtp({
      challengeId: input.challengeId,
      email: challenge.email,
      purpose: challenge.purpose,
      otp: input.otp,
    }, secret);
    const policy = evaluateChallengePolicy({
      challenge,
      requesterUid,
      nowMs,
      submittedHash,
      defaultMaxAttempts: MAX_VERIFY_ATTEMPTS,
    });
    if (!policy.ok && policy.update) {
      transaction.update(challengeRef, {
        attempts: policy.update.attempts,
        status: policy.update.status,
        lastAttemptAt: Timestamp.fromMillis(nowMs),
        ...(policy.update.locked ? { lockedAt: Timestamp.fromMillis(nowMs) } : {}),
      });
      return policy;
    }
    if (!policy.ok) return policy;

    const issuedAt = Math.floor(nowMs / 1000);
    const payload = {
      jti: crypto.randomUUID(),
      challengeId: input.challengeId,
      uid: requesterUid,
      emailKey: challenge.emailKey,
      purpose: challenge.purpose,
      iat: issuedAt,
      exp: issuedAt + TOKEN_LIFETIME_SECONDS,
    };
    const verificationToken = signVerificationToken(payload, secret);
    transaction.update(challengeRef, {
      attempts: (Number(challenge.attempts) || 0) + 1,
      status: 'verified',
      verifiedAt: Timestamp.fromMillis(nowMs),
      tokenId: payload.jti,
    });
    return { ok: true, verificationToken, expiresInSeconds: TOKEN_LIFETIME_SECONDS };
  });

  if (!result.ok) {
    throw new HttpsError(result.code, result.message, {
      attemptsRemaining: result.attemptsRemaining,
    });
  }
  return {
    verificationToken: result.verificationToken,
    expiresInSeconds: result.expiresInSeconds,
  };
});

exports.submitRegistrationRequest = onCall(accessOptions, async (request) => {
  const caller = requireNativeCaller(request);
  let username;
  let name;
  try {
    username = normalizeAccessUsername(request.data?.username);
    name = normalizeAccessName(request.data?.name);
  } catch (error) {
    if (error instanceof AccessValidationError) {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }

  const requestRef = db.collection(REGISTRATION_REQUESTS).doc(caller.uid);
  const accessRef = db.collection(ACCOUNT_ACCESS).doc(caller.uid);
  const usernameRef = db.collection(USERNAMES).doc(username);
  const profileRef = db.collection('users').doc(caller.uid);
  await db.runTransaction(async (transaction) => {
    const [requestSnap, accessSnap, usernameSnap] = await Promise.all([
      transaction.get(requestRef),
      transaction.get(accessRef),
      transaction.get(usernameRef),
    ]);
    if (usernameSnap.exists && usernameSnap.data().uid !== caller.uid) {
      throw new HttpsError('already-exists', 'Username is unavailable.');
    }
    if (requestSnap.exists && requestSnap.data().username !== username) {
      throw new HttpsError(
        'failed-precondition',
        'The pending request username cannot be changed.',
      );
    }

    const now = Timestamp.now();
    const currentStatus = requestSnap.data()?.status;
    const status = ['approved', 'rejected', 'suspended'].includes(currentStatus)
      ? currentStatus
      : 'pending';
    transaction.set(usernameRef, {
      uid: caller.uid,
      reservedAt: usernameSnap.data()?.reservedAt || now,
    });
    transaction.set(requestRef, {
      uid: caller.uid,
      email: caller.email,
      username,
      name,
      status,
      requestedRole: 'Staff',
      emailVerified: caller.emailVerified,
      createdAt: requestSnap.data()?.createdAt || now,
      updatedAt: now,
    }, { merge: true });
    if (!accessSnap.exists) {
      transaction.create(accessRef, {
        uid: caller.uid,
        email: caller.email,
        username,
        name,
        role: 'Staff',
        status: 'pending',
        active: false,
        createdAt: now,
        updatedAt: now,
      });
    }
    transaction.set(profileRef, {
      uid: caller.uid,
      email: caller.email,
      username,
      name,
      role: accessSnap.data()?.role || 'Staff',
      account_status: accessSnap.data()?.status || 'pending',
      is_active: accessSnap.data()?.active === true,
      created_at: (requestSnap.data()?.createdAt || now).toDate().toISOString(),
    }, { merge: true });
  });
  return { status: 'pending', emailVerified: caller.emailVerified };
});

exports.refreshRegistrationVerification = onCall(accessOptions, async (request) => {
  const caller = requireNativeCaller(request);
  if (!caller.emailVerified) {
    throw new HttpsError('failed-precondition', 'Email verification is required.');
  }
  const requestRef = db.collection(REGISTRATION_REQUESTS).doc(caller.uid);
  const accessRef = db.collection(ACCOUNT_ACCESS).doc(caller.uid);
  await db.runTransaction(async (transaction) => {
    const [requestSnap, accessSnap] = await Promise.all([
      transaction.get(requestRef),
      transaction.get(accessRef),
    ]);
    if (!requestSnap.exists || !accessSnap.exists) {
      throw new HttpsError('not-found', 'Registration request was not found.');
    }
    const now = Timestamp.now();
    transaction.update(requestRef, {
      emailVerified: true,
      verifiedAt: now,
      updatedAt: now,
    });
    transaction.update(accessRef, { email: caller.email, updatedAt: now });
  });
  return { status: 'pending', emailVerified: true };
});

exports.reviewRegistrationRequest = onCall(accessOptions, async (request) => {
  const administrator = await requireAdministrator(request);
  let review;
  try {
    review = validateReview(request.data);
  } catch (error) {
    if (error instanceof AccessValidationError) {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }
  if (review.uid === administrator.uid) {
    throw new HttpsError('permission-denied', 'Administrators cannot review themselves.');
  }

  const requestRef = db.collection(REGISTRATION_REQUESTS).doc(review.uid);
  const accessRef = db.collection(ACCOUNT_ACCESS).doc(review.uid);
  const profileRef = db.collection('users').doc(review.uid);
  await db.runTransaction(async (transaction) => {
    const [requestSnap, accessSnap] = await Promise.all([
      transaction.get(requestRef),
      transaction.get(accessRef),
    ]);
    if (!requestSnap.exists || !accessSnap.exists) {
      throw new HttpsError('not-found', 'Registration request was not found.');
    }
    if (review.decision === 'approved' && requestSnap.data().emailVerified !== true) {
      throw new HttpsError(
        'failed-precondition',
        'The requester must verify their email before approval.',
      );
    }
    const now = Timestamp.now();
    const active = review.decision === 'approved';
    transaction.update(requestRef, {
      status: review.decision,
      approvedRole: review.role,
      reviewedBy: administrator.uid,
      reviewedAt: now,
      updatedAt: now,
    });
    transaction.update(accessRef, {
      status: review.decision,
      active,
      role: review.role,
      reviewedBy: administrator.uid,
      reviewedAt: now,
      updatedAt: now,
    });
    transaction.set(profileRef, {
      role: review.role,
      account_status: review.decision,
      is_active: active,
      updated_at: now.toDate().toISOString(),
    }, { merge: true });
  });
  return { uid: review.uid, status: review.decision, role: review.role };
});
