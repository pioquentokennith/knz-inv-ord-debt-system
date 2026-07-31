'use strict';

const { escapeHtml, normalizeEmail } = require('./otp_helpers');

class BackendConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'BackendConfigurationError';
  }
}

function readOtpSecuritySecret(value) {
  if (typeof value !== 'string' || value.length < 32) {
    throw new BackendConfigurationError(
      'OTP_SECURITY_SECRET must be configured with at least 32 characters.',
    );
  }
  return value;
}

function readBrevoConfiguration({ apiKey, senderEmail, senderName }) {
  if (typeof apiKey !== 'string' || apiKey.length < 20) {
    throw new BackendConfigurationError('BREVO_API_KEY is not configured.');
  }

  let email;
  try {
    email = normalizeEmail(senderEmail);
  } catch (_) {
    throw new BackendConfigurationError('BREVO_SENDER_EMAIL is not configured.');
  }
  if (email.endsWith('.invalid')) {
    throw new BackendConfigurationError('BREVO_SENDER_EMAIL is not configured.');
  }
  const name = String(senderName || '').trim().slice(0, 80);
  if (!name) {
    throw new BackendConfigurationError('BREVO_SENDER_NAME is not configured.');
  }
  return { apiKey, senderEmail: email, senderName: name };
}

async function sendOtpEmail({
  email,
  otp,
  purpose,
  apiKey,
  senderEmail,
  senderName,
  fetchImpl = globalThis.fetch,
}) {
  const config = readBrevoConfiguration({ apiKey, senderEmail, senderName });
  const purposeLabel = purpose === 'register'
    ? 'account registration'
    : 'password reset';
  const safeRecipient = escapeHtml(email);
  const safeSenderName = escapeHtml(config.senderName);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const response = await fetchImpl('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        accept: 'application/json',
        'api-key': config.apiKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        sender: { name: config.senderName, email: config.senderEmail },
        to: [{ email }],
        subject: 'Your KNZ Scent verification code',
        htmlContent: `
<!doctype html>
<html lang="en">
<body style="font-family:Arial,sans-serif;background:#1a1a1a;margin:0;padding:20px">
  <div style="max-width:480px;margin:0 auto;background:#242424;border-radius:16px;padding:32px;border:1px solid #333">
    <h1 style="color:#C9A84C;font-size:24px;text-align:center;letter-spacing:2px">${safeSenderName}</h1>
    <p style="color:#fff;text-align:center">Your code for <strong style="color:#C9A84C">${purposeLabel}</strong> is:</p>
    <div style="background:#1a1a1a;border:2px solid #C9A84C;border-radius:12px;padding:20px;text-align:center">
      <strong style="color:#C9A84C;font-size:40px;letter-spacing:12px">${otp}</strong>
    </div>
    <p style="color:#aaa;font-size:13px;text-align:center">Valid for 10 minutes. Do not share this code.</p>
    <p style="color:#666;font-size:11px;text-align:center">Sent to ${safeRecipient}</p>
  </div>
</body>
</html>`,
      }),
    });

    if (response.status !== 201) {
      throw new Error('Email provider rejected the request.');
    }
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = {
  BackendConfigurationError,
  readBrevoConfiguration,
  readOtpSecuritySecret,
  sendOtpEmail,
};
