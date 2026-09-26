import { serve } from '@hono/node-server';
import {
  checkDependencies,
  createIdentityTokenVerifier,
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
} from '@form/service';

import { createApp } from './app.js';
import { readApiConfig } from './config.js';

const config = readApiConfig();

function clientIds(value: string): string[] {
  return value.split(',').map((id) => id.trim()).filter(Boolean);
}
const database = createDatabase(config);
const storage = createPrivateObjectStorage(config);

await migrateDatabase(database);
await ensurePrivateBucket(storage);

const app = createApp({
  checkReadiness: () => checkDependencies(database, storage),
  database,
  storage,
  sessionSecret: config.SESSION_SECRET,
  sessionLifetimeSeconds: config.SESSION_LIFETIME_SECONDS,
  secureCookies: config.SESSION_COOKIE_SECURE,
  webOrigin: config.WEB_ORIGIN,
  publicOrigin: config.WEB_ORIGIN,
  detectionModel: config.OPENAI_DETECTION_MODEL,
  personalAccountId: config.PERSONAL_ACCOUNT_ID,
  identityVerifier: createIdentityTokenVerifier({
    apple: clientIds(config.APPLE_CLIENT_IDS),
    google: clientIds(config.GOOGLE_CLIENT_IDS),
  }),
  devSignIn: config.DEV_SIGN_IN,
});
if (config.DEV_SIGN_IN) console.warn('DEV_SIGN_IN is on: any email can sign in without a password.');
const server = serve({
  fetch: app.fetch,
  hostname: config.API_HOST,
  port: config.API_PORT,
});

console.log(`FORM API listening on http://${config.API_HOST}:${config.API_PORT}`);

let stopping = false;
async function stop(): Promise<void> {
  if (stopping) return;
  stopping = true;
  server.close();
  storage.client.destroy();
  await database.end();
}

process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());
