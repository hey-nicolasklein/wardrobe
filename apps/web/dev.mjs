import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { Hono } from 'hono';

const apiOrigin = process.env.FORM_API_ORIGIN ?? 'http://127.0.0.1:4143';
const app = new Hono();

app.all('/v1/*', proxyApi);
app.all('/health/*', proxyApi);
app.get('/', serveStatic({ path: './apps/web/public/index.html' }));
app.get('/*', serveStatic({ root: './apps/web/public' }));

function proxyApi(context) {
  const requestUrl = new URL(context.req.url);
  const upstreamUrl = new URL(requestUrl.pathname + requestUrl.search, apiOrigin);
  const method = context.req.method;
  return fetch(upstreamUrl, {
    method,
    headers: context.req.raw.headers,
    body: method === 'GET' || method === 'HEAD' ? undefined : context.req.raw.body,
    duplex: 'half',
  });
}

serve({ fetch: app.fetch, hostname: '0.0.0.0', port: 8081 });
console.log('FORM PWA dev server listening on http://0.0.0.0:8081');
