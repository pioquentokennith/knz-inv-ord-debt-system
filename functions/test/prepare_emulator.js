'use strict';

const fs = require('node:fs');
const path = require('node:path');

const functionsRoot = path.resolve(__dirname, '..');

fs.writeFileSync(
  path.join(functionsRoot, '.env.demo-knz-scent'),
  [
    'BREVO_SENDER_EMAIL=unconfigured@example.invalid',
    'BREVO_SENDER_NAME=KNZ Scent',
    'OTP_ENFORCE_APP_CHECK=false',
    '',
  ].join('\n'),
  { encoding: 'utf8', mode: 0o600 },
);

fs.writeFileSync(
  path.join(functionsRoot, '.secret.local'),
  [
    'BREVO_API_KEY=unconfigured',
    'OTP_SECURITY_SECRET=unconfigured',
    '',
  ].join('\n'),
  { encoding: 'utf8', mode: 0o600 },
);
