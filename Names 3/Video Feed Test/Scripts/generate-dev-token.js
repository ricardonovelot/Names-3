/**
 * Apple Music Developer Token generator (ES256)
 *
 * Usage (env vars recommended):
 *   TEAM_ID=AAAAA KEY_ID=BBBBB P8=/absolute/path/AuthKey_BBBBB.p8 TTL_DAYS=30 node generate-dev-token.js
 *
 * Or edit the constants below (env vars still override):
 *   node generate-dev-token.js
 *
 * Verifying the token:
 *   curl -H "Authorization: Bearer <TOKEN>" \
 *     "https://api.music.apple.com/v1/catalog/us/search?term=beatles&types=songs&limit=1"
 */

const fs = require('fs');
const jwt = require('jsonwebtoken');

// Optional inline defaults (override with env vars)
const DEFAULTS = {
  TEAM_ID: 'YOUR_TEAM_ID',
  KEY_ID: 'YOUR_KEY_ID',
  P8: '/absolute/path/to/AuthKey_KEYID.p8',
  TTL_DAYS: 30
};

const TEAM_ID = process.env.TEAM_ID || DEFAULTS.TEAM_ID;
const KEY_ID = process.env.KEY_ID || DEFAULTS.KEY_ID;
const PRIVATE_KEY_P8_PATH = process.env.P8 || DEFAULTS.P8;
const TTL_DAYS = Number(process.env.TTL_DAYS || DEFAULTS.TTL_DAYS);

if (!TEAM_ID || TEAM_ID === 'YOUR_TEAM_ID') {
  console.error('ERROR: TEAM_ID is not set. Set TEAM_ID env var or edit DEFAULTS.TEAM_ID.');
  process.exit(1);
}
if (!KEY_ID || KEY_ID === 'YOUR_KEY_ID') {
  console.error('ERROR: KEY_ID is not set. Set KEY_ID env var or edit DEFAULTS.KEY_ID.');
  process.exit(1);
}
if (!PRIVATE_KEY_P8_PATH || PRIVATE_KEY_P8_PATH.startsWith('/absolute/path')) {
  console.error('ERROR: P8 path is not set. Set P8 env var or edit DEFAULTS.P8 with an absolute path.');
  process.exit(1);
}
if (!fs.existsSync(PRIVATE_KEY_P8_PATH)) {
  console.error(`ERROR: .p8 file not found at ${PRIVATE_KEY_P8_PATH}`);
  process.exit(1);
}

const now = Math.floor(Date.now() / 1000);
const exp = now + (TTL_DAYS * 24 * 60 * 60); // Max 6 months total

const privateKey = fs.readFileSync(PRIVATE_KEY_P8_PATH, 'utf8');

const token = jwt.sign(
  { iss: TEAM_ID, iat: now, exp },
  privateKey,
  { algorithm: 'ES256', header: { alg: 'ES256', kid: KEY_ID } }
);

console.log(token);
console.error(`Generated token valid for ${TTL_DAYS} day(s). Expires at: ${new Date(exp * 1000).toISOString()}`);
console.error('Verify with:');
console.error('curl -H "Authorization: Bearer <TOKEN>" "https://api.music.apple.com/v1/catalog/us/search?term=beatles&types=songs&limit=1"');