import { contractVersion } from '@form/contracts';
import {
  checkDependencies,
  type Database,
  type PrivateAssetStore,
} from '@form/service';
import { Hono } from 'hono';

export interface ApiDependencies {
  database: Database;
  assets: PrivateAssetStore;
  bucket: string;
}

export function createApp(dependencies: ApiDependencies): Hono {
  const app = new Hono();

  app.get('/', (context) =>
    context.json({
      service: 'form-api',
      status: 'ok',
      contractVersion,
    }),
  );

  app.get('/health/live', (context) =>
    context.json({ service: 'form-api', status: 'alive' }),
  );

  app.get('/health/ready', async (context) => {
    const health = await checkDependencies(
      dependencies.database,
      dependencies.assets.client,
      dependencies.bucket,
    );
    return context.json(health, health.status === 'ready' ? 200 : 503);
  });

  return app;
}
