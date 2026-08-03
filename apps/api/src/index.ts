import { serve } from '@hono/node-server';
import { contractVersion } from '@form/contracts';
import { Hono } from 'hono';

import { apiConfigSchema } from './config.js';

const bootstrapConfigSchema = apiConfigSchema.pick({
  API_HOST: true,
  API_PORT: true,
});

const config = bootstrapConfigSchema.parse(process.env);
const app = new Hono();

app.get('/', (context) =>
  context.json({
    service: 'form-api',
    status: 'workspace-ready',
    contractVersion,
  }),
);

serve({
  fetch: app.fetch,
  hostname: config.API_HOST,
  port: config.API_PORT,
});

console.log(`FORM API workspace listening on http://${config.API_HOST}:${config.API_PORT}`);
