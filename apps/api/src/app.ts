import { contractVersion } from '@form/contracts';
import type { DependencyHealth } from '@form/service';
import { Hono } from 'hono';

export type ReadinessCheck = () => Promise<DependencyHealth>;

export function createApp(checkReadiness: ReadinessCheck): Hono {
  const app = new Hono();

  app.get('/', (context) =>
    context.json({
      service: 'form-api',
      status: 'ready',
      contractVersion,
    }),
  );

  app.get('/health/live', (context) =>
    context.json({ service: 'form-api', status: 'alive' }),
  );

  app.get('/health/ready', async (context) => {
    const health = await checkReadiness();
    return context.json(health, health.status === 'ready' ? 200 : 503);
  });

  return app;
}
