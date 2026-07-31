'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  BackendConfigurationError,
  readBrevoConfiguration,
  readOtpSecuritySecret,
  sendOtpEmail,
} = require('../otp_delivery');

test('fails clearly when backend secrets or sender parameters are missing', () => {
  assert.throws(() => readOtpSecuritySecret('short'), BackendConfigurationError);
  assert.throws(
    () => readBrevoConfiguration({
      apiKey: '',
      senderEmail: 'sender@example.com',
      senderName: 'KNZ Scent',
    }),
    BackendConfigurationError,
  );
  assert.throws(
    () => readBrevoConfiguration({
      apiKey: 'test-only-api-key-value',
      senderEmail: 'invalid',
      senderName: 'KNZ Scent',
    }),
    BackendConfigurationError,
  );
  assert.throws(
    () => readBrevoConfiguration({
      apiKey: 'test-only-api-key-value',
      senderEmail: 'unconfigured@example.invalid',
      senderName: 'KNZ Scent',
    }),
    BackendConfigurationError,
  );
});

test('sends a fixed server-generated Brevo request', async () => {
  let outbound;
  await sendOtpEmail({
    email: 'admin@example.com',
    otp: '123456',
    purpose: 'resetPassword',
    apiKey: 'test-only-api-key-value',
    senderEmail: 'sender@example.com',
    senderName: 'KNZ Scent',
    fetchImpl: async (url, options) => {
      outbound = { url, options };
      return { status: 201 };
    },
  });

  assert.equal(outbound.url, 'https://api.brevo.com/v3/smtp/email');
  assert.equal(outbound.options.headers['api-key'], 'test-only-api-key-value');
  const body = JSON.parse(outbound.options.body);
  assert.deepEqual(body.to, [{ email: 'admin@example.com' }]);
  assert.match(body.htmlContent, /123456/);
  assert.match(body.htmlContent, /password reset/);
});

test('does not expose provider response content in delivery errors', async () => {
  await assert.rejects(
    sendOtpEmail({
      email: 'admin@example.com',
      otp: '123456',
      purpose: 'resetPassword',
      apiKey: 'test-only-api-key-value',
      senderEmail: 'sender@example.com',
      senderName: 'KNZ Scent',
      fetchImpl: async () => ({ status: 400 }),
    }),
    /Email provider rejected the request/,
  );
});
