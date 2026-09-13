import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
  resetFixtures,
  fixtureIds,
} from '@form/service';
import { createApp } from '../../api/src/app.ts';
const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());
// Bootstrap its own schema and bucket so launching is one command against an empty
// fixture database, not a launch that half-fails until someone runs migrate by hand.
await migrateDatabase(database);
await ensurePrivateBucket(storage);
await resetFixtures(database, storage);
const app = createApp({
  database,
  storage,
  personalAccountId: fixtureIds.populatedAccount,
  sessionSecret: 'browser-test-secret-at-least-32-characters',
  webOrigin: 'http://127.0.0.1:18444',
  publicOrigin: 'http://127.0.0.1:18444',
  checkReadiness: async () => ({
    status: 'ready',
    database: 'up',
    objectStorage: 'up',
  }),
});
app.get('/', serveStatic({ path: './apps/web/public/index.html' }));
// createApp owns the root health response; replace only that route when serving the web fixture.
const server = serve({
  port: 18444,
  hostname: '127.0.0.1',
  fetch: async (request) => {
    if (new URL(request.url).pathname === '/')
      return new Response(
        await (
          await import('node:fs/promises')
        ).readFile('apps/web/public/index.html'),
        { headers: { 'Content-Type': 'text/html' } },
      );
    return app.fetch(request);
  },
});
app.get('/*', serveStatic({ root: './apps/web/public' }));
console.log('PWA test server ready');
process.once('SIGTERM', () => {
  server.close();
  database.end();
  storage.client.destroy();
});
